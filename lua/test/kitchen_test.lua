-- kitchen_test.lua —— 后厨规则测试（把网页版真实踩过的 bug 一条条钉住）
--   node tools/lua-test.mjs lua/test/kitchen_test.lua
--
-- 每一条 X/X 都是**从玩家反馈或真机日志里来的**，不是我自己想的：
--   · 名额池按单填池（不能让第一杯开工把同单第二杯挤出去）
--   · 每一杯都出票（没名额的也要有票，否则玩家以为"第二杯做不了"）
--   · 一天只结一次账（否则房租反复扣、欠租滚雪球）
--   · 打烊清场耐心冻结（否则客人走到一半没了，玩家觉得"什么都干不了"）
--   · 没有僵尸票（"杯子做完了但票说没做完"会赖在工位上被反复点）
--   · 做完即出（甜筒不进打包台）

local CFG = require('config')
local R = require('recipes')
local S = require('state')
local O = require('order')
local K = require('kitchen')
local D = require('day')

local pass, fail = 0, 0
local function ok(c, m)
  if c then pass = pass + 1; print('  OK  ' .. m) else fail = fail + 1; print('  X   ' .. m) end
end
local function eq(a, b, m)
  ok(a == b, string.format('%s（期望 %s，实际 %s）', m, tostring(b), tostring(a)))
end

-- ── 固定随机源：可复现（测试必须确定性，别靠运气）──
local seq, si = {}, 0
local function rng()
  si = si + 1
  if seq[si] ~= nil then return seq[si] end
  return 0.5
end
O.setRng(rng)

