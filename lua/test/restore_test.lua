-- restore_test.lua —— 「还原度」契约测试（HTML 原版 vs 千星移植）
--   node tools/lua-test.mjs lua/test/restore_test.lua
--
-- 这个文件是**用户反馈的直接产物**，不是我自己想出来的规则：
--   真机日志（Beyond_Debug_Log，2026-09-27）里 9085 条 [LOGIC] 中 ok=false 占 8984 条，
--   另有 9003 条 [REJECT]（如 `[REJECT] want=brew slips=1 [#1:open:chem]`）。
--   也就是说：**按四个工位键，99% 的按键什么都没发生** → 玩家判定"快捷键坏了"。
--
-- 根因不是键位、不是事件注册（[bind] 证明 11 个键全绑上了、[act] 证明事件都到了），
-- 而是**移植漏了原版的一条交互**：
--   原版：点小票 → 立刻送该工位（雪皇的后厨.html:1472 → forwardSlip:859）
--         + 闲 5 秒自动流转（autoForward）
--         ⇒ 票**总是已经在工位上**，按键当然次次有活。
--   移植：只有 5 秒自动流转，**点小票没有任何路由处理**（xuehuang.lua 只对工位卡做命中测试）
--         ⇒ 票不在工位上的时候，按键全部被拒。
--
-- 本文件把"还原契约"钉死，改坏了立刻红。

local CFG = require('config')
local R = require('recipes')
local S = require('state')
local O = require('order')
local K = require('kitchen')
local G = require('game')

local pass, fail = 0, 0
local function ok(c, m)
  if c then pass = pass + 1; print('  OK  ' .. m) else fail = fail + 1; print('  X   ' .. m) end
end
local function eq(a, b, m)
  ok(a == b, string.format('%s（期望 %s，实际 %s）', m, tostring(b), tostring(a)))
end

-- 造单：直接指定配方与杯数（绕开随机，专测规则）
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

-- 让某杯"已经站在它的下一步工位上"（模拟：票已经流过去了）
local function placeCupAtNext(s, o, cup)
  local sl = K.slipFor(s, cup) or K.makeSlip(s, o, cup)
  local nx = S.nextStep(cup)
  if nx then K.routeSlip(s, sl, nx.st) end
  return sl, nx
end

-- ══════════════════════════════════════════════════════════════════════════
print('== R1. 点小票 = 立刻送它去下一步（原版 forwardSlip）==')
do
  -- 原版：点小票把"这一杯的下一步"送到该去的工位（不是送到你点的那个工位）
  local s = S.new('fast')
  local o = makeOrder(s, { { rec = R.byId('peach'), n = 1 } })
  local cup = o.cups[1]
  local sl = K.makeSlip(s, o, cup)
  -- ★ 出票时就挂到第一手（K.makeTicketsFor 也是这么做的，与原版 startCup 一致）
  eq(sl.st, 'brew', 'R1 出票即挂在第一手 brew')

  -- 做完 brew 这一步 → 票必须能一键送到下一步 fire
  local nx = S.nextStep(cup)
  nx.holdOn = true
  K.tickHolds(s, CFG.hold.sec + 0.1)
  ok(cup.steps[1].ok == true, 'R1 brew 这一步（hold）已收口')
  local autoBefore = s.autoMoves
  local r, dst = K.forwardSlip(s, sl)     -- ← 原版点小票走的就是这个
  eq(r, true, 'R1 点小票 → 成功送到下一步工位')
  eq(dst, 'fire', 'R1 目的地是"这一杯的下一步" fire（不是点的那张工位）')
  eq(sl.st, 'fire', 'R1 票现在挂在 fire')
  eq(s.autoMoves, autoBefore, 'R1 玩家手动送票 **不算** 自动流转次数')

  -- 已经在目的地的票：不重复路由、不报错
  local r2 = K.forwardSlip(s, sl)
  eq(r2, false, 'R1 已经在目的地的票 → false（不空转）')
end

