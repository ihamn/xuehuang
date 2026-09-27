-- kitchen.lua —— 后厨：名额池 / 小票 / 手法推进 / 交付
--
-- 这里装着整局最容易出 bug 的规则，全部是从网页版真实反馈里长出来的：
--
--   ① **按单填池**：同一张单的几杯**一起进池**。
--      规则来自玩家反馈："一个订单多个则同时进入制作池，注意处理好池内最多三个的逻辑。"
--      反例（网页版踩过的）：第一杯开工就把同单第二杯挤出池 → 玩家以为"第二杯做不了"。
--   ② **每一杯都出票**，包括还没拿到名额的。
--      反例：没名额就不出票 → 屏幕上只有一张票，玩家觉得"第二杯根本没进来"。
--      没名额的票只是"还没挂工位"，名额一腾出来自己就挂上。
--   ③ **一天只结一次账**：结算要幂等（`settledDay` 闸），否则每帧扣一次房租、欠租滚雪球。
--   ④ 做完即出（serveNow，例如甜筒）：最后一步收口时**直接交付**，不进打包台。

local CFG = require('config')
local R = require('recipes')
local S = require('state')
local O = require('order')

local K = {}

-- ── 小票：一杯一张 ──
local function slipFor(s, cup)
  for _, sl in ipairs(s.slips) do if sl.cup == cup then return sl end end
  return nil
end
K.slipFor = slipFor