-- 造一单：直接指定配方与杯数（绕开随机，专测规则）
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
  local names = {}
  for _, line in ipairs(lines) do names[#names + 1] = line.n .. '×' .. line.rec.name end
  o.makeup = table.concat(names, ' + ')
  s.orders[#s.orders + 1] = o
  return o
end

local function countSlips(s)
  local n = 0
  for _ in ipairs(s.slips) do n = n + 1 end
  return n
end

-- 把一杯按真实路径做完（走 routeSlip + pressStep/mash/hold）
local function finishCup(s, o, cup)
  local sl = K.slipFor(s, cup) or K.makeSlip(s, o, cup)
  local guard = 0
  while not cup.done and guard < 60 do
    guard = guard + 1
    local nx = S.nextStep(cup)
    if not nx then break end
    K.routeSlip(s, sl, nx.st)
    if nx.kind == 'hold' then
      nx.holdOn = true
      local t2 = 0
      while t2 < CFG.hold.sec + 0.05 and not nx.ok do K.tickHolds(s, 0.05); t2 = t2 + 0.05 end
    else
      K.pressStep(s, sl)
    end
  end
  return sl
end

print('== 1. per-order pool ==')
do
  local s = S.new('fast')
  local o = makeOrder(s, { { rec = R.byId('newton'), n = 2 } })
  K.refreshSlots(s)
  eq(o.cups[1].slotReady, true, 'cup1 got a slot')
  eq(o.cups[2].slotReady, true, 'cup2 also got a slot (cap holds 2)')
  o.cups[1].startedAt = 1              -- 第一杯开工
  K.refreshSlots(s)
  eq(o.cups[2].slotReady, true, 'after cup1 starts, cup2 stays in pool')
  -- 在制 = "已开工、还没做完"的杯数。此刻只有杯 1 开工过，所以是 1。
  eq(S.wipCount(s), 1, 'wip count = 1 (only started cup holds a slot)')
end

print('== ② 名额不足时：每一杯都出票，只是"等名额" ==')
do
  local s = S.new('fast')
  CFG.kitchen.maxWip = 1
  local o = makeOrder(s, { { rec = R.byId('newton'), n = 2 } })
  K.refreshSlots(s)
  K.makeTicketsFor(s)
  eq(countSlips(s), 2, 'both cups have slips (even without a slot)')
  eq(o.cups[1].slotReady, true, 'cup1 has slot')
  eq(o.cups[2].slotReady, false, 'cup2 waits for slot')
  local sl2 = K.slipFor(s, o.cups[2])
  ok(sl2 ~= nil and sl2.st == nil, '杯 2 的票存在但**没挂工位**（等名额状态）')
  -- 杯 1 做完并交付 → 名额腾出来 → 杯 2 应该自动拿到
  local sl1 = K.slipFor(s, o.cups[1]) or K.makeSlip(s, o, o.cups[1])
  finishCup(s, o, o.cups[1])
  K.deliverCup(s, sl1)
  K.refreshSlots(s)                      -- 真机上名额是下一帧重算的，这里手动推一次
  eq(o.cups[2].slotReady, true, 'after cup1 delivered, cup2 gets the slot')
  CFG.kitchen.maxWip = 3
end

print('== 3. hard cap ==')
do
  local s = S.new('fast')
  makeOrder(s, { { rec = R.byId('newton'), n = 3 } })
  makeOrder(s, { { rec = R.byId('peach'), n = 3 } })
  K.refreshSlots(s)
  local n = 0
  for _, o in ipairs(s.orders) do for _, c in ipairs(o.cups) do if c.slotReady and not c.done then n = n + 1 end end end
  ok(n <= CFG.kitchen.maxWip, string.format('池内杯数 %d ≤ %d', n, CFG.kitchen.maxWip))
end

print('== 4. no zombie slips ==')
do
  local s = S.new('fast')
  local o = makeOrder(s, { { rec = R.byId('peach'), n = 1 } })
  K.refreshSlots(s); K.makeTicketsFor(s)
  local cup = o.cups[1]
  local sl = K.slipFor(s, cup)
  finishCup(s, o, cup)
  eq(cup.made, true, 'cup is made (cup.made)')
  eq(sl.ready, true, '票也同时标了 ready（不会留下"做完了但票没做完"的僵尸票）')
  eq(K.sweepZombieSlips(s), 0, 'self-heal finds no zombie slip')
end

print('== 5. serveNow: no pack station ==')
do
  local s = S.new('fast')
  local o = makeOrder(s, { { rec = R.byId('qilin'), n = 1 } })
  K.refreshSlots(s); K.makeTicketsFor(s)
  local cup = o.cups[1]
  finishCup(s, o, cup)
  eq(cup.made, true, 'cone is made'); eq(cup.done, true, 'cone delivered immediately (serveNow)')
  eq(countSlips(s), 0, 'slip gone (not stuck at pack)')
  eq(s.today.served, 1, 'served counted immediately')
  eq(#s.orders, 0, 'order removed after full delivery')
end

print('== 6. never two heavy recipes in one order ==')
do
  local heavyPairs = 0
  for i = 1, 200 do
    local lines = O.drinkPlan(2)
    local h = 0
    for _, l in ipairs(lines) do if l.rec.heavy then h = h + 1 end end
    if h >= 2 then heavyPairs = heavyPairs + 1 end
  end
  eq(heavyPairs, 0, '200 次两杯混点里，出现"两个重活同单"的次数')
end

print('== 7. mixing: cup conservation ==')
do
  local bad = 0
  for i = 1, 300 do
    local n = 2 + (i % 3)                 -- 2/3/4 杯
    local lines = O.drinkPlan(n)
    local sum = 0
    for _, l in ipairs(lines) do
      sum = sum + l.n
      if l.n < 1 then bad = bad + 1 end
    end
    if sum ~= n then bad = bad + 1 end
  end
  eq(bad, 0, '300 次混点的杯数守恒与"每项至少 1 杯"')
end

print('== 8. settle is idempotent ==')
do
  local s = S.new('fast')
  s.money = 500
  D.settle(s)
  local debt1, paid1 = s.rentDebt, s.rentPaid
  D.settle(s)                            -- 再调 5 次
  for _ = 1, 5 do D.settle(s) end
  eq(s.rentPaid, paid1, 'rent charged once (rentPaid unchanged)')
  eq(s.rentDebt, debt1, 'rent debt did not snowball')
  eq(#s.dayStats, 1, 'exactly one day log')
end

print('== 9. closing: patience frozen ==')
do
  local s = S.new('fast')
  local o = makeOrder(s, { { rec = R.byId('newton'), n = 1 } })
  K.refreshSlots(s)
  o.pat = 3                              -- 只剩 3 秒耐心
  s.dayLeft = 0.01
  D.tick(s, 0.05)                        -- 触发打烊
  eq(s.phase, 'closing', 'entered closing phase')
  local patBefore = o.pat
  for _ = 1, 40 do D.tick(s, 0.05) end    -- 再推 2 秒
  eq(o.pat, patBefore, 'patience frozen during closing')
  ok(#s.orders >= 1, '这单还在手上（没被删掉）')
end

print('== 10. last call: arrivals get sparser ==')
do
  local s = S.new('fast')
  s.dayLeft = s.mode.perDay
  local f1 = D.slowFactor(s)
  s.dayLeft = s.mode.perDay * 0.2
  local f2 = D.slowFactor(s)
  s.dayLeft = 0
  local f3 = D.slowFactor(s)
  eq(f1, 1, 'no slowdown right after opening')
  ok(f2 > 1, '最后 35% 开始减速（' .. string.format('%.2f', f2) .. '）')
  ok(math.abs(f3 - CFG.closing.rampTo) < 0.01, string.format('到点减速到 ×%d', CFG.closing.rampTo))
end

print('== 11. instcoffee: first 3 steps use no slot ==')
do
  local s = S.new('fast')
  local o = makeOrder(s, { { rec = R.byId('instcoffee'), n = 1 } })
  K.refreshSlots(s); K.makeTicketsFor(s)
  local cup = o.cups[1]
  local sl = K.slipFor(s, cup)
  local nx = S.nextStep(cup)
  K.routeSlip(s, sl, nx.st)
  eq(cup.startedAt, nil, '只是"票挂上工位"时**还没有开工**（排队不占名额）')
  K.pressStep(s, sl)                      -- 真动手：第一下
  eq(cup.startedAt ~= nil, true, 'work starts on the first real press')
  eq(S.cupWip(cup), false, 'still holds no slot (noSlot steps)')
  -- 推到第 4 步（注入热水），这时才占名额
  local guard = 0
  while guard < 20 do
    guard = guard + 1
    local n2 = S.nextStep(cup)
    if not n2 then break end
    if not n2.noSlot then break end
    K.pressStep(s, sl)
  end
  eq(S.cupWip(cup), true, '做到"注入热水"时开始占名额')
end

print('== 12. mistakes and lost guests ==')
do
  local s = S.new('fast')
  local o = makeOrder(s, { { rec = R.byId('newton'), n = 1 } })
  K.refreshSlots(s); K.makeTicketsFor(s)
  local cup = o.cups[1]
  s.money = 100                          -- 先给点钱，否则罚款被 math.max(0, …) 夹住、看不出效果
  local money0 = s.money
  K.doWrong(s, cup, 'fire')
  eq(cup.err, true, 'cup marked as mistaken')
  eq(s.today.mistakes, 1, 'mistake counter +1')
  ok(s.money < money0, '翻车扣钱')
  local left0 = s.left
  O.leave(s, o, true)
  eq(s.left, left0 + 1, 'guest left -> lost counter +1')
  eq(#s.orders, 0, 'order removed')
  eq(countSlips(s), 0, 'its slips removed too')
end

print('== summary ==')
print(string.format('  passed %d / failed %d', pass, fail))
if fail > 0 then print('  TEST-ERROR failures present') end