print('== R2. 工位键在"票不在该工位"时也必须能开工（这就是按键无反应的根因）==')
do
  local s = S.new('fast')
  G.s = s                                                          -- G.act 读的是当前局
  local o = makeOrder(s, { { rec = R.byId('peach'), n = 1 } })    -- 第一步是 brew/hold
  local cup = o.cups[1]
  K.makeSlip(s, o, cup)                                           -- 票存在，但还没挂工位
  local r = G.act('brew', 'press', nil, { route = true })          -- ← 玩家按 P（带自动送票）
  ok(r and r.ok == true,
     'R2 票的下一步就是 brew、票还没挂工位 → 按键必须开工（now: ' .. tostring(r and r.why) .. '）')
  local sl = K.slipFor(s, cup)
  -- ★ brew 的第一步是 hold，而 hold 现在是"一次输入即完成"（真机不送 KeyUp，见 R3）
  --   ⇒ 按完这一步就收口，票的 st 会被归一成 nil。所以这里断言"这一步真的做掉了"，
  --     而不是断言"票还挂在 brew"（那是旧语义，已被真机证据推翻）。
  ok(cup.steps[1].ok == true, 'R2 按键后这一步真的收口了（自动找活 + 送票 + 推进一气呵成）')

  -- ★ 绝不能改成"按任意键自动去别的工位"：按 shake 必须仍然拒绝（原版就是拒绝）
  local s3 = S.new('fast')
  G.s = s3
  local o3 = makeOrder(s3, { { rec = R.byId('peach'), n = 1 } })  -- 下一步是 brew
  local sl3 = K.makeSlip(s3, o3, o3.cups[1])
  sl3.st = 'brew'                                                 -- 票在 brew，下一步也还是 brew
  local r3 = G.act('shake', 'press', nil, { route = true })        -- 按 Y（捣锤）
  eq(r3 and r3.ok, false, 'R2 票该去 brew 时按 shake → 仍然拒绝（不做自动抢活）')
  -- ⚠️ 被拒绝时票不会被挪动：这里 brew 的下一步是 hold（一次输入即完成），
  --    所以票要么还挂在 brew、要么这一步已经收口（st 归一成 nil）—— 两者都算"没被抢走"。
  ok(sl3.st == 'brew' or sl3.st == nil,
     string.format('R2 被拒绝时票没被挪去别处（现在 st=%s）', tostring(sl3.st)))
end

print('== R3. 手法：tap 一下 / mash 连按 N 下 / hold 一次输入即完成（平台约束）==')
do
  -- tap
  local s = S.new('fast')
  local o = makeOrder(s, { { rec = R.byId('instcoffee'), n = 1 } })
  local cup = o.cups[1]
  local sl = placeCupAtNext(s, o, cup)
  local nx = S.nextStep(cup)
  eq(nx.kind, 'tap', 'R3 速溶咖啡第一步是 tap')
  K.pressStep(s, sl)
  ok(cup.steps[1].ok == true, 'R3 tap：按一下就该收口')

  -- ★★ hold：**一次输入即完成**（真机证据逼出来的，不是偷懒）
  --   19:15 真机：按 P 13 次，[STATE] 48 次采样全是 hold:0.0/0.9，整份日志**没有一条 [KUP]**。
  --   ⇒ 这个平台不送 KeyUp（键事件可能被千星的跳跃/滑翔占用），按住累积永远攒不起来。
  --   所以 hold 必须"一下完成"，否则按住类步骤**永远做不完**（玩家："按键盘它从不变，鼠标点却能完成"）。
  local s2 = S.new('fast')
  local o2 = makeOrder(s2, { { rec = R.byId('peach'), n = 1 } })
  local c2 = o2.cups[1]
  local sl2 = placeCupAtNext(s2, o2, c2)
  local nx2 = S.nextStep(c2)
  eq(nx2.kind, 'hold', 'R3 蟠桃第一步是 hold')
  ok(CFG.hold.oneTap == true, 'R3 hold 走"一次输入即完成"模式（真机不送 KeyUp）')
  local r = K.pressStep(s2, sl2)
  eq(c2.steps[1].ok, true, 'R3 hold：按一下就该收口（否则这杯永远做不完）')
  ok(r and r.done == true, 'R3 hold：按一下汇报 done=true')

  -- hold：oneTap 关掉时必须回到"原版按住累积"（换平台/换键位后能切回来）
  local saved = CFG.hold.oneTap
  CFG.hold.oneTap = false
  local s3 = S.new('fast')
  local o3 = makeOrder(s3, { { rec = R.byId('peach'), n = 1 } })
  local c3 = o3.cups[1]
  local sl3 = placeCupAtNext(s3, o3, c3)
  local nx3 = S.nextStep(c3)
  local r3 = K.pressStep(s3, sl3)
  ok(r3 and r3.done == false, 'R3 oneTap=false 时：按一下**不**收口（原版按住语义仍在）')
  nx3.holdOn = true
  K.tickHolds(s3, CFG.hold.sec + 0.05)
  ok(c3.steps[1].ok == true, 'R3 oneTap=false 时：累积满 ' .. tostring(CFG.hold.sec) .. ' 秒收口（旧逻辑没坏）')
  CFG.hold.oneTap = saved

  -- mash：要连按 N 下，一下不完成
  local s4 = S.new('fast')
  local o4 = makeOrder(s4, { { rec = R.byId('newton'), n = 1 } })
  local c4 = o4.cups[1]
  local sl4 = placeCupAtNext(s4, o4, c4)
  local nx4 = S.nextStep(c4)
  eq(nx4.kind, 'mash', 'R3 牛顿苹果第一步是 mash')
  K.pressStep(s4, sl4)
  eq(nx4.done, 1, 'R3 mash：按一下进度 +1')
  ok(c4.steps[1].ok ~= true, 'R3 mash：没按满 → 不收口')
  for _ = 2, (nx4.taps or 1) do K.pressStep(s4, sl4) end
  ok(c4.steps[1].ok == true, 'R3 mash：按满 ' .. tostring(nx4.taps) .. ' 下 → 收口')
