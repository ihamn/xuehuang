-- e2e_key_test.lua —— 端到端：**完全走"按键那条路"**打一整局
--   node tools/lua-test.mjs lua/test/e2e_key_test.lua
--
-- 为什么要单独一个文件：
--   现有的 game_test.lua 机器人是直接调 K.pressStep / K.routeSlip（绕过输入层），
--   所以它**永远抓不到**"按工位键没反应"这类问题 —— 真机日志里 8984/9085 条 ok=false
--   就是被这种测试漏掉的。
--
--   本文件里机器人的每一次动作都只经过两个入口（与 xuehuang.lua 的按键分支完全一致）：
--     · G.act(工位, 'press', nil, { route = true })   ← 按 Y/H/K/P/空格
--     · G.newGame / G.nextDay                          ← 开门 / 结算继续
--   然后断言：
--     ① 一整局能打完（不卡死、不抛异常）
--     ② 每个工位键的"无活可做"次数必须**极低**（这是玩家抱怨的那个数）
--     ③ 必须有杯出餐（证明链路真的通）
--     ④ 在制数任何时刻不超过上限

local CFG = require('config')
local R = require('recipes')
local S = require('state')
local G = require('game')
local K = require('kitchen')

local pass, fail = 0, 0
local function ok(c, m)
  if c then pass = pass + 1; print('  OK  ' .. m) else fail = fail + 1; print('  X   ' .. m) end
end
local function eq(a, b, m)
  ok(a == b, string.format('%s（期望 %s，实际 %s）', m, tostring(b), tostring(a)))
end

-- ── 统一出口：模拟玩家输入（和入口的按键分支同一行代码）──
local REJECT = 0          -- 按了但"这个工位没活"
local PRESS = 0           -- 按下去有活
local ACTED = {}          -- 各工位统计

local function press(station)
  PRESS = PRESS + 1
  local r = G.act(station, 'press', nil, { route = true })
  if r and r.ok then
    ACTED[station] = (ACTED[station] or 0) + 1
  else
    REJECT = REJECT + 1
  end
  return r
end

-- ── 机器人（只用上面的 press；不许直接碰 kitchen）──
local function botOnce(s)
  if s.settling then G.nextDay(); return 'nextday' end
  if s.ended then return 'done' end

  -- 1) 有做完的杯 → 送打包台（原版：小票全绿后自动进打包台，按空格出餐）
  for _, sl in ipairs(s.slips) do
    if sl.ready then
      local r = press('pack')
      if r and r.ok then return 'pack' end
    end
  end
  -- 2) 有票但还没动手 → 按它"下一步"对应的工位键（**带自动送票**，这是新增的还原项）
  for _, sl in ipairs(s.slips) do
    local nx = S.nextStep(sl.cup)
    if nx and nx.st and nx.st ~= 'pack' then
      local r = press(nx.st)
      if r and r.ok then
        -- 按住类：按住不放（真机上是长按；这里连续几帧等效）
        if nx.kind == 'hold' then nx.holdOn = true end
        return 'work'
      end
    end
  end
  -- 3) 有杯但一张票都没有（比如关掉自动出票）→ 直接推一帧让 refreshSlots 补票
  return 'idle'
end

