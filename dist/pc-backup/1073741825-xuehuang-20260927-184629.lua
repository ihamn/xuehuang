-- ==== 自动合成（铺平形态），请勿手改 ====
-- 源：lua/src/*.lua　　生成：node tools/lua-test.mjs --entry=xuehuang --out=<文件>
-- 每个模块一个独立作用域 + 结果缓存；入口源码铺在同一层（生命周期函数必须是全局）
do
local __c_config, __m_config
local __c_day, __m_day
local __c_game, __m_game
local __c_host, __m_host
local __c_input, __m_input
local __c_kitchen, __m_kitchen
local __c_order, __m_order
local __c_recipes, __m_recipes
local __c_skin, __m_skin
local __c_state, __m_state
local __c_view, __m_view
__m_config = function()
  if __c_config ~= nil then return __c_config end
  __c_config = (function()
-- config.lua —— 雪皇的后厨 · 所有数值的唯一来源
--
-- 为什么单独一个文件：网页版那 2900 行里最痛的经验是"同一个数散在三处"，
-- 改了一处另一处没改，表现就是"改了没反应"。所以千星版从第一天起：
--   **任何会被调的数字都只写在这里**，别的文件一律 require 这份。
--
-- 平台约束（真机实测，别踩）：
--   · 整数是 32 位（不要写需要 64 位整数的运算）
--   · 画布 1815x900 是 PC；2D 布局基线是手机 16:9（1280x720），表现层按它构图再等比缩放
--   · require 按路径 '子目录/文件名'（无 .lua 后缀）

local CFG = {}

-- ── 玩法模式：每个模式自带"几天 / 每天多久"，总时长 = days x perDay ──
--   arriveScale = 本盘的"人数密度"（1 = 基准）；短盘时间少，所以把人数也降下来
--   quick = 5 分钟一口气一天（没有日结打断）
CFG.modes = {
  quick = { days = 1, perDay = 300,  arriveScale = 1.45, label = '5 \229\136\134\233\146\159\229\177\128',  desc = '\228\184\128\229\143\163\230\176\148\231\187\143\232\144\165 5 \229\136\134\233\146\159' },
  fast  = { days = 5, perDay = 120,  arriveScale = 1.00, label = '10 \229\136\134\233\146\159\229\177\128', desc = '\230\175\143\229\164\169 2 \229\136\134\233\146\159' },
  slow  = { days = 5, perDay = 240,  arriveScale = 1.00, label = '20 \229\136\134\233\146\159\229\177\128', desc = '\230\175\143\229\164\169 4 \229\136\134\233\146\159' },
}
-- ★ 默认模式必须是**可玩**的：quick（fast/slow 需要多人，施工中）
--   ⚠️ 上一版这里还是 'fast'（施工中）→ 别的路径若用它开局会直接失败
CFG.defaultMode = 'quick'

-- ── 后厨容量：同时**未完成的任务（杯）** ≤ maxWip；等候区最多 maxWaiting 位 ──
--   ★ 关键规则：同一张单的几杯**一起进池**（按单填池），不能"第一杯开工就把同单第二杯挤出去"
CFG.kitchen = { maxWip = 3, maxWaiting = 10 }

-- ── 到店：每次间隔在 [min,max] 内随机 → 到店时间天然动态；dayScale 逐日收紧 ──
--   closing.rampFrom：当天剩余进入最后这个比例后，到店间隔被逐渐拉长（最多 xrampTo）
--   closing.graceSec：打烊后的"清场"宽限期硬上限（这段时间耐心**冻结**）
CFG.arrive = { first = 2.5, min = 8, max = 14, dayScale = 0.95, jitter = 0.2 }
CFG.closing = { rampFrom = 0.35, rampTo = 4, graceSec = 45 }

-- ── 点单 ──
--   cups：杯数的加权分布（加权查表就够，不需要复杂随机）
--   ice/sugar：同上
CFG.cups  = { { n = 1, p = 0.50 }, { n = 2, p = 0.25 }, { n = 3, p = 0.125 }, { n = 4, p = 0.125 } }
CFG.ice   = { { v = '\230\173\163\229\184\184', p = 0.75 }, { v = '\229\142\187\229\134\176', p = 0.125 }, { v = '\229\184\184\230\184\169', p = 0.125 } }
CFG.sugar = { { v = '\230\173\163\229\184\184\231\179\150', p = 0.75 }, { v = '\228\184\131\229\136\134\231\179\150', p = 0.125 }, { v = '\228\186\148\229\136\134\231\179\150', p = 0.125 } }

-- ── 混点：一单可以同款多杯，也可以多种不同 ──
--   mixedChance2/3：2 杯 / 3 杯以上时"混点"的概率
--   twoHeavyBan：不允许把两个"重活"放同一单（干冰 + 重活 = 二十多下连按，那是惩罚不是玩法）
CFG.mix = { mixedChance2 = 0.50, mixedChance3 = 0.65 }

-- ── 耐心：按"这一单点了几杯"动态给（杯数越多，客人愿意等越久）──
--   waitDrain：排队的掉得慢一档；readyDrain：做完了只是没交的掉得更慢
--   doneBonus/perStep/doneBonusMax：**每做完一杯给客人续一点耐心**（进度本身就是补偿）
CFG.patience = {
  base = 38, perCup = 12, min = 26, jitter = 0.15,
  doneBonus = 3, perStep = 0.4, doneBonusMax = 8,
  waitDrain = 0.6, readyDrain = 0.35,
}

-- ── 时间流速：积压 → 慢，空闲 → 快；均值 ≈ 1，所以总时长仍锁在 days x perDay ──
CFG.flow = { base = 0.85, backlogGain = 0.05, backlogMax = 6, idleBonus = 0.4, idleAfter = 8, min = 0.5, max = 1.6 }

-- ── 钱与评分 ──
CFG.money = { perCup = 26, rushBonus = 12, strikePenalty = 18, leavePenalty = 30, comboStep = 2, comboMax = 30 }
CFG.score = { perCup = 100, rushBonus = 40, mistake = 60, leave = 80, flowWeight = 0.8 }
-- 房租：每天固定 100；欠款从最终结算里扣，并按每 debtPerRank 元降一档评级
CFG.rent  = { perDay = 100, debtPerRank = 100 }
-- 评级档位（分数从高到低）
CFG.ranks = { { min = 34000, r = 'S' }, { min = 24000, r = 'A' }, { min = 15000, r = 'B' }, { min = 8000, r = 'C' }, { min = 0, r = 'D' } }

-- ── 手法（tap/mash/hold）与"不占名额的纯手感步骤" ──
-- ★★ 2026-09-27 还原度修正（原版 网页版 938~962 行 + HOLD_SEC=0.9）：
--   原版语义就是三条，**一条都不能少**：
--     tap  → 一下就收口
--     mash → 每次输入 +1，按满 taps 下才收口
--     hold → 每次输入只把 holdOn 置真，进度靠**每帧累积**，满 0.9 秒才收口；松手就停
--   我一度为了"一按就出结果"加了 oneTap/tapBoost 两个优待：hold 点一下直接算 0.9 秒、
--   mash 点一下直接按满 —— 那样确实"按了立刻有反应"，但**手法玩法被整个抹掉了**
--   （按住类和连按类变得和一下没区别，等于删掉原版的手感设计）。
--   真正让"按了有反应"成立的是**点小票立刻送工位 + 按键自动送票**（见 kitchen.forwardSlip
--   与 game.act 的 opt.route），不是把手法砍掉。所以这里恢复原版：
--     hold.sec   = 0.9 秒（原版 HOLD_SEC）
--     hold.tapBoost = 0（点按**不给**进度：想推进就得按住）
--     hold.oneTap   = false（不再"一下完成"）
CFG.hold = { sec = 0.9, tapBoost = 0, oneTap = false }
CFG.taps = { 4, 5, 6 }            -- 连按类每步的档位（按配方难度取）

-- ── 自动（可关）──
--   auto.on：小票自动流转（某一步长时间没人管，自动送去该去的工位）
--   autoTicket.on：客人一进后厨，这单每杯立刻出票（不用手动起杯）
CFG.auto = { on = true, after = 5 }
CFG.autoTicket = { on = true, maxPerOrder = 8 }

-- ── 界面（表现层用；逻辑层不读，但放这里省得两处对不上）──
CFG.ui = {
  designW = 1280, designH = 720,      -- 2D 布局基线（手机 16:9），PC 上等比放大
  stallWarn = 3.0,                    -- 小票在某工位停留超过这么久就闪
}

-- 取某个模式的完整配置（含总时长）
function CFG.mode(name)
  local m = CFG.modes[name] or CFG.modes[CFG.defaultMode]
  return {
    key = name or CFG.defaultMode,
    days = m.days, perDay = m.perDay,
    total = m.days * m.perDay,
    arriveScale = m.arriveScale,
    label = m.label, desc = m.desc,
  }
end

return CFG

  end)()
  if __c_config == nil then __c_config = true end
  return __c_config
end
__m_day = function()
  if __c_day ~= nil then return __c_day end
  __c_day = (function()
-- day.lua —— 时间推进 / 到店 / 打烊清场 / 每日结算
--
-- 这里有三条**用真机日志和玩家反馈换来的**规则：
--   ① 到店间隔逐日收紧，且收尾会**越来越稀**（到点直接不放人）—— "快结束时人来的几率减小"
--   ② 打烊后进入清场：**耐心冻结**，让玩家把手上的做完
--      （反例：网页版打烊后耐心还在掉 → 客人走到一半没了 → 玩家觉得"打烊后什么都干不了"）
--   ③ 结算**幂等**：一天只结一次账
--      （反例：网页版每帧重复结算 → 房租被反复扣、欠租几秒滚成几千）

local CFG = __m_config()
local R = __m_recipes()
local S = __m_state()
local O = __m_order()
local K = __m_kitchen()

local D = {}

local function pickWeighted(tbl, u) return R.pickWeighted(tbl, u) end

-- 时间流速：积压 → 慢，空闲 → 快；均值 ≈ 1（总时长仍锁在 days × perDay）
local function updateFlow(s, dtReal)
  local backlog = 0
  for _, sl in ipairs(s.slips) do if not sl.ready then backlog = backlog + 1 end end
  s.backlog = backlog
  local busy = (#s.orders > 0) or (backlog > 0)
  if busy then s.idle = 0 else s.idle = s.idle + dtReal end
  local F = CFG.flow
  local target = F.base + math.min(backlog, F.backlogMax) * F.backlogGain
  if s.idle > F.idleAfter then target = target + F.idleBonus end
  if (not busy) and #s.orders == 0 then target = math.min(target, 1.0) end
  s.flow = s.flow + (target - s.flow) * math.min(1, dtReal * 1.5)
  s.flow = math.max(F.min, math.min(F.max, s.flow))
  return s.flow
end

-- 到店：算"现在多久来一个"（含收尾减速），不动状态（方便测试）
function D.arriveInterval(s)
  local A = CFG.arrive
  local scale = A.dayScale ^ (s.day - 1)
  local base = A.min + math.random() * (A.max - A.min)
  base = base * scale * (s.mode.arriveScale or 1)
  local jit = 1 + (math.random() * 2 - 1) * A.jitter
  return math.max(1.5, base * jit)
end

-- 收尾减速倍率：当天剩余进入最后 rampFrom 比例后，间隔被逐渐拉长（最多 ×rampTo）
function D.slowFactor(s)
  local CL = CFG.closing
  local frac = S.dayFrac(s)
  if frac >= CL.rampFrom then return 1 end
  local r = math.min(1, (CL.rampFrom - frac) / CL.rampFrom)
  return 1 + (CL.rampTo - 1) * r * r          -- 二次曲线：越到后面掉得越快
end

-- 推进一步。返回本帧发生的事件列表（供表现层弹提示）
function D.tick(s, dtReal)
  local ev = {}
  if s.ended or s.phase == 'done' then return ev end
  if s.settling then return ev end            -- 正在结算：整段打烊逻辑冻结

  local dt = dtReal * updateFlow(s, dtReal)
  s.t = s.t + dtReal
  s.totalLeft = math.max(0, s.totalLeft - dt)
  s.dayLeft = math.max(0, s.dayLeft - dt)

  -- ── 到店 ──
  if s.phase == 'closing' or s.dayLeft <= 0 then
    -- 打烊了：不再放人
  else
    local slow = D.slowFactor(s)
    s.nextArrive = s.nextArrive - dt / slow
    if s.nextArrive <= 0 and #s.orders < CFG.kitchen.maxWaiting + 4 then
      local o = O.spawn(s)
      s.nextArrive = D.arriveInterval(s)
      ev[#ev + 1] = { kind = 'arrive', o = o }
    end
    if slow > 1.6 and s.lastCallDay ~= s.day then
      s.lastCallDay = s.day
      ev[#ev + 1] = { kind = 'lastcall' }
    end
  end

  -- ── 名额池 + 耐心 ──
  -- ★ ARRIVE 探针（ASCII）：到店计时器与订单数（排查"跑了很久没客人"）
  do
    _arr = (_arr or 0) + 1
    if print and _arr % 60 == 0 then
      pcall(print, string.format('[ARRIVE] t=%.1f dayLeft=%.1f next=%.2f orders=%d slips=%d slow=%.2f phase=%s',
        s.t, s.dayLeft, s.nextArrive, #s.orders, #s.slips, D.slowFactor(s), tostring(s.phase)))
    end
  end

  K.refreshSlots(s)
  local P = CFG.patience
  local closingNow = (s.phase == 'closing')
  for i = #s.orders, 1, -1 do
    local o = s.orders[i]
    if o.status ~= 'done' and not closingNow then   -- ★ 清场期间耐心冻结
      local drain = (not o.inProgress) and P.waitDrain or (o.status == 'ready' and P.readyDrain or 1)
      o.pat = o.pat - dt * drain
      if o.pat <= 0 then
        O.leave(s, o, not o.inProgress)
        ev[#ev + 1] = { kind = 'leave', o = o }
      end
    end
  end

  K.tickHolds(s, dt)
  K.sweepZombieSlips(s)
  K.autoForward(s, dtReal, true)

  -- ── 打烊流程 ──
  if s.phase ~= 'closing' and s.dayLeft <= 0 then
    s.phase = 'closing'
    s.closingLeft = CFG.closing.graceSec
    ev[#ev + 1] = { kind = 'closing' }
  end
  if s.phase == 'closing' then
    local pending = {}
    for _, o in ipairs(s.orders) do
      local allDone = true
      for _, c in ipairs(o.cups) do if not c.made then allDone = false end end
      if not allDone then pending[#pending + 1] = o end
    end
    s.closingLeft = s.closingLeft - dtReal
    if (#pending == 0 or s.closingLeft <= 0) and not s.settling then
      s.settling = true
      if #pending > 0 then
        -- ★ 宽限期到了：**已经动过手的单直接算你完成**（别让玩家做掉的白费），
        --   只有"压根没开工"的才算流失 —— 惩罚的是"没动手"，不是"手慢"。
        for _, o in ipairs(pending) do
          if o.inProgress or (o.made or 0) > 0 then
            for _, c in ipairs(o.cups) do
              if not c.done then
                c.done = true
                for _, st in ipairs(c.steps) do st.ok = true end
              end
            end
            O.finish(s, o, s.t)
          else
            s.left = s.left + 1; s.today.left = s.today.left + 1
            for i = #s.orders, 1, -1 do if s.orders[i] == o then table.remove(s.orders, i) end end
          end
        end
        s.slips = {}
        ev[#ev + 1] = { kind = 'graceout' }
      end
      D.settle(s)
      ev[#ev + 1] = { kind = 'dayend', day = s.day }
      return ev
    end
  end

  s.today.flow = s.flow
  return ev
end

-- 结算（幂等：一天只结一次）
function D.settle(s)
  if s.settledDay == s.day then return false end
  s.settledDay = s.day
  local rent = CFG.rent.perDay
  s.rentPaid = s.rentPaid + rent
  local paid = s.money >= rent
  if paid then
    s.money = s.money - rent
  else
    s.rentDebt = s.rentDebt + (rent - s.money)
    s.money = 0
  end
  local rec = { day = s.day, served = s.today.served, money = s.today.money,
                left = s.today.left, mistakes = s.today.mistakes,
                rent = rent, paid = paid, debt = s.rentDebt }
  s.dayStats[#s.dayStats + 1] = rec
  s.log[#s.log + 1] = string.format('\231\172\172 %d \229\164\169\239\188\154\229\135\186\233\164\144 %d \230\157\175 / \232\144\165\228\184\154\233\162\157 %d / \230\181\129\229\164\177 %d / \231\191\187\232\189\166 %d \226\134\146 \230\136\191\231\167\159 %d %s',
    rec.day, rec.served, rec.money, rec.left, rec.mistakes, rent, paid and '\229\183\178\228\187\152' or ('\230\172\160\231\188\180(\231\180\175\232\174\161 ' .. s.rentDebt .. ')'))
  if s.day >= s.mode.days then
    D.endGame(s)
    return true
  end
  s.settling = true          -- 等表现层"继续"→ nextDay
  return true
end

-- 下一天
function D.nextDay(s)
  s.settling = false
  s.phase = 'open'
  s.day = s.day + 1
  s.dayLeft = s.mode.perDay
  s.today = { served = 0, money = 0, left = 0, mistakes = 0 }
  s.nextArrive = CFG.arrive.first
  return s.day
end

-- 收工：算总分与评级
function D.endGame(s)
  s.ended = true
  s.phase = 'done'
  for _, o in ipairs(s.orders) do s.left = s.left + 1; s.today.left = s.today.left + 1 end
  s.orders = {}; s.slips = {}
  local acc = (s.served + s.left) > 0 and (s.served / (s.served + s.left)) or 0
  local flowScore = math.floor(acc * 100 * CFG.score.flowWeight)
  local debt = s.rentDebt
  local total = math.max(0, s.score + flowScore + s.money - debt)
  local rank = 'D'
  for _, r in ipairs(CFG.ranks) do
    if total >= r.min then rank = r.r; break end
  end
  -- 欠租降档：每 debtPerRank 元降一档
  local steps = math.min(4, math.floor(debt / math.max(1, CFG.rent.debtPerRank)))
  local ORDER = { 'S', 'A', 'B', 'C', 'D' }
  if steps > 0 then
    local idx = 1
    for i, x in ipairs(ORDER) do if x == rank then idx = i end end
    rank = ORDER[math.min(#ORDER, idx + steps)]
  end
  s.result = { rank = rank, total = total, score = s.score, flowScore = flowScore,
               money = s.money, debt = debt, downgraded = steps, acc = acc }
  return s.result
end

return D

  end)()
  if __c_day == nil then __c_day = true end
  return __c_day
end
__m_game = function()
  if __c_game ~= nil then return __c_game end
  __c_game = (function()
-- game.lua —— 主循环与生命周期（这一层是逻辑层的主循环；真机入口是 hello.lua）
--
-- 三条真机契约（都在注释里写死，避免以后有人"顺手优化"回去）：
--   ① 建控件必须在 OnStart 及之后：`game.InstantiateClientUIControl` 在 **OnInit 返回 nil**
--      （网页版前身踩过：在 OnInit 建控件 → 全 nil → 连报错提示都建不出来 → 白屏且无提示）
--   ② 不调 `script:EnableUpdate(true)` 就**永远收不到 OnUpdate**（逐帧是命脉）
--   ③ `game` 的全局函数用**点号**调用（`game.GetUICanvasSize()`），冒号会多传隐式实参

local CFG = __m_config()
local R = __m_recipes()
local S = __m_state()
local O = __m_order()
local K = __m_kitchen()
local D = __m_day()

local G = {}

-- 不依赖控件的日志通道（诊断必须走 print，否则"控件建不出来"时什么都看不到）
local function fmt(f, ...)
  if type(f) ~= 'string' then return tostring(f) end
  local args, ai, out = { ... }, 1, {}
  local i = 1
  while true do
    local s, e = string.find(f, '%%[-+ #0]*%d*%.?%d*[sdf]', i)
    if not s then out[#out + 1] = string.sub(f, i); break end
    out[#out + 1] = string.sub(f, i, s - 1)
    local v = args[ai]; ai = ai + 1
    out[#out + 1] = (v == nil) and '(nil)' or tostring(v)
    i = e + 1
  end
  return table.concat(out)
end
local function say(...)
  local ok, line = pcall(fmt, ...)
  if not ok then line = tostring((...)) end
  if print then pcall(print, '[\233\155\170\231\154\135] ' .. line) end
end
G.say = say
G.fmt = fmt

G.BUILD = 'xuehuang-core 2026-09-26 c1'

-- 回调表：表现层 subscribe（这样逻辑层不认识 UI，反过来 UI 只收事件）
G.listeners = {}
function G.on(evt, fn) G.listeners[evt] = G.listeners[evt] or {}; table.insert(G.listeners[evt], fn) end
function G.emit(evt, payload)
  local l = G.listeners[evt]
  if not l then return end
  for _, fn in ipairs(l) do
    local ok, e = pcall(fn, payload)
    if not ok then say('\231\155\145\229\144\172 %s \229\135\186\233\148\153\239\188\154%s', evt, tostring(e)) end
  end
end

-- 开一局
function G.newGame(modeName)
  G.s = S.new(modeName or CFG.defaultMode)
  say('\229\188\128\230\150\176\229\177\128\239\188\154%s\239\188\136%d \229\164\169 \195\151 %d \231\167\146 = %d \231\167\146\239\188\140\228\186\186\230\149\176\229\175\134\229\186\166 \195\151%s\239\188\137',
      G.s.mode.label, G.s.mode.days, G.s.mode.perDay, G.s.mode.total, tostring(G.s.mode.arriveScale))
  return G.s
end

-- 推进一步（表现层每帧调它；测试也能直接推）
--   dtReal：真实经过秒数
function G.tick(dtReal)
  local s = G.s
  if not s or s.ended then return end
  local ev = D.tick(s, dtReal)
  if ev then
    for _, e in ipairs(ev) do
      if e.kind == 'arrive' then
        say('%s \232\166\129 %s %s %s', e.o.name, e.o.makeup, e.o.ice, e.o.sugar)
      elseif e.kind == 'leave' then
        say('%s \232\181\176\228\186\134\239\188\136\232\128\144\229\191\131\232\128\151\229\176\189\239\188\137', e.o.name)
      elseif e.kind == 'lastcall' then
        say('\230\156\128\229\144\142\230\142\165\229\141\149\239\188\154\228\185\139\229\144\142\228\184\141\229\134\141\230\148\190\228\186\186\232\191\155\230\157\165\239\188\140\230\137\139\228\184\138\231\154\132\229\129\154\229\174\140\229\176\177\230\148\182\230\145\138')
      elseif e.kind == 'closing' then
        say('\230\137\147\231\131\138\239\188\154\228\184\141\229\134\141\230\142\165\229\190\133\230\150\176\233\161\190\229\174\162')
      elseif e.kind == 'graceout' then
        say('\230\184\133\229\156\186\229\174\189\233\153\144\230\156\159\229\136\176\239\188\154\229\183\178\231\187\143\229\138\168\232\191\135\230\137\139\231\154\132\229\141\149\231\174\151\228\186\164\228\187\152\239\188\140\230\178\161\229\188\128\229\183\165\231\154\132\232\174\176\230\181\129\229\164\177')
      end
      G.emit(e.kind, e)
    end
  end
end

-- 玩家动作：在某工位按一下
--   返回 { ok=bool, why=string, done=bool }
--
--   opt.route（默认 false）：**票不在这个工位时，先把票送过来**再动手。
--     ★ 为什么需要（真机日志：9085 条 [LOGIC] 里 8984 条 ok=false）：
--       玩家的操作顺序是"按下工位键"，而票经常还在别的工位/还没挂工位。
--       没有这一项时，按键 99% 什么都发生不了 → 玩家判定"快捷键坏了"。
--       等价于原版"点小票立刻送过去"（网页版 forwardSlip）——**不改变任何规则**，
--       只是把玩家原本要点两次的操作做成一次。翻车判定（票该去别的工位）仍然保留。
--     ⚠️ 有 opt.route 也**不会**抢别的工位的活：只会把"下一步就是这个工位"的票送过来，
--        该去别的工位的票照样拒绝（否则 shake 键能把 chem 的活抢走，规则就错了）。
function G.act(stationId, kind, slipId, opt)
  local s = G.s
  if not s or s.ended then return { ok = false, why = '\232\191\152\230\178\161\229\188\128\233\151\168' } end
  opt = opt or {}
  -- 找出这个工位上"能动的那张票"（优先指定 id，否则队列里第一张能做的）
  local function workable(sl)
    local nx = S.nextStep(sl.cup)
    if stationId == 'pack' then return sl.ready or (nx and nx.st == 'pack') end
    return (not sl.ready) and nx ~= nil and nx.st == stationId
  end
  local sl
  if slipId then
    for _, x in ipairs(s.slips) do if x.id == slipId and workable(x) then sl = x end end
  end
  if not sl then for _, x in ipairs(s.slips) do if workable(x) then sl = x; break end end end
  -- ★ 票不在这个工位 → 把"下一步就是这个工位"的票先送过来（还原原版"点小票立刻送过去"）
  --   挑票顺序：**按耐心从低到高**（快没耐心的先做），同耐心按票号。
  --   只挑"下一步 == 本工位"的；没名额的票会被 routeSlip 挡下（名额规则不变）。
  if not sl and opt.route then
    local cands = {}
    for _, x in ipairs(s.slips or {}) do
      local nx2 = S.nextStep(x.cup)
      local want = (stationId == 'pack') and x.ready or ((not x.ready) and nx2 ~= nil and nx2.st == stationId)
      if want and x.st ~= stationId then cands[#cands + 1] = x end
    end
    table.sort(cands, function(a, b)
      local pa = (a.o and a.o.pat) or 1e9
      local pb = (b.o and b.o.pat) or 1e9
      if pa == pb then return a.id < b.id end
      return pa < pb
    end)
    for _, x in ipairs(cands) do
      if K.forwardSlip(s, x, true) and workable(x) then sl = x; break end
    end
  end
  if not sl then
    -- ★ REJECT 探针（纯 ASCII，真机可 grep）：把"为什么这个工位没活"一次说清 ——
    --   列出每张票的 (票号, ready?, 下一步工位)。用来区分：
    --     ① 根本没有票（杯子还没拿到在制名额）  ② 票的下一步不是这个工位  ③ 票已 ready 等打包
    --   ⚠️ 上一版这个探针插在别处、源文件里那句有空格差异 → 没进去（白查一轮）
    if print then
      local parts = {}
      for _, x in ipairs(s.slips or {}) do
        local nx2 = S.nextStep(x.cup)
        parts[#parts + 1] = string.format('#%s:%s:%s', tostring(x.id),
          x.ready and 'ready' or 'open', nx2 and tostring(nx2.st) or 'nil')
      end
      pcall(print, string.format('[REJECT] want=%s slips=%d [%s] orders=%d served=%d',
        tostring(stationId), #(s.slips or {}), table.concat(parts, ' '), #(s.orders or {}), s.served or 0))
    end
    return { ok = false, why = '\232\191\153\228\184\170\229\183\165\228\189\141\230\154\130\230\151\182\230\178\161\230\156\137\232\131\189\229\129\154\231\154\132\229\176\143\231\165\168' }
  end

  local nx = S.nextStep(sl.cup)
  if stationId == 'pack' and sl.ready then
    local okk, why = K.deliverCup(s, sl)
    return { ok = okk, why = why }
  end
  if not nx then return { ok = false, why = '\232\191\153\230\157\175\229\183\178\231\187\143\229\129\154\229\174\140\228\186\134\239\188\140\233\128\129\230\137\147\229\140\133\229\143\176' } end
  if nx.st ~= stationId then
    K.doWrong(s, sl.cup, stationId)
    return { ok = false, why = string.format('\231\191\187\232\189\166\239\188\129%s \229\129\154\228\184\141\228\186\134\227\128\140%s\227\128\141', stationId, nx.t) }
  end
  if kind == 'release' then nx.holdOn = false; return { ok = true } end
  local r = K.pressStep(s, sl)
  return { ok = true, done = r.done, step = r.step }
end

-- 玩家动作：点手册起杯（关掉自动出票后才有用）
function G.startCup(recId)
  local rec = R.byId(recId)
  if not rec then return { ok = false, why = '\230\178\161\230\156\137\232\191\153\228\184\170\228\186\167\229\147\129' } end
  local okk, why = K.startCup(G.s, rec)
  return { ok = okk, why = why }
end

-- 表现层在结算页按"继续"时调
function G.nextDay()
  if not G.s then return end
  if G.s.ended then return end
  D.nextDay(G.s)
  G.emit('daystart', { day = G.s.day })
end

return G

  end)()
  if __c_game == nil then __c_game = true end
  return __c_game
end
__m_host = function()
  if __c_host ~= nil then return __c_host end
  __c_host = (function()
-- host.lua —— 脚本与"千星客户端控件"打交道的那一层
--
-- 职责：**只做"怎么把控件建出来、怎么找到模板"，不管"画什么"**。
-- 从 hello.lua（M0 的验证脚本）里提炼出来的，那些能力都在真机上验过：
--   · 双空间扫描控件模板索引（真机索引是大数字，形如 1073741855）
--   · 解析图片素材号（脚本变量 artImage > ART 表 > 在画布里借一张配好图的控件）
--   · 隐藏"没配图的图片控件"（引擎会给它画一个"?"）
--   · 拿画布尺寸、拿挂载根控件
--
-- 真机契约（别改回去）：
--   ① `game.InstantiateClientUIControl` 在 **OnInit 阶段返回 nil** → 建控件必须在 OnStart 及之后
--   ② 不调 `script:EnableUpdate(true)` 就**收不到 OnUpdate**
--   ③ `game` 的全局函数用**点号**调用（冒号会多传隐式 game 实参）
--   ④ 运行期只改属性，不新建/销毁（模板子节点不能动态创建）→ 一律控件池

local H = {}

-- ── 日志：不依赖控件的通道（诊断必须走 print）──
local function fmt(f, ...)
  if type(f) ~= 'string' then return tostring(f) end
  local args, ai, out = { ... }, 1, {}
  local i = 1
  while true do
    local s, e = string.find(f, '%%[-+ #0]*%d*%.?%d*[sdf]', i)
    if not s then out[#out + 1] = string.sub(f, i); break end
    out[#out + 1] = string.sub(f, i, s - 1)
    local v = args[ai]; ai = ai + 1
    out[#out + 1] = (v == nil) and '(nil)' or tostring(v)
    i = e + 1
  end
  return table.concat(out)
end
function H.fmt(...) return fmt(...) end
function H.say(tag, ...)
  local ok, line = pcall(fmt, ...)
  if not ok then line = tostring((...)) end
  if print then pcall(print, '[' .. tostring(tag or '\233\155\170\231\154\135') .. '] ' .. line) end
end

function H.param(name, dflt)
  local v = script and script:GetParam(name)
  if v == nil then return dflt end
  return v
end

-- ★ 图片素材号（资产号）：和"控件模板索引"是两套数字，别混
--   用户 2026-09-26 从编辑器里点出来的编号
H.ART = {
  box      = 100001,   -- 基本方形（底衬通用：工位底板 / 打包台 / 进度条 / 卡片底；可拉伸不糊）
  roundbox = 100182,   -- 圆角方形（只用于接近正方形的场合；拉长会糊）
  mark     = 100122,   -- ⚠ 标识
  back     = 100109,   -- 返回箭头
  info     = 100115,   -- 详情 i 图标
}

-- ── 画布 ──
function H.canvas()
  local w, h = game.GetUICanvasSize()
  return w or 1280, h or 720
end

-- 挂载根控件：脚本挂在客户端控件容器上，子控件就挂在它这棵树上
function H.root()
  local r = script and script.object
  if r then return r end
  local rs = game.GetClientUIRoots()
  return rs and rs[1]
end

-- ── 控件类型判定（typeof 返回运行时类型名）──
function H.kindOf(c)
  if not c or not typeof then return '' end
  local ok, t = pcall(typeof, c)
  if not ok or not t then return '' end
  return tostring(t)
end
function H.isImage(c) return H.kindOf(c):find('Image', 1, true) ~= nil end
function H.isText(c) return H.kindOf(c):find('TextBox', 1, true) ~= nil end
function H.isCursor(c) return H.kindOf(c):find('Cursor', 1, true) ~= nil end
function H.isContainer(c) return H.kindOf(c):find('Container', 1, true) ~= nil end

-- ── 模板索引自动识别 ──
--   真机的控件模板索引是**大数字**（和关卡目录同一个 ID 空间，形如 1073741855）。
--   只扫 1~32 是错的（zuma 和我都为这个白查过一轮）。
local BASE = 1073741824                 -- 2^30
local SMALL_MAX, BIG_MAX = 32, 1023

-- 试着用某个索引建一个控件；建出来就按类型归类并**立刻销毁**（探针不占控件预算）
local function tryPrefab(idx, found, parent)
  local ok, c = pcall(game.InstantiateClientUIControl, idx, parent)
  if not ok or not c then return nil end
  local t = H.kindOf(c)
  if DestroyClientUIControl then pcall(DestroyClientUIControl, c) end
  if t:find('Image', 1, true) and not found.img then found.img = idx end
  if t:find('TextBox', 1, true) and not found.text then found.text = idx end
  if t:find('Cursor', 1, true) and not found.cursor then found.cursor = idx end
  if t:find('Container', 1, true) and not found.panel then found.panel = idx end
  return t
end

-- 返回 { img=?, text=?, cursor=?, panel=? }
function H.detectPrefabs(parent)
  local found, probe = {}, {}
  for i = 1, SMALL_MAX do
    local t = tryPrefab(i, found, parent)
    if t and t ~= '' then probe[#probe + 1] = i .. '=' .. t end
  end
  if not (found.img and found.text) then
    for i = BASE + 1, BASE + BIG_MAX do
      local t = tryPrefab(i, found, parent)
      if t and t ~= '' and #probe < 12 then probe[#probe + 1] = i .. '=' .. t end
      if found.img and found.text and found.cursor then break end
    end
  end
  H.probeLog = probe
  return found
end

-- ── 在画布里"借"一个素材号（用户只要在画布里摆一张配好图的控件，脚本就能拿到号）──
function H.adoptImageId(root)
  local found, seen = {}, {}
  local function walk(ctrl, depth)
    if not ctrl or depth > 4 or seen[ctrl] then return end
    seen[ctrl] = true
    local ok, kids = pcall(function() return ctrl:GetChildren() end)
    if not ok or type(kids) ~= 'table' then return end
    for i = 1, #kids do
      local ch = kids[i]
      local id = nil
      pcall(function() id = ch.imageId end)
      -- 只认正整数：0 = 没配图（真机/模拟器都这么给），捡了 0 等于没设 → 全画成"?"
      if type(id) == 'number' and id > 0 and H.isImage(ch) then
        found[#found + 1] = { id = id, name = tostring(ch.name), t = H.kindOf(ch) }
      end
      walk(ch, depth + 1)
    end
  end
  walk(root, 0)
  local up = root
  for _ = 1, 3 do
    if not up then break end
    -- ★ `parent` 是**字段**（官方注解：`---@field parent ClientUIBaseControl # 父控件`）。
    --   我原来写的是 `up:GetParent()` —— 官方注解里**没有这个方法**，真机上会被 pcall 吞掉，
    --   于是"往上几层找配好图的控件"整段静默失效。本地模拟器恰好有这个方法，所以本地看着是好的。
    local ok, p = pcall(function() return up.parent end)
    up = ok and p or nil
    walk(up, 0)
  end
  local okr, roots = pcall(game.GetClientUIRoots)
  if okr and type(roots) == 'table' then for i = 1, #roots do walk(roots[i], 0) end end
  return found
end

-- ── 隐藏"没配图的图片控件"（引擎会给它画一个"?"，而它不在我们控制之内）──
--   只关没配图的；用户在编辑器里刻意配好图的不动。
function H.hideBlankImages(root, quiet)
  local hidden = 0
  local function walk(c, depth)
    if not c or depth > 3 then return end
    local ok, kids = pcall(function() return c:GetChildren() end)
    if not ok or type(kids) ~= 'table' then return end
    for i = 1, #kids do
      local k = kids[i]
      if H.isImage(k) then
        local id = nil
        pcall(function() id = k.imageId end)
        if id == nil or id == 0 then
          pcall(function() k:SetVisible(false) end)
          local ok2 = pcall(function() k:SetActive(false) end)
          if ok2 then hidden = hidden + 1 end
        end
      end
      walk(k, depth + 1)
    end
  end
  walk(root, 0)
  if not quiet and hidden > 0 then H.say('host', '\233\154\144\232\151\143\228\186\134 %s \228\184\170\230\178\161\233\133\141\229\155\190\231\154\132\229\155\190\231\137\135\230\142\167\228\187\182\239\188\136\229\174\131\228\187\172\228\188\154\232\162\171\231\148\187\230\136\144"?"\239\188\137', hidden) end
  return hidden
end

-- ── 一次性初始化：模板索引 + 素材号 + 枚举 ──
--   返回 hostCfg：{ img=索引, text=索引, cursor=索引, panel=索引, art=素材号, src=图片来源 }
function H.setup(root)
  local cfg = {}
  cfg.root = root
  cfg.canvasW, cfg.canvasH = H.canvas()

  local w, h = cfg.canvasW, cfg.canvasH
  H.say('host', 'BUILD=%s canvas=%sx%s', 'xuehuang-core', tostring(w), tostring(h))

  -- ★★ 挂载点（客户端控件容器）：**只激活，不要动它的尺寸！**
  --   我原来无条件 `root:SetSizeDelta(画布宽, 画布高)`（抄 zuma 的"容器 0x0 会被裁掉"经验），
  --   但用户的容器是**锚点拉满式**布局（Min(0,0) / Max(1,1) / 中心(0.5,0.5)，1600x900 居中），
  --   对锚点拉满的控件强行改 sizeDelta 会触发重新布局 → **整块 UI 被推歪**
  --   （用户截图里 UI 偏右偏上、订单栏被切，就是这个造成的）。
  --   现在只在"容器小得离谱"时才补尺寸，正常情况一个字都不碰。
  pcall(function() root:SetActive(true) end)
  do
    local cw, ch = nil, nil
    pcall(function() cw, ch = root:GetSizeDelta() end)
    if type(cw) ~= 'number' or cw < 8 or type(ch) ~= 'number' or ch < 8 then
      local ok, err = pcall(function() root:SetSizeDelta(w, h) end)
      H.say('host', '\229\174\185\229\153\168\229\176\186\229\175\184\232\191\135\229\176\143\239\188\136%sx%s\239\188\137\226\134\146 \229\133\156\229\186\149\232\174\190\228\184\186 %sx%s -> %s',
            tostring(cw), tostring(ch), tostring(w), tostring(h), ok and 'ok' or tostring(err))
    else
      H.say('host', '\229\174\185\229\153\168\229\176\186\229\175\184\230\173\163\229\184\184\239\188\136%sx%s\239\188\137\226\134\146 \228\184\141\229\138\168\229\174\131\239\188\136\233\148\154\231\130\185\230\139\137\230\187\161\231\154\132\229\174\185\229\153\168\230\148\185\228\186\134\228\188\154\230\142\168\230\173\170\230\149\180\229\157\151 UI\239\188\137',
            tostring(cw), tostring(ch))
    end
  end
  -- ★★ 光标常驻（官方 API：ContainerControl.showCursor "是否显示常驻光标；
  --   **CursorEvent 相关方法都需设置该参数为真后才可正常使用**"）。
  --   不设它，玩家要**按住 Alt** 才看得见光标。编辑器里等价开关：容器节点控件 → 功能设置 → 显示常驻光标。
  do
    local ok, err = pcall(function() root.showCursor = true end)
    H.say('host', '\230\152\190\231\164\186\229\184\184\233\169\187\229\133\137\230\160\135 showCursor=true -> %s%s', ok and 'ok' or '\229\164\177\232\180\165\239\188\154', ok and '' or tostring(err))
  end

  -- ★★ 屏蔽"输入穿透到角色"（用户反馈：**鼠标点击会让角色攻击**；按键也会传给角色）
  --   官方 ContainerControl 的两个字段（原话）：
  --     · disableKeyEventPassthrough    "是否屏蔽按键事件穿透"
  --     · disableCursorEventPassthrough "是否屏蔽区域内点击事件穿透"
  --   设成 true 后：在容器范围内按的键/点的鼠标**只给 UI**，不会再触发角色的攻击/技能。
  --   这是"UI 抢输入"的正解 —— 不设的话，玩家边点工位边砍空气。
  --   编辑器里的等价开关：容器节点控件 → 功能设置 → 屏蔽按键/点击事件穿透。
  do
    local ok1, e1 = pcall(function() root.disableKeyEventPassthrough = true end)
    local ok2, e2 = pcall(function() root.disableCursorEventPassthrough = true end)
    H.say('host', '\229\177\143\232\148\189\232\190\147\229\133\165\231\169\191\233\128\143\239\188\154\230\140\137\233\148\174=%s%s  \231\130\185\229\135\187=%s%s',
      ok1 and 'ok' or '\229\164\177\232\180\165(', ok1 and '' or tostring(e1),
      ok2 and 'ok' or '\229\164\177\232\180\165(', ok2 and '' or tostring(e2))
  end
  -- 手柄导航隔离（避免摇杆在 UI 控件间乱跳；UI 里我们只用键鼠）
  do
    local ok, err = pcall(function() root.isolateNavigation = true end)
    H.say('host', '\233\154\148\231\166\187\230\137\139\230\159\132\229\175\188\232\136\170 isolateNavigation=true -> %s%s', ok and 'ok' or '\229\164\177\232\180\165\239\188\154', ok and '' or tostring(err))
  end

  -- textStyle=1：允许脚本覆盖字号/颜色（默认不覆盖，用模板里配好的样式）
  H.forceTextStyle = tonumber(tostring(H.param('textStyle', 0))) ~= 0
  H.say('host', '\230\150\135\229\173\151\230\160\183\229\188\143\239\188\154%s', H.forceTextStyle and '\232\132\154\230\156\172\232\166\134\231\155\150\229\173\151\229\143\183/\233\162\156\232\137\178' or '\231\148\168\230\168\161\230\157\191\233\187\152\232\174\164\239\188\136\228\184\141\232\166\134\231\155\150\239\188\137')

  do -- __SPACE：把挂载控件的真实位置/尺寸打进日志（坐标系的原点就在这里）
    local info = H.probeSpace(root)
    cfg.spaceW = (type(info.cw) == 'number' and info.cw > 1) and info.cw or nil
    cfg.spaceH = (type(info.ch) == 'number' and info.ch > 1) and info.ch or nil
    cfg.spaceX, cfg.spaceY = info.cx, info.cy
    H.say('host', '__SPACE space=%sx%s at (%s,%s)',
          tostring(cfg.spaceW), tostring(cfg.spaceH), tostring(cfg.spaceX), tostring(cfg.spaceY))
    for i = 1, #info.parents do H.say('host', '__SPACE %s', info.parents[i]) end
  end

  local auto = tonumber(tostring(H.param('autoPrefabs', 1))) ~= 0
  local found = auto and H.detectPrefabs(root) or {}
  cfg.img    = H.param('imgPrefab', found.img)
  cfg.text   = H.param('textPrefab', found.text)
  cfg.cursor = H.param('cursorPrefab', found.cursor)
  cfg.panel  = H.param('panelPrefab', found.panel)
  H.say('host', '\232\135\170\229\138\168\232\174\164\230\168\161\230\157\191\239\188\154img=%s text=%s cursor=%s panel=%s\239\188\136\230\142\167\228\187\182\230\168\161\230\157\191\231\180\162\229\188\149\239\188\1401073741xxx \233\130\163\228\184\178\239\188\137',
        tostring(found.img), tostring(found.text), tostring(found.cursor), tostring(found.panel))
  if not cfg.img or not cfg.text then
    error('\230\178\161\232\174\164\229\135\186\229\191\133\233\156\128\231\154\132\230\142\167\228\187\182\230\168\161\230\157\191\239\188\136img/text\239\188\137\227\128\130\232\175\183\229\156\168\227\128\144\231\149\140\233\157\162\230\142\167\228\187\182\231\187\132\231\174\161\231\144\134 \226\134\146 \231\149\140\233\157\162\230\142\167\228\187\182\231\187\132\229\186\147 \226\134\146 \229\174\162\230\136\183\231\171\175\230\142\167\228\187\182\230\168\161\230\157\191 \226\134\146 '
      .. '\230\183\187\229\138\160\229\174\162\230\136\183\231\171\175\230\142\167\228\187\182 \226\134\146 \229\173\152\228\184\186\230\168\161\230\157\191\227\128\145\233\135\140\229\187\186"\229\155\190\231\137\135\230\142\167\228\187\182"\229\146\140"\230\150\135\230\156\172\230\161\134\230\142\167\228\187\182"\239\188\140\230\136\150\229\156\168\232\132\154\230\156\172\229\143\152\233\135\143\233\135\140\229\161\171 imgPrefab/textPrefab\227\128\130'
      .. '\239\188\136\231\156\159\230\156\186\231\180\162\229\188\149\230\152\175\229\164\167\230\149\176\229\173\151\239\188\140\229\189\162\229\166\130 1073741855\239\188\137')
  end

  -- 图片类型：Basic 按原图尺寸画（会显得小），Stretch 铺满控件
  local okE, e = pcall(function() return Enum.ImageType.Stretch end)
  cfg.imageTypeStretch = (okE and e) or nil
  local okE2, e2 = pcall(function() return Enum.ImageType.Basic end)
  cfg.imageTypeBasic = (okE2 and e2) or nil

  -- 素材号：脚本变量 > ART 表 > 在画布里借
  -- ★ 素材号可覆盖：脚本变量 artImage
  --     artImage=0        → **完全不贴图**（控件只填色；排查"深色小块是不是图片"用）
  --     artImage=100181   → 换别的素材号
  --     不填              → 用内置 ART.box
  local artRaw = tostring(H.param('artImage', ''))
  local artVar = tonumber(artRaw)
  if artRaw ~= '' and artVar == 0 then
    cfg.art, cfg.artSrc = nil, '\232\132\154\230\156\172\229\143\152\233\135\143 artImage=0\239\188\136\228\184\141\232\180\180\229\155\190\239\188\140\229\143\170\229\161\171\232\137\178\239\188\137'
  elseif artVar then
    cfg.art, cfg.artSrc = artVar, '\232\132\154\230\156\172\229\143\152\233\135\143 artImage=' .. artRaw
  else
    cfg.art, cfg.artSrc = H.ART.box, '\229\134\133\231\189\174 ART\239\188\136\229\159\186\230\156\172\230\150\185\229\189\162 ' .. tostring(H.ART.box) .. '\239\188\137'
  end
  local cand = H.adoptImageId(root)
  cfg.borrowed = cand
  if #cand > 0 then
    H.say('host', '\231\148\187\229\184\131\233\135\140\233\133\141\229\165\189\229\155\190\231\154\132\230\142\167\228\187\182\239\188\154%s\239\188\136\231\180\160\230\157\144\229\143\183 %s\239\188\137', tostring(cand[1].name), tostring(cand[1].id))
  end
  H.say('host', '\231\148\168\231\180\160\230\157\144\229\143\183 = %s\239\188\136\230\157\165\230\186\144\239\188\154%s\239\188\137', tostring(cfg.art), tostring(cfg.artSrc))

  H.hideBlankImages(root, true)
  return cfg
end

-- ── 量出挂载控件的真实位置/尺寸（★★ 关键：坐标系的原点是**挂载控件的中心**，
--   而不是画布中心！用户截图证实：容器在画布右侧、还是竖长的，
--   于是我按"画布中心为原点"算的所有坐标整体偏右偏上，右侧订单栏还被切掉。
--   所以必须先问清楚"我这个父控件到底占哪儿"。──
function H.probeSpace(root)
  local info = { cw = nil, ch = nil, cx = nil, cy = nil, parents = {} }
  pcall(function() info.cw, info.ch = root:GetSizeDelta() end)
  pcall(function() info.cx, info.cy = root:GetAnchoredPosition() end)
  -- 往上找几层，看有没有更大的容器（挂载点可能不是根）
  local up, depth = root, 0
  while up and depth < 4 do
    local w, h, x, y, nm = nil, nil, nil, nil, nil
    pcall(function() w, h = up:GetSizeDelta() end)
    pcall(function() x, y = up:GetAnchoredPosition() end)
    pcall(function() nm = tostring(up.name) end)
    info.parents[#info.parents + 1] = string.format('L%s name=%s pos=(%s,%s) size=(%s,%s)',
      tostring(depth), tostring(nm), tostring(x), tostring(y), tostring(w), tostring(h))
    local ok, par = pcall(function() return up.parent end)
    up = ok and par or nil
    depth = depth + 1
  end
  return info
end

-- ── 建一个控件（运行期只调属性；不要每帧建/销毁）──
--   cfg：H.setup 的返回值；kind：'img' | 'text'
function H.spawn(cfg, kind, name)
  local idx = (kind == 'text') and cfg.text or cfg.img
  local c = game.InstantiateClientUIControl(idx, cfg.root)
  if not c then error('\229\187\186\230\142\167\228\187\182\229\164\177\232\180\165\239\188\154kind=' .. tostring(kind) .. ' \231\180\162\229\188\149=' .. tostring(idx)) end
  -- ★★ 新建控件**默认 active=false**（实测：建完不显式激活的话，真实状态就是 active=false，
  --   即使你从没隐藏过它）。曾经 H.spawn 里只写了一句 c:SetActive(true)，被静默吞掉 →
  --   整个 UI 只有图片/少量控件可见，表现是"进去啥都没有"。
  --   所以这里**双重设置 + 回读**，确保新建的控件一定是激活的。
  pcall(function() c:SetActive(true) end)
  pcall(function() c:SetVisible(true) end)
  do
    local a = nil
    pcall(function() a = c.active end)
    if a ~= true then
      pcall(function() c.active = true end)          -- 有的绑定支持直接写字段
      pcall(function() c:SetActive(true) end)
    end
  end
  if name then pcall(function() c.name = name end) end
  if kind ~= 'text' and cfg.art then
    local ok = pcall(function() c:SetImage(Enum.ImageSource.StaticReference, cfg.art) end)
    if ok and cfg.imageTypeStretch then pcall(function() c.imageType = cfg.imageTypeStretch end) end
  end
  if kind == 'text' then
    -- ★★ 文本框模板自带**不透明背景色**（`bgColor`），不关掉的话每个文字后面都会拖一个
    --   深色小方块 —— 用户看到的"四个深色小块"就是这个（我原以为文本框是透明的）。
    --   设成全透明，字才能直接落在工位方块上。
    pcall(function() c.bgColor = Color.FromRGBA(0, 0, 0, 0) end)
    -- ★★ 对齐必须**显式设置**！官方注解里文本框的 horizontalAlignment / verticalAlignment
    --   是读写字段，但**默认值取决于编辑器里那个模板控件**（模拟器里默认就是 nil）。
    --   模板若是"垂直靠上/水平靠左"，我按"居中"算的位置就会把文字推出控件框 → 完全看不见。
    --   （这就是"HUD 文字不显示、但工位文字正常"的根源：两者只是模板默认对齐的表现不同。）
    pcall(function() c.horizontalAlignment = Enum.TextHorizontalAlignment.Middle end)
    pcall(function() c.verticalAlignment = Enum.TextVerticalAlignment.Middle end)
    -- ★★ 描边要关掉：模板里默认是**开着**的（我在 studio 快照里读到 enableOutline=true），
    --   描边会把字往外扩几个像素 → 框高刚好等于字号时就被裁掉。我不需要描边。
    pcall(function() c.enableOutline = false end)
  end
  return c
end

-- ── 绘制小工具：一个"带边色的区块" ──
--   平台没有"描边"字段，边框只能自己画：底 + 一条细色条（色条比底更亮/更饱和）。
--   这是原神式 UI 的关键做法 —— 深底 + 小面积亮色，而不是大色块铺满。
--   edge：'top' | 'left' | 'bottom' | nil（无边框）
function H.spawnBox(cfg, name, x, y, w, h, bg, edge, edgeCol, edgeThick)
  local box = H.spawn(cfg, 'img', name)
  H.setPos(box, x, y); H.setSize(box, w, h)
  if bg then H.setColor(box, bg[1], bg[2], bg[3], bg[4] or 255) end
  local strip = nil
  if edge and edgeCol then
    local t = edgeThick or 5
    local sw, sh, sx, sy = w, t, x, y
    if edge == 'top' then sy = y + h / 2 - t / 2
    elseif edge == 'bottom' then sy = y - h / 2 + t / 2
    elseif edge == 'left' then sw, sh = t, h; sx = x - w / 2 + t / 2; sy = y
    elseif edge == 'right' then sw, sh = t, h; sx = x + w / 2 - t / 2; sy = y
    end
    strip = H.spawn(cfg, 'img', name .. '_edge')
    H.setPos(strip, sx, sy); H.setSize(strip, sw, sh)
    H.setColor(strip, edgeCol[1], edgeCol[2], edgeCol[3], edgeCol[4] or 255)
  end
  return box, strip
end

-- 隐藏一个区块（底 + 它的边条）
function H.hideBox(box, strip, ...)
  H.hide(box); H.hide(strip)
  for _, extra in ipairs({ ... }) do H.hide(extra) end
end

-- ── 给文本控件"按字号配够尺寸" ──
--   ★★ 这是"HUD 文字不显示"的真凶修复：
--     我把 HUD 标题的框高写成 34px，而字号是 24（模板还开着描边）→ 字被裁掉。
--     工位文字能显示，只是因为它们的框子（56px 配 15 号字）留了余量。
--   规则：**框高 >= 字号 × 2**（留出描边/行距/渲染误差的余量）。
function H.fitText(c, size, w)
  if not c then return c end
  size = math.floor((tonumber(size) or 20) + 0.5)
  local h = size * 2
  if h < 24 then h = 24 end
  pcall(function() c:SetSizeDelta(w or (size * 12), h) end)
  pcall(function() c.fontSize = size end)
  return c
end

-- 改属性的小工具（一律 pcall 包住：某个字段在某个控件上不支持时不要炸整帧）
function H.setPos(c, x, y)
  if c then pcall(function() c:SetAnchoredPosition(x, y) end) end
  return c
end
function H.setSize(c, w, h)
  if c then pcall(function() c:SetSizeDelta(w, h) end) end
  return c
end
function H.setColor(c, r, g, b, a)
  if c then
    pcall(function() c.imageColor = Color.FromRGBA(r, g, b, a or 255) end)
  end
  return c
end
function H.setText(c, s)
  if c then pcall(function() c.text = tostring(s) end) end
  return c
end
-- ★★ 文字样式：**默认什么都不设**，用文本框模板里编辑器配好的字号/颜色。
--   为什么要这样（真机教训）：我原来每帧都写 fontSize + fontColor，而这两个字段都是
--   "Tweenable"（带补间），在真机上用脚本反复赋值有可能把模板里配好的样式覆盖成看不见的状态 ——
--   表现就是"方框（图片控件）都正常、一个字的都不显示"。
--   需要覆盖时用脚本变量 textStyle=1 打开（那时才写 fontSize/fontColor）。
function H.setFont(c, size, r, g, b, a)
  if not c then return c end
  -- ★ 真机拒绝**非整数**字号（新版模拟器会直接报错：integer expected）。
  --   我们的字号理论上都是整数，但"乘过缩放"之后就可能是 23.56 这种 —— 一律取整。
  if type(size) == 'number' then size = math.floor(size + 0.5) end
  if not H.forceTextStyle then return c end
  pcall(function() c.fontSize = size end)
  if r then pcall(function() c.fontColor = Color.FromRGBA(r, g, b, a or 255) end) end
  return c
end
-- 文字控件的"用颜色显隐"：把 fontColor 的 alpha 设 0/255
--   ★★ 为什么不用 SetActive：实测对某批控件 SetActive(true) 被**无声吞掉**
--      （H.show 回读 true，控件实际 false）→ 菜单大字死活不显示。
--      而 `Color.FromRGBA` 的 alpha 一直是可靠的（bgColor 设透明就在用），
--      所以这里用 alpha 做显隐兜底：反正文字不显示时也不占视觉。
function H.setAlpha(c, a)
  if not c then return end
  local rgb = c.__rgb                       -- 自定义字段挂不上控件，用 host 侧的表记
  local base = H._colorOf and H._colorOf[c] or nil
  if not base then
    -- 没有记录过颜色：就地读一次（读不到就用白色）
    local r, g, b = 255, 255, 255
    pcall(function()
      local col = c.fontColor
      if col then r, g, b = col.R, col.G, col.B end
    end)
    base = { r, g, b }
  end
  pcall(function() c.fontColor = Color.FromRGBA(base[1], base[2], base[3], a or 255) end)
end

-- 记住颜色（setFont/setStyle 时调），供 setAlpha 恢复用
H._colorOf = {}
function H.rememberColor(c, rgb)
  if c and rgb then H._colorOf[c] = { rgb[1], rgb[2], rgb[3] } end
end

-- 显示/隐藏控件
--   ★★ 血泪教训（实测复现，probe 结论）：
--      ① 用 `SetActive(false)` 隐藏过的控件，之后 `SetActive(true)` **回不来**（会锁死）
--      ② 顺序也很讲究：`SetVisible(true)` 之后紧跟 `SetActive(true)`，**visible 会被回滚成 false**
--         （probe: hide>false show>false set>true act=true —— 单独 SetVisible 能亮，
--          放在 H.show 里就不行）
--      ⇒ 最终口径：**显示时只动 visible；隐藏时只动 visible**。永远不碰 active=false。
--        新建控件本来就 active=true（H.spawn 里已确保），所以够用。
function H.show(c, on)
  if not c then return end
  if on then
    pcall(function() c.active = true end)
    pcall(function() c:SetVisible(true) end)
  else
    pcall(function() c:SetVisible(false) end)
  end
end
-- ★ 隐藏：**只**设 visible=false（可逆）；绝不下 active=false
H.hide = function(c)
  if not c then return end
  pcall(function() c:SetVisible(false) end)
end

-- 颜色快捷（RGB）
function H.rgb(r, g, b, a) return Color.FromRGBA(r, g, b, a or 255) end

return H

  end)()
  if __c_host == nil then __c_host = true end
  return __c_host
end
__m_input = function()
  if __c_input ~= nil then return __c_input end
  __c_input = (function()
-- ═══════════════════════════════════════════════════════════════════════════
-- input.lua —— 输入层（**重写版 v2** 2026-09-27）
--
-- 血泪教训（真机日志实测，别改回去）：
--   ① **鼠标一直正常、按键一直不生效** ⇒ 两者用**不同的注册机制**：
--        鼠标 → 挂在「光标检测区域」控件上的 AddCursorEventListener
--        按键 → AddKeyEventListener（挂在哪很关键）
--      ⇒ 现在**两个控件都挂**（光标检测区域 + 容器根节点），日志里能看到各自绑了几条。
--   ② 键回调**直接派发**，不走队列：真机上出现过 [key] 有 123 条而 [act] 是 0 的情况
--      （回调与 OnUpdate 不共享队列表）。
--   ③ 一个动作一个键，**没有候选/去重/推断**（旧版多键候选导致同键双绑、主键错位）。
--   ④ 判据一律用 **ASCII 日志**（真机中文会乱码）：[key] / [act] / [REJECT] / [LOGIC]。
-- ═══════════════════════════════════════════════════════════════════════════

local H = __m_host()
local IN = {}

-- ── 物理键 → 千星"奇匠按键 N"编号（取自官方注解的"默认物理键"）────────────
IN.K = {
  ['1'] = 1,  ['2'] = 2,  ['3'] = 3,  ['4'] = 4,  ['5'] = 5,
  ['6'] = 6,  ['7'] = 7,  ['8'] = 8,  ['9'] = 9,  ['0'] = 10,
  ['U'] = 11, ['Z'] = 12, ['Y'] = 13, ['G'] = 14, ['H'] = 15, ['I'] = 16,
  ['O'] = 17, ['P'] = 18, ['J'] = 19, ['K'] = 20, ['L'] = 21, ['V'] = 22,
  ['F5'] = 23, ['F6'] = 24, ['F7'] = 25, ['F8'] = 26, ['F9'] = 27, ['F10'] = 28,
  [','] = 33, ['.'] = 34, ['/'] = 35,
  ['SPACE'] = 'JUMP',      -- 空格（跳跃键，不是奇匠按键）
}

-- ★★ 出餐（打包）必须有**两个**可用输入，理由见 BIND 表里 pack/pack2 的注释：
--   空格在千星里是"跳跃/滑翔"（KeyboardJumpKeyDown），可能被世界系统先吃掉；
--   Z 是奇匠按键12（默认物理键 Z），一定收得到。
IN.PACK_KEYS = { 'SPACE', 'Z' }

-- ── 绑定表（唯一真相：一个动作一个键）────────────────────────────────────
--   原版（网页版 1718~1726 行）的命名原则：**取工位名的动作字**，不取屏幕位置 ——
--      捣 / 火 / 化 / 泡 各一个键，键位跟着活儿走。
--   ⚠️ 平台约束（官方注解 Enum.KeyEventType，lua/types/mihoyo_client_ui_api.d.lua:331-495）：
--      千星**没有 B / C / R 这三个键**（奇匠按键只有 1-10、U Z Y G H I O P J K L V、F5-F10、
--      标点、42=Backspace、43=CapsLock；另有通用键 Space/F/E/Q/R/T/X/Tab/WASD/Ctrl）。
--      所以物理键无法与网页版逐个相同；这里保住**语义**（四个工位各一键、与原版一一对应）：
--        捣锤=Y（原版 B）· 火系=H（原版 H，相同）· 化学=K（原版 C）· 萃茶=P（原版 P，相同）
--      编辑器里可以把这几个奇匠按键的物理键改成 B/C，Lua 侧不用动。
--   ⚠️ 开关：原版是 Esc 暂停 / A 自动流转 / S 自动出小票，平台没有这三个语义键，
--      按用户拍板：**营业中** 1 / 2 / 3 = 自动流转 / 自动出票 / 暂停。
--      菜单态同一个 1/2/3 是"选模式"（见 xuehuang.lua 的 uiAct）——
--      和原版"1~8 只在关掉自动出票后才有用"是同一类"按键随场景换语义"。
IN.BIND = {
  { act = 'shake',   key = 'Y',         label = '\230\141\163\233\148\164' },
  { act = 'fire',    key = 'H',         label = '\231\129\171\231\179\187' },
  { act = 'chem',    key = 'K',         label = '\229\140\150\229\173\166' },
  { act = 'brew',    key = 'P',         label = '\232\144\131\232\140\182' },
  { act = 'pack',    key = 'SPACE',     label = '\230\137\147\229\140\133' },
  -- ★★ 出餐备用键（2026-09-27 真机日志逼出来的）：那次运行玩家按了 23 次键，
  --   **空格一次都没按过**，而咖啡早已做完只等出餐 → 看起来就是"卡住了"。
  --   空格在千星是"跳跃/滑翔"（KeyboardJumpKeyDown），可能被世界系统先吃掉，
  --   所以出餐**不能只挂在空格上**：再绑一个奇匠按键 Z（按键12）。
  --   语义与 pack 完全一致（入口把 pack2 归一成 pack）。
  { act = 'pack2',   key = 'Z',         label = '\230\137\147\229\140\133\239\188\136\229\164\135\231\148\168\233\148\174\239\188\137' },
  { act = 'mode1',   key = '1',         label = '\232\143\156\229\141\1491 / \232\135\170\229\138\168\230\181\129\232\189\172' },
  { act = 'mode2',   key = '2',         label = '\232\143\156\229\141\1492 / \232\135\170\229\138\168\229\135\186\231\165\168' },
  { act = 'mode3',   key = '3',         label = '\232\143\156\229\141\1493 / \230\154\130\229\129\156' },
  { act = 'confirm', key = 'BACKSPACE', label = '\231\161\174\232\174\164' },
}

-- ── 状态 ────────────────────────────────────────────────────────────────
IN.primary = {}
IN.bound = {}
IN.down = {}
IN.stats = {}
IN.clicked = nil
IN.MODES = { 'quick', 'fast', 'slow' }
IN.frameDt = 0.033
IN.keys = IN.down

-- ── 内部：取/存全局（回调与主体可能不共享 _ENV）──────────────────────────
local function G() return _G or _ENV end
local function getAct() local g = G(); return g and g.__IN_ACT end

-- ── 派发辅助：有回调就直呼，没有就排队（pump 下一帧消费）──────────────
local function dispatch(act, kind)
  local g = G()
  local fn = g and g.__IN_ACT
  if kind == 'press' then
    IN.down[act] = true
  elseif kind == 'release' then
    IN.down[act] = nil
  end
  IN.stats[act] = (IN.stats[act] or 0) + 1
  if print then pcall(print, '[act] ' .. tostring(act) .. ' ' .. tostring(kind)) end
  if fn then
    local ok, err = pcall(fn, act, kind)
    if not ok and print then pcall(print, '[act] \230\180\190\229\143\145\229\135\186\233\148\153: ' .. tostring(err)) end
  else
    IN.queue[#IN.queue + 1] = { act = act, kind = kind }
  end
end

IN.queue = {}

function IN.clearInput()
  for k in pairs(IN.queue) do IN.queue[k] = nil end
  for k in pairs(IN.down) do IN.down[k] = nil end
  IN.clicked = nil
end

-- ── 枚举名 ──────────────────────────────────────────────────────────────
local function enumOf(keyName)
  local n = IN.K[keyName]
  if n == 'JUMP' then return 'KeyboardJumpKeyDown' end
  if type(n) == 'number' then return 'KeyboardCraftspersonKey' .. n .. 'Down' end
  return nil
end

-- ── 找光标检测区域 ──────────────────────────────────────────────────────
local function findCursorArea(c, depth)
  if not c or depth > 4 then return nil end
  if H.kindOf(c):find('Cursor', 1, true) then return c end
  local ok, kids = pcall(function() return c:GetChildren() end)
  if ok and type(kids) == 'table' then
    for i = 1, #kids do
      local r = findCursorArea(kids[i], depth + 1)
      if r then return r end
    end
  end
  return nil
end
IN.findArea = function(root) return findCursorArea(root, 0) end

-- ══════════════════════════════════════════════════════════════════════════
-- attach：绑定按键（双挂）+ 光标
-- ══════════════════════════════════════════════════════════════════════════
function IN.attach(cfg, tip)
  local root = cfg and cfg.root
  if not root then H.say('input', '\230\178\161\230\156\137\230\140\130\232\189\189\230\142\167\228\187\182\239\188\140\232\190\147\229\133\165\228\184\141\229\143\175\231\148\168'); return 0 end

  local override = {
    shake = H.param('keyShake', ''), fire = H.param('keyFire', ''),
    chem = H.param('keyChem', ''), brew = H.param('keyBrew', ''),
    pack = H.param('keyPack', ''),
  }

  -- 绑定目标：**光标检测区域 + 容器根节点都挂**（真机上鼠标那条路是好的，键也挂同一控件上试）
  local area = findCursorArea(root, 0)
  local targets = {}
  if area then targets[#targets + 1] = { name = 'area', c = area } end
  targets[#targets + 1] = { name = 'root', c = root }
  IN.targets = targets

  -- ★★ 真机钥匙探针（ASCII，2026-09-27 r2）：唯一能一刀切开的判据
  --   背景：移植侧一直只打印"绑定成功"（[bind]），**从没在按键回调里打过日志**，
  --   所以"按键到底有没有进来"从来没有真机证据（本地模拟器与真机可能不同）。
  --   判据：
  --     ① 日志出现 [KTARGET] → 监听挂在哪些控件上一目了然（以及容器 active/visible）
  --     ② 按一下键，日志里出现**恰好一行** [KDOWN X] → 事件路径通，锅在动作分发
  --     ③ 按一下键，[KDOWN] 连成一片（每帧一行）→ 真机**按住就每帧回调**，
  --        必须用"边沿触发"（只在 false→true 的那一帧派发），否则等于一直按着
  --     ④ 一行都没有 → 事件根本没进来 → 查容器 active/visible、脚本是否真导入
  IN.keyCount = { area = 0, root = 0 }
  function IN.logKey(on)
    IN.keyLog = (on ~= false)
  end
  local function kl(fmt, ...)
    if IN.keyLog == false then return end
    if print then pcall(print, string.format(fmt, ...)) end
  end
  IN.kl = kl
  do
    local w, h = '?', '?'
    pcall(function() w, h = cfg.spaceW or '?', cfg.spaceH or '?' end)
    local a, v2, nm = '?', '?', '?'
    pcall(function()
      a = tostring(root.active); v2 = tostring(root.visible); nm = tostring(root.name)
    end)
    kl('[KTARGET] root=%s active=%s visible=%s \231\155\145\229\144\172\230\140\130\231\130\185=%d \229\133\137\230\160\135\229\140\186=%s canvas=%sx%s',
      nm, a, v2, #targets, area and '\230\156\137' or '\230\151\160', tostring(w), tostring(h))
    for _, tg in ipairs(targets) do
      local ta, tv, tn = '?', '?', '?'
      pcall(function() ta = tostring(tg.c.active); tv = tostring(tg.c.visible); tn = tostring(tg.c.name) end)
      kl('[KTARGET]   %s name=%s active=%s visible=%s', tg.name, tn, ta, tv)
    end
  end

  local function bindOne(act, keyName)
    local evName = enumOf(keyName)
    if not evName then
      H.say('input', '  \233\148\174 %s \228\184\141\232\174\164\232\175\134\239\188\136\229\138\168\228\189\156 %s \232\183\179\232\191\135\239\188\137', tostring(keyName), tostring(act))
      return false
    end
    local okE, ev = pcall(function() return Enum.KeyEventType[evName] end)
    if not okE or ev == nil then
      H.say('input', '  \228\186\139\228\187\182 %s \228\184\141\229\173\152\229\156\168\239\188\136\229\138\168\228\189\156 %s \232\183\179\232\191\135\239\188\137', tostring(evName), tostring(act))
      return false
    end
    local upName = string.gsub(evName, 'KeyDown$', 'KeyUp')
    local okU, evU = pcall(function() return Enum.KeyEventType[upName] end)
    if not okU then evU = nil end

    local bound = 0
    for _, tg in ipairs(targets) do
      local okD = pcall(function()
        tg.c:AddKeyEventListener(ev, function()
          IN.keyCount[tg.name] = (IN.keyCount[tg.name] or 0) + 1
          kl('[KDOWN %s] %s <- %s (\231\172\172 %d \230\172\161)',
            tostring(tg.name), tostring(act), tostring(keyName), IN.keyCount[tg.name])
          dispatch(act, 'press')
          return true
        end)
      end)
      if okD then bound = bound + 1 end
      if evU ~= nil then
        pcall(function()
          tg.c:AddKeyEventListener(evU, function()
            kl('[KUP %s] %s <- %s', tostring(tg.name), tostring(act), tostring(keyName))
            dispatch(act, 'release')
            return true
          end)
        end)
      end
    end
    if print then pcall(print, string.format('[bind] %s=%s \230\140\130\229\136\176 %d \228\184\170\230\142\167\228\187\182', tostring(act), tostring(keyName), bound)) end
    if bound > 0 then
      IN.bound[#IN.bound + 1] = act .. '=' .. keyName
      return true
    end
    return false
  end

  local used, n = {}, 0
  for _, b in ipairs(IN.BIND) do
    local keyName = b.key
    local ov = override[b.act]
    if ov and ov ~= '' then keyName = string.upper(tostring(ov)) end
    if used[keyName] then
      H.say('input', '  \233\148\174 %s \229\156\168\231\187\145\229\174\154\232\161\168\233\135\140\233\135\141\229\164\141\239\188\136\229\138\168\228\189\156 %s\239\188\137\226\134\146 \232\183\179\232\191\135', tostring(keyName), tostring(b.act))
    else
      used[keyName] = true
      if bindOne(b.act, keyName) then
        IN.primary[b.act] = keyName
        n = n + 1
      end
    end
  end

  H.say('input', '\229\183\178\231\187\145\229\174\154 %d \228\184\170\233\148\174\239\188\136\231\155\174\230\160\135 %d \228\184\170\230\142\167\228\187\182\239\188\137\239\188\154%s', n, #targets, table.concat(IN.bound, ' '))
  local show = {}
  for _, b in ipairs(IN.BIND) do
    if IN.primary[b.act] then show[#show + 1] = b.act .. '=' .. IN.primary[b.act] end
  end
  H.say('input', '\233\148\174\228\189\141\239\188\154%s', table.concat(show, ' '))

  -- ── 光标点击 ──
  if area then
    pcall(function() area:SetSizeDelta(cfg.spaceW or 1920, cfg.spaceH or 1080) end)
    local okL = pcall(function()
      area:AddCursorEventListener(Enum.CursorEventType.CursorClick, function()
        local okp, gx, gy = pcall(game.GetCursorUIPos)
        if okp and type(gx) == 'number' and type(gy) == 'number' then
          IN.clicked = { x = gx, y = gy }
          if print then pcall(print, string.format('[key] click %.0f %.0f', gx, gy)) end
          dispatch('click', 'press')
        end
      end)
    end)
    H.say('input', '\229\133\137\230\160\135\229\140\186\229\183\178\233\147\186\230\187\161 %sx%s \231\155\145\229\144\172=%s', tostring(cfg.spaceW), tostring(cfg.spaceH), okL and 'ok' or '\229\164\177\232\180\165')
  else
    H.say('input', '\230\142\167\228\187\182\230\160\145\233\135\140\230\178\161\230\156\137"\229\133\137\230\160\135\230\163\128\230\181\139\229\140\186\229\159\159" \226\134\146 \233\188\160\230\160\135\231\130\185\229\135\187\228\184\141\229\143\175\231\148\168')
  end
  return n
end

-- ══════════════════════════════════════════════════════════════════════════
-- pump：每帧调用。把 act 回调发布到全局（键回调直呼它）+ 消费排队事件
-- ══════════════════════════════════════════════════════════════════════════
function IN.pump(handlers)
  local g = G()
  if g then g.__IN_ACT = handlers and handlers.act or nil end
  IN.frame = (IN.frame or 0) + 1

  -- 消费排队事件（回调已经在派发时这里通常是空的；留给"早于 pump 到达"的事件）
  if #IN.queue > 0 then
    local q = {}
    for i = 1, #IN.queue do q[i] = IN.queue[i] end
    for i = #IN.queue, 1, -1 do IN.queue[i] = nil end
    for i = 1, #q do
      local e = q[i]
      if handlers and handlers.act then handlers.act(e.act, e.kind) end
    end
  end

  -- ★★ **不再每帧补发**（2026-09-27 真机教训）：
  --   旧版对"按着的工位键"每帧重发一次 press。而真机上 KeyUp 可能送不到
  --   → IN.down[act] 永不清除 → **每帧都重按** → 日志刷屏、表现错乱、玩家看到"没变化"。
  --   现在所有步骤都是"一次输入即完成"，无需补发。
  --   （保留 IN.down 只是给"是否按着"的查询用，不驱动任何派发。）
end

-- ══════════════════════════════════════════════════════════════════════════
-- 命中测试（鼠标点工位卡）
--   实测：GetCursorUIPos 的 y 向下为正；控件 anchoredPosition 的 y 向上为正
--   ⇒ cy 用 H/2 - clicked.y 翻转方向
-- ══════════════════════════════════════════════════════════════════════════
function IN.hit(v, ctrl, pad)
  if not IN.clicked or not ctrl or not v then return false end
  pad = pad or 0
  local cx = IN.clicked.x - (v.W or 0) / 2
  local cy = (v.H or 0) / 2 - IN.clicked.y
  local ok, x, y, w, h = pcall(function()
    return ctrl.anchoredPositionX, ctrl.anchoredPositionY, ctrl.sizeDeltaX, ctrl.sizeDeltaY
  end)
  if not ok or type(x) ~= 'number' then return false end
  return cx >= x - w / 2 - pad and cx <= x + w / 2 + pad
     and cy >= y - h / 2 - pad and cy <= y + h / 2 + pad
end

function IN.clearClick() IN.clicked = nil end

return IN

  end)()
  if __c_input == nil then __c_input = true end
  return __c_input
end
__m_kitchen = function()
  if __c_kitchen ~= nil then return __c_kitchen end
  __c_kitchen = (function()
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

local CFG = __m_config()
local R = __m_recipes()
local S = __m_state()
local O = __m_order()

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
      print('[CAP] \229\133\156\229\186\149\228\187\141\230\156\170\230\148\182\230\149\155 used=' .. tostring(w) .. ' pool=' .. tostring(#pool) .. ' CAP=' .. tostring(CAP))
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
  if cup.done then return false, '\232\191\153\230\157\175\229\183\178\231\187\143\228\186\164\228\187\152\228\186\134' end
  local nx = S.nextStep(cup)
  if not nx and not sl.ready then return false, '\232\191\153\230\157\175\230\178\161\230\156\137\228\184\139\228\184\128\230\173\165\228\186\134' end
  -- 没拿到名额的杯**先不许开工**（例外：下一步是"不占名额的纯手感步骤"，那种不占人手）
  if cup.startedAt == nil and not cup.slotReady and not (nx and nx.noSlot) then
    return false, string.format('\229\144\142\229\142\168\229\183\178\231\187\143 %d \228\184\170\228\187\187\229\138\161\229\156\168\229\136\182\228\186\134\239\188\140\232\191\153\229\188\160\231\165\168\229\133\136\230\142\146\233\152\159\239\188\136\231\173\137\228\184\128\228\184\170\229\144\141\233\162\157\232\133\190\229\135\186\230\157\165\239\188\137', CFG.kitchen.maxWip)
  end
  if sl.ready and stationId ~= 'pack' then return false, '\232\191\153\230\157\175\229\183\178\231\187\143\229\129\154\229\174\140\228\186\134\239\188\140\233\128\129\230\137\147\229\140\133\229\143\176' end
  local dst = sl.ready and 'pack' or (nx and nx.st)
  if not dst then return false, '\230\178\161\230\156\137\228\184\139\228\184\128\230\173\165\228\186\134' end
  if stationId and stationId ~= dst then
    return false, string.format('\227\128\140%s\227\128\141\232\191\153\228\184\128\230\173\165\232\175\165\229\142\187 %s', nx and nx.t or '\229\135\186\233\164\144', dst)
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
    nx.holdOn = true                      -- 按住：进度交给 tickHolds 每帧累积
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
    return false, '\232\191\153\230\157\175\232\191\152\230\178\161\229\129\154\229\174\140\239\188\140\228\184\141\232\131\189\228\186\164\231\187\153\229\174\162\228\186\186\239\188\136\231\165\168\229\183\178\233\128\128\229\155\158\239\188\137'
  end
  if cup.done then                            -- 已经交过了：清掉这张僵尸票
    for i = #s.slips, 1, -1 do if s.slips[i] == sl then table.remove(s.slips, i) end end
    return false, '\232\191\153\230\157\175\229\183\178\231\187\143\228\186\164\232\191\135\228\186\134\239\188\140\230\184\133\230\142\137\232\191\153\229\188\160\231\165\168'
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
  if not s or not sl then return false, '\230\178\161\230\156\137\232\191\153\229\188\160\231\165\168' end
  if sl.cup and sl.cup.done then return false, '\232\191\153\230\157\175\229\183\178\231\187\143\228\186\164\228\187\152\228\186\134' end
  if sl.st == 'pack' and sl.ready then return false, '\229\183\178\231\187\143\229\156\168\230\137\147\229\140\133\229\143\176\228\186\134' end
  local nx = S.nextStep(sl.cup)
  if not sl.ready and not nx then
    if sl.cup.made then sl.ready = true else return false, '\230\178\161\230\156\137\228\184\139\228\184\128\230\173\165\228\186\134' end
  end
  local dst = sl.ready and 'pack' or (nx and nx.st)
  if not dst then return false, '\230\178\161\230\156\137\228\184\139\228\184\128\230\173\165\228\186\134' end
  if sl.st == dst then return false, '\229\174\131\229\183\178\231\187\143\229\156\168\232\191\153\228\184\170\229\183\165\228\189\141\228\186\134' end
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
          if slipFor(s, c) then return true, '\232\191\153\228\184\128\230\157\175\229\183\178\231\187\143\230\156\137\231\165\168\228\186\134' end
          local sl = makeSlip(s, o, c)
          local ok = K.routeSlip(s, sl, nx and nx.st)
          if not ok then
            for i = #s.slips, 1, -1 do if s.slips[i] == sl then table.remove(s.slips, i) end end
          end
          return ok, ok and '\229\176\143\231\165\168\229\183\178\230\140\130\229\136\176\229\183\165\228\189\141' or '\230\140\130\228\184\141\228\184\138'
        end
      end
    end
  end
  -- 分清"没人点"和"没名额"
  for _, o in ipairs(s.orders) do
    if o.status ~= 'done' then
      for _, c in ipairs(o.cups) do
        if not c.made and c.rec.id == rec.id then
          return false, string.format('\227\128\140%s\227\128\141\232\191\153\228\184\128\230\157\175\232\191\152\230\178\161\230\139\191\229\136\176\229\144\141\233\162\157\239\188\136\229\144\142\229\142\168\229\144\140\230\151\182\229\143\170\232\131\189 %d \228\184\170\228\187\187\229\138\161\229\156\168\229\136\182\239\188\137',
                                      rec.name, CFG.kitchen.maxWip)
        end
      end
    end
  end
  return false, string.format('\231\142\176\229\156\168\230\178\161\228\186\186\231\130\185\227\128\140%s\227\128\141\226\128\148\226\128\148\230\142\165\229\141\149\228\186\134\229\134\141\229\129\154', rec.name)
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

  end)()
  if __c_kitchen == nil then __c_kitchen = true end
  return __c_kitchen
end
__m_order = function()
  if __c_order ~= nil then return __c_order end
  __c_order = (function()
-- order.lua —— 点单（混点生成 + 耐心）
--
-- 三条从网页版搬来的硬规则（每条都是玩家反馈换来的）：
--   ① 一单可以同款多杯，也可以多种不同（"顾客可以点同一种点多杯，也可以点多种不同的"）
--   ② **不把两个重活放同一单**（干冰 + 另一个重活 = 二十多下连按，那是惩罚不是玩法）
--   ③ 耐心按**这一单点了几杯**给（杯数越多越愿意等），并且**每做完一杯回补一点**
--      —— 因为"全做完一起交"会让客人等更久，进度本身就是补偿

local CFG = __m_config()
local R = __m_recipes()
local S = __m_state()

local O = {}

-- 抽签用的随机源：**可以注入**（测试要可复现，所以不直接调 math.random）
--   默认用 math.random；测试里换成确定性序列
local rng = function() return math.random() end
function O.setRng(fn) rng = fn end

local function pickWeighted(tbl)
  return R.pickWeighted(tbl, rng())
end
local function pickUniform(list)
  return list[math.min(#list, math.floor(rng() * #list) + 1)]
end

-- 生成"这一单要哪几杯什么"：返回 lines = { { rec = 配方, n = 杯数 }, ... }
--   cupN 总杯数；重活不与重活同单
function O.drinkPlan(cupN)
  local pool = R.list
  if cupN <= 1 then
    return { { rec = pickUniform(pool), n = cupN } }
  end
  -- 混不混：2 杯一半概率，3 杯以上多半会混
  local mixed = rng() < (cupN == 2 and CFG.mix.mixedChance2 or CFG.mix.mixedChance3)
  if not mixed then
    return { { rec = pickUniform(pool), n = cupN } }
  end
  local kinds = 2
  if cupN >= 3 and rng() < 0.5 then kinds = 3 end
  kinds = math.min(kinds, cupN, #pool)

  local lines, left = {}, cupN
  for i = 1, kinds do
    local rest = kinds - i
    -- 候选：没用过的配方
    local cand = {}
    for _, r in ipairs(pool) do
      local used = false
      for _, l in ipairs(lines) do if l.rec.id == r.id then used = true end end
      if not used then cand[#cand + 1] = r end
    end
    -- ① 第一项优先选**非重活**（避免"重活 + 重活"）
    if i == 1 then
      local light = {}
      for _, r in ipairs(cand) do if not r.heavy then light[#light + 1] = r end end
      if #light > 0 then cand = light end
    end
    -- ② 后面几项也尽量避开重活（只要还有非重活可选）
    if i > 1 then
      local light = {}
      for _, r in ipairs(cand) do if not r.heavy then light[#light + 1] = r end end
      if #light > 0 then cand = light end
    end
    if #cand == 0 then cand = pool end
    local rec = pickUniform(cand)
    -- 给后面几项至少各留 1 杯
    local maxN = left - rest
    local n
    if i == kinds then n = left
    else n = math.max(1, math.min(maxN, 1 + math.floor(rng() * math.max(1, maxN)))) end
    lines[#lines + 1] = { rec = rec, n = n }
    left = left - n
  end
  -- 兜底：万一算法把杯数算漏了，全补到最后一项（宁可名字难看，也不能少杯）
  local sum = 0
  for _, l in ipairs(lines) do sum = sum + l.n end
  if sum < cupN then lines[#lines].n = lines[#lines].n + (cupN - sum) end
  return lines
end

-- 生成一张订单
function O.spawn(s)
  local cupN = pickWeighted(CFG.cups).n
  local lines = O.drinkPlan(cupN)
  local ice = pickWeighted(CFG.ice).v
  local sugar = pickWeighted(CFG.sugar).v
  local P = CFG.patience
  -- 耐心：按杯数给 + 个体差异
  local pat = math.max(P.min, P.base + cupN * P.perCup) * (1 + (rng() * 2 - 1) * P.jitter)
  s.oid = s.oid + 1
  local o = {
    id = s.oid, name = O.pickName(), rec = lines[1].rec, lines = lines,
    ice = ice, sugar = sugar,
    cups = {}, need = cupN, pat = pat, patMax = pat,
    made = 0, delivered = 0, status = 'wait',
    inProgress = false, priority = false, queueNo = 0,
    patBonus = 0, born = s.t,
  }
  local i = 0
  for _, line in ipairs(lines) do
    for _ = 1, line.n do
      i = i + 1
      local steps = {}
      for _, st in ipairs(line.rec.steps) do
        steps[#steps + 1] = { st = st.st, t = st.t, kind = st.kind, taps = st.taps,
                              noSlot = st.noSlot, ok = false, done = 0 }
      end
      o.cups[#o.cups + 1] = { made = false,
        i = i, rec = line.rec, steps = steps, done = false, served = false,
        err = false, startedAt = nil, finishedAt = nil, slotReady = false,
      }
    end
  end
  local names = {}
  for _, line in ipairs(lines) do names[#names + 1] = line.n .. '\195\151' .. line.rec.name end
  o.makeup = table.concat(names, ' + ')
  s.orders[#s.orders + 1] = o
  return o
end

O.NAMES = { '\233\154\148\229\163\129\232\128\129\231\142\139', '\233\155\170\231\154\135\230\156\172\229\176\138', '\230\159\160\230\170\172\231\178\190', '\229\185\178\229\134\176\231\136\177\229\165\189\232\128\133', '\228\184\141\229\150\157\229\134\176\231\154\132\233\152\191\229\167\168', '\231\137\169\231\144\134\231\179\187\229\173\166\229\188\159',
            '\231\137\155\233\161\191\230\156\172\228\186\186', '\229\144\142\229\142\168\229\174\158\228\185\160\231\148\159', '\230\140\145\229\137\148\231\154\132\231\190\142\233\163\159\229\174\182', '\229\138\160\231\143\173\229\136\176\229\135\140\230\153\168\231\154\132\228\186\186', '\228\184\128\230\157\175\229\176\177\229\128\146', '\229\155\155\230\157\175\230\137\147\229\140\133' }
function O.pickName() return pickUniform(O.NAMES) end

-- 做完一杯：记账 + **给客人续一点耐心**（续的量与这杯的工序量挂钩）
--
-- ★★ 杯子有三个状态，别混（我第一版把 done 既当"做完"又当"放上托盘"，结果整局交不掉单）：
--     cup.steps 全 ok  = 这一步做完了
--     cup.made   = true = **这杯真的做完了**（可以放托盘 / 直接交付）
--     cup.done   = true = **这杯已经交给客人了**（结单计数用这个）
--   `o.made` 统计的是 "做完" 的杯数；`O.finish` 只在**全部交付**时调用。
function O.onCupMade(s, o, cup, served)
  o.made = 0
  for _, c in ipairs(o.cups) do if c.made then o.made = o.made + 1 end end
  if not served and o.status ~= 'done' then
    o.status = (o.made < o.need) and 'ready' or 'done'
  end
  local P = CFG.patience
  local load = 0
  for _, st in ipairs(cup.steps) do
    load = load + ((st.kind == 'mash') and (st.taps or 1) or 1)
  end
  local bonus = P.doneBonus + math.min(P.doneBonusMax, load * P.perStep)
  o.pat = math.min(o.patMax, o.pat + bonus)
  o.patBonus = o.patBonus + bonus
  return bonus
end

-- 整单交付的判定：**每一杯都交付了**才算整单完成（不是"做完了"）
function O.allDelivered(o)
  for _, c in ipairs(o.cups) do if not c.done then return false end end
  return true
end

-- 客人走了（耐心清零）：记流失并把它移除
function O.leave(s, o, wasWaiting)
  o.status = 'lost'
  s.left = s.left + 1
  s.today.left = s.today.left + 1
  if wasWaiting then s.leftWaiting = s.leftWaiting + 1 end
  s.combo = 0
  s.money = math.max(0, s.money - CFG.money.leavePenalty)
  s.score = math.max(0, s.score - CFG.score.leave)
  for i = #s.orders, 1, -1 do if s.orders[i] == o then table.remove(s.orders, i) end end
  -- 它的票也一起撤掉（否则会留下"没有主人的票"）
  for i = #s.slips, 1, -1 do if s.slips[i].o == o then table.remove(s.slips, i) end end
  return o
end

-- 整单交付结算：一次连击、一次评分
function O.finish(s, o, now)
  o.delivered = o.need
  o.status = 'done'
  local perfect = true
  local slowest = 0
  for _, c in ipairs(o.cups) do
    if c.err then perfect = false end
    local used = (c.finishedAt or now) - (c.startedAt or 0)
    if used > slowest then slowest = used end
  end
  local fast = slowest < 25
  if perfect then s.combo = s.combo + 1; s.maxCombo = math.max(s.maxCombo, s.combo)
  else s.combo = 0 end
  local tip = math.min(CFG.money.comboMax, s.combo * CFG.money.comboStep)
  local earn, sc = 0, 0
  for _, c in ipairs(o.cups) do
    earn = earn + CFG.money.perCup + math.floor(c.rec.price * 0.2)
      + (perfect and 4 or 0) + (fast and CFG.money.rushBonus or 0) + tip
    sc = sc + CFG.score.perCup + (perfect and 20 or 0)
      + (fast and CFG.score.rushBonus or 0) + s.combo * 2
  end
  if not perfect then earn = math.floor(earn * 0.5); sc = math.floor(sc * 0.7) end
  s.money = s.money + earn
  s.score = s.score + sc
  s.today.money = s.today.money + earn
  -- 已"做完即出"的杯已经单独记过 served，不重复计
  local already = 0
  for _, c in ipairs(o.cups) do if c.served then already = already + 1 end end
  local addCups = o.need - already
  s.served = s.served + addCups
  s.today.served = s.today.served + addCups
  for i = #s.orders, 1, -1 do if s.orders[i] == o then table.remove(s.orders, i) end end
  return { earn = earn, score = sc, perfect = perfect, fast = fast, tip = tip, cups = addCups }
end

return O

  end)()
  if __c_order == nil then __c_order = true end
  return __c_order
end
__m_recipes = function()
  if __c_recipes ~= nil then return __c_recipes end
  __c_recipes = (function()
-- recipes.lua —— 产品表（配方 + 手法 + 出餐方式）
--
-- 每一步写三件事：
--   st   工位（shake 捣 / fire 火 / chem 化 / brew 泡 / pack 打包）
--   t    这一步的文案（会显示在按钮和手册上，写清"做什么"，别写"点这里"）
--   kind 手法：tap 一下 ／ mash 连按 N 下 ／ hold 按住
-- 缺省 kind 由 taps 推断：
--   有 taps（且 >1）→ mash；否则 tap。
-- ★ 手法要**混着来**：全是连按会很累，全是一下又没手感。
--
-- 特殊标记：
--   serveNow = 做完即出（不进打包台，最后一步收口时直接交给客人）
--   noSlot   = 这一步**不占后厨名额**（纯手感步骤，例如速溶咖啡的拆包）
--             意义：一杯 3 步的咖啡不该和一杯十几下连按的干冰抢同一个名额
--   heavy    = 重活（混点时不把两个重活放同一单）

local recipes = {}

-- ── 工位 id（逻辑层只认这四个 + pack）──
recipes.STATIONS = { 'shake', 'fire', 'chem', 'brew', 'pack' }

local list = {
  {
    id = 'dryice', name = '\229\185\178\229\134\176\229\185\178\230\159\160\230\170\172\230\176\180', tag = '\229\134\176', price = 30, diff = 2, source = '\229\174\152\230\150\185',
    heavy = true,   -- 重活：十几下连按
    steps = {
      { st = 'brew',  t = '\230\148\190\229\133\165\229\185\178\230\159\160\230\170\172\231\137\135', kind = 'tap' },
      { st = 'brew',  t = '\229\138\160\230\176\180\232\135\179\228\184\131\229\136\134\230\187\161', kind = 'tap' },
      { st = 'shake', t = '\229\143\140\230\137\139\230\143\161\228\189\143\230\157\175\229\173\144', kind = 'hold' },
      { st = 'shake', t = '\229\191\171\233\128\159\229\142\139\231\188\169\229\134\133\233\131\168\231\169\186\230\176\148\232\135\179 25000 \229\141\131\229\184\149', kind = 'mash', taps = 6 },
      { st = 'shake', t = '\231\187\167\231\187\173\229\142\139\231\188\169\239\188\140\231\155\180\232\135\179\229\135\186\231\142\176\229\155\186\230\128\129\229\185\178\229\134\176', kind = 'mash', taps = 6 },
      { st = 'pack',  t = '\229\176\129\230\157\175\229\135\186\233\164\144', kind = 'tap' },
    },
  },
  {
    -- ★ 恶搞产品：neta 现实里的「黑芝麻冰麒麟」（黑→白、冰→火、雪糕→辣甜筒）
    --   定位：快消品 —— 工序只有"掏枪筒 + 喷火"两件事，喷完直接递给客人，不进打包台
    --   它本质是**一支甜筒**，不是杯装饮料，所以没有封杯这回事
    --   ★ 第一步文案按用户要求改过：原来是「从枪筒里掏出甜筒」→ 现在直接「掏出枪筒」
    id = 'qilin', name = '\231\153\189\232\138\157\233\186\187\231\129\171\233\186\146\233\186\159', tag = '\231\148\156', price = 32, diff = 1, source = '\229\174\152\230\150\185',
    serveNow = true,
    steps = {
      { st = 'fire', t = '\230\142\143\229\135\186\230\158\170\231\173\146', kind = 'tap' },
      { st = 'fire', t = '\231\148\168\229\150\183\231\129\171\230\158\170\231\131\164\233\166\153\239\188\140\231\131\164\229\174\140\231\155\180\230\142\165\233\128\146\231\187\153\229\174\162\228\186\186\239\188\136\231\148\156\231\173\146\228\184\141\231\148\168\230\137\147\229\140\133\239\188\137', kind = 'hold' },
    },
  },
  {
    id = 'bromine', name = '\231\169\186\230\157\175\230\187\161\230\157\175\229\141\131\230\186\180\230\176\180', tag = '\230\186\180', price = 44, diff = 3, source = '\229\174\152\230\150\185',
    steps = {
      { st = 'chem',  t = '\231\148\168\233\135\143\231\173\146\229\143\150 10ml \230\186\180\230\176\180\229\142\159\230\182\178', kind = 'hold' },
      { st = 'chem',  t = '\229\138\160\230\187\161\231\169\186\230\157\175\232\135\179\230\187\161\230\157\175', kind = 'mash', taps = 5 },
      { st = 'shake', t = '\230\145\135\229\140\128\232\135\179\233\162\156\232\137\178\229\157\135\228\184\128', kind = 'mash', taps = 4 },
      { st = 'pack',  t = '\229\176\129\230\157\175\229\135\186\233\164\144', kind = 'tap' },
    },
  },
  {
    id = 'instcoffee', name = '\231\142\176\232\144\131\233\128\159\230\186\182\229\146\150\229\149\161', tag = '\229\146\150', price = 24, diff = 1, source = '\229\174\152\230\150\185',
    -- ★ 全 tap：这是"新手第一杯"，刻意不做连按/按住；前三步拆包也不占名额
    steps = {
      { st = 'brew', t = '\229\143\150\233\128\159\230\186\182\229\146\150\229\149\161\231\178\137', kind = 'tap', noSlot = true },
      { st = 'brew', t = '\230\148\190\229\133\165\229\146\150\229\149\161\230\156\186\231\178\137\231\162\151', kind = 'tap', noSlot = true },
      { st = 'brew', t = '\230\140\137\228\184\139\232\144\131\229\143\150\233\148\174', kind = 'tap', noSlot = true },
      { st = 'brew', t = '\230\179\168\229\133\165\231\131\173\230\176\180', kind = 'tap' },
      { st = 'pack', t = '\229\176\129\230\157\175\229\135\186\233\164\144', kind = 'tap' },
    },
  },
  {
    id = 'newton', name = '\231\137\155\233\161\191\232\139\185\230\158\156\229\165\182\231\187\191', tag = '\232\139\185', price = 34, diff = 2, source = '\229\174\152\230\150\185',
    steps = {
      { st = 'shake', t = '\230\138\138\232\139\185\230\158\156\231\160\184\232\191\155\230\157\175\229\173\144\233\135\140\239\188\136\233\135\141\229\138\155\229\138\160\233\128\159\229\186\166\232\175\183\232\135\170\232\161\140\232\132\145\232\161\165\239\188\137', kind = 'mash', taps = 4 },
      { st = 'brew',  t = '\230\179\168\229\133\165\231\187\191\232\140\182\230\177\164', kind = 'tap' },
      { st = 'chem',  t = '\229\138\160\229\133\165\229\165\182\231\178\190', kind = 'tap' },
      { st = 'brew',  t = '\230\179\168\229\133\165\231\137\155\229\165\182', kind = 'hold' },
      { st = 'pack',  t = '\229\176\129\230\157\175\229\135\186\233\164\144', kind = 'tap' },
    },
  },
  {
    id = 'peach', name = '\232\159\160\230\161\131\229\155\155\229\173\163\230\152\165', tag = '\230\161\131', price = 36, diff = 2, source = '\229\174\152\230\150\185',
    steps = {
      { st = 'brew',  t = '\230\179\168\229\133\165\229\155\155\229\173\163\230\152\165\232\140\182\230\177\164', kind = 'hold' },
      { st = 'fire',  t = '\231\130\153\231\131\164\230\157\175\229\143\163\239\188\136\231\131\164\229\135\186\231\132\166\231\179\150\233\166\153\239\188\137', kind = 'hold' },
      { st = 'shake', t = '\229\138\160\229\133\165\232\159\160\230\161\131\230\158\156\232\130\137\229\185\182\230\145\135\229\140\128', kind = 'mash', taps = 5 },
      { st = 'pack',  t = '\229\176\129\230\157\175\229\135\186\233\164\144', kind = 'tap' },
    },
  },
}

-- ── 规范化：给每一步补上 kind / taps / noSlot，并算出这杯的"工序量" ──
--   工序量 = 每步的成本之和（连按按次数算），用于：耐心回补量、评分里"重活"的判定
local TAPS = __m_config().taps
for _, r in ipairs(list) do
  local load = 0
  for i, s in ipairs(r.steps) do
    if not s.kind then s.kind = (s.taps and s.taps > 1) and 'mash' or 'tap' end
    if s.kind == 'mash' and not s.taps then
      -- 没写 taps 的连按：按配方难度取档（4/5/6 下）
      s.taps = TAPS[math.min(#TAPS, math.max(1, r.diff))]
    end
    if s.kind ~= 'mash' then s.taps = nil end
    s.noSlot = s.noSlot == true
    load = load + (s.kind == 'mash' and (s.taps or 1) or 1)
  end
  r.load = load
  -- 出餐方式：serveNow 的品最后一步自己就是交付点
  r.needsPack = not r.serveNow and r.steps[#r.steps].st == 'pack'
end

recipes.list = list

-- 按 id 取配方
function recipes.byId(id)
  for _, r in ipairs(list) do if r.id == id then return r end end
  return nil
end

-- 线性插值取加权随机项（加权查表：比概率累加快、也比它好读）
--   util 传 [0,1) 的随机数进来，方便测试复现
function recipes.pickWeighted(tbl, util)
  local total = 0
  for _, e in ipairs(tbl) do total = total + (e.p or 0) end
  local x = (util or 0) * total
  local acc = 0
  for _, e in ipairs(tbl) do
    acc = acc + (e.p or 0)
    if x < acc then return e end
  end
  return tbl[#tbl]
end

return recipes

  end)()
  if __c_recipes == nil then __c_recipes = true end
  return __c_recipes
end
__m_skin = function()
  if __c_skin ~= nil then return __c_skin end
  __c_skin = (function()
-- skin.lua —— 视觉层（唯一数值源）
--
-- ★★ 为什么单独一层：之前每加一个界面就随手写数（框高 34、字号 24、位置 -320…），
--   结果反复出现"字被裁""色块像塑料""间距不齐"，换风格要改十几个地方。
--   现在**所有尺寸/颜色/字号/间距/图标号只写在这里**（配套：雪皇-视觉规范.md），
--   `view.lua` 只负责"哪个数据放哪个位置"，不许出现魔法数字。
--
-- ★★ 视觉规则（用户逐轮定的，改动前先读）：
--   ① 有**整屏黑色打底**，UI 压在其上（不是"UI 直接压在游戏画面上"）
--   ② 按钮要**撑满可用空间**（左区 1391 / 纵向用到 824），不留大片空白
--   ③ 字号要**内敛**：不靠粗体、不靠透明度差拉层次
--   ④ **步骤**（该做什么）比**区域名**略大一档：step 28 > title 26
--   ⑤ 工位卡 = 【名称行 + 图标列】保留原色；**其余内容区加底衬**（方案 A）
--      底衬 = 卡片原色 **提亮 +40**（"浅半档"）—— ⚠️ 是**提亮**，不是压暗（压暗是我理解反了）
--      内容区与名称行之间有一条 **2px 半透明白分隔线**；底衬**固定铺满**，不跟字数伸缩
--      底衬底边**上收 radius(14)**，否则直角会切掉卡片圆角（实测出现过）

local H = __m_host()

local SK = {}

-- ══════════════════════════════════════════════════════════
-- 一、数值标记（唯一来源）
-- ══════════════════════════════════════════════════════════
SK.T = {
  -- 基准（真机画布 1815×900，≈2.02:1）
  designW = 1815, designH = 900,
  safe = 24,
  gap = { xs = 4, s = 8, m = 16, l = 24, xl = 32 },

  -- 字号阶梯（框高必须 >= 字号 × 1.6，否则字被裁 —— layout-lint 会查）
  font = { display = 32, step = 28, title = 26, head = 20, body = 16, small = 13, tiny = 11 },

  -- 控件尺寸
  --   横向 24 + 左列 380 + 16 + 中列 1032 + 16 + 右列 388 + 24 = 1880（= 真机画布宽）
  --   纵向 24 + 72 + 26 + 208 + 26 + 208 + 26 + 176 + 24 = 790
  size = {
    stationW = 508, stationH = 208,     -- 中列 2×2（1032 = 508*2 + 16）
    -- ★ 打包台从 176 收到 168：为下面的**小票行**（原版"点小票立刻送工位"的载体）腾地方。
    --   纵向 = 24 + 72 + 26 + 208 + 16 + 208 + 16 + 168 + 16 + 100 + 24 = 878 ≤ 900 ✓
    packW = 1032, packH = 168,
    -- ★★ 小票行（原版工位队列卡的等价物）：**点一下就送它去该去的工位**
    --   为什么必须有：真机日志 9085 条 [LOGIC] 里 8984 条 ok=false、
    --   9003 条 [REJECT] —— 根因就是票没被搬到工位，而玩家没有任何手动搬运手段。
    --   ⚠️ 尺寸教训：原来是"卡宽 200 × 6 列"塞进 380 宽的左列 → 可用宽算成负数，
    --      被兜底压成 56.7×80，看着像一堆小方块（probe-slips 抓出来的）。
    --      现在按**左列实际宽度**排：6 列 × 58 + 5 × 6.4 间隙 ≈ 380。
    slipH = 84, slipCols = 6, slipGap = 6,
    -- 左列
    colLW = 380, orderW = 348, orderH = 104,
    dataW = 380, dataH = 190,
    -- 右列
    colRW = 388, bookW = 388, bookH = 470, keysW = 388, keysH = 300,
    hudW = 1832, hudH = 72,
    panelW = 380, panelH = 560,
    iconS = 22, iconL = 30, iconBig = 80, iconMid = 64,
    barH = 8, edgeW = 6,
    nameRowH = 72,
    pad = 12,
    radius = 14,
    dividerH = 2,
  },

  -- 版式位置（设计坐标：原点在画布中心，y 向上）
  --   横向 24 + 1391 + 24 + 352 + 24 = 1815（正好填满真机画布宽）
  --   纵向 24 + 72 + 32 + 208 + 32 + 208 + 32 + 192 + 24 = 824
  at = {
    leftW = 1367,
    gapLR = 48,                                       -- 左区与订单面板之间的间隙
    leftX = -(1815 / 2) + 24 + 1367 / 2,              -- 左区中心 = -200
    -- ★ 左区左边缘 = 左区中心 - 左区宽/2
    --   ⚠️ 我第一版写成 `-((1815/2) - 24 - 1391)` = **507.5**（少减半个左区宽、符号也错）
    --      → 所有"相对左边缘"的控件整体右移 → 全跑到画布外。是 layout-lint 抓出来的。
    leftL = -(1815 / 2) + 24,

    hudY = 450 - 24 - 72 / 2,                        -- 354
    hudPad = 24,
    -- HUD 内部（相对左区左边缘）
    hudIconX = 30, hudTitleX = 54,
    hudClockX = 300, hudClockW = 180,
    -- 三项数据：图标 22 + 数字 46 + 说明 70 = 138，间距 190（不重叠）
    hudStatX = 544, hudStatGap = 190,
    hudTipW = 200, hudTipR = 28,

    panelL = (1815 / 2) - 24 - 352,                  -- 面板左边缘 528.5（设计坐标）
    panelY = 450 - 24 - 72 - 32 - (736 / 2),         -- 面板中心 y = -14
    panelHeadY = 736 / 2 - 36,                       -- 相对面板中心

    -- 订单卡（相对面板中心）
    orderTop = (736 / 2) - 64,                       -- 第一张卡的中心 y
    orderStep = 136 + 16,                            -- 卡高 + 间距
    orderInX = 16,                                   -- 卡内左内边距

    stationX = -(1815 / 2) + 24 + 672 / 2,
    stationX2 = -(1815 / 2) + 24 + 1367 - 672 / 2,
    stationY = 220, stationY2 = 220 - 208 - 32,
    packX = -(1815 / 2) + 24 + 1367 / 2,
    packY = 220 - 208 - 32 - 208 - 32 - 192 / 2,
  },

  -- 配色
  color = {
    shake = { 58, 122, 220 }, fire = { 232, 126, 52 },
    chem = { 158, 106, 224 }, brew = { 52, 176, 128 }, pack = { 40, 192, 176 },

    hudBg = { 14, 17, 26, 246 }, panelBg = { 24, 29, 46, 247 },
    cardBg = { 35, 43, 66 }, slotBg = { 18, 21, 31 },

    text = { 238, 243, 252 }, dim = { 176, 190, 216 }, gold = { 255, 214, 130 },
    good = { 122, 232, 160 }, warn = { 255, 196, 96 }, bad = { 255, 122, 132 },
    onColor = { 255, 255, 255 },
  },

  -- 图标素材号
  --   ★ 工位图标（用户逐个在编辑器素材库里找出来的，2026-09-27 定稿）
  --     素材库里**没有**雪克杯/烧瓶/量筒/茶壶这类"工具"图标，所以按**语义**选：
  icon = {
    -- 工位
    shake = 102004,   -- 冰元素 → 捣锤区（这区做的正是干冰："压缩至出现固态干冰"）
    fire  = 102002,   -- 火元素 → 火系区（喷火枪烤甜筒）
    chem  = 102015,   -- 护盾+雷 → 化学区（没有烧瓶/量筒，用雷元素顶上；"别的真没了"）
    brew  = 102041,   -- 壶/罐 → 萃茶区（泡茶/滤咖啡）；备选 102027（像咖啡滤网）
    pack  = 102028,   -- 装箱 → 打包台（封杯出餐）

    -- 通用功能
    ok = 100102, no = 100101, next = 100103, prev = 100104, back = 100109,
    plus = 100107, minus = 100108, info = 100115, ask = 100113, warn = 100122,
    play = 100181, pin = 100131, lock = 100132,
  },

  -- 底衬深度（规则 ⑤）：卡片原色 **提亮** 这个量。40 = "浅半档"
  --   ⚠️ 这是**加法提亮**，不是乘法压暗 —— 我曾在方向上搞反，用户明确指出"是低半档"。
  chipLift = 40,
  chipAlpha = 255,
  dividerCol = { 255, 255, 255, 51 },   -- 分隔线（半透明白 ~20%）
}

local T = SK.T

-- ══════════════════════════════════════════════════════════
-- ★★ 画布自适应（踩过大坑，务必看清）
--   问题：编辑器里那个「客户端控件容器」的锚点是 Min(0,0)/Max(1,1) → **跟着设备拉伸**，
--         而设备预设有一堆（16:9 / 21:9 / 19.5:9 / 4:3 …），宽高都不同。
--         我原来把坐标全按"画布中心 + 写死 1815 宽"算 →
--         ① 换设备整块 UI 左右漂移（用户截图：左边露黑边）
--         ② 宽画布上订单面板被挤出去，和工位卡重叠
--   做法：
--     · **尺寸只按高度缩放**（元件保持像素大小，不跟着宽度变胖）
--     · **左右分区各自锚边**：左区贴左边距、订单面板贴右边距 → 中间自动留空档
--       （宽画布多出来的空间落在中间，不会挤到面板，也不会溢出被切）
--   ⚠️ 只做一次（幂等），否则每帧乘一次会越缩越小。
function SK.fitCanvas(canvasW, canvasH)
  if SK._fitted then return SK._scale end
  local cw = tonumber(canvasW) or T.designW
  local ch = tonumber(canvasH) or T.designH
  if cw < 8 then cw = T.designW end
  if ch < 8 then ch = T.designH end
  SK._fitted = true
  SK._canvasW, SK._canvasH = cw, ch

  -- ① 尺寸与字号：**只按高度**缩放
  local s = ch / T.designH
  if s <= 0 then s = 1 end
  SK._scale = s
  local function scale(t)
    for k, val in pairs(t) do
      if type(val) == 'number' then t[k] = val * s
      elseif type(val) == 'table' then scale(val) end
    end
  end
  scale(T.size)
  scale(T.gap)
  for k, fsz in pairs(T.font) do
    local v = math.floor(fsz * s + 0.5)
    if v < 10 then v = 10 end
    T.font[k] = v
  end

  -- ② 位置：**按实际画布重算 —— 三列布局**（还原原版：左=等候区+营业数据 / 中=工位 / 右=产品手册+快捷键）
  --   横向：24 + 左列 380 + 间隙 16 + 中列 1032 + 间隙 16 + 右列 388 + 24 = 1880
  local m  = T.safe * (ch / T.designH)      -- 边距（按高度缩放）
  local gp = 16 * (ch / T.designH)          -- 列间隙
  local colLW = T.size.colLW
  local colRW = T.size.colRW
  local colL = -cw / 2 + m                            -- 左列左边缘（贴左）
  local colR = cw / 2 - m                             -- 右列右边缘（贴右）
  -- 中列 = 剩下的宽度（画布越宽，中列越宽）
  local midW = (colR - colRW - gp) - (colL + colLW + gp)
  if midW < 400 then midW = 400 end                    -- 画布太窄时保底
  -- 工位卡宽 = (中列 - 列间隙)/2
  local cardW = (midW - gp) / 2
  local cardH = T.size.stationH
  T.size.stationW = cardW
  T.size.packW    = midW
  T.size.hudW     = cw - 2 * m                       -- HUD 条：横跨三列，两侧留边距
  T.size.orderW   = colLW - 2 * gp
  T.size.orderH   = T.size.orderH
  T.size.panelW   = colRW

  local A = T.at
  -- 三列的中心 x
  A.colLC = colL + colLW / 2
  A.colRC = colR - colRW / 2
  A.midC  = colL + colLW + gp + midW / 2
  A.colLL = colL
  A.colRL = colR - colRW
  A.panelX = A.colLC
  A.midL  = colL + colLW + gp
  A.midW  = midW
  A.colLW = colLW
  A.colRW = colRW
  -- ★★ 小票行（左列底部，横跨整个左列）：位置与卡宽**只在这里算一次**
  --   锚点 = 打包台底部（packY 是中心，减半个卡高得到它的底边）
  A.slipRowY = A.packY - T.size.packH / 2 - gp - T.size.slipH / 2
  A.slipL = A.colLL
  -- 卡宽按左列可用宽均分（不留空、也不会压成负数）
  do
    local cols, gapS = T.size.slipCols, T.size.slipGap
    local avail = (T.size.colLW - gapS * (cols - 1)) / cols
    T.size.slipW = avail
    A.slipW = avail
    A.slipRowW = avail * cols + gapS * (cols - 1)
  end
  -- 纵向：HUD 贴顶 → 中列 2×2 工位 → 打包台
  A.hudX      = 0                                    -- HUD 居中（宽度已扣边距）
  A.hudY      = ch / 2 - m - T.size.hudH / 2
  local topY  = A.hudY - T.size.hudH / 2 - 26 * (ch / T.designH)   -- 第一行工位中心
  A.stationY  = topY - cardH / 2        -- 第一行工位中心
  A.stationY2 = A.stationY - cardH - gp -- 第二行工位中心
  A.packY     = A.stationY2 - cardH / 2 - gp - T.size.packH / 2
  A.stationX  = A.midL + cardW / 2
  A.stationX2 = A.midL + midW - cardW / 2
  A.packX     = A.midC
  -- 左列：等候区（贴列顶）+ 营业数据（在它下面）
  A.orderTop  = A.hudY - T.size.hudH / 2 - 26 * (ch / T.designH) - T.size.orderH / 2 - 30
  A.orderStep = T.size.orderH + 8 * (ch / T.designH)
  A.panelL    = A.colLL
  A.panelY    = A.orderTop - 5 * A.orderStep / 2 - 30               -- 等候区面板中心
  A.panelHeadY = 24 * (ch / T.designH)
  -- 左列两块：**从上往下顺序堆叠**（不再互相推导，避免任一处改动就伸出屏幕）
  --   内容顶 = HUD 底边 - 间隙；等候区紧贴其下；营业数据再接在等候区下面
  local contentTop = A.hudY - T.size.hudH / 2 - 26 * (ch / T.designH)
  A.panelY = contentTop - T.size.panelH / 2                      -- 等候区面板中心
  A.dataY  = contentTop - T.size.panelH - gp - T.size.dataH / 2  -- 营业数据面板中心
  -- 订单卡：第 1 张贴着面板顶（留出头高 56），往下排
  A.orderTop  = T.size.panelH / 2 - 56 - T.size.orderH / 2
  A.orderStep = T.size.orderH + 8 * (ch / T.designH)

  -- 右列：产品手册（上）+ 快捷键（下）
  A.bookY = A.hudY - T.size.hudH / 2 - 26 * (ch / T.designH) - T.size.bookH / 2
  A.keysY = A.bookY - T.size.bookH / 2 - gp - T.size.keysH / 2
  A.hudTitleX  = 54 * (ch / T.designH)
  A.hudClockX  = 300 * (ch / T.designH)
  A.hudStatX   = 560 * (ch / T.designH)
  A.hudStatGap = 172 * (ch / T.designH)
  A.hudTipW    = 260 * (ch / T.designH)
  A.hudTipR    = 28 * (ch / T.designH)
  A.orderInX   = 14 * (ch / T.designH)
  return s
end

SK._scale = 1
SK._fitted = false

-- ══════════════════════════════════════════════════════════
-- 二、颜色工具
-- ══════════════════════════════════════════════════════════

-- 内容区底衬的颜色：卡片原色 **提亮** chipLift（"浅半档"）
--   ⚠️ 方向别搞反：是提亮，不是压暗。
function SK.chip(col, d)
  d = d or T.chipLift
  return { math.min(255, col[1] + d), math.min(255, col[2] + d), math.min(255, col[3] + d), T.chipAlpha }
end

-- 压暗（备用：给"进度条槽"之类需要更暗的地方）
function SK.darken(col, k)
  k = k or 0.5
  return { math.floor(col[1] * k), math.floor(col[2] * k), math.floor(col[3] * k) }
end

-- 提亮（等价于 SK.chip，保留名字方便阅读）
function SK.lift(col, d)
  return SK.chip(col, d)
end

function SK.accent(id)
  return T.color[id] or T.color.text
end

-- ══════════════════════════════════════════════════════════
-- 三、绘图 helper
-- ══════════════════════════════════════════════════════════

-- 一块纯色矩形（真机没有原生圆角，靠素材号决定外观；这里统一用 100001 方形）
function SK.bg(cfg, name, x, y, w, h, col)
  local c = H.spawn(cfg, 'img', name)
  H.setPos(c, x, y); H.setSize(c, w, h)
  H.setColor(c, col[1], col[2], col[3], col[4] or 255)
  return c
end

-- 工位卡（方案 A）：名称行 + 图标列保留原色；其余整块加"同色系提亮"底衬
--   返回一张表（各内容元素的坐标），调用方往里填文字/图标/进度条
--   ⚠️ 底色**不做状态变色**（曾经"有活就提亮"和内容区提亮打架 → 颜色发花）
--
--   ★ 精致度（用户："边缘生硬、没层次、没有原版精致"）：引擎没有原生圆角/描边，
--     用**叠块**做层次 —— 原版 UI 的立体感就是这么来的：
--       ① 最外描边（底色压暗 0.72）→ 像"卡片有边框"
--       ② 卡片底（纯原色，比描边小 4px，于是露出一圈边）
--       ③ 顶部高光条（底色提亮 46，3px）→ 像"上缘受光"，立体感的关键
--       ④ 内容区提亮底衬 + 2px 分隔线
function SK.stationCard(cfg, name, x, y, col, active)
  local w = T.size.stationW
  local h = T.size.stationH
  local outline = SK.bg(cfg, name .. '_edge', x, y, w, h, SK.darken(col, 0.72))  -- ① 描边
  local card = SK.bg(cfg, name .. '_box', x, y, w - 4, h - 4, col)               -- ② 卡片
  local hi = SK.bg(cfg, name .. '_hi', x, y + h / 2 - 6, w - 12, 3, SK.chip(col, 46)) -- ③ 高光

  local iw = T.size.pad + T.size.iconBig + T.size.pad
  local x0 = x - w / 2
  local y0 = y + h / 2
  local dx = x0 + iw
  local dy = y0 - T.size.nameRowH
  local dw = w - iw
  local dh = h - T.size.nameRowH
  local ph = dh - T.size.radius
  local panel = SK.bg(cfg, name .. '_panel', dx + dw / 2, dy - ph / 2, dw - 2, ph, SK.chip(col))
  local divider = SK.bg(cfg, name .. '_line',
    dx + dw / 2, dy + T.size.dividerH / 2, dw - 2, T.size.dividerH, T.dividerCol)

  local t = {}
  t.box = card
  t.outline = outline
  t.hi = hi
  t.panel = panel
  t.divider = divider
  t.nameX = dx
  t.nameY = y0 - T.size.nameRowH / 2
  t.iconX = x0 + T.size.pad + T.size.iconBig / 2
  t.iconY = y
  t.stepX = dx + T.size.pad            -- ★ 左边界（SK.textL 收左边界）
  t.stepY = dy - 46                    -- 步骤文字所在的 y
  t.stepW = dw - T.size.pad * 2        -- 步骤文字框宽（= 进度条同宽，正好在内容区内）
  t.barX = dx + T.size.pad            -- ★ 左边界（SK.bar 收左边界）
  t.barY = y - h / 2 + T.size.pad + T.size.barH / 2
  t.barW = dw - T.size.pad * 2
  t.keyX = x + w / 2 - T.size.pad - 17
  t.keyY = y0 - T.size.nameRowH / 2
  return t
end

-- 文字：**自动按字号配足框高**（框高 = 字号 × 1.8）
--   ⚠️ 不许再手写矮框 —— 那是"HUD 文字不显示"的真凶，layout-lint 会查
--
--   ★★ 坐标口径（踩过坑，务必看清）：
--      真机把文字按**左对齐**画，所以"文字从框左边开始"。为了让**框位置 = 文字位置**：
--        `SK.textL(..., leftX, ...)`  → 把框的**左边缘**放在 leftX（框范围 leftX .. leftX+w）
--        `SK.textC(..., centerX, ...)` → 以 centerX 为**框中心**
--      我上一版把 leftX 当成了"框中心"（`H.setPos(c, leftX)`），
--      结果框整体左移半个宽度、伸出容器外（lint 报"顾客名出界"，真机也偏）。
function SK.textL(cfg, name, leftX, y, w, fontKey, col)
  local c = H.spawn(cfg, 'text', name)
  local size = T.font[fontKey] or fontKey or T.font.body
  H.setPos(c, leftX + w / 2, y)          -- 框中心 = 左边缘 + 半个宽
  H.fitText(c, size, w)
  if col then H.setFont(c, size, col[1], col[2], col[3]) end
  c.horizontalAlignment = Enum.TextHorizontalAlignment.Left
  return c
end

-- 居中：以 centerX 为框中心
function SK.textC(cfg, name, centerX, y, w, fontKey, col)
  return SK.textL(cfg, name, centerX - w / 2, y, w, fontKey, col)
end

-- 图标（图片控件 + SetImage 素材号）
function SK.icon(cfg, name, x, y, artId, size, col)
  local c = H.spawn(cfg, 'img', name)
  size = size or T.size.iconS
  H.setPos(c, x, y); H.setSize(c, size, size)
  if artId then pcall(function() c:SetImage(Enum.ImageSource.StaticReference, artId) end) end
  if col then H.setColor(c, col[1], col[2], col[3], 255) end
  return c
end

-- 进度条：槽 + 填充（固定高度）
--   ★★ 参数 `x` = **槽的左边界**（不是中心！）
--      这条 API 我第一版语义混乱：槽内部用中心、填充却按左边界算 →
--      **槽本身偏出卡片半个宽度**（实测槽 -1039..-495，而卡片只有 -883..-211），
--      表现就是"进度条跑到卡片外面、看着粗糙"。
--      现在统一：**进左边界，内部自己算中心**，从根上杜绝再错。
function SK.bar(cfg, name, left, y, w, col)
  local cx = left + w / 2                       -- 槽中心
  local slot = SK.bg(cfg, name, cx, y, w, T.size.barH, { 0, 0, 0 })
  local fill = H.spawn(cfg, 'img', name .. '_f')
  H.setPos(fill, left, y); H.setSize(fill, 1, T.size.barH)
  local c = col or T.color.good
  H.setColor(fill, c[1], c[2], c[3], 255)
  return { slot = slot, fill = fill, left = left, y = y, maxW = w - 2 }
end

-- 按比例设进度（从左侧生长）
function SK.barSet(bar, frac, col)
  if not bar or not bar.fill then return end
  frac = math.max(0, math.min(1, frac or 0))
  local fw = math.max(1, math.floor(bar.maxW * frac))
  pcall(function() bar.fill:SetSizeDelta(fw, T.size.barH) end)
  pcall(function() bar.fill:SetAnchoredPosition(bar.left + fw / 2, bar.y) end)
  if col then H.setColor(bar.fill, col[1], col[2], col[3], 255) end
end

return SK

  end)()
  if __c_skin == nil then __c_skin = true end
  return __c_skin
end
__m_state = function()
  if __c_state ~= nil then return __c_state end
  __c_state = (function()
-- state.lua —— 运行时状态（唯一的一份，谁都不许另开变量存游戏数据）
--
-- 为什么要单独一个模块：网页版吃过亏 —— "谁在制、谁排队"这类状态散在几个函数里各存一份，
-- 改了 A 忘了 B，表现就是"莫名其妙的重复小票/名额不释放"。
-- 千星版从第一天起：**所有游戏状态都挂在这一个表上**。

local CFG = __m_config()

local S = {}

-- 一局的状态。newGame 时创建，之后所有模块都读写它。
function S.new(modeName)
  local m = CFG.mode(modeName)
  return {
    mode = m,
    -- 时间
    t = 0,                 -- 真实经过（秒）
    day = 1,
    dayLeft = m.perDay,
    totalLeft = m.total,
    flow = 1,
    idle = 0,
    phase = 'open',        -- open 营业中 | closing 打烊清场（耐心冻结）| done 收工
    lastCallDay = 0,       -- "最后接单"提示只在当天弹一次
    closingLeft = 0,
    settling = false,      -- 正在出当日结算页（防止每帧重复结算）
    settledDay = 0,        -- 已结算过哪一天（幂等闸）
    -- 内容
    orders = {},           -- 订单数组
    slips = {},            -- 小票数组（一杯一张）
    oid = 0,               -- 订单自增 id
    sid = 0,               -- 小票自增 id
    nextArrive = CFG.arrive.first,
    -- 账
    money = 0, rentPaid = 0, rentDebt = 0,
    served = 0, mistakes = 0, left = 0, leftWaiting = 0,
    score = 0, combo = 0, maxCombo = 0,
    today = { served = 0, money = 0, left = 0, mistakes = 0 },
    dayStats = {},
    log = {},
    ended = false,
    autoMoves = 0,
  }
end

-- 今天还剩多少比例（打烊减速用）
function S.dayFrac(s)
  if s.mode.perDay <= 0 then return 1 end
  return math.max(0, math.min(1, s.dayLeft / s.mode.perDay))
end

-- 当前这一杯的"下一步"（每一步 ok=true 之后自动往后走；全做完返回 nil）
function S.nextStep(cup)
  for i = 1, #cup.steps do
    if not cup.steps[i].ok then return cup.steps[i], i end
  end
  return nil
end

-- 这一杯算不算"占着后厨名额"
--   ★ 口径（与原版一致，是 K.refreshSlots 的算法）：开工了（startedAt ~= nil）且没做完
--   ⚠️ noSlot（纯手感步骤，例：速溶咖啡前三步）**不占名额** —— 这是原版的设计意图：
--      一杯三步的咖啡不该和一杯十几下连按的干冰抢同一个名额。
--      但它**不能变成"绕过名额闸门"的通行证**：那条路我踩过 ——
--      beginWork 里 `if not freeStep then 检查名额 end` 让连续按兑茶键开出无限杯，
--      端到端测试实测在制峰值 7（上限 3）。现在用 S.wipGateCount 单独管闸门（见下）。
function S.cupWip(cup)
  if cup.made or cup.startedAt == nil then return false end
  local _, idx = S.nextStep(cup)
  local upto = idx or #cup.steps
  for k = 1, upto do
    if not cup.steps[k].noSlot then return true end
  end
  return false
end

-- ★★ 闸门口径：**在飞的杯** = 已开工（`startedAt ~= nil`）**或**已发到资格（`slotReady`，等着动手）。
--   为什么必须与 cupWip 分开：cupWip 允许 noSlot 的杯不占名额，
--   如果闸门也用它，就没有任何东西限制"同时开多少杯纯手感步骤的活" → 无上界。
--   为什么连 `slotReady` 也要算：refreshSlots 会**预发**资格给排队中的杯，
--   如果闸门不认这份预发，就会出现"3 个在制 + 3 个预发"→ 第 4 杯照样开工（实测过）。
--   有了它，`S.wipCount ≤ maxWip` 成了**真的不变量**（端到端测试盯着）。
function S.wipGateCount(s)
  local n = 0
  for _, o in ipairs(s.orders) do
    for _, c in ipairs(o.cups) do
      if not c.made and (c.startedAt ~= nil or c.slotReady) then n = n + 1 end
    end
  end
  return n
end

-- 现在有几个"未完成任务"在制
function S.wipCount(s)
  local n = 0
  for _, o in ipairs(s.orders) do
    for _, c in ipairs(o.cups) do if S.cupWip(c) then n = n + 1 end end
  end
  return n
end

return S

  end)()
  if __c_state == nil then __c_state = true end
  return __c_state
end
__m_view = function()
  if __c_view ~= nil then return __c_view end
  __c_view = (function()
-- view.lua —— 表现层：把逻辑层的状态画成控件
--
-- ★★ 数值全部来自 skin.lua（见《雪皇-视觉规范.md》）；**这个文件不许出现魔法数字**。
--   要改风格 → 改 skin.lua；要改布局 → 改 skin.lua 的 at 表 + 这里的相对摆放。
--
-- 视觉规则（用户逐轮定的）：
--   ① 整屏黑色打底，UI 压在其上            ② 按钮撑满空间，不留大片空白
--   ③ 字号内敛，不靠粗体拉层次              ④ 步骤(28) 比区域名(26) 略大一档
--   ⑤ 工位卡：名称行+图标列=原色；内容区=**提亮 +40** 底衬；2px 分隔线
--   ★ 底色**不用状态变色**（曾经"有活就提亮"和内容区提亮打架 → 颜色发花，用户一眼看出）
--
-- Z 序（实测确定）：**后建的在上**（同级子节点，索引大的画在上面）。
--   ⇒ 建池顺序 = 从底层到顶层：Backdrop → 工位 → 打包台 → 面板 → 订单卡 → HUD → 菜单大字。
--   ⚠️ 我一度按"先建的在上"建，结果 HUD 盖住了菜单大字。别再用 SetAsLastSibling/SetAsFirstSibling
--      （模拟器实测都不改渲染顺序）。
--
-- 平台约束（都是踩过的坑）：
--   · **控件池**：运行期只改属性，绝不新建/销毁
--   · 新建控件默认"**纯白 + 不可见**"→ 建完立刻设色；要显示的显式 SetActive(true)
--   · 坐标原点是**父控件中心**，单位屏幕像素（设计单位 × scale）
--   · 文本框对齐/框高由 H.spawn + H.fitText 处理（框太矮会裁字）
--   · 文字只用中文/ASCII（原神没 emoji 字体 → 豆腐块；tools/font-audit.mjs 会拦）

local H = __m_host()
local STATE = __m_state()
local CFG = __m_config()
local SK = __m_skin()
local K = __m_kitchen()   -- 只为读"当前这步的进度"（只读快照，不碰玩法状态）
local IN = __m_input()    -- 只为读"实际绑定的键位"（让界面显示和真按键一致）

local V = {}

local T = SK.T
local AT = T.at

-- 工位定义（id 要和 recipes.lua / kitchen.lua 里的字符串一致）
--   ★ 键位**从 input.lua 的实际绑定读**（IN.primary），没有才退回默认 ——
--     这样"界面上印的键"永远等于"真按得响的键"，不会再出现显示与实际不一致。
--   ★ 原版网页版键位是助记字母 B/H/C/P + 空格；但千星 enum **没有 B 和 C**，
--     所以捣锤用 Z（B 的邻居）、化学用 V（C 的邻居），H/P/空格 与原版一致。
--     换键只改 input.lua 的 IN.CAND（唯一来源），这里会自动跟着变。
-- ★ 键位**延迟读取**：V.STATIONS 在模块加载时求值，而 IN.primary 要等 boot 时才填好，
--   所以这里用**函数**而不是值 —— 界面渲染时再取，才能拿到真正绑上的键。
local function keyOf(act, fallback)
  local t = IN and IN.primary
  local k = t and t[act]
  if k == nil or k == '' then return fallback end
  if k == 'SPACE' then return '\231\169\186\230\160\188' end
  return tostring(k)
end

V.STATIONS = {
  { id = 'shake', name = '\230\141\163\233\148\164\229\140\186', key = function() return keyOf('shake', 'Y') end, icon = T.icon.shake },
  { id = 'fire',  name = '\231\129\171\231\179\187\229\140\186', key = function() return keyOf('fire', 'H') end, icon = T.icon.fire },
  { id = 'chem',  name = '\229\140\150\229\173\166\229\140\186', key = function() return keyOf('chem', 'K') end, icon = T.icon.chem },
  { id = 'brew',  name = '\232\144\131\232\140\182\229\140\186', key = function() return keyOf('brew', 'P') end, icon = T.icon.brew },
}
V.PACK = { id = 'pack', name = '\230\137\147\229\140\133\229\143\176', key = function() return keyOf('pack', '\231\169\186\230\160\188') end, icon = T.icon.pack }
V.STATION_NAME = { shake = '\230\141\163\233\148\164\229\140\186', fire = '\231\129\171\231\179\187\229\140\186', chem = '\229\140\150\229\173\166\229\140\186', brew = '\232\144\131\232\140\182\229\140\186', pack = '\230\137\147\229\140\133\229\143\176' }

local MAX_ORDERS = 5
local MAX_SLIPS = 6        -- 小票行容量（一屏能看到 6 张"在制/排队"的票）
local C = T.color

-- ── 每帧只改"变了"的属性（控件池的基本盘：少调 API 少出错）──
local txtCache, styleCache = {}, {}
local function setText(c, s)
  if not c then return end
  s = tostring(s)
  if txtCache[c] == s then return end
  txtCache[c] = s
  pcall(function() c.text = s end)
end
local function setStyle(c, size, col)
  if not c then return end
  local key = tostring(size) .. '|' .. (col and (col[1] * 65536 + col[2] * 256 + col[3]) or 'd')
  if styleCache[c] == key then return end
  styleCache[c] = key
  pcall(function()
    if size then c.fontSize = size end
    if col then c.fontColor = Color.FromRGB(col[1], col[2], col[3]) end
  end)
end
local function setColor(c, col)
  if not c or not col then return end
  H.setColor(c, col[1], col[2], col[3], col[4] or 255)
end
local function recName(o)
  if o.makeup and o.makeup ~= '' then return o.makeup end
  local r = o.lines and o.lines[1] and o.lines[1].rec
  return r and r.name or '?'
end

-- 步骤文字限长：太长会**溢出卡片**（真机文本框不裁剪 → 直接盖到隔壁工位）
--   实测 28 号字下卡片内容区约放 16 个汉字（540px / 28px ≈ 19，留余量取 16）。
--   超长就加省略号；完整文案在逻辑层还有（小票/结算里能看全）。
local STEP_MAX = 16
local function clip(s, n)
  s = tostring(s or '')
  n = n or STEP_MAX
  local width = 0
  local i = 1
  while i <= #s do
    local b = s:byte(i)
    local step
    if b >= 240 then step = 4
    elseif b >= 224 then step = 3
    elseif b >= 192 then step = 2
    else step = 1 end
    width = width + (step > 1 and 1 or 0.55)
    if width > n then return s:sub(1, i - 1) .. '\226\128\166' end
    i = i + step
  end
  return s
end

-- 横幅：显示临时提示（顾客到店/离开/打烊…）
function V.setBanner(v, msg)
  if not v or not v.hud or not v.hud.banner then return end
  if msg and msg ~= '' then
    local s = tostring(msg)
    if txtCache[v.hud.banner] ~= s then
      txtCache[v.hud.banner] = s
      pcall(function() v.hud.banner.text = s end)
    end
    H.show(v.hud.banner)
  else
    H.hide(v.hud.banner)
  end
end

-- ── 玩区显隐（菜单里不显示玩区；用户要求"菜单里不能有彩块和顾客区"）──
--   ★ 入口每帧按 scene 对齐（单一数据源）。曾经写成"切换时调一次"→ 被别处推翻，
--     又写成"每帧对比+自愈"→ 和显隐逻辑互相打架。最终：每帧幂等对齐，先设后不设。
-- 玩区可见性（工位/打包台/等候区/订单卡/结算背景板）—— **只管玩区**
--   ⚠️ 菜单专属内容（营业数据/产品手册/快捷键）不在这里管，见 V.setMenuVisible
-- 菜单/结算时才显示的"参考资料"面板（营业数据 · 产品手册 · 快捷键）
--   ★ 用户反馈："初始界面忘记把产品菜单以及其他的隐藏了"
--     进玩区时收起它们（玩区有工位/等候区/打包台，屏幕已经排满）
function V.setMenuVisible(v, on)
  if not v then return end
  -- ★ 必须**直设 active + visible**，不能走 H.show：
  --   H.show 的顺序是 `active=true` 再 `SetVisible(true)`，而实测
  --   **SetVisible(true) 紧跟 SetActive(true) 会把 visible 翻回 false** → 面板永远不显示。
  --   直设两个字段是稳的（和玩区的 toggle 同一套）。
  for _, bag in ipairs({ v.data, v.book, v.keys, v.menu }) do
    if bag and bag.controls then
      for _, c in ipairs(bag.controls) do
        if c then
          pcall(function() c:SetActive(on and true or false) end)
          pcall(function() c:SetVisible(on and true or false) end)
        end
      end
    end
  end
end

function V.setBoardVisible(v, on)
  if not v or not v.stations then return 0 end
  local n = 0
  local function toggle(ctl)
    if not ctl then return end
    pcall(function() ctl:SetActive(on and true or false) end)
    pcall(function() ctl:SetVisible(on and true or false) end)
    n = n + 1
  end
  local function each(list) for _, c in ipairs(list) do toggle(c) end end
  for _, st in ipairs(V.STATIONS) do
    local slot = v.stations[st.id]
    if slot then each(slot.controls) end
  end
  each(v.pack.controls)
  each(v.panel.controls)
  -- ★ 小票行：属于玩区（原版的工位队列卡），随玩区一起显隐
  for i = 1, MAX_SLIPS do
    if v.slips[i] then each(v.slips[i].controls) end
  end
  for i = 1, MAX_ORDERS do
    if v.orders[i] then each(v.orders[i].controls) end
  end
  return n
end

-- ═══════════════════════════════════════════════════════════════════
-- 初始化：建控件池（**顺序 = Z 序**：先建的在上）
-- ═══════════════════════════════════════════════════════════════════
function V.init(hostCfg)
  local v = { cfg = hostCfg, stations = {}, orders = {}, slips = {} }
  local W = hostCfg.spaceW or hostCfg.canvasW
  local H0 = hostCfg.spaceH or hostCfg.canvasH
  v.W, v.H = W, H0
  -- 设计坐标 → 屏幕坐标的缩放（真机高 900 → scale = 1.0）
  --   ★ 用 900 作基准（不是 720）：规范是按 1815×900 定的
  -- ★★ 按**实测画布**等比缩放整个版式（版式按 1815×900 设计）。
  --   之前写死 1815 → 画布宽度不同就整体偏右、打底铺不满、面板和工位重叠（用户两次反馈）。
  local s = SK.fitCanvas(W, H0)
  v.designScale = s
  v.scale = s
  v.W = W
  v.pad = hostCfg.root

  -- ═══ 0. 整屏黑色打底（规则 ①）═══
  --   最下层：**最先建**（先建的在下…… 不，先建的在上）
  --   ⚠️ 这里是唯一例外：打底必须**最后建**才对？—— 不对，见下：
  --   实测结论：paintList 里**索引大的在最上**（sibling-order 测试：Front 索引 2，在最上）。
  --   而"同级先出现的在上"是 Runtime scene 树的说法。两者相反，所以这里**按绘制实测**：
  --   打底放最先建 → 运行时它索引最小 → 按"索引小的在下"它就是最底 → 正确。
  do
    local bd = H.spawn(hostCfg, 'img', 'Backdrop')
    -- ★ 打底按**实测画布**铺，并留富余（原来用设计宽 → 21:9/16:9 宽屏上铺不满）
    H.setPos(bd, 0, 0); H.setSize(bd, W + 960, H0 + 960)
    -- ★ 用**不透明**（截图暴露：240 会透出左右边缘的游戏画面）
    H.setColor(bd, 3, 4, 7, 255)
    v.backdrop = bd
  end

  -- ═══ 2. 四张工位卡（2×2）═══
  local pos = {
    { AT.stationX,  AT.stationY },
    { AT.stationX2, AT.stationY },
    { AT.stationX,  AT.stationY2 },
    { AT.stationX2, AT.stationY2 },
  }
  for i, st in ipairs(V.STATIONS) do
    local px, py = pos[i][1], pos[i][2]
    local col = SK.accent(st.id)
    local lay = SK.stationCard(hostCfg, 'St_' .. st.id, px, py, col, false)
    -- 工位名：居中文本，x 要给它**框中心**（内容区中心略偏左，右边留给键位胶囊）
    local name = SK.textL(hostCfg, 'StN_' .. st.id, lay.nameX, lay.nameY, 200, 'title', C.onColor)
    local key  = SK.bg(hostCfg, 'StK_' .. st.id, lay.keyX, lay.keyY, 34, 28, { 0, 0, 0, 66 })
    local keyT = SK.textL(hostCfg, 'StKT_' .. st.id, lay.keyX - 6, lay.keyY, 34, 'small', C.onColor)
    local icon = SK.icon(hostCfg, 'StI_' .. st.id, lay.iconX, lay.iconY, st.icon, T.size.iconBig, { 255, 255, 255 })
    local step = SK.textL(hostCfg, 'StS_' .. st.id, lay.stepX, lay.stepY, lay.stepW, 'step', { 255, 255, 255 })
    local bar = SK.bar(hostCfg, 'StB_' .. st.id, lay.barX, lay.barY, lay.barW, { 255, 255, 255 })

    setText(name, st.name)
    setText(keyT, type(st.key) == 'function' and st.key() or st.key)
    setText(step, '\231\173\137\229\190\133\229\176\143\231\165\168')
    v.stations[st.id] = {
      col = col, lay = lay,
      controls = { lay.outline, lay.box, lay.hi, lay.panel, lay.divider, name, key, keyT, icon, step, bar.slot, bar.fill },
      box = lay.box, panel = lay.panel,
      name = name, key = key, keyT = keyT, icon = icon, step = step, bar = bar,
      barW = lay.barW,
    }
  end

  -- ═══ 3. 打包台 ═══
  do
    local col = C.pack
    local w, h = T.size.packW, T.size.packH
    local px, py = AT.packX, AT.packY
    local x0 = px - w / 2
    local y0 = py + h / 2
    local box = SK.bg(hostCfg, 'Pk_box', px, py, w, h, col)
    local iw = T.size.pad + T.size.iconMid + T.size.pad
    local dx = x0 + iw
    local dy = y0 - T.size.nameRowH
    local dw = w - iw
    local ph = h - T.size.nameRowH - T.size.radius
    local panel = SK.bg(hostCfg, 'Pk_panel', dx + dw / 2, dy - ph / 2, dw, ph, SK.chip(col))
    local divider = SK.bg(hostCfg, 'Pk_line', dx + dw / 2, dy + T.size.dividerH / 2, dw, T.size.dividerH, T.dividerCol)
    local icon = SK.icon(hostCfg, 'Pk_icon', x0 + T.size.pad + T.size.iconMid / 2, py, V.PACK.icon, T.size.iconMid, { 255, 255, 255 })
    local name = SK.textL(hostCfg, 'Pk_name', dx, y0 - T.size.nameRowH / 2, 120, 'head', C.onColor)
    local key  = SK.bg(hostCfg, 'Pk_keybg', dx + 130, y0 - T.size.nameRowH / 2, 56, 28, { 0, 0, 0, 66 })
    local keyT = SK.textL(hostCfg, 'Pk_key', dx + 108, y0 - T.size.nameRowH / 2, 56, 'small', C.onColor)
    local list = SK.textL(hostCfg, 'Pk_list', dx + T.size.pad, dy - 48, dw - T.size.pad * 2, 'step', { 255, 255, 255 })
    -- 交付提示（右下）
    local hint = SK.textL(hostCfg, 'Pk_hint', x0 + w - 220, y0 - h + 30, 200, 'small', C.dim)

    setText(name, V.PACK.name)
    setText(keyT, type(V.PACK.key) == 'function' and V.PACK.key() or V.PACK.key)
    setText(list, '\230\154\130\230\151\182\230\178\161\230\156\137\232\166\129\228\186\164\228\187\152\231\154\132')
    setText(hint, '\230\140\137\231\169\186\230\160\188\229\133\168\233\131\168\228\186\164\228\187\152')
    v.pack = {
      col = col, controls = { box, panel, divider, icon, name, key, keyT, list, hint },
      box = box, name = name, list = list, hint = hint,
    }
  end

  -- ═══ 4. 订单面板（贴右，整条到底）═══
  do
    local w = T.size.panelW
    local px = AT.panelL + w / 2
    local py = AT.panelY
    local h = T.size.panelH
    local box = SK.bg(hostCfg, 'OrderPanel', px, py, w, h, C.panelBg)
    local head = SK.textL(hostCfg, 'OrderHead', AT.panelL + T.gap.m, py + AT.panelHeadY, 260, 'head', C.gold)
    local empty = SK.textL(hostCfg, 'OrderEmpty', AT.panelL + T.gap.m, py - h / 2 + 40, w - 40, 'small', C.dim)
    setText(head, '\231\173\137\229\128\153\229\140\186 / \229\156\168\229\136\182')
    setText(empty, '\239\188\136\230\154\130\230\151\160\233\161\190\229\174\162\239\188\137')
    v.panel = { box = box, head = head, empty = empty, x = px, y = py, w = w, h = h,
                controls = { box, head, empty } }
  end

  -- ═══ 5. 订单卡（最多 5 张，整条铺满面板）═══
  for i = 1, MAX_ORDERS do
    local oy = AT.panelY + AT.orderTop - (i - 1) * AT.orderStep
    local w, h = T.size.orderW, T.size.orderH
    -- ★★ 坐标系口径（这里踩了大坑，看清再改）：
    --   `SK.bg` / `SK.textL` / `SK.bar` 的 x 都是**相对父控件中心**的坐标；
    --   而 AT.panelL 是"面板左边缘（相对中心）"。
    --   我上一版把 `ox = AT.panelL + 边距` 当"卡左"用，却又把它当"中心系"传给子元素 →
    --   **整张卡的内容右移了半个面板宽（176）**，真机上顾客名/标签/进度条全跑出面板（用户截图可见）。
    --   现在统一：ox = 卡片**左边缘**（中心系），子元素一律 ox + 偏移，底色类再 + w/2 换算成中心。
    local ox = AT.panelL + (T.size.panelW - w) / 2
    local y0 = oy + h / 2
    local box = SK.bg(hostCfg, 'Od_' .. i, ox + w / 2, oy, w, h, C.cardBg)
    -- 内容区提亮（和工位卡同一套规则：内容区比卡片浅半档）
    local cy = y0 - 60 - (h - 60 - 10) / 2
    local cpanel = SK.bg(hostCfg, 'OdP_' .. i, ox + w / 2, cy, w, h - 60 - 10, SK.chip(C.cardBg, 22))
    local divider = SK.bg(hostCfg, 'OdL_' .. i, ox + w / 2, y0 - 60 + T.size.dividerH / 2, w, T.size.dividerH, T.dividerCol)
    local edge = SK.bg(hostCfg, 'OdE_' .. i, ox + 3, oy, 4, h - 40, C.dim)
    -- ★ 框宽要"内收"，否则框本身会伸到卡外（文字是左对齐的，视觉无碍，但框出界会被 lint 报）
    local whoW = w - AT.orderInX * 2 - 118
    local who = SK.textL(hostCfg, 'OdW_' .. i, ox + AT.orderInX, y0 - 30, whoW, 'small', C.text)
    local tag = SK.bg(hostCfg, 'OdT_' .. i, ox + w - 48, y0 - 30, 64, 24, { 0, 0, 0, 56 })
    local tagT = SK.textL(hostCfg, 'OdTt_' .. i, ox + w - 60, y0 - 30, 56, 'tiny', C.dim)
    local whatW = w - AT.orderInX * 2
    local what = SK.textL(hostCfg, 'OdS_' .. i, ox + AT.orderInX, y0 - 84, whatW, 'small', C.text)
    local bar = SK.bar(hostCfg, 'OdB_' .. i, ox + AT.orderInX,
                       y0 - 56, whatW, C.good)  -- 耐心条：名称与要求之间
    local pct = SK.textL(hostCfg, 'OdPc_' .. i, ox + w - AT.orderInX - 64, y0 - 30, 56, 'tiny', C.good)
    setText(who, '\233\161\190\229\174\162'); setText(tagT, ''); setText(what, ''); setText(pct, '')
    v.orders[i] = {
      controls = { box, cpanel, divider, edge, who, tag, tagT, what, bar.slot, bar.fill, pct },
      box = box, who = who, tagT = tagT, what = what, bar = bar, pct = pct,
      barW = w - AT.orderInX * 2, tagBg = tag,
    }
  end

  -- ═══ 5.5 小票行（原版"工位队列卡"的等价物）═══
  --   ★★ 为什么必须补：原版玩家**点一下小票就把它送到该去的工位**（网页版 1472 → forwardSlip）
  --      + 拖拽指定工位；移植版把这条交互整个漏了，只剩"闲 5 秒自动流转"，
  --      于是按工位键时票常常不在工位 → 真机日志 9003 条 [REJECT]、8984/9085 条 ok=false。
  --   ★ 每张卡三行：谁（产品名 + 杯号）/ 下一步做什么 / 点我送去哪（或"等名额""可出餐"）。
  --     点卡的路由在入口 xuehuang.lua 的 click 分支里（V.slips[i].box 命中 → K.forwardSlip）。
  for i = 1, MAX_SLIPS do
    local w, h = T.size.slipW, T.size.slipH
    local gapS = T.size.slipGap
    local x0 = AT.slipL + (w + gapS) * (i - 1)
    local cx = x0 + w / 2
    local cy = AT.slipRowY
    local box   = SK.bg(hostCfg, 'Sl' .. i, cx, cy, w, h, C.cardBg)
    local edge  = SK.bg(hostCfg, 'SlE' .. i, x0 + 3, cy, 5, h - 24, C.dim)
    local who   = SK.textL(hostCfg, 'SlW' .. i, x0 + 14, cy + h / 2 - 24, w - 28, 'small', C.text)
    local nextT = SK.textL(hostCfg, 'SlN' .. i, x0 + 14, cy + 2, w - 28, 'tiny', C.dim)
    local fwd   = SK.textL(hostCfg, 'SlF' .. i, x0 + 14, cy - h / 2 + 22, w - 28, 'tiny', C.gold)
    setText(who, ''); setText(nextT, ''); setText(fwd, '')
    v.slips[i] = {
      controls = { box, edge, who, nextT, fwd },
      box = box, edge = edge, who = who, nextT = nextT, fwd = fwd,
      w = w, h = h,
    }
  end

  -- ═══ 6. 左列：营业数据（还原原版 9 项）═══
  do
    local w, h = T.size.dataW, T.size.dataH
    local px, py = AT.colLC, AT.dataY
    local box = SK.bg(hostCfg, 'DataBox', px, py, w, h, C.panelBg)
    local head = SK.textL(hostCfg, 'DataHead', AT.colLL + T.gap.m, py + h / 2 - 26, w - 30, 'head', C.gold)
    setText(head, '\232\144\165\228\184\154\230\149\176\230\141\174')
    -- 9 项做成 **2 列 × 5 行**网格（原版是宽屏横排；竖排 9 行在 900 高的画布里装不下）
    --   列宽 = 面板内宽的一半；每格"标签 + 数值"
    --   字段全部来自 state.lua / day.lua / config.lua（不自己造数）
    local rowDefs = {
      { k = 'money',    label = '\232\144\165\228\184\154\233\162\157' },
      { k = 'rent',     label = '\228\187\138\230\151\165\230\136\191\231\167\159' },
      { k = 'served',   label = '\229\183\178\229\135\186\233\164\144' },
      { k = 'bad',      label = '\231\191\187\232\189\166\230\181\129\229\164\177' },
      { k = 'combo',    label = '\232\191\158\229\135\187' },
      { k = 'auto',     label = '\232\135\170\229\138\168\230\181\129\232\189\172' },
      { k = 'kitchen',  label = '\229\144\142\229\142\168\229\174\185\233\135\143' },
      { k = 'arrive',   label = '\229\136\176\229\186\151\233\151\180\233\154\148' },
      { k = 'leftwait', label = '\230\142\146\233\152\159\231\173\137\232\183\145\231\154\132' },
    }
    local grid = {}
    local innerW = w - T.gap.m * 2
    local cellW = innerW / 2
    local rowH = 24
    for i, d in ipairs(rowDefs) do
      local col = (i - 1) % 2          -- 0=左列 1=右列
      local row = math.floor((i - 1) / 2)
      local gx = AT.colLL + T.gap.m + col * cellW
      local gy = py + h / 2 - 52 - row * rowH
      local lab = SK.textL(hostCfg, 'DataL' .. i, gx, gy, cellW * 0.60, 'tiny', C.dim)
      local val = SK.textL(hostCfg, 'DataV' .. i, gx + cellW * 0.58, gy, cellW * 0.42, 'tiny', C.text)
      setText(lab, d.label)
      setText(val, '\226\128\148')
      grid[i] = { label = lab, val = val, def = d }
    end
    v.data = { box = box, head = head, rows = grid,
               controls = { box, head } }
    for _, r in ipairs(grid) do
      v.data.controls[#v.data.controls + 1] = r.label
      v.data.controls[#v.data.controls + 1] = r.val
    end
  end

  -- ═══ 7. 右列：产品手册（6 个配方）+ 快捷键 ═══
  do
    local w, h = T.size.bookW, T.size.bookH
    local px, py = AT.colRC, AT.bookY
    local box = SK.bg(hostCfg, 'BookBox', px, py, w, h, C.panelBg)
    local head = SK.textL(hostCfg, 'BookHead', AT.colRL + T.gap.m, py + h / 2 - 26, w - 30, 'head', C.gold)
    setText(head, '\228\186\167\229\147\129\230\137\139\229\134\140')
    local sub = SK.textL(hostCfg, 'BookSub', AT.colRL + T.gap.m, py + h / 2 - 52, w - 30, 'small', C.dim)
    setText(sub, '\231\130\185\228\184\128\230\157\161\232\181\183\230\157\175 \194\183 \233\148\174 1~8')
    -- 配方来自 recipes.lua（唯一来源）
    local RECIPES = __m_recipes()
    local list = RECIPES.list or {}
    local rows = {}
    local rowH2 = 44
    for i = 1, math.min(6, #list) do
      local r = list[i]
      local ry = py + h / 2 - 92 - (i - 1) * rowH2
      local tag = SK.textL(hostCfg, 'BookT' .. i, AT.colRL + T.gap.m, ry, 40, 'small', C.gold)
      setText(tag, '[' .. tostring(r.tag or '?') .. ']')
      local nm = SK.textL(hostCfg, 'BookN' .. i, AT.colRL + T.gap.m + 44, ry, w - 140, 'body', C.text)
      setText(nm, tostring(r.name or '?'))
      local pr = SK.textL(hostCfg, 'BookP' .. i, AT.colRL + w - 76, ry, 60, 'small', C.dim)
      setText(pr, tostring(r.price or 0) .. ' \229\133\131')
      rows[i] = { tag = tag, name = nm, price = pr, rec = r }
    end
    v.book = { box = box, head = head, sub = sub, rows = rows, controls = { box, head, sub } }
    for _, r in ipairs(rows) do
      v.book.controls[#v.book.controls + 1] = r.tag
      v.book.controls[#v.book.controls + 1] = r.name
      v.book.controls[#v.book.controls + 1] = r.price
    end
  end

  -- 右列：快捷键说明（键位**从 input 读**，和实际绑定一致）
  do
    local w, h = T.size.keysW, T.size.keysH
    local px, py = AT.colRC, AT.keysY
    local box = SK.bg(hostCfg, 'KeysBox', px, py, w, h, C.panelBg)
    local head = SK.textL(hostCfg, 'KeysHead', AT.colRL + T.gap.m, py + h / 2 - 26, w - 30, 'head', C.gold)
    setText(head, '\229\191\171\230\141\183\233\148\174')
    local kk = IN and IN.primary or {}
    local function kn(a, d) local q = kk[a]; return (q == nil or q == '') and d or (q == 'SPACE' and '\231\169\186\230\160\188' or tostring(q)) end
    local lines = {
      string.format('%s \230\141\163\233\148\164\229\140\186 \194\183 %s \231\129\171\231\179\187\229\140\186 \194\183 %s \229\140\150\229\173\166\229\140\186 \194\183 %s \232\144\131\232\140\182\229\140\186', kn('shake','Y'), kn('fire','H'), kn('chem','K'), kn('brew','P')),
      string.format('%s \230\137\147\229\140\133\229\143\176\229\135\186\233\164\144\239\188\136\229\164\135\231\148\168\233\148\174 %s \228\185\159\229\143\175\239\188\137', kn('pack','\231\169\186\230\160\188'), kn('pack2','Z')),
      -- ★★ 命名原则照抄原版（网页版 1720 行原话）：**取工位名的"动作字"**，不取屏幕位置、不取英文首字母
      --   我上一版写的是"取动作英文首字母（Shake/Fire/Chem/Brew）" —— 方向是反的，用户看得出。
      --   ⚠️ 平台没有 B/C 这两个键（官方枚举里只有奇匠按键 1-43 那批 + 通用键），
      --      所以物理键是 Y/H/K/P；编辑器里可以把它们改绑成 B/C，Lua 侧不用动。
      '\229\145\189\229\144\141\239\188\154\229\183\165\228\189\141\233\148\174\229\143\150\229\183\165\228\189\141\229\144\141\231\154\132"\229\138\168\228\189\156\229\173\151"\239\188\136\230\141\163/\231\129\171/\229\140\150/\230\179\161\239\188\137\239\188\140\233\148\174\228\189\141\232\183\159\231\157\128\230\180\187\229\132\191\232\181\176',
      '\239\188\136\229\141\131\230\152\159\230\178\161\230\156\137 B/C \233\148\174\239\188\140\231\148\168 Y/H/K \233\161\182\230\155\191\239\188\155H/P \228\184\142\229\142\159\231\137\136\231\155\184\229\144\140\239\188\137',
      string.format('%s \232\135\170\229\138\168\230\181\129\232\189\172 \194\183 %s \232\135\170\229\138\168\229\135\186\231\165\168 \194\183 %s \230\154\130\229\129\156\239\188\136\232\144\165\228\184\154\228\184\173\239\188\137', kn('mode1','1'), kn('mode2','2'), kn('mode3','3')),
      '\231\130\185\229\176\143\231\165\168 = \231\171\139\229\136\187\233\128\129\229\174\131\229\142\187\232\175\165\229\142\187\231\154\132\229\183\165\228\189\141',
    }
    local txts = {}
    for i, s in ipairs(lines) do
      local c = SK.textL(hostCfg, 'KeysL' .. i, AT.colRL + T.gap.m, py + h / 2 - 66 - (i - 1) * 34, w - 30, 'small', i == 1 and C.text or C.dim)
      setText(c, s)
      txts[i] = c
    end
    v.keys = { box = box, head = head, lines = txts, controls = { box, head } }
    for _, c in ipairs(txts) do v.keys.controls[#v.keys.controls + 1] = c end
  end

  -- ═══ 1. HUD 条 ═══
  v.hud = {}
  do
    local bar = SK.bg(hostCfg, 'HudBar', AT.hudX or 0, AT.hudY, T.size.hudW, T.size.hudH, C.hudBg)
    local lx = -(T.size.hudW) / 2      -- HUD 左边缘（HUD 居中，宽度已扣边距）
    local title = SK.textL(hostCfg, 'HudTitle', lx + AT.hudTitleX, AT.hudY, 150, 'head', C.gold)
    local clock = SK.textL(hostCfg, 'HudClock', lx + AT.hudClockX, AT.hudY, AT.hudClockW, 'head', C.text)
    -- 三项数据：图标 + 数字 + 说明（规则：图标化）
    --   ★ 坐标是**相对左区左边缘**的 → 必须写成 lx + (相对值)，别忘加 lx（我第一版忘了，
    --     结果三项数据全跑到画布外 1900+，是 layout-lint 抓出来的）
    local stats = { bar = bar, title = title, clock = clock, items = {} }
    local defs = {
      { key = 'served', icon = T.icon.ok,   col = C.good, label = '\229\135\186\233\164\144' },
      { key = 'left',   icon = T.icon.warn, col = C.bad,  label = '\230\181\129\229\164\177' },
      { key = 'wip',    icon = T.icon.pack, col = C.text, label = '\229\156\168\229\136\182' },
    { key = 'combo',  icon = T.icon.brew, col = C.warn, label = '\232\191\158\229\135\187' },   -- 原版 HUD 第 4 项
    }
    for i, d in ipairs(defs) do
      local x = lx + AT.hudStatX + (i - 1) * AT.hudStatGap
      stats.items[i] = {
        icon = SK.icon(hostCfg, 'HudIc' .. i, x, AT.hudY, d.icon, T.size.iconS, d.col),
        val  = SK.textL(hostCfg, 'HudVal' .. i, x + 20, AT.hudY, 46, 'head', d.col),
        label = SK.textL(hostCfg, 'HudLab' .. i, x + 68, AT.hudY, 70, 'small', C.dim),
        def = d,
      }
    end
    -- 提示行：**右对齐到左区右边缘**（框中心 = 右边缘 - 框宽/2 - 边距）
    local tipW = AT.hudTipW
    stats.tip = SK.textL(hostCfg, 'HudTip', lx + T.size.hudW - tipW - AT.hudTipR, AT.hudY, tipW, 'small', C.dim)
    -- 横幅（临时提示：顾客到店/走了/打烊…）—— 独立控件，别借用标题
    --   （旧版把提示写进 HUD 标题，结果"标题长期显示游戏名"和"临时提示"互相覆盖）
    local bw = T.size.hudW - 96
    stats.banner = SK.textC(hostCfg, 'HudBanner', -(T.size.hudW) / 2 + 24 + bw / 2, AT.hudY - T.size.hudH / 2 - 22,
                           bw, 'body', C.gold)
    H.hide(stats.banner)
    v.hud = stats
  end

  -- ★★ 动作反馈大字 / 按键反馈行：**已删除**（2026-09-27 还原度重做）。
  --   它们是上一版为了掩盖"票没搬到工位"而加的表现层补丁：
  --   屏幕正中弹「捣锤 成功」、HUD 上挂一行按键回显 —— 原版都没有。
  --   真正的反馈是原版本来就有的三样：小票自己走过去、工位卡上的进度、
  --   以及工位卡上"→ 点我送 X 区"的提示。信息够了，不需要大字。

  -- 菜单/结算的居中大字（复用，不另建 → 少踩"新建控件纯白"的坑）
  --   ★ 中间区域的文字已实测能显示（不像顶部 HUD 那样容易被裁/被盖）
  -- ★ 结算背景板：**不透明**整屏底，进结算时显示 → 盖住玩区（但盖不住更后建的结算大字）
  do
    local bag = H.spawn(hostCfg, 'img', 'SheetBag')
    H.setPos(bag, 0, 0); H.setSize(bag, W + 4, H0 + 4)
    H.setColor(bag, 4, 6, 11, 255)
    H.hide(bag)
    v.sheetBag = bag
  end

  v.big = {}
  do
    v.big.title = SK.textC(hostCfg, 'BigTitle', 0, 80, 900, 'display', C.gold)
    v.big.line1 = SK.textC(hostCfg, 'BigL1', 0, 10, 900, 'head', C.text)
    v.big.line2 = SK.textC(hostCfg, 'BigL2', 0, -40, 900, 'body', C.dim)
    v.big.line3 = SK.textC(hostCfg, 'BigL3', 0, -90, 900, 'small', C.dim)
    v.big.controls = { v.big.title, v.big.line1, v.big.line2, v.big.line3 }

  -- ═══════════════════════════════════════════════════════════════════
  -- ★★ 初始界面（照原版 showStart 还原）
  --   原版面板：标题 + 一句话说明 + **3 张模式卡**（26px 大字"N 分钟" + 粗体名 + 灰说明，
  --   选中的卡粉色描边）+ **怎么玩**（7 条规则，虚线上边）+ **开门营业 →** 按钮 + tagline
  --   我第一版只做了 3 行大字 → 信息量和布局都差得远（用户指出）
  -- ═══════════════════════════════════════════════════════════════════
  v.menu = { controls = {}, cards = {}, ruleLines = {} }
  do
    local M = v.menu
    -- ★★ 菜单占用**整屏**（用户："菜单区域该有的区域没占满"）
    --   原版是 .veil（整屏半透明黑）+ 居中面板；千星没有 blur，用整屏不透明底衬等效。
    --   底部（等下）再放背景压暗，让菜单像"独立一屏"而不是"飘在中间的框"。
    local m0 = T.safe
    local panelW = math.min(W - m0 * 2, 1240)

    -- 整屏底衬（菜单背景）：不透明深色，盖住玩区
    M.veil = SK.bg(hostCfg, 'MnVeil', 0, 0, W + 8, H0 + 8, { 8, 10, 15, 255 })
    M.controls[#M.controls + 1] = M.veil
    -- 面板底衬：**整屏**（占满；内容块居中，宽度由 panelW 控制）
    M.panel = SK.bg(hostCfg, 'MnPanel', 0, 0, W + 8, H0 + 8, { 17, 22, 33, 255 })
    M.controls[#M.controls + 1] = M.panel

    local panelL = -panelW / 2   -- 内容块左边缘（居中）
    local pad = T.gap.xl
    local cx = 0
    local topY = H0 / 2 - m0 - pad            -- 内容顶端（中心系 y）
    -- 标题 + 说明
    M.title = SK.textL(hostCfg, 'MnTitle', panelL + pad, topY - 24, panelW - pad * 2, 'title', C.gold)
    M.controls[#M.controls + 1] = M.title
    M.sub = SK.textL(hostCfg, 'MnSub', panelL + pad, topY - 62, panelW - pad * 2, 'small', C.dim)
    M.controls[#M.controls + 1] = M.sub
    -- 3 张模式卡（铺满面板宽）
    local gapCard = T.gap.m
    local cw = (panelW - pad * 2 - gapCard * 2) / 3
    local chh = 104
    local cardCY = topY - 72 - chh / 2
    for i = 1, 3 do
      local cxx = panelL + pad + (cw + gapCard) * (i - 1) + cw / 2
      local card = SK.bg(hostCfg, 'MnCard' .. i, cxx, cardCY, cw, chh, { 21, 27, 40, 255 })
      local edge = SK.bg(hostCfg, 'MnCardE' .. i, cxx, cardCY, cw, chh, { 47, 58, 86, 255 })
      local big  = SK.textC(hostCfg, 'MnCardBig' .. i, cxx, cardCY + 26, cw - 16, 'title', C.text)
      local nm   = SK.textC(hostCfg, 'MnCardNm' .. i, cxx, cardCY - 10, cw - 16, 'small', C.text)
      local desc = SK.textC(hostCfg, 'MnCardD' .. i, cxx, cardCY - 34, cw - 16, 'tiny', C.dim)
      M.cards[i] = { card = card, edge = edge, big = big, name = nm, desc = desc,
                     controls = { card, edge, big, nm, desc } }
      for _, c in ipairs(M.cards[i].controls) do M.controls[#M.controls + 1] = c end
    end
    -- 怎么玩：标题 + 7 行（占满余下高度）
    local rulesTop = cardCY - chh / 2 - T.gap.xl
    M.rulesHead = SK.textL(hostCfg, 'MnRulesHead', panelL + pad, rulesTop - 10, panelW - pad * 2, 'body', C.text)
    M.controls[#M.controls + 1] = M.rulesHead
    local lineGap = 32
    for i = 1, 7 do
      local c = SK.textL(hostCfg, 'MnRule' .. i, panelL + pad, rulesTop - 44 - (i - 1) * lineGap, panelW - pad * 2, 'small', C.dim)
      M.ruleLines[i] = c
      M.controls[#M.controls + 1] = c
    end
    -- 底部：开门按钮 + tagline
    local btnY = -H0 / 2 + m0 + pad + 40    -- 底部一行（与标题/卡片同一内容列）
    local goW, goH = 150, 40
    local goCX = panelL + goW / 2   -- 与内容块左边缘对齐
    M.goLo = SK.bg(hostCfg, 'MnGoLo', goCX, btnY - 3, goW, goH, { 217, 59, 76, 255 })
    M.goBg = SK.bg(hostCfg, 'MnGoBg', goCX, btnY + 2, goW, goH - 6, { 255, 94, 108, 255 })
    M.goTx = SK.textC(hostCfg, 'MnGoTx', goCX, btnY, goW, 'head', { 255, 255, 255 })
    M.controls[#M.controls + 1] = M.goLo
    M.controls[#M.controls + 1] = M.goBg
    M.controls[#M.controls + 1] = M.goTx
    M.tag = SK.textL(hostCfg, 'MnTag', panelL + pad + goW + T.gap.l, btnY, panelW - pad * 2 - goW - T.gap.l, 'tiny', C.dim)
    M.controls[#M.controls + 1] = M.tag
    -- 命中矩形（菜单里点任意处都能开门，这里只保留给"将来要精确点击"用）
    M.goHit = { box = { anchoredPositionX = goCX, anchoredPositionY = btnY,
                        sizeDeltaX = goW, sizeDeltaY = goH } }

    -- 初始全隐藏（进菜单时再显示）
    for _, c in ipairs(M.controls) do H.hide(c) end
  end
  end

  H.say('view', '\229\183\178\229\187\186\230\142\167\228\187\182\230\177\160\239\188\154\230\137\147\229\186\149 + HUD + 4\229\183\165\228\189\141 + \230\137\147\229\140\133\229\143\176 + \233\157\162\230\157\191 + %d \232\174\162\229\141\149\229\141\161 + \232\143\156\229\141\149\229\164\167\229\173\151',
        tostring(MAX_ORDERS))
  return v
end

-- ═══════════════════════════════════════════════════════════════════
-- 每帧：把逻辑状态映射成控件属性
-- ═══════════════════════════════════════════════════════════════════
function V.sync(v, s)
  if not v or not s then return end
  local S = v.stations

  -- HUD：时钟 + 三项数据
  local left = (s.phase == 'closing') and s.closingLeft or s.dayLeft
  setText(v.hud.clock, string.format('\231\172\172 %d/%d \229\164\169   %02d:%02d',
    s.day, s.mode.days, math.floor(left / 60), math.floor(left % 60)))
  setStyle(v.hud.clock, T.font.head, C.text)
  local vals = {
    tostring(s.served or 0), tostring(s.left or 0),
    string.format('%d/%d', STATE.wipCount(s), CFG.kitchen.maxWip),
    'x' .. tostring(s.combo or 0),          -- 连击（原版 HUD 第 4 项）
  }
  -- ★★ 每个工位"真正排在它这里的票数"（**不是全店未开工总数**）
  --   踩坑：原来卡上显示的是"全店未开工的杯数"，跟这个工位毫无关系 →
  --     捣锤区显示「等待小票（5 杯排队）」，而那 5 杯根本不经过捣锤区
  --     → 玩家以为有活，按了没反应，判定"按键坏了"（用户报的就是这个）。
  --   现在只统计"下一步就在这个工位"的票。
  local queued = {}
  for _, sl in ipairs(s.slips or {}) do
    local nx = STATE.nextStep(sl.cup)
    if nx and nx.st and not sl.ready then
      queued[nx.st] = (queued[nx.st] or 0) + 1
    end
  end
  local wipN = 0
  for _, n in pairs(queued) do wipN = wipN + n end
  for i, it in ipairs(v.hud.items) do
    setText(it.val, vals[i] or '0')
    setText(it.label, it.def.label)
    -- 连击没起来时压暗，起来了才发亮（一眼看出"连上了没有"）
    if it.def.key == 'combo' then
      setStyle(it.val, T.font.head, (s.combo or 0) > 1 and C.warn or C.dim)
    end
  end
  -- ★ 提示行里的键位**动态拼**（读实际绑定），不再写死
  --   ⚠️ 真正的赋值放到工位循环**之后**（要用 busy 状态算"哪个工位有活"），见下面
  local ks = IN and IN.primary or {}
  local function kk(a, d) local x = ks[a]; return (x == nil or x == '') and d or (x == 'SPACE' and '\231\169\186\230\160\188' or tostring(x)) end

  -- 工位卡
  for _, st in ipairs(V.STATIONS) do
    local slot = S[st.id]
    if slot then
      local mine = nil
      for _, sl in ipairs(s.slips) do
        local nx = STATE.nextStep(sl.cup)
        if nx and nx.st == st.id then mine = sl break end
      end
      if mine then
        local nx = STATE.nextStep(mine.cup)
        local rec = mine.cup.rec
        local tag = (rec and rec.tag) and ('[' .. rec.tag .. '] ') or ''
        local prog = ''
        -- ★ 进度必须写出来：
        --   · 连按类 → "连按 2/5"（按一下数字就变）
        --   · 按住类 → "按住 0.3/0.9"（**按住时数字在涨**，玩家才知道要一直按着）
        --   原来按住类只写"按住"两个字 → 按一下没反应，看起来像按键坏了
        if nx.kind == 'mash' then
          prog = string.format('   \232\191\158\230\140\137 %d/%d', nx.done or 0, nx.taps or 1)
        elseif nx.kind == 'hold' then
          local full = CFG.hold and CFG.hold.sec or 0.9
          prog = string.format('  \226\135\169\230\140\137\228\189\143\228\184\141\230\148\190 %.1f/%.1f \231\167\146', nx.done or 0, full)
        end
        setText(slot.step, clip(tag .. nx.t) .. prog)
        -- ★ 进度条：mash(连按) 和 hold(按住) **都要显示进度**。
        --   原来只算 mash → 按住时进度条一直不动，用户以为"按住没用"（真实反馈）。
        local frac = K.stepProgress(s, st.id)
        SK.barSet(slot.bar, frac, { 255, 255, 255 })
        -- ★★ 这个工位**有活** → 卡片用原色 + 键位胶囊高亮
        --   用户反馈"按了没反应"：现场日志证实按键每次都被收到了，
        --   真正的原因是**这个工位当时没有能做的小票**，而画面没把"有活/没活"说清楚。
        --   现在：没活的工位压暗（一眼看出"按它没用"），有活的亮起来。
        H.setColor(slot.box, slot.col[1], slot.col[2], slot.col[3], 255)
        H.setColor(slot.panel, SK.chip(slot.col, 40)[1], SK.chip(slot.col, 40)[2], SK.chip(slot.col, 40)[3], 255)
        H.setColor(slot.key, 255, 255, 255, 90)
        H.setColor(slot.icon, 255, 255, 255, 255)     -- 有活：图标全亮
        slot.busy = true
      else
        -- ★★ 没活的工位要把话说死（用户真实困惑："我按 30 次才有反应"）：
        --   前 29 次按的时候这个工位**确实没有票**，但画面只写"等待小票"，
        --   玩家看不出"现在是按不了"还是"按键坏了" → 只能狂按碰运气。
        --   现在直接写【本工位无活】+ 哪个键，并且在进度条画一条低对比度满条。
        local q = queued[st.id] or 0
        local kname = tostring((st.key and type(st.key) == 'function' and st.key()) or st.key or '?')
        if q > 0 then
          -- 有票排队但没轮到这个工位（池子里在排）→ 也说清楚
          setText(slot.step, string.format('\230\142\146\233\152\159\228\184\173 %d \229\188\160 \194\183 \232\191\152\230\178\161\232\189\174\229\136\176', q))
        else
          setText(slot.step, string.format('\230\156\172\229\183\165\228\189\141\230\151\160\230\180\187\239\188\136\230\140\137 %s \230\151\160\230\149\136\239\188\137', kname))
        end
        -- 进度条画一条很暗的满条，视觉上表明"这里现在不能做"
        SK.barSet(slot.bar, 0, { 255, 255, 255 })
        SK.barSet(slot.bar, 0, { 255, 255, 255 })
        -- ★ 这个工位**没活** → 压暗（按它不会有反应，画面先告诉你）
        local d = SK.darken(slot.col, 0.42)      -- 0.55 → 0.42：压得更暗，一眼区分
        H.setColor(slot.box, d[1], d[2], d[3], 255)
        H.setColor(slot.panel, SK.chip(d, 18)[1], SK.chip(d, 18)[2], SK.chip(d, 18)[3], 255)
        H.setColor(slot.key, 0, 0, 0, 30)
        H.setColor(slot.icon, 255, 255, 255, 90)          -- 没活：图标也压暗
        slot.busy = false
      end
    end
  end

  -- ★★ HUD 提示行：**明确告诉你哪个工位有活**
  --   用户报"按了没反应"，现场日志证明按键每次都被收到，
  --   真正原因是那个工位当时没活 → 现在直接把"有活"的工位列出来，按它一定有用。
  do
    local busy = {}
    for _, st in ipairs(V.STATIONS) do
      local slot = S[st.id]
      if slot and slot.busy then busy[#busy + 1] = kk(st.id, st.key) .. ' ' .. st.name:sub(1, 2) end
    end
    local tipTxt
    if s.phase == 'closing' then
      tipTxt = '\230\148\182\229\176\190\228\184\173\239\188\136\229\129\154\229\174\140\230\137\139\228\184\138\231\154\132\229\176\177\230\148\182\230\145\138\239\188\137'
    elseif #busy > 0 then
      tipTxt = '\231\142\176\229\156\168\232\131\189\230\140\137\239\188\154' .. table.concat(busy, '  ')
    else
      tipTxt = string.format('\230\154\130\230\151\160\229\143\175\229\129\154\231\154\132\230\180\187 \194\183 \233\148\174\228\189\141 %s/%s/%s/%s',
        kk('shake','Y'), kk('fire','H'), kk('chem','K'), kk('brew','P'))
    end
    setText(v.hud.tip, tipTxt)
    -- ★ 存一份"本帧原文"：入口的调试追加要用它当基准，
    --   否则读 v.hud.tip.text 再追加会**每帧自我累加、无限膨胀**（踩过）
    v.hudTips = tipTxt
  end

  -- 打包台
  do
    local n, names = 0, {}
    for _, sl in ipairs(s.slips) do
      if sl.ready then
        n = n + 1
        if #names < 3 then names[#names + 1] = (sl.cup.rec and sl.cup.rec.name) or '?' end
      end
    end
    if n > 0 then
      -- ★ 有杯等出餐时，**把要按的键写在打包台上**（真机日志证明玩家不知道该按什么：
      --   23 次按键里空格一次没按过，一直在按没用的键）
      local ph = string.format('\229\143\175\228\186\164\228\187\152 %d \230\157\175   %s%s   \226\134\144 \230\140\137 %s \229\135\186\233\164\144',
        n, table.concat(names, ' \194\183 '), n > 3 and ' \226\128\166' or '',
        kk('pack', '\231\169\186\230\160\188'))
      setText(v.pack.list, ph)
      H.setColor(v.pack.hint, C.onColor[1], C.onColor[2], C.onColor[3], 255)
    else
      setText(v.pack.list, '\230\154\130\230\151\182\230\178\161\230\156\137\232\166\129\228\186\164\228\187\152\231\154\132')
      H.setColor(v.pack.hint, C.dim[1], C.dim[2], C.dim[3], 255)
    end
  end

  -- 订单卡
  local oi = 0
  for _, o in ipairs(s.orders) do
    oi = oi + 1
    local card = v.orders[oi]
    if not card then break end
    for _, c in ipairs(card.controls) do H.show(c) end
    local frac = math.max(0, math.min(1, o.pat / (o.patMax > 0 and o.patMax or 1)))
    local acc = o.inProgress and C.shake or C.dim
    if frac < 0.28 then acc = C.bad elseif frac < 0.6 then acc = C.warn end
    H.setColor(card.tagBg, acc[1], acc[2], acc[3], 56)
    setText(card.tagT, o.inProgress and '\229\156\168\229\136\182' or ('\231\173\137\229\128\153 #' .. tostring(o.queueNo)))
    setStyle(card.tagT, T.font.small, acc)
    setText(card.who, o.name)
    setText(card.what, string.format('%s %s    \229\183\178\229\129\154 %d/%d', o.ice or '', o.sugar or '', o.made or 0, o.need))
    SK.barSet(card.bar, frac, acc)
    setText(card.pct, string.format('%d%%', math.floor(frac * 100)))
    setStyle(card.pct, T.font.small, acc)
  end
  for i = oi + 1, MAX_ORDERS do
    for _, c in ipairs(v.orders[i].controls) do H.hide(c) end
  end
  setText(v.panel.head, oi == 0 and '\231\173\137\229\128\153\229\140\186   \230\154\130\230\151\182\230\178\161\228\186\186' or ('\231\173\137\229\128\153\229\140\186 / \229\156\168\229\136\182   ' .. tostring(oi) .. ' \228\189\141'))
  if oi == 0 then H.show(v.panel.empty) else H.hide(v.panel.empty) end

  -- ═══ 小票行：每张票三行（谁 / 下一步 / 点我送去哪）═══
  --   ★ 卡上的提示直接照抄原版（网页版 1460-1463 行的 hint）：
  --     · 还没拿到名额      → 「等名额（后厨满了）」（灰色，点了没用）
  --     · 做完了等出餐      → 「可出餐 → 空格」
  --     · 已经在目的工位    → 「在本工位（按 X 动手）」
  --     · 票在别的工位/没挂 → 「→ 点我送 <工位名>」
  do
    local si = 0
    for _, sl in ipairs(s.slips or {}) do
      si = si + 1
      local sc = v.slips[si]
      if not sc then break end
      for _, c in ipairs(sc.controls) do H.show(c) end
      local nx = STATE.nextStep(sl.cup)
      local startable = sl.cup.done or sl.cup.startedAt ~= nil or sl.cup.slotReady
      local rec = sl.cup.rec or (sl.o and sl.o.rec)
      setText(sc.who, string.format('#%d %s', sl.id, rec and rec.name or '?'))
      local nxTxt
      -- ★ 出餐提示要**写出实际绑定的两个键**（空格 + 备用键 Z），
      --   真机日志里玩家根本不知道该按什么，最后一直在按没用的键。
      local packHint = string.format('\229\143\175\229\135\186\233\164\144 \226\134\146 %s \230\136\150 %s', kk('pack', '\231\169\186\230\160\188'), kk('pack2', 'Z'))
      if sl.ready then nxTxt = packHint
      elseif nx then
        local extra = ''
        if nx.kind == 'hold' then extra = '\239\188\136\230\140\137\228\189\143 ' .. tostring((CFG.hold and CFG.hold.sec) or 0.9) .. ' \231\167\146\239\188\137'
        elseif nx.kind == 'mash' then extra = string.format('\239\188\136\232\191\158\230\140\137 %d \228\184\139\239\188\137', nx.taps or 1) end
        nxTxt = clip(tostring(nx.t)) .. extra
      else nxTxt = '\239\188\136\230\178\161\230\156\137\228\184\139\228\184\128\230\173\165\228\186\134\239\188\137' end
      setText(sc.nextT, nxTxt)
      local hint, col
      if not startable then
        hint = '\231\173\137\229\144\141\233\162\157\239\188\136\229\144\142\229\142\168\230\187\161\228\186\134\239\188\137'; col = C.dim
      elseif sl.ready then
        hint = packHint; col = C.good
      elseif nx and sl.st == nx.st then
        hint = string.format('\229\156\168\230\156\172\229\183\165\228\189\141\239\188\136\230\140\137 %s \229\138\168\230\137\139\239\188\137', kk(nx.st, nx.st)); col = C.text
      elseif nx then
        hint = string.format('\226\134\146 \231\130\185\230\136\145\233\128\129 %s', V.STATION_NAME[nx.st] or tostring(nx.st)); col = C.gold
      else
        hint = '\226\128\148'; col = C.dim
      end
      setText(sc.fwd, hint)
      setStyle(sc.fwd, T.font.tiny, col)
      -- 卡身配色：等名额=压暗；可出餐=亮；有活可送=本色
      if not startable then
        setColor(sc.box, C.slotBg); setColor(sc.edge, C.dim)
      elseif sl.ready then
        setColor(sc.box, C.cardBg); setColor(sc.edge, C.good)
      else
        setColor(sc.box, C.cardBg); setColor(sc.edge, C.gold)
      end
    end
    for i = si + 1, MAX_SLIPS do
      for _, c in ipairs(v.slips[i].controls) do H.hide(c) end
    end
  end

  -- ★★ 左列"营业数据"9 项（还原原版的信息量）
  --   字段全部来自 state.lua / day.lua / config.lua，不自己造数
  if v.data then
    local D = __m_day()
    local wip = 0
    for _, sl in ipairs(s.slips or {}) do
      if not sl.ready then wip = wip + 1 end
    end
    local interval = 0
    pcall(function() interval = D.arriveInterval(s) end)
    local money = (s.money or 0)
    local rent = (s.today and s.today.rent) or CFG.rent.perDay
    local vals = {
      string.format('%d \229\133\131', money),
      string.format('%d \229\133\131%s', (s.rentPaid or 0), ((s.rentDebt or 0) > 0) and ('  \230\172\160' .. s.rentDebt) or ''),
      string.format('%d \230\157\175', s.served or 0),
      string.format('%d / %d', s.mistakes or 0, s.left or 0),
      string.format('x%d  (\230\156\128\233\171\152 x%d)', s.combo or 0, s.maxCombo or 0),
      CFG.auto and CFG.auto.on and '\229\188\128' or '\229\133\179',
      string.format('%d / %d \229\141\149', wip, CFG.kitchen.maxWip),
      string.format('%.1f \231\167\146', interval),
      string.format('%d \228\189\141', s.leftWaiting or 0),
    }
    for i, r in ipairs(v.data.rows) do
      setText(r.val, vals[i] or '\226\128\148')
      -- 颜色：营业额金色、翻车流失红色、连击奶油色
      local col = C.text
      if i == 1 then col = C.gold
      elseif i == 4 then col = ((s.mistakes or 0) + (s.left or 0)) > 0 and C.bad or C.dim
      elseif i == 5 then col = (s.combo or 0) > 1 and C.warn or C.dim
      elseif i == 6 then col = (CFG.auto and CFG.auto.on) and C.good or C.dim
      elseif i == 9 then col = (s.leftWaiting or 0) > 0 and C.bad or C.dim end
      setStyle(r.val, T.font.small, col)
    end
  end
end

-- ═══════════════════════════════════════════════════════════════════
-- 菜单（居中大字；玩区由入口隐藏）
-- ═══════════════════════════════════════════════════════════════════
function V.drawMenu(v, sel)
  if not v or not v.menu then return end
  local M = v.menu
  local CFGM = __m_config().modes
  -- 模式表（顺序 = 原版 Object.entries(CFG.modes)：按总时长从短到长）
  --   ★★ 2026-09-27 还原度修正：三个模式**都开放**。
  --      原版（网页版 391-395）quick/fast/slow 全是单人局，days = 1/5/5、总时长 300/600/1200 秒。
  --      移植版曾把 fast/slow 标成"施工中（多人相关）"锁掉 —— 那是我自己加的闸，
  --      代码里没有任何依据，直接砍掉了原版的**主玩法（5 天日循环）**。
  local MODES = {
    { key = 'quick', ready = true },
    { key = 'fast',  ready = true },
    { key = 'slow',  ready = true },
  }
  local selKey = (MODES[sel] and MODES[sel].key) or 'quick'
  local selM = CFGM[selKey]

  setText(M.title, '\233\155\170\231\154\135\231\154\132\229\144\142\229\142\168 \194\183 \232\141\146\232\175\158\233\165\174\229\147\129\230\168\161\230\139\159\229\153\168')
  setStyle(M.title, T.font.title, C.gold)
  setText(M.sub, '\229\144\141\229\173\151\231\166\187\232\176\177\239\188\140\230\147\141\228\189\156\231\156\159\229\174\158\227\128\130\230\138\138\229\183\166\232\190\185\231\154\132\229\176\143\231\165\168\230\139\150\229\136\176\229\183\165\228\189\141\239\188\140\228\184\128\230\173\165\228\184\128\230\173\165\229\129\154\229\135\186\230\157\165\239\188\140\233\128\129\229\136\176\230\137\147\229\140\133\229\143\176\227\128\130')

  for i = 1, 3 do
    local card = M.cards[i]
    local mk = MODES[i]
    local m = mk and CFGM[mk.key]
    if not card or not m then
      for _, c in ipairs(card and card.controls or {}) do H.hide(c) end
    else
      local on = (i == sel)
      local secs = m.total or ((m.days or 1) * (m.perDay or 0))
      setText(card.big, string.format('%d \229\136\134\233\146\159', math.floor(secs / 60)))
      setStyle(card.big, T.font.title, C.text)
      setText(card.name, m.label)
      setStyle(card.name, T.font.small, C.text)
      setText(card.desc, string.format('%s%s', m.desc or '',
        (m.days or 1) > 1 and string.format('\239\188\136\230\175\143\229\164\169 %d \229\136\134\233\146\159\239\188\137', math.floor((m.perDay or 0) / 60)) or ''))
      -- 选中卡：粉色描边（原版 .mode.sel{border-color:#ff5e6c}）
      H.setColor(card.edge, on and 255 or 47, on and 94 or 58, on and 108 or 86, 255)
      H.setColor(card.card, on and 30 or 21, on and 36 or 27, on and 52 or 40, 255)
    end
  end

  setText(M.rulesHead, '\230\128\142\228\185\136\231\142\169')
  setStyle(M.rulesHead, T.font.small, C.text)
  -- 原版 7 条（键位替换成我们的实际绑定）
  local ks = IN and IN.primary or {}
  local function kn(a, d) local q = ks[a]; return (q == nil or q == '') and d or (q == 'SPACE' and '\231\169\186\230\160\188' or tostring(q)) end
  local rules = {
    '\230\142\165\229\141\149\239\188\154\229\183\166\232\190\185\232\135\170\229\138\168\232\191\155\229\174\162\239\188\155\229\144\142\229\142\168\229\144\140\230\151\182\229\143\170\232\131\189\230\156\137 3 \228\184\170\230\156\170\229\174\140\230\136\144\228\187\187\229\138\161\239\188\140\229\164\154\231\154\132\229\156\168\231\173\137\229\128\153\229\140\186\230\142\146\233\152\159\239\188\136\230\142\146\233\152\159\228\185\159\229\144\131\232\128\144\229\191\131\239\188\137',
    '\230\181\129\232\189\172\239\188\154\229\176\143\231\165\168\228\188\154\232\135\170\229\138\168\232\181\176\229\136\176\228\184\139\228\184\128\230\137\139\239\188\155\230\131\179\230\138\162\233\128\159\229\186\166\229\176\177**\231\130\185\229\176\143\231\165\168**\231\171\139\229\136\187\233\128\129\232\191\135\229\142\187',
    string.format('\229\129\154\229\183\165\228\189\141\239\188\154%s \230\141\163\233\148\164 \194\183 %s \231\129\171\231\179\187 \194\183 %s \229\140\150\229\173\166 \194\183 %s \232\144\131\232\140\182\239\188\136\230\140\137\228\189\143\231\177\187\232\166\129\230\140\137\228\189\143\227\128\129\232\191\158\230\140\137\231\177\187\232\166\129\232\191\158\230\140\137\239\188\137',
      kn('shake','Y'), kn('fire','H'), kn('chem','K'), kn('brew','P')),
    string.format('\229\135\186\233\164\144\239\188\154\229\176\143\231\165\168\229\133\168\231\187\191\229\144\142\232\135\170\229\138\168\232\191\155\230\137\147\229\140\133\229\143\176\239\188\140\230\140\137 %s \230\136\150 %s \229\135\186\233\164\144\239\188\140\232\182\138\229\191\171\232\175\132\229\136\134\232\182\138\233\171\152',
      kn('pack','\231\169\186\230\160\188'), kn('pack2','Z')),
    '\231\186\170\229\190\139\239\188\154\229\129\154\233\148\153\229\183\165\228\189\141 = \231\191\187\232\189\166\230\137\163\233\146\177\239\188\155\229\174\162\228\186\186\232\128\144\229\191\131\230\157\161\231\169\186\228\186\134\229\176\177\232\181\176\228\186\186',
    string.format('\230\151\182\233\151\180\239\188\154\230\149\180\229\165\151\231\187\143\232\144\165\233\148\129\230\173\187\229\156\168 %d \229\136\134\233\146\159\233\135\140\239\188\140\229\191\153\231\154\132\230\151\182\229\128\153\230\151\182\233\151\180\231\168\141\230\133\162\227\128\129\233\151\178\228\184\139\230\157\165\231\168\141\229\191\171',
      math.floor(((selM and (selM.total or ((selM.days or 1) * (selM.perDay or 0)))) or 300) / 60)),
    string.format('\229\188\128\229\133\179\239\188\136\232\144\165\228\184\154\228\184\173\239\188\137\239\188\154%s \232\135\170\229\138\168\230\181\129\232\189\172 \194\183 %s \232\135\170\229\138\168\229\135\186\231\165\168 \194\183 %s \230\154\130\229\129\156',
      kn('mode1','1'), kn('mode2','2'), kn('mode3','3')),
  }
  for i, line in ipairs(M.ruleLines) do
    setText(line, '\194\183 ' .. (rules[i] or ''))
    setStyle(line, T.font.tiny, i == 7 and C.warn or C.dim)
  end

  setText(M.goTx, '\229\188\128\233\151\168\232\144\165\228\184\154 \226\134\146')
  setStyle(M.goTx, T.font.body, { 255, 255, 255 })
  local okGo = MODES[sel] ~= nil
  H.setColor(M.goBg, okGo and 255 or 90, okGo and 94 or 100, okGo and 108 or 120, 255)
  if M.goLo then H.setColor(M.goLo, okGo and 217 or 74, okGo and 59 or 82, okGo and 76 or 100, 255) end
  setText(M.tag, '\227\128\140\229\166\130\230\158\156\228\189\160\229\156\168\231\148\159\230\180\187\228\184\173\229\150\132\228\186\142\232\167\130\229\175\159\239\188\140\228\184\128\229\174\154\232\131\189\228\189\147\228\188\154\229\136\176\232\191\153\231\167\141\230\132\159\232\167\137\227\128\130\227\128\141')
  -- HUD 在菜单里当"品牌条"：只留副标题 + 提示
  setText(v.hud.title, '\232\141\146\232\175\158\233\165\174\229\147\129\230\168\161\230\139\159\229\153\168'); setStyle(v.hud.title, T.font.small, C.dim)
  setText(v.hud.clock, (MODES[sel] and MODES[sel].ready) and '\231\130\185\227\128\140\229\188\128\233\151\168\232\144\165\228\184\154\227\128\141\229\188\128\229\167\139' or '\230\150\189\229\183\165\228\184\173')
  setStyle(v.hud.clock, T.font.head, (MODES[sel] and MODES[sel].ready) and C.good or C.bad)
  for _, it in ipairs(v.hud.items) do setText(it.val, ''); setText(it.label, '') end
  -- 三行大字在菜单里不用（原版的信息都在面板里）
  setText(v.big.title, ''); setText(v.big.line1, '')
  setText(v.big.line2, ''); setText(v.big.line3, '')
  -- ★ 最后**直接 SetVisible(true)**（H.show 对这批无效，且 SetVisible 紧跟 SetActive 会翻回 false）
  for _, c in ipairs(M.controls) do
    pcall(function() c:SetActive(true) end)
    pcall(function() c:SetVisible(true) end)
  end
end

-- ═══════════════════════════════════════════════════════════════════
-- 结算 / 总分
-- ═══════════════════════════════════════════════════════════════════
function V.drawResult(v, s)
  if not v or not s then return end
  for _, c in ipairs(v.big.controls) do pcall(function() c:SetVisible(true) end) end
  local function put(title, tCol, tSize, l1, l2, l3)
    setText(v.big.title, title); setStyle(v.big.title, tSize, tCol)
    setText(v.big.line1, l1 or ''); setStyle(v.big.line1, T.font.head, C.text)
    setText(v.big.line2, l2 or ''); setStyle(v.big.line2, T.font.body, C.dim)
    setText(v.big.line3, l3 or ''); setStyle(v.big.line3, T.font.small, C.dim)
  end
  if s.ended and s.result then
    local r = s.result
    put(string.format('\230\148\182\230\145\138\239\188\129\232\175\132\231\186\167 %s', tostring(r.rank)), C.gold, T.font.display,
      string.format('\230\128\187\229\136\134 %d', r.total or 0),
      string.format('\229\135\186\233\164\144 %d \194\183 \230\181\129\229\164\177 %d \194\183 \231\191\187\232\189\166 %d', s.served or 0, s.left or 0, s.mistakes or 0),
      '\230\140\137\231\169\186\230\160\188\229\155\158\229\136\176\232\143\156\229\141\149\239\188\140\229\134\141\230\157\165\228\184\128\229\177\128')
    return
  end
  if s.settling then
    local last = s.dayStats and s.dayStats[#s.dayStats]
    -- ★ 字段名必须与 day.lua 的记录一致：dayStats 存的是 { day, served, money, left, mistakes, rent, paid }
    --   原来读 `last.revenue`（不存在）→ 结算页营业额**恒显示 0**（审计挖出来的真值 bug）。
    put(string.format('\231\172\172 %d \229\164\169\231\187\147\231\174\151\229\174\140\228\186\134', s.day), C.gold, T.font.title,
      last and string.format('\229\135\186\233\164\144 %d \230\157\175 \194\183 \232\144\165\228\184\154\233\162\157 %d', last.served or 0, last.money or 0) or '',
      last and string.format('\230\181\129\229\164\177 %d \194\183 \231\191\187\232\189\166 %d', last.left or 0, last.mistakes or 0) or '',
      string.format('\230\136\191\233\146\177 %s \194\183 \230\137\139\228\184\138\232\191\152\229\137\169 %d \229\133\131      \230\140\137\231\169\186\230\160\188\231\187\167\231\187\173',
        (last and last.paid) or '\229\183\178\228\187\152', s.money or 0))
  end
end

-- 收起菜单/结算大字（进玩区时调）
-- ★★ 动作反馈大字（V.showFeed / V.hideFeed）已随还原度重做删除 —— 原版没有这种东西。
function V.hideBig(v)
  if not v or not v.big then return end
  for _, c in ipairs(v.big.controls) do H.hide(c) end
end

-- ★★ 结算页/总分页的"独占画面"开关
--   用户反馈："收摊！出现了但**没盖住后面**"（工位卡还看得见、糊在一起）。
--   做法：进结算 → 藏玩区 + 显示"结算背景板"（SheetBag：一块**后建**的不透明整屏底，
--        因为 Z 序是"后建的在上"，它会盖住工位/打包台/订单面板，但不会盖住结算大字
--        —— 大字是在它之后建的）。回玩区 → 玩区恢复 + 藏掉背景板。
--   幂等：只在状态**变化**时动控件。
function V.showResultSheet(v, on)
  if not v then return end
  if v._sheet == on then return end
  v._sheet = on
  if on then
    V.setBoardVisible(v, false)
    if v.sheetBag then H.show(v.sheetBag) end
  else
    if v.sheetBag then H.hide(v.sheetBag) end
    V.setBoardVisible(v, true)
  end
end

return V

  end)()
  if __c_view == nil then __c_view = true end
  return __c_view
end
-- ── 入口源码（与本层同级：能看见上面的缓存；生命周期函数在这里定义 = 真正的全局）──
-- @entry
-- xuehuang.lua —— 雪皇的后厨 · 千星客户端脚本入口（正式版）
--
-- 这一层只做四件事：
--   ① 生命周期接线（OnInit / OnStart / OnUpdate）
--   ② 状态机：菜单 → 营业 → 当日结算 → 总分 → 重开
--   ③ 输入路由（按键 + 光标点击 → 逻辑层动作 / 界面操作）
--   ④ 把逻辑层的事件变成提示文案
-- ★ 它**不含任何玩法规则**：规则全在 kitchen/order/day 里，改规则不要改这个文件。
--
-- 平台契约（踩过的坑，别改回去）：
--   · 建控件必须在 OnStart 及之后（InstantiateClientUIControl 在 OnInit 返回 nil）
--   · 必须 script:EnableUpdate(true)，否则收不到 OnUpdate
--   · game 的全局函数用点号调用；新建控件默认"纯白 + 可见"→ 建完立刻设色或隐藏
--   · 光标点击要先 showCursor=true（host.lua 已设），且需要一个"光标检测区域"控件

local H = __m_host()
local G = __m_game()
local V = __m_view()
local IN = __m_input()
local CFG = __m_config()

local BUILD = 'xuehuang-r3'   -- 纯 ASCII，方便在日志里搜（r3 = 出餐双键 + 按键探针 + 名额硬上界）

local built, bootErr = false, nil
local _tickErrShown = false
local v, hostCfg = nil, nil
local banner, bannerT, _bannerActive = nil, 0, false
-- ★ showCounts **默认关**：HUD 上不该出现调试尾巴（要看就在脚本变量里设 showCounts=1）
local autoplay, heartbeat, showCounts = false, false, false
-- ★ 有菜单（原版 showStart 就是选模式界面）：scene = 'menu' | 'play'
local menuMode = 2          -- 菜单上选中的模式（1..3）；★ 默认 2 = 原版默认的「标准」fast
local scene = 'menu'
local paused = false        -- 暂停（原版 Esc；平台无 Esc 语义键 → 营业中用 3 切换）

local function say(...) H.say('\233\155\170\231\154\135', ...) end

local function tip(msg, sec)
  banner, bannerT = tostring(msg), (sec or 2.0)
  _bannerActive = true
  if v then V.setBanner(v, banner) end
end

-- ── 逻辑事件 → 提示 ──
local function wireEvents()
  G.on('arrive', function(e) tip(string.format('%s \232\166\129 %s %s %s', e.o.name, e.o.makeup, e.o.ice, e.o.sugar), 2.2) end)
  G.on('leave',  function(e) tip(string.format('%s \231\173\137\228\184\141\229\143\138\232\181\176\228\186\134', e.o.name), 2.2) end)
  G.on('lastcall', function() tip('\230\156\128\229\144\142\230\142\165\229\141\149\239\188\154\228\185\139\229\144\142\228\184\141\229\134\141\230\148\190\228\186\186\232\191\155\230\157\165', 3) end)
  G.on('closing',  function() tip('\230\137\147\231\131\138\239\188\154\228\184\141\229\134\141\230\142\165\229\190\133\230\150\176\233\161\190\229\174\162\239\188\140\230\137\139\228\184\138\231\154\132\229\129\154\229\174\140\229\176\177\230\148\182\230\145\138', 3) end)
  G.on('graceout', function() tip('\230\184\133\229\156\186\230\151\182\233\151\180\229\136\176\239\188\154\229\138\168\232\191\135\230\137\139\231\154\132\231\174\151\228\186\164\228\187\152\239\188\140\230\178\161\229\188\128\229\183\165\231\154\132\232\174\176\230\181\129\229\164\177', 3) end)
  G.on('dayend',   function(e) tip(string.format('\231\172\172 %d \229\164\169\231\187\147\231\174\151', e.day), 3) end)
end

-- ── 状态机 ──
-- ★ 菜单 = 原版 showStart 的选模式界面（用户指出我漏了它）。
--   ⚠️ 用户要求"删掉按空格开始的逻辑"指的**不是菜单**，而是别的地方；
--      原版确实是"选完模式 → 开门营业 → 进游戏"，所以菜单保留。
local function enterMenu()
  scene = 'menu'
  pcall(function() __m_input().clearInput() end)
  if v then
    V.setBoardVisible(v, false)
    V.setMenuVisible(v, true)
    V.setBanner(v, nil)
  end
end

-- ★★ 三个模式**全部可玩**（2026-09-27 还原度修正）。
--   原版（网页版 391-395 行）quick/fast/slow 都是单人局，days=1/5/5、总时长 300/600/1200 秒，
--   移植版却把 fast/slow 标成"施工中（多人相关）"锁掉了 —— 那是我自己加的闸，
--   代码里没有任何依据，而且直接砍掉了原版的**主玩法（5 天日循环）**。
--   现在恢复：三个模式都能进，菜单上不再有"施工中"。
local DEFAULT_MODE = 'fast'       -- 与 menuMode 的默认值一致
local MODE_ORDER = { 'quick', 'fast', 'slow' }

-- 工位动作 → 中文名（提示文案用；键位映射的唯一真相仍在 input.lua 的 IN.BIND）
local STATION_ACT = { shake = '\230\141\163\233\148\164', fire = '\231\129\171\231\179\187', chem = '\229\140\150\229\173\166', brew = '\232\144\131\232\140\182', pack = '\230\137\147\229\140\133' }

local function startGame()
  local m = IN.MODES[menuMode] or DEFAULT_MODE
  G.newGame(m)
  scene = 'play'
  paused = false
  pcall(function() __m_input().clearInput() end)
  if v then
    local n = V.setBoardVisible(v, true)
    V.setMenuVisible(v, false)    -- 玩区排满了，收起菜单资料面板
    V.hideBig(v)                  -- 收起大字
    say('\229\188\128\229\177\128\239\188\154\230\168\161\229\188\143=%s\239\188\140\230\152\190\231\164\186\231\142\169\229\140\186 %d \228\184\170\230\142\167\228\187\182', m, n)
  end
  tip('\229\188\128\229\188\160\239\188\129\230\140\137 Y/H/K/P \229\129\154\229\183\165\228\189\141\239\188\140\231\169\186\230\160\188\230\137\147\229\140\133', 3.5)
end

-- 菜单/结算页的按键消费；返回 true = 已消费
--   · 菜单：1/2/3 选模式（三个都能玩），确认键 / 点屏幕 = 开门营业
--   · 结算中（一天的账）→ 确认键 = 进入下一天
--   · 整局结束（总分页）→ 确认键 = 回菜单再选一局
local function uiAct(act)
  if scene == 'menu' then
    -- 1/2/3 选模式（与原版 showStart 的模式卡片一一对应）
    local mi = ({ mode1 = 1, mode2 = 2, mode3 = 3 })[act]
    if mi then
      menuMode = mi
      local mk = IN.MODES[mi]
      V.drawMenu(v, menuMode)
      tip(string.format('\229\183\178\233\128\137\239\188\154%s \226\128\148\226\128\148 \231\130\185\227\128\140\229\188\128\233\151\168\232\144\165\228\184\154\227\128\141\229\188\128\229\167\139', tostring(mk)), 2.5)
      return true
    end
    -- ★ 开局方式（用户要求）：菜单里**空格不触发开门**；点屏幕 = 原版「开门营业」按钮
    --   键盘后备 = 确认键（Backspace；43 个奇匠按键里没有回车）
    if act == 'confirm' or act == 'click' then startGame(); return true end
    return false
  end
  if G.s and (G.s.settling or G.s.ended) and (act == 'confirm' or act == 'pack') then
    if G.s.ended then
      say('\230\149\180\229\177\128\231\187\147\230\157\159 \226\134\146 \229\155\158\232\143\156\229\141\149')
      enterMenu()
    else
      G.nextDay()
    end
    return true
  end
  return false
end

local function boot()
  if built then return end
  built = true
  local ok, err = pcall(function()
    local root = H.root()
    if not root then error('\230\137\190\228\184\141\229\136\176\230\140\130\232\189\189\230\142\167\228\187\182\239\188\154\232\132\154\230\156\172\232\166\129\230\140\130\229\156\168**\229\174\162\230\136\183\231\171\175\230\142\167\228\187\182\229\174\185\229\153\168**\228\184\138') end
    pcall(function() root:SetActive(true) end)
    hostCfg = H.setup(root)
    v = V.init(hostCfg)
    autoplay   = tonumber(tostring(H.param('autoplay', 0))) ~= 0
    heartbeat  = tonumber(tostring(H.param('heartbeat', 0))) ~= 0
    showCounts = tonumber(tostring(H.param('showCounts', 0))) ~= 0
    if autoplay then say('autoplay=1\239\188\154\230\156\186\229\153\168\228\186\186\230\155\191\231\142\169\229\174\182\230\137\147\239\188\136\230\156\172\229\156\176\229\135\186\229\155\190\231\148\168\239\188\137') end
    wireEvents()
    IN.attach(hostCfg, tip)
    -- ★ 按键探针默认开（r2 诊断版）：按一下键就会在日志里留下 [KDOWN X] 一行。
    --   要关就设脚本变量 keyLog=0（日志干净之前先别关，它只打按键那几行）。
    IN.logKey(tonumber(tostring(H.param('keyLog', 1))) ~= 0)
    -- ★ 光标检测区域铺满画布（默认 0×0 → 点不中；见 input.lua 的 ensureAreaSize）
    do
      local area = IN.findArea(hostCfg.root)
      if area then
        -- ★ 兼容：旧版有 IN.ensureAreaSize，重写后它并入了 attach；
        --   这里用 pcall + 直调 SetSizeDelta，**绝不能再让 boot 抛错**
        --   （boot 抛错 → bootErr 设置 → 之后每帧 return → 全游戏卡死，这是真机"点一次也没反应"的根因）
        local okA = pcall(function() area:SetSizeDelta(hostCfg.spaceW or 1920, hostCfg.spaceH or 1080) end)
        say('\229\133\137\230\160\135\230\163\128\230\181\139\229\140\186\229\159\159\229\183\178\233\147\186\230\187\161 %sx%s -> %s', tostring(hostCfg.spaceW), tostring(hostCfg.spaceH), okA and 'ok' or '\229\164\177\232\180\165')
      else
        say('\232\173\166\229\145\138\239\188\154\230\142\167\228\187\182\230\160\145\233\135\140\230\178\161\230\156\137"\229\133\137\230\160\135\230\163\128\230\181\139\229\140\186\229\159\159"\239\188\140\233\188\160\230\160\135\231\130\185\229\135\187\228\184\141\229\143\175\231\148\168\239\188\136\232\143\156\229\141\149\229\176\134\229\143\170\232\131\189\233\157\160\233\148\174\231\155\152\239\188\137')
      end
    end
    -- ★ 先停在菜单（原版 showStart）——点「开门营业」或按确认键才开局
    scene = 'menu'
    V.setBoardVisible(v, false)
    V.setMenuVisible(v, true)
    V.drawMenu(v, menuMode)
    say('\229\183\178\229\176\177\231\187\170 BUILD=%s \226\128\148\226\128\148 \232\143\156\229\141\149\239\188\136\230\140\137 1/2/3 \233\128\137\230\168\161\229\188\143 \226\134\146 \231\130\185\229\177\143\229\185\149\229\188\128\233\151\168\232\144\165\228\184\154\239\188\137', BUILD)
    tip(string.format('BUILD=%s  \232\143\156\229\141\149\239\188\154\230\140\137 1/2/3 \233\128\137\230\168\161\229\188\143 \226\134\146 \229\188\128\233\151\168\232\144\165\228\184\154', BUILD), 6)
  end)
  if not ok then
    bootErr = tostring(err)
    say('BUILD-FAILED %s', bootErr)
    pcall(function() if v then V.setBanner(v, 'BOOT-ERR ' .. bootErr) end end)
  end
end

function OnInit()
  say('OnInit\239\188\136\229\143\170\231\153\187\232\174\176\239\188\140\228\184\141\229\187\186\230\142\167\228\187\182\239\188\137')
  if script and script.EnableUpdate then
    local ok, e = pcall(function() script:EnableUpdate(true) end)
    say('EnableUpdate(true) -> %s', ok and 'ok' or tostring(e))
  end
end

function OnStart() boot() end

local _heart = 0
function OnUpdate(dt)
  _heart = _heart + 1
  if heartbeat and _heart % 60 == 0 then
    say('\229\191\131\232\183\179 %d \229\184\167 \194\183 \229\156\186\230\153\175=%s \194\183 t=%s', _heart, tostring(scene),
        G.s and string.format('%.1f', G.s.t) or 'nil')
  end
  if not built then boot() end
  if bootErr then return end
  local dt2 = dt or 0.033

  -- ① 逻辑推进（结算页/总分时冻结；暂停时不推进）
  if scene == 'play' and not paused and G.s and not G.s.settling and not G.s.ended then
    local ok, err = pcall(function() G.tick(dt2) end)
    if not ok then
      -- ★★ 逻辑出错**不再永久卡死**（旧版设置 bootErr → 之后每帧直接 return →
      --   玩家看到的就是"按键/点击全都没反应"）。现在：记日志 + 报一次横幅，但**继续跑**。
      say('tick \229\135\186\233\148\153\239\188\136\229\183\178\229\191\189\231\149\165\239\188\140\231\187\167\231\187\173\232\191\144\232\161\140\239\188\137\239\188\154%s', tostring(err))
      if v and not _tickErrShown then
        _tickErrShown = true
        pcall(function() V.setBanner(v, '\233\128\187\232\190\145\233\148\153\232\175\175\239\188\154' .. tostring(err)) end)
      end
    end
  end

  -- ② 自动演示（只在脚本变量 autoplay=1 时）
  --   ★ autoplay 也要**自己开门**：默认停在菜单（等玩家点"开门营业"），
  --     而本地出图/回归没有鼠标 → 不放行的话截图永远停在菜单上（我踩过这个坑）。
  if autoplay then
    pcall(function()
      if scene == 'menu' then startGame() end
    end)
  end
  if autoplay and scene == 'play' then
    pcall(function()
      if G.s and G.s.settling then G.nextDay()
      elseif G.s and not G.s.ended then __bot() end
    end)
  end

  -- ③ 输入：界面层优先，剩下的给玩法
  IN.frameDt = dt2
  IN.pump({
    tip = tip,
    act = function(act, kind)
      -- ★ 出餐有两个键（空格 + Z）：语义归一成 pack，后面只认一个名字。
      --   为什么需要备用键：真机日志里玩家 23 次按键中**空格一次都没按过**，
      --   而空格在千星是"跳跃/滑翔"事件，可能收不到（详见 input.lua 的 BIND 注释）。
      if act == 'pack2' then act = 'pack' end
      -- ★★ 鼠标点击：**必须在这里拦**（在玩法命中测试之前）
      if act == 'click' then
        -- ★ 顺序（关键）：**菜单/结算页先处理点击**，再轮到玩区的命中测试。
        --   踩坑记录：原来 click 分支无条件 return（提前退出），而"菜单点任意处开门"
        --   的逻辑在 uiAct 里 → 菜单永远收不到点击 → 卡在菜单进不去游戏。
        if uiAct('click') then return nil end
        if not v then IN.clearClick(); return nil end
        local I2 = __m_input()
        local ck = I2.clicked
        local hitId = nil
        for _, st in ipairs(V.STATIONS) do
          local slot = v.stations[st.id]
          if slot and IN.hit(v, slot.box, 10) then hitId = st.id break end
        end
        if not hitId and IN.hit(v, v.pack.box, 10) then hitId = 'pack' end
        if ck then
          say('\233\188\160\230\160\135\231\130\185\229\135\187 (%d,%d) \226\134\146 \229\145\189\228\184\173 %s', math.floor(ck.x), math.floor(ck.y), tostring(hitId or '\231\169\186\229\164\132'))
        end
        I2.clearClick()
        -- ★★ 点工位卡 = 按那个工位键（原版 doStationAction(btn,'press')）
        if hitId then return G.act(hitId, 'press', nil, { route = true }) end
        -- ★★ 点小票卡 = 立刻把它送去"该去的工位"（原版 forwardSlip，网页版 859/1472 行）
        --   这条交互以前**整个漏掉**：玩家没有任何手动寻路手段，只能等 5 秒自动流转，
        --   于是按工位键 99% 无活可做（真机日志 9003 条 [REJECT]）。
        --   ⚠️ 顺序：先判工位卡再判小票卡 —— 工位卡压在面板上层，先命中它更符合直觉。
        if v.slips then
          for _, sc in ipairs(v.slips) do
            if sc.box and sc.slip and IN.hit(v, sc.box, 6) then
              local okf, dst = K.forwardSlip(G.s, sc.slip, false)
              if okf and dst then
                -- 原版提示：小票自动流转 → <工位名>
                local nmS = ({ shake = '\230\141\163\233\148\164\229\140\186', fire = '\231\129\171\231\179\187\229\140\186', chem = '\229\140\150\229\173\166\229\140\186', brew = '\232\144\131\232\140\182\229\140\186', pack = '\230\137\147\229\140\133\229\143\176' })[dst] or dst
                tip(string.format('\229\176\143\231\165\168 #%d \226\134\146 %s', sc.slip.id, nmS), 1.8)
                say('\231\130\185\229\176\143\231\165\168 #%d \226\134\146 %s', sc.slip.id, tostring(dst))
              else
                tip(string.format('\229\176\143\231\165\168 #%d\239\188\154%s', sc.slip.id, tostring(dst or '\233\128\129\228\184\141\232\191\135\229\142\187')), 1.8)
                say('\231\130\185\229\176\143\231\165\168 #%d \230\178\161\233\128\129\229\138\168\239\188\154%s', sc.slip.id, tostring(dst))
              end
              return nil
            end
          end
        end
        return nil
      end
      -- ★★ 界面层优先（菜单选模式 / 开门 / 结算继续）
      if uiAct(act) then return nil end
      -- ★ 营业中的开关：1/2/3 = 自动流转 / 自动出票 / 暂停（原版 A/S/Esc）
      if act == 'mode1' then
        if kind ~= 'release' then
          CFG.auto.on = not CFG.auto.on
          tip(CFG.auto.on and '\232\135\170\229\138\168\230\181\129\232\189\172\239\188\154\229\188\128\239\188\136\229\176\143\231\165\168\232\135\170\229\183\177\232\181\176\239\188\137' or '\232\135\170\229\138\168\230\181\129\232\189\172\239\188\154\229\133\179\239\188\136\232\166\129\228\189\160\228\186\178\230\137\139\231\130\185\229\176\143\231\165\168\233\128\129\239\188\137', 2.2)
        end
        return nil
      end
      if act == 'mode2' then
        if kind ~= 'release' then
          CFG.autoTicket.on = not CFG.autoTicket.on
          tip(CFG.autoTicket.on and '\232\135\170\229\138\168\229\135\186\231\165\168\239\188\154\229\188\128' or '\232\135\170\229\138\168\229\135\186\231\165\168\239\188\154\229\133\179\239\188\136\232\166\129\230\137\139\229\138\168\232\181\183\230\157\175\239\188\137', 2.2)
        end
        return nil
      end
      if act == 'mode3' then
        if kind ~= 'release' then
          paused = not paused
          tip(paused and '\229\183\178\230\154\130\229\129\156\239\188\136\229\134\141\230\140\137 3 \231\187\167\231\187\173\239\188\137' or '\231\187\167\231\187\173\232\144\165\228\184\154', 2.2)
        end
        return nil
      end
      if act == 'confirm' then return nil end

      -- ★★ 四个工位键 + 空格：走玩法层，**带自动送票**（opt.route）。
      --   这就是"按下去永远有回应"的那一环：票不在工位 → 先把票送过来，再动手。
      --   结果一律有可见反馈（成功/翻车/没活），不再有静默失败。
      if kind ~= 'release' and STATION_ACT[act] then
        local nm = STATION_ACT[act]
        local r = G.act(act, kind, nil, { route = true })
        if r and r.ok then
          local step = r.step
          say('%s \226\134\146 %s\239\188\136%s\239\188\137', nm, tostring(r.after or 0),
              step and tostring(step.t) or '')
          if step and step.kind == 'mash' then
            tip(string.format('%s\239\188\154\232\191\158\230\140\137 %d/%d', nm, math.floor(r.after or 0), step.taps or 1), 1.6)
          elseif step and step.kind == 'hold' then
            tip(string.format('%s\239\188\154\230\140\137\228\189\143\228\184\141\230\148\190 %.1f/%.1f \231\167\146', nm, r.after or 0,
                (CFG.hold and CFG.hold.sec) or 0.9), 1.8)
          elseif r.done then
            tip(string.format('OK %s\239\188\154\232\191\153\228\184\128\230\173\165\229\174\140\230\136\144', nm), 1.8)
          else
            tip(string.format('OK %s \230\142\168\232\191\155\228\184\173', nm), 1.4)
          end
        else
          say('%s \230\178\161\230\180\187\239\188\154%s', nm, tostring(r and r.why))
          tip(string.format('\195\151 %s\239\188\154%s', nm, tostring(r and r.why or '\231\142\176\229\156\168\229\129\154\228\184\141\228\186\134')), 2.4)
        end
        return r
      end
      if kind == 'release' and STATION_ACT[act] then
        return G.act(act, kind)          -- 松手：按住类停下（原版 doStationAction(btn,'release')）
      end
      return nil
    end,
  })

  -- ④ 画面
  local okSync, errSync = pcall(V.sync, v, G.s)
  if not okSync then say('V.sync \229\135\186\233\148\153\239\188\154%s', tostring(errSync)) end
  -- ★ 玩区显隐：**每帧按 scene 对齐**（幂等，先设后不设）。
  --   为什么不用"切换时调一次"：实测那次调用会被后续逻辑推翻（14 个控件设成显示、
  --   下一帧又变回隐藏），查不出是谁干的。每帧对齐是"单一数据源"，不会再打架。
  if v then
    V.setBoardVisible(v, scene == 'play')
    -- ★ 菜单资料面板（营业数据/产品手册/快捷键）：**只有菜单态显示**
    --   （用户反馈"初始界面忘记把产品菜单以及其他的隐藏了"）
    V.setMenuVisible(v, scene ~= 'play')
  end

  -- ★ 常显诊断尾巴：**默认关**（HUD 上不该出现调试字样）
  --   ⚠️ 曾经写成 H.setText(c, c.text .. '…') 每帧追加 → 那行几秒涨到几千字，
  --      表现就是"文字乱掉/看不见"。这是本节最经典的坑。
  --   ★ 拼的时候必须用**本帧 view 写的原文**（V.sync 存在 v.hudTips 里），
  --     不能读 `v.hud.tip.text` 再追加 —— 那会每帧自追加、无限膨胀。
  if v and v.hud and v.hud.tip then
    local extra = ''
    if showCounts then extra = extra .. '   |   ' .. __counts() end
    if extra ~= '' then
      local base = v.hudTips or ''
      H.setText(v.hud.tip, tostring(base) .. extra)
    end
  end
  -- ★★ 结算/总分页：**只在"s.settling 或 s.ended"且"确实在玩"时才画**。
  --   ① 我一度误读截图，以为"开局就显示收摊" —— 用户澄清：**那是最后才出现的**，位置对。
  --   ② 真正的问题是：**结算页没盖住后面的玩区**（工位卡还看得见，糊在一起）。
  --      → 结算时必须【藏玩区 + 把打底提到最上】，让结算页独占画面。
  --      用 V.showResultSheet 统一处理（幂等：只在状态变化时动控件，不每帧翻）。
  if scene == 'menu' then
    local okM, errM = pcall(V.drawMenu, v, menuMode)
    if not okM then say('V.drawMenu \229\135\186\233\148\153\239\188\154%s', tostring(errM)) end
  end
  local showResult = (scene == 'play') and G.s and (G.s.settling or G.s.ended)
  if showResult then
    if v then V.showResultSheet(v, true) end
    local okR, errR = pcall(V.drawResult, v, G.s)
    if not okR then say('V.drawResult \229\135\186\233\148\153\239\188\154%s', tostring(errR)) end
  elseif scene == 'play' and v then
    V.showResultSheet(v, false)   -- 回到玩区：玩区恢复、打底回到底层
    V.hideBig(v)
  end

  -- ★ STATEDBG：每秒一条"工位真实状态"快照（脚本变量 showState=1 才开）
  --   用途：玩家报"按键无反应"时，把玩家看到的画面与内部状态对上。
  --   （真机日志看不到画面，只能把状态打出来；默认关，别污染日志）
  local showState = tonumber(tostring(H.param('showState', 0))) ~= 0
  if showState and scene == 'play' and G.s then
    _tick = (_tick or 0) + 1
    if _tick % 30 == 0 then
      local S2 = __m_state()
      local parts = {}
      for _, sid in ipairs({ 'shake', 'fire', 'chem', 'brew' }) do
        local found = nil
        for _, sl in ipairs(G.s.slips or {}) do
          local nx = S2.nextStep(sl.cup)
          if nx and nx.st == sid then found = nx break end
        end
        parts[#parts + 1] = string.format('%s=%s', sid, found and '\230\156\137\230\180\187' or '\230\178\161\230\180\187')
      end
      say('\231\138\182\230\128\129 t=%.0f %s \231\165\168=%d', G.s.t or 0, table.concat(parts, ' '), #(G.s.slips or {}))
    end
  end

  -- ⑤ 提示计时（放在最后）：横幅到点就收
  if bannerT > 0 then
    bannerT = bannerT - dt2
    if bannerT <= 0 then
      _bannerActive = false
      if v then V.setBanner(v, nil) end
    end
  end
end

function OnLevelUpdate(dt) end
function OnDestroy() end

-- ── 外部调用入口（script:Invoke）＋ 自检 ──
function __state()
  local s = G.s
  if not s then return 'no-game' end
  return H.fmt('scene=%s t=%.1f day=%d/%d phase=%s orders=%d slips=%d served=%d money=%d ended=%s',
    tostring(scene), s.t, s.day, s.mode.days, s.phase, #s.orders, #s.slips, s.served, s.money, tostring(s.ended))
end
function __act(stationId, kind)
  local r = G.act(tostring(stationId), tostring(kind or 'press'))
  return (r and r.ok) and 'ok' or ('no: ' .. tostring(r and r.why))
end
function __bot()
  local K = __m_kitchen(); local S = __m_state()
  local s = G.s
  if not s or s.ended then return 'done' end
  if s.settling then G.nextDay(); return 'nextday' end
  for _, sl in ipairs(s.slips) do
    if sl.ready then K.deliverCup(s, sl); return 'pack' end
    local nx = S.nextStep(sl.cup)
    if nx then
      if sl.st ~= nx.st then K.routeSlip(s, sl, nx.st) end
      if nx.kind == 'hold' then nx.holdOn = true; K.tickHolds(s, 0.05) else K.pressStep(s, sl) end
      return 'work'
    end
  end
  for _, o in ipairs(s.orders) do for _, c in ipairs(o.cups) do
    if not c.made and K.slipFor(s, c) == nil and c.slotReady then G.startCup(c.rec.id); return 'start' end
  end end
  return 'idle'
end
function __counts()
  local imgOn, imgAll, txtOn, txtAll = 0, 0, 0, 0
  local function walk(c, depth)
    if not c or depth > 3 then return end
    local t = H.kindOf(c)
    local on = false
    pcall(function() on = (c.active ~= false) and (c.visible ~= false) end)
    if t:find('Image', 1, true) then imgAll = imgAll + 1; if on then imgOn = imgOn + 1 end end
    if t:find('TextBox', 1, true) then txtAll = txtAll + 1; if on then txtOn = txtOn + 1 end end
    local ok, kids = pcall(function() return c:GetChildren() end)
    if ok and type(kids) == 'table' then for i = 1, #kids do walk(kids[i], depth + 1) end end
  end
  if hostCfg and hostCfg.root then walk(hostCfg.root, 0) end
  return string.format('IMG %d/%d  TXT %d/%d', imgOn, imgAll, txtOn, txtAll)
end
-- 自检：把每个方块的 active/visible 报出来（排查"方块没显示"这类问题）
function __diag()
  local out = {}
  local function st(c, tag)
    if not c then out[#out + 1] = tag .. '=nil'; return end
    local a, vis = '?', '?'
    pcall(function() a = tostring(c.active) end)
    pcall(function() vis = tostring(c.visible) end)
    out[#out + 1] = string.format('%s(%s,%s)', tag, a, vis)
  end
  if v then
    for _, sid in ipairs({ 'shake', 'fire', 'chem', 'brew' }) do
      local slot = v.stations[sid]
      if slot then
        st(slot.lay.box, 'box_' .. sid)
        st(slot.lay.panel, 'pnl_' .. sid)
      end
    end
    st(v.pack.box, 'pack')
    st(v.hud.bar, 'hud')
    st(v.backdrop, 'bg')
  end
  local txt = 'DBG scene=' .. tostring(scene) .. ' ' .. table.concat(out, ' ')
  if v then V.setBanner(v, txt) end
  return txt
end
function __menu(m)
  if m then menuMode = math.max(1, math.min(3, tonumber(m) or 1)) end
  if scene == 'menu' and v then V.drawMenu(v, menuMode) end
  return 'mode=' .. tostring(IN.MODES[menuMode]) .. ' scene=' .. tostring(scene)
end

return { OnInit = OnInit, OnStart = OnStart, OnUpdate = OnUpdate,
         OnLevelUpdate = OnLevelUpdate, OnDestroy = OnDestroy,
         __state = __state, __act = __act, __bot = __bot, __counts = __counts, __menu = __menu, __diag = __diag }

end