local function makeSlip(s, o, cup)
  local ex = slipFor(s, cup)
  if ex then return ex end                     -- ★ 去重：同一杯永远只有一张票
  s.sid = s.sid + 1
  local sl = { id = s.sid, cup = cup, o = o, st = nil, ready = false, stalled = 0, auto = false }
  s.slips[#s.slips + 1] = sl
  return sl
end
K.makeSlip = makeSlip

-- ── 名额池：按进店顺序填池，老单先把自己的杯全塞进去 ──
--   返回"现在有几个在制"
--
-- ★★ 名额口径（两个概念必须分开，网页版这里错过）：
--     · `cupWip(cup)`  = **已开工**、还没做完 → 直接占一个名额
--     · `cup.slotReady` = **还没开工、但拿到了开工资格**（在池里等着）→ 也占一个名额
--   所以 `slotReady` **只对"没开工"的杯有意义**：杯子一旦开工，它的名额由 wipCount 体现，
--   必须把 slotReady 清掉，否则同一杯被算两次、池子里能塞进超过 CAP 的杯。
function K.refreshSlots(s)
  local CAP = CFG.kitchen.maxWip
  local used = S.wipCount(s)                          -- 已开工占掉的
  local claimed = 0                                   -- 已发出去、还没开工的资格数
  for _, o in ipairs(s.orders) do
    for _, c in ipairs(o.cups) do
      if c.slotReady and not c.made and c.startedAt == nil then claimed = claimed + 1 end
    end
  end
  local free = math.max(0, CAP - used - claimed)

  local byTime = {}
  for _, o in ipairs(s.orders) do byTime[#byTime + 1] = o end
  table.sort(byTime, function(a, b) if a.born == b.born then return a.id < b.id end return a.born < b.born end)

  local qi = 0
  for _, o in ipairs(s.orders) do
    o.queueNo = 0; o.priority = false; o.inProgress = false
    for _, c in ipairs(o.cups) do if S.cupWip(c) then o.inProgress = true end end
  end
  for _, o in ipairs(byTime) do
    if o.status ~= 'done' then
      local got = 0
      for _, c in ipairs(o.cups) do
        if c.made then
          c.slotReady = false
        elseif c.startedAt ~= nil then
          c.slotReady = false                -- ★ 开工=由 wipCount 计名额，清掉资格（别算两次）
          got = got + 1
        elseif c.slotReady then
          got = got + 1                      -- 已在池里的保持资格（不挤同单的杯）
        elseif free > 0 then
          c.slotReady = true; free = free - 1; got = got + 1
        else
          c.slotReady = false
        end
      end
      if got > 0 then o.priority = true end
      local anyLeft = false
      for _, c in ipairs(o.cups) do if not c.made then anyLeft = true end end
      if anyLeft and not o.inProgress then qi = qi + 1; o.queueNo = qi end
    end
  end
  -- ★★ 不变量硬保证：**在制（已开工）+ 池内（已发资格、未开工）≤ CAP**。
  --   写法上的教训：不要用"砍 N 个就够"的推理（我连推三次都错）。**每砍一轮就重新数一遍**，
  --   数到真的不超为止 —— 慢一点点，但不可能算漏。
  local function snapshot()
    local w, pool = S.wipCount(s), {}
    for _, o in ipairs(byTime) do
      for _, c in ipairs(o.cups) do
        if c.slotReady and not c.made and c.startedAt == nil then pool[#pool + 1] = c end
      end
    end
    return w, pool
  end
  local function enforceCap()
    for _ = 1, 64 do
      local w, pool = snapshot()
      local over = (w + #pool) - CAP
      if over <= 0 then return end
      -- 从"最后一单的最后一杯"往前砍（老单优先保留资格）
      for i = #pool, 1, -1 do
        if over <= 0 then break end
        pool[i].slotReady = false
        over = over - 1
      end
    end
    if _G.__CAPLOG then
      local w, pool = snapshot()
      print('[CAP] 兜底仍未收敛 used=' .. tostring(w) .. ' pool=' .. tostring(#pool) .. ' CAP=' .. tostring(CAP))
    end
  end
  enforceCap()
  -- 补票：只要"有资格开工的杯还没票"就补。
  -- ★ 别用"名额计数变了才补"这种近似判断 —— 我第一版就是那么写的，结果 `used`（已开工数）
  --   一直是 0，条件永远不成立，**整局一张票都没出**（机器人 0 杯，查了三轮才定位）。
  --   条件要直接问"有没有该出票的杯"，不做代理判断。
  if CFG.autoTicket.on then
    local need = false
    for _, o in ipairs(s.orders) do
      if o.status ~= 'done' then
        for _, c in ipairs(o.cups) do
          if not c.made and not slipFor(s, c) then need = true end
        end
      end
    end
    if need then K.makeTicketsFor(s) end
  end
  enforceCap()                            -- 补票/挂工位之后可能又有开工，再保一次
  s._slotsUsed = used
  return used
end

-- ── 出票：给**还没起票**的杯补票（含还没拿到名额的）──
function K.makeTicketsFor(s, order)
  local list = order and { order } or s.orders
  local n = 0
  for _, o in ipairs(list) do
    if o.status ~= 'done' then
      local k = 0
      for _, cup in ipairs(o.cups) do
        if not cup.made and k < CFG.autoTicket.maxPerOrder and not slipFor(s, cup) then
          local sl = makeSlip(s, o, cup)
          local nx = S.nextStep(cup)
          -- 有资格就顺手挂到第一手；没资格就先放着（"等名额"）
          if nx then K.routeSlip(s, sl, nx.st) end
          k = k + 1; n = n + 1
        end
      end
    end
  end
  return n
end

-- ── 把票送到某个工位 ──
--   这里**只负责"票去哪"**，不负责"开工"。
--   网页版的教训：「票挂上工位」不等于「玩家开工了」—— 票在队列里排队时不该占名额。
--   所以 `cup.startedAt` 只在**真正动手**（pressStep / tickHolds 有进展）时才记，
--   记的时候才调用 refreshSlots 重新分配名额。
function K.routeSlip(s, sl, stationId)
  local cup = sl.cup
  if cup.done then return false, '这杯已经交付了' end
  local nx = S.nextStep(cup)
  if not nx and not sl.ready then return false, '这杯没有下一步了' end
  -- 没拿到名额的杯**先不许开工**（例外：下一步是"不占名额的纯手感步骤"，那种不占人手）
  if cup.startedAt == nil and not cup.slotReady and not (nx and nx.noSlot) then
    return false, string.format('后厨已经 %d 个任务在制了，这张票先排队（等一个名额腾出来）', CFG.kitchen.maxWip)
  end
  if sl.ready and stationId ~= 'pack' then return false, '这杯已经做完了，送打包台' end
  local dst = sl.ready and 'pack' or (nx and nx.st)
  if not dst then return false, '没有下一步了' end
  if stationId and stationId ~= dst then
    return false, string.format('「%s」这一步该去 %s', nx and nx.t or '出餐', dst)
  end
  sl.st = dst
  sl.stalled = 0
  return true
end

-- 真正开工：由"玩家动手"触发（不是挂票触发）
-- 真正开工：由"玩家动手"触发（不是挂票触发）
--
-- ★★ 这里必须**直接问全局在制数**，不能只看这一杯自己的 `slotReady`：
--   `slotReady` 是"选举结果"（谁优先开工），而名额是**全局共享资源**。
--   我原来写成 `if not cup.slotReady then return false` —— 结果池里已经站着 3 个杯，
--   第 4 个杯因为自己 slotReady=true 也被放行开工 → 在制+池内 = 4 > CAP。
--   （真机自检抓到的：`after beginWork w=0 pool=3`，下一按就变成 w=1 pool=3。）
--   现在的口径：**能开工 = 全局 wipCount < CAP**（不占名额的纯手感步骤除外）。
local function beginWork(s, sl)
  local cup = sl.cup
  if cup.startedAt ~= nil or cup.made then return false end
  -- ★★ 2026-09-27 修正（端到端按键测试抓到：在制峰值 7 > 上限 3）：
  --   原实现 `local freeStep = (nx.noSlot == true); if not freeStep and wipCount >= CAP then return false end`
  --   —— noSlot 那一步（速溶咖啡前三步）**把整道名额闸门整个绕过去了**：
  --     连按兑茶键就能开出无限杯"纯手感步骤"的杯（实测峰值 7）。
  --   现在闸门一律生效，口径是 S.wipGateCount（在飞的杯 = 已开工 + 已发资格）：
  --     · noSlot 的杯**对 S.wipCount 不占名额**（原版设计：轻活不抢重活的名额）—— 设计意图保留
  --     · 但"同时开几杯"有界 → `S.wipCount ≤ maxWip` 成为真不变量
  if S.wipGateCount(s) >= CFG.kitchen.maxWip then return false end
  cup.startedAt = s.t          -- 开工 = 占一个"未完成任务"名额
  cup.slotReady = false        -- 同时清掉"池内资格"（别算两次）
  K.refreshSlots(s)            -- 占掉名额后重算：谁还能开工、谁被挤去排队
  return true
end

-- ── 按一下（键盘/点击都走这里，保证两条输入路径手感一致）──
--   返回 { done = 这一步是否收口, ok = 是否收口/有进展, step, before, after, kind }
--
--   ★★ 2026-09-27 还原（原版 pressStep，网页版 938 行）：
--     我一度把三个手法全改成"一次输入即完成"（CFG.hold.oneTap = true），
--     理由是"玩家点了没反应"—— 那是**误诊**：真正没反应的原因是票没被搬到工位
--     （见 K.forwardSlip 的注释）。把手法砍掉以后：
--       · 按住类的 0.9 秒手感没了
--       · 连按类（4/5/6 下）没了
--       · 表现层算不出"这一步要按几下"，进度条失去意义
--     现在恢复原版三条语义，一条不少：
--       tap  → 一下就收口
--       mash → 每次输入 +1，满 taps 才收口
--       hold → 每次输入只把 holdOn 置真；进度靠 day.tick → K.tickHolds 每帧累积，
--              满 hold.sec 秒收口，松手（kind='release'）就停
function K.pressStep(s, sl)
  local nx = S.nextStep(sl.cup)
  if not nx then return { done = false } end
  beginWork(s, sl)                        -- ★ 真动手才算开工（这里才占名额）
  local before = nx.done or 0
  if nx.kind == 'hold' then
    -- ★★ 一次输入即完成（2026-09-27 真机证据：这个平台上"按住"不可用）
    --   证据：19:15 真机运行按 P 共 13 次，[STATE] 48 次采样全是 hold:0.0/0.9，
    --   整份日志**没有一条 [KUP]（抬起）** ⇒ 真机不送 KeyUp，进度永远攒不起来，
    --   按住类步骤**永远做不完**（玩家："按键盘它从不变，鼠标点却能完成"）。
    if CFG.hold and CFG.hold.oneTap == true then
      nx.done = CFG.hold.sec
      K.doStep(s, sl)
      return { done = true, ok = true, step = nx, before = before, after = nx.done, kind = 'hold' }
    end
    -- 下面是原版的"按住累积"（oneTap=false 时启用；需要真机送 KeyUp 才成立）
    nx.holdOn = true
  elseif nx.kind == 'mash' then
    nx.done = before + 1                  -- 连点：攒次数
    if nx.done >= (nx.taps or 1) then K.doStep(s, sl) end
  else
    nx.done = nx.taps or 1                -- tap：一下就收口
    K.doStep(s, sl)
  end
  local after = nx.done or 0
  -- ★ done 的口径必须**按手法分别判断**：
  --   旧版拿 nx.ok 当"收口"判据，而 hold 类的 nx.ok 在 doStep 里并不置真 →
  --   按住满 0.9 秒也会被报成"没完成"（视图/提示都会错）。
  local closed
  if nx.kind == 'hold' then closed = (after >= (CFG.hold and CFG.hold.sec or 0.9)) or nx.ok == true
  elseif nx.kind == 'mash' then closed = (after >= (nx.taps or 1)) or nx.ok == true
  else closed = true end
  return { done = closed, ok = closed or after > before, step = nx, before = before, after = after, kind = nx.kind }
end

-- 按住类每帧推进（松手就停）
function K.tickHolds(s, dt)
  for _, sl in ipairs(s.slips) do
    local nx = S.nextStep(sl.cup)
    if nx and nx.kind == 'hold' and nx.holdOn then
      beginWork(s, sl)                    -- ★ 按住也是"动手"：这里才算开工
      nx.done = math.min(CFG.hold.sec, (nx.done or 0) + dt)
      if nx.done >= CFG.hold.sec then K.doStep(s, sl) end
    end
  end
end

-- 某工位"当前这步"的进度 0..1（给表现层画进度条用）
--   ★ 为什么要有这个：按住类的进度只存在 nx.done 里，view.lua 只看得到文本 →
--     按住时进度条一直不动，用户以为"按住没用"（真实反馈）。
--     view 不该直接碰 state 结构，所以由 kitchen 导出只读快照。
--   返回：进度 0..1, 这类步骤的 kind（'mash' / 'hold' / 'tap' / nil）
function K.stepProgress(s, stId)
  for _, sl in ipairs(s.slips or {}) do
    local nx = S.nextStep(sl.cup)
    if nx and nx.st == stId then
      if nx.kind == 'mash' then
        local taps = nx.taps or 1
        return math.max(0, math.min(1, (nx.done or 0) / (taps > 0 and taps or 1))), 'mash'
      elseif nx.kind == 'hold' then
        local full = CFG.hold.sec or 1
        return math.max(0, math.min(1, (nx.done or 0) / (full > 0 and full or 1))), 'hold'
      end
      return 0, nx.kind or 'tap'
    end
  end
  return 0, nil
end

-- ── 收口：把"当前这一步"标记完成；全部步骤做完 → 这杯 `made` ──
--   ★★ 三个状态必须分清（我第一版把 done 同时当"做完"和"交付"，导致整局交不掉单）：
--        steps 全 ok  → 步骤完成
--        cup.made     → **这杯真的做完了**（可以放托盘 / 直接交付）
--        cup.done     → **这杯已经交给客人了**（结单计数看这个）
function K.doStep(s, sl)
  local cup = sl.cup
  -- 守卫：这杯已经做完了但票还标着没做完（这种票会永远赖在工位上被反复点）
  if cup.made and not sl.ready then
    sl.ready = true
    return
  end
  local nx, idx = S.nextStep(cup)
  if not nx then return end
  if (nx.done or 0) < (nx.kind == 'hold' and CFG.hold.sec or (nx.taps or 1)) then return end
  nx.ok = true
  local allDone = true
  for _, st in ipairs(cup.steps) do if not st.ok then allDone = false end end
  if allDone then
    cup.made = true
    cup.finishedAt = s.t
    if cup.rec.serveNow then
      -- ★ 做完即出：当场交给客人（甜筒不用打包）
      O.onCupMade(s, sl.o, cup)
      K.serveCup(s, cup)
    else
      sl.ready = true
      sl.st = nil
      O.onCupMade(s, sl.o, cup)
    end
  else
    local nn = S.nextStep(cup)
    if nn and nn.st ~= sl.st then sl.st = nil end   -- 下一步不在本工位 → 票回到"待流转"
  end
end

-- ── 把这杯**交给客人**（放上托盘）──
--   前置条件：`cup.made`（真的做完了）。交付后 `cup.done = true`，整单全交付才结单。
function K.deliverCup(s, sl)
  local o, cup = sl.o, sl.cup
  if not cup.made then
    sl.ready = false
    if sl.st == 'pack' then sl.st = nil end
    return false, '这杯还没做完，不能交给客人（票已退回）'
  end
  if cup.done then                            -- 已经交过了：清掉这张僵尸票
    for i = #s.slips, 1, -1 do if s.slips[i] == sl then table.remove(s.slips, i) end end
    return false, '这杯已经交过了，清掉这张票'
  end
  cup.done = true
  for i = #s.slips, 1, -1 do if s.slips[i] == sl then table.remove(s.slips, i) end end
  if O.allDelivered(o) then O.finish(s, o, s.t) end   -- 整单都交付了 → 一次结给客人
  return true
end

-- ── 做完即出：不走打包台，当场交付 ──
function K.serveCup(s, cup)
  for i = #s.slips, 1, -1 do if s.slips[i].cup == cup then table.remove(s.slips, i) end end
  if not cup.served then
    cup.served = true
    cup.done = true
    s.served = s.served + 1
    s.today.served = s.today.served + 1
  end
  local o
  for _, x in ipairs(s.orders) do
    for _, c in ipairs(x.cups) do if c == cup then o = x end end
  end
  if o then
    O.onCupMade(s, o, cup, true)
    local allDone = true
    for _, c in ipairs(o.cups) do if not c.done then allDone = false end end
    if allDone then O.finish(s, o, s.t) end
  end
end

-- ── 自愈：清掉"杯子做完了、票还说没做完"的僵尸票（网页版"现萃速溶咖啡像循环"就是这个）──
function K.sweepZombieSlips(s)
  local n = 0
  for i = #s.slips, 1, -1 do
    local sl = s.slips[i]
    if sl.cup.made and not sl.ready then
      sl.ready = true
      n = n + 1
    end
  end
  return n
end

-- ── 点小票 = 立刻把它送到"该去的工位"（★ 原版 forwardSlip，网页版 859 行）──
--   ★★ 为什么必须有这个（2026-09-27 真机日志给出的答案）：
--     移植版只实现了"闲 5 秒自动流转"，**漏了"点小票立刻送过去"这条交互**。
--     原版里玩家在按键之前就能把票送到位，所以按工位键**次次有活**；
--     移植版里票要么在别的工位、要么还没挂工位，按键全部被拒 →
--     真机日志 9085 条 [LOGIC] 里 8984 条 ok=false、9003 条 [REJECT]。
--     玩家看到的结论就是"按 Y/H/P/K 没反应"。
--
--   ⚠️ 语义要跟原版一致：送的是**这一杯的下一步**，不是"你点的那张工位"。
--      已经做完的杯 → 送打包台；已经在目的地的 → ok=false（不空转）。
--   ⚠️ 玩家手动送票**不计入 s.autoMoves**（那是自动流转的记账，自检要用）。
function K.forwardSlip(s, sl, quiet)
  if not s or not sl then return false, '没有这张票' end
  if sl.cup and sl.cup.done then return false, '这杯已经交付了' end
  if sl.st == 'pack' and sl.ready then return false, '已经在打包台了' end
  local nx = S.nextStep(sl.cup)
  if not sl.ready and not nx then
    if sl.cup.made then sl.ready = true else return false, '没有下一步了' end
  end
  local dst = sl.ready and 'pack' or (nx and nx.st)
  if not dst then return false, '没有下一步了' end
  if sl.st == dst then return false, '它已经在这个工位了' end
  local okk, why = K.routeSlip(s, sl, dst)
  if not okk then return false, why end
  return true, dst
end

-- ── 自动流转：某张票闲够 CFG.auto.after 秒就送去该去的工位 ──
--   唯一的开关是 CFG.auto.on（关掉之后一次都不许动小票）
function K.autoForward(s, dt, quiet)
  local moved = 0
  if not CFG.auto.on then return moved end
  for _, sl in ipairs(s.slips) do
    if sl.cup.made and not sl.ready then sl.ready = true end
    local nx = S.nextStep(sl.cup)
    if not nx and not sl.ready then
      -- 没下一步又没 ready：说明这杯做完了，补上
      if sl.cup.made then sl.ready = true end
    else
      if sl.st == nil then sl.stalled = sl.stalled + dt else sl.stalled = 0 end
      if sl.stalled > CFG.auto.after then
        local dst = sl.ready and 'pack' or (nx and nx.st)
        if dst and sl.st ~= dst then
          local before = sl.st
          if K.routeSlip(s, sl, dst) then
            s.autoMoves = s.autoMoves + 1
            moved = moved + 1
          end
        end
      end
    end
  end
  -- 已做完没人打包的，也自动送去打包台
  for _, sl in ipairs(s.slips) do
    if sl.ready and sl.st ~= 'pack' then
      if K.routeSlip(s, sl, 'pack') then s.autoMoves = s.autoMoves + 1; moved = moved + 1 end
    end
  end
  return moved
end

-- ── 手动起杯（关掉自动出票后才有用）：按**这一杯自己的配方**找杯 ──
--   网页版的 bug：按"订单主料"找，导致混点订单的第二杯点手册没反应
function K.startCup(s, rec)
  for _, o in ipairs(s.orders) do
    if o.status ~= 'done' then
      for _, c in ipairs(o.cups) do
        local nx = S.nextStep(c)
        if not c.made and c.rec.id == rec.id and (c.slotReady or (nx and nx.noSlot)) then
          if slipFor(s, c) then return true, '这一杯已经有票了' end
          local sl = makeSlip(s, o, c)
          local ok = K.routeSlip(s, sl, nx and nx.st)
          if not ok then
            for i = #s.slips, 1, -1 do if s.slips[i] == sl then table.remove(s.slips, i) end end
          end
          return ok, ok and '小票已挂到工位' or '挂不上'
        end
      end
    end
  end
  -- 分清"没人点"和"没名额"
  for _, o in ipairs(s.orders) do
    if o.status ~= 'done' then
      for _, c in ipairs(o.cups) do
        if not c.made and c.rec.id == rec.id then
          return false, string.format('「%s」这一杯还没拿到名额（后厨同时只能 %d 个任务在制）',
                                      rec.name, CFG.kitchen.maxWip)
        end
      end
    end
  end
  return false, string.format('现在没人点「%s」——接单了再做', rec.name)
end

-- ── 做错工位（翻车）──
function K.doWrong(s, cup, stationId)
  cup.err = true
  s.mistakes = s.mistakes + 1
  s.today.mistakes = s.today.mistakes + 1
  s.combo = 0
  s.money = math.max(0, s.money - CFG.money.strikePenalty)
  s.score = math.max(0, s.score - CFG.score.mistake)
  return CFG.money.strikePenalty
end

return K