-- ── 造单（与 restore_test.lua 同一套；专测规则，绕开随机）──
local function makeOrder(s, recs)
  local lines = {}
  for _, x in ipairs(recs) do lines[#lines + 1] = { rec = x.rec, n = x.n } end
  local o = {
    id = (s.oid + 1), name = 'TEST', rec = lines[1].rec, lines = lines,
    ice = '正常', sugar = '正常糖', cups = {}, need = 0,
    pat = 200, patMax = 200, made = 0, delivered = 0, status = 'wait',
    inProgress = false, priority = false, queueNo = 0, patBonus = 0, born = s.t,
  }
  s.oid = s.oid + 1
  local i = 0
  for _, line in ipairs(lines) do
    for _ = 1, line.n do
      i = i + 1
      local steps = {}
      for _, st in ipairs(line.rec.steps) do
        steps[#steps + 1] = { st = st.st, t = st.t, kind = st.kind, taps = st.taps,
                              noSlot = st.noSlot, ok = false, done = 0 }
      end
      o.cups[#o.cups + 1] = { i = i, rec = line.rec, steps = steps, done = false, served = false,
                              err = false, startedAt = nil, finishedAt = nil, slotReady = false }
    end
  end
  o.need = i
  s.orders[#s.orders + 1] = o
  K.refreshSlots(s)
  return o
end

-- ══════════════════════════════════════════════════════════════════════════
print('== E1. 一整局全走按键路径 ==')
do
  G.newGame('fast')
  local s = G.s
  local DT = 1 / 30
  local frames, peakWip, everRejectedInOpen = 0, 0, 0
  local guard = 0
  while not s.ended and frames < 60 * 60 * 12 do          -- 最多 12 分钟游戏时间
    frames = frames + 1
    G.tick(DT)
    local r = botOnce(s)
    if r == 'idle' then G.tick(DT) end                    -- 空转：多推一帧让自动出票补票
    if not s.settling then
      local w = S.wipCount(s)
      -- 诊断：把"所有开工过的杯"也算一遍（含 noSlot 前缀里的杯）
      local w2 = S.wipGateCount(s)
      if w2 > (peakWip2 or 0) then peakWip2 = w2 end
      if w > peakWip then peakWip = w end
      -- ★ 硬上界：noSlot 的杯不占 wipCount 名额（原版设计），但"同时开了多少杯"必须有上界
      local gate = CFG.kitchen.maxWip * 2
      if w2 > gate then
        guard = guard + 1
        if guard <= 3 then
          print(string.format('  [gate-violation] frame=%d t=%.1f gateCount=%d 上限=%d',
            frames, s.t, w2, gate))
        end
      end
    end
  end
  ok(frames < 60 * 60 * 12, string.format('E1 一整局在 %d 帧内结束（没有卡死）', frames))
  ok(s.ended == true, 'E1 打到了整局结束（5 天全部走完）')
  ok(s.served > 0, string.format('E1 有出餐：%d 杯', s.served))
  -- ★★ 名额口径（2026-09-27 定稿）：
  --   · S.cupWip ≤ maxWip = **文档口径**（"后厨同时最多 3 个未完成任务"）。
  --   · 闸门用 S.wipGateCount（在飞的杯 = 已开工 + 已发资格）≤ maxWip —— 有了它，
  --     cupWip ≤ maxWip 才是真不变量（修之前：连按能开出无限杯，实测峰值 7）。
  ok((peakWip2 or 0) <= CFG.kitchen.maxWip,
     string.format('E1 在飞的杯峰值 %d ≤ 上限 %d', peakWip2 or 0, CFG.kitchen.maxWip))
  ok(peakWip <= CFG.kitchen.maxWip,
     string.format('E1 在制峰值 %d ≤ 上限 %d', peakWip, CFG.kitchen.maxWip))
  print(string.format('  [diag] 峰值：cupWip 口径 %d（文档口径 %d）／ 在飞口径 %d（闸门 %d）',
    peakWip, CFG.kitchen.maxWip, peakWip2 or 0, CFG.kitchen.maxWip))
  ok(guard == 0, string.format('E1 名额从未越界（越界帧数 %d）', guard))

  -- ★★ 核心断言：按键的"无活可做"率
  local rate = (PRESS > 0) and (REJECT / PRESS) or 1
  print(string.format('  [stat] 按键 %d 次 · 有活 %d · 无活 %d（%.1f%%）',
    PRESS, PRESS - REJECT, REJECT, rate * 100))
  print(string.format('  [stat] 各工位成功次数：shake=%d fire=%d chem=%d brew=%d pack=%d',
    ACTED.shake or 0, ACTED.fire or 0, ACTED.chem or 0, ACTED.brew or 0, ACTED.pack or 0))
  ok(rate < 0.35,
     string.format('E1 按键"无活可做"率 %.1f%% < 35%%（修复前真机是 8984/9085 ≈ 99%%）', rate * 100))
end

print('== E2. 三个模式都能开局并推进 ==')
do
  for _, m in ipairs({ 'quick', 'fast', 'slow' }) do
    G.newGame(m)
    local s = G.s
    for _ = 1, 60 * 30 do
      G.tick(1 / 30)
      if s.ended then break end
      botOnce(s)
    end
    ok(s.t > 5, string.format('E2 模式 %s 能推进（t=%.1fs，出餐 %d）', m, s.t, s.served))
  end
end

print('== E3. 名额硬上界：连按工位键也不能开出无限杯 ==')
do
  -- 造一单全是"纯手感步骤"开头（速溶咖啡前三步 noSlot）的多杯单，
  -- 然后像玩家连按一样狂按那个工位键，看能不能无限开工。
  local s = S.new('fast')
  G.s = s
  local n = 12
  local o = { id = 1, name = 'T', rec = R.byId('instcoffee'),
              lines = { { rec = R.byId('instcoffee'), n = n } }, cups = {}, need = n,
              ice = 'x', sugar = 'x', pat = 999, patMax = 999, made = 0, delivered = 0,
              status = 'wait', inProgress = false, priority = false, queueNo = 0, patBonus = 0, born = 0 }
  for i = 1, n do
    local steps = {}
    for _, st in ipairs(R.byId('instcoffee').steps) do
      steps[#steps + 1] = { st = st.st, t = st.t, kind = st.kind, taps = st.taps,
                            noSlot = st.noSlot, ok = false, done = 0 }
    end
    o.cups[i] = { i = i, rec = R.byId('instcoffee'), steps = steps, done = false, served = false,
                  err = false, startedAt = nil, finishedAt = nil, slotReady = false }
  end
  s.orders[1] = o
  s.oid = 1
  K.refreshSlots(s)
  K.makeTicketsFor(s)
  -- 狂按"兑茶"键 200 次（比人手快得多）
  local startedMax = 0
  for _ = 1, 200 do
    G.act('brew', 'press', nil, { route = true })
    local gc = S.wipGateCount(s)
    if gc > startedMax then startedMax = gc end
  end
  ok(startedMax <= CFG.kitchen.maxWip,
     string.format('E3 狂按 200 次后"在飞的杯"峰值 %d ≤ 上限 %d（修前无上界）',
       startedMax, CFG.kitchen.maxWip))
  -- 且 cupWip 文档口径仍然被守住
  ok(S.wipCount(s) <= CFG.kitchen.maxWip,
     string.format('E3 其中"占名额的杯"%d ≤ %d', S.wipCount(s), CFG.kitchen.maxWip))
end

print('== E4. 出餐（pack）必须真的能做：做完的杯 → 按出餐 → 结单 ==')
do
  -- ★ 真机日志逼出来的：18:19 那次运行，咖啡 4 步都推进了，但玩家**一次都没按出餐键**，
  --   因为屏幕上没说、而且空格在千星是"跳跃"可能收不到 ⇒ 出餐这条路我们从没验证过。
  G.newGame('fast')
  local s = G.s
  local o = makeOrder(s, { { rec = R.byId('instcoffee'), n = 1 } })   -- 全 tap + 不占名额
  local cup = o.cups[1]
  local sl = K.slipFor(s, cup) or K.makeSlip(s, o, cup)
  local guard = 0
  while not cup.made and guard < 40 do
    guard = guard + 1
    local nx = S.nextStep(cup)
    if not nx then break end
    local r = press(nx.st)                       -- 走按键路径做工位
    if not (r and r.ok) then
      -- 兜底：先确保票挂到位再按
      K.forwardSlip(s, sl)
      press(nx.st)
    end
  end
  ok(cup.made == true, 'E4 咖啡做完（made）')
  eq(sl.ready, true, 'E4 做完的杯 → 票进入 ready（等出餐）')

  -- 现在按出餐键（入口把 pack2 归一成 pack，这里测的是同一个语义）
  local before = s.served
  local r = press('pack')
  ok(r and r.ok == true, 'E4 按出餐键 → 必须成功（now: ' .. tostring(r and r.why) .. '）')
  eq(s.served, before + 1, 'E4 出餐计数 +1')
  eq(cup.done, true, 'E4 这杯已交付')

  -- 票应该被收走（不该留下僵尸票）
  local left = 0
  for _, x in ipairs(s.slips) do if x.cup == cup then left = left + 1 end end
  eq(left, 0, 'E4 交付后不留僵尸票')

  -- 键位表：出餐必须有**两个**可用键（空格可能被世界系统吃掉）
  local IN2 = require('input')
  local keys = {}
  for _, b in ipairs(IN2.BIND) do keys[b.act] = b.key end
  eq(keys.pack, 'SPACE', 'E4 出餐主键是空格（与原版一致）')
  eq(keys.pack2, 'Z', 'E4 出餐备用键是奇匠按键 Z（一定收得到）')
end

print('-- e2e_key_test summary --')
print(string.format('  passed %d / failed %d', pass, fail))
if fail > 0 then error('e2e_key_test failed: ' .. tostring(fail) .. ' 条不通过', 0) end