end

print('== R4. 名额上限仍然生效（按键不能绕过在制上限）==')
do
  local s = S.new('fast')
  local CAP = CFG.kitchen.maxWip
  -- 造 CAP+1 杯，只有前 CAP 杯拿得到名额
  local o = makeOrder(s, { { rec = R.byId('peach'), n = CAP + 1 } })
  local q = 0
  for _, c in ipairs(o.cups) do if not c.slotReady then q = q + 1 end end
  ok(q >= 1, string.format('R4 有 %d 杯在排队（上限 %d）', q, CAP))
  local waiting
  for _, c in ipairs(o.cups) do if not c.slotReady then waiting = c break end end
  if waiting then
    local sl = K.makeSlip(s, o, waiting)
    local r = K.forwardSlip(s, sl)
    eq(r, false, 'R4 没名额的杯：点小票也不能开工')
    eq(sl.st, nil, 'R4 没名额的杯：票没被挂上工位')
    G.s = s
    local r2 = G.act('brew', 'press', nil, { route = true })
    -- ★ 按键可以去做"有资格的那一杯"（这本来就对），但**绝不能把没名额的杯硬拉开工**。
    --   真正要守住的契约是：在制数（已开工）永远 ≤ 上限。
    ok(S.wipCount(s) <= CFG.kitchen.maxWip,
       string.format('R4 按键后仍在制数 %d ≤ 上限 %d', S.wipCount(s), CFG.kitchen.maxWip))
    eq(sl.st, nil, 'R4 没名额的那张票：按键也没把它拉开工')
  end
end

print('== R5. 工位键的"可见回应"契约 ==')
do
  -- 有活 → ok=true；没活 → ok=false **且带 why**（why 会被打成提示，绝不静默）
  local s = S.new('fast')
  G.s = s
  eq(#s.slips, 0, 'R5 开局没有票')
  local r = G.act('brew', 'press', nil, { route = true })
  eq(r and r.ok, false, 'R5 没票时按 brew → ok=false')
  ok(type(r and r.why) == 'string' and #r.why > 0,
     'R5 拒绝必须带 why（否则玩家只看到"按了没反应"）: ' .. tostring(r and r.why))
end

print('-- restore_test summary --')
print(string.format('  passed %d / failed %d', pass, fail))
if fail > 0 then error('restore_test failed: ' .. tostring(fail) .. ' 条不通过', 0) end
