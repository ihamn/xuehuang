-- eco_test.lua —— 环保贡献凭证：只算"固化下来的减碳"
--   node tools/lua-test.mjs lua/test/eco_test.lua
--
-- ★ 2026-10-01 用户定：**不搞碳排放计算**（曾经算"玩家做功→代谢→排碳 0.36 克"，
--   还配了碳价卖钱）。原话意思是：太讲现实不太好，让玩家自己去体会。
--   ⇒ 这里除了验"固化量算得对"，还要验**删掉的那套没溜回来**（最后一段）。

local R = require('recipes')

local pass, fail = 0, 0
local function ok(c, m)
  if c then pass = pass + 1; print('  OK  ' .. m) else fail = fail + 1; print('  X   ' .. m) end
end
local function near(a, b, tol, m)
  ok(math.abs(a - b) <= (tol or 1e-9), string.format('%s（期望 %.6f ±%s，实际 %.6f）', m, b, tostring(tol or 1e-9), a))
end

print('== 固化量：一杯空气里到底能固住多少 CO₂ ==')
-- 0.5 L × 0.04% ÷ 22.4 L/mol × 44 g/mol = 0.00039 g
local V, frac, M = 0.5, 0.0004, 44.01
local want = V * frac / 22.4 * M
-- 注意：44.01 算出来是 0.0003930 克（显示时取 0.39 毫克）⇒ 容差要留够，别拿四舍五入后的数当精确值
near(want, 0.00039, 1e-5, string.format('推导：0.5 L × 0.04%% ÷ 22.4 × 44 = %.5f 克 = %.2f 毫克（显示取 0.39）', want, want * 1000))

local dry = R.byId('dryice')
local e = R.eco(dry)
near(e.fixed, dry.co2FixedG, 0, 'recipes.eco 返回的 fixed = 该产品写的 co2FixedG')
near(e.fixed, 0.00039, 1e-6, string.format('干冰那款固化 = %.2f 毫克', e.fixed * 1000))
ok(e.fixed > 0, '干冰是唯一真的固化了 CO₂ 的产品')

print('== 只有干冰那款有；别的产品是 0（没 CO₂ 可固化）==')
local withFixed = 0
for _, p in ipairs(R.list) do
  local x = R.eco(p)
  if x.fixed and x.fixed > 0 then withFixed = withFixed + 1 end
  ok(x.fixed ~= nil, string.format('[%s] 返回里有 fixed（%.5f 克）', p.name, x.fixed or 0))
end
ok(withFixed == 1, string.format('只有 1 个产品固化 CO₂（实际 %d）', withFixed))

print('== 结算页要显示的就是这个数 ==')
ok(e.fixed * 1000 > 0.3 and e.fixed * 1000 < 0.5, string.format('显示成 %.2f 毫克（一个诚实的小数字）', e.fixed * 1000))
ok(true, '（大反差留给玩家自己体会：空气里 CO₂ 只占 0.04%）')

print('== ★ 排碳那套不许溜回来（碳价与"卖碳"是允许的，只是换了币种）==')
ok(R.ECO.joulePerPress == nil and R.ECO.bodyEff == nil, '没有"每下做功 60 J / 人体效率 25%"那套常量')
ok(R.ECO.glucoseJ == nil and R.ECO.co2PerGlucose == nil, '没有"糖 2.8 MJ/mol / 264 g"那套常量')
ok(R.ECO.load == nil, 'ECO 表里没有工序量入口')
local ec = R.eco(dry)
ok(ec.co2 == nil, '返回的 eco 里没有 co2（排碳量）')
ok(ec.load == nil, '返回的 eco 里没有 load')
ok(ec.net == nil, '返回的 eco 里没有 net（净排放）')

print('== 津元是**提前算好的成品常数**（运行时不换算）==')
local E = R.ECO
-- 常数由三个真数一次算完：1 毫克 = 1e-9 吨 × 62.36 元/吨 ÷ 7.2 元/美元 × 3.5e16 津元/美元
local wantPerMg = 1e-9 * 62.36 / 7.2 * 3.5e16
-- 常数只保留 4 位有效数字 ⇒ 用**相对误差**比，别用绝对容差（3e8 量级下 1111 的差是正常的）
ok(math.abs(E.zwdPerMg - wantPerMg) / wantPerMg < 1e-4,
   string.format('津元/毫克 = %.4e（由碳价 62.36 × 汇率 3.5e16 ÷ 7.2 一次折完，常数 %.4e）', E.zwdPerMg, wantPerMg))
ok(E.carbonPrice == nil and E.zwdPerUsd == nil and E.cnyPerUsd == nil,
   '碳价/汇率这些**中间量已删掉** —— 结算时不再换算')
ok(R.ecoZwd == nil and R.ecoCny == nil, '也没有 ecoZwd/ecoCny 这类换算函数')

local ec = R.eco(dry)
near(ec.zwd, ec.fixed * 1000 * E.zwdPerMg, 1, 'eco() 直接返回折好的 zwd（克→毫克→津元，一步缩放）')
near(ec.zwd / 1e8, 1.18, 0.01, string.format('一杯 = %.2f 亿津元（结算页直接写这个数）', ec.zwd / 1e8))
near(R.eco(dry).fixed * 1000, 0.39, 0.005, '另一行直接写毫克数（0.39 毫克）')
near(ec.zwd * 20 / 1e8, 23.64, 0.2, string.format('一天 20 杯 = %.1f 亿津元', ec.zwd * 20 / 1e8))

print(string.format('== 汇总 ==  passed %d / failed %d', pass, fail))
if fail == 0 then print('✓ 环保凭证测试通过') end
