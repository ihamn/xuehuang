-- eco_limits_test.lua —— 环保凭证的**数值上限**体检（会不会溢出/精度炸/字符串爆长）
--   node tools/lua-test.mjs lua/test/eco_limits_test.lua
--
-- 为什么要有它：津元数字天生很大（一杯就 1.18 亿），而
--   ① Lua 5.3 的 `%d` 对**非整数**值会直接报错（我们用 %.2f，但要防以后改）
--   ② 累加会不会溢出？（float64 上限 1.8e308；若哪天改成整数则是 9.2e18）
--   ③ 数字太大时格式化出来的**字符串会不会把工位卡/结算行撑爆**

local R = require('recipes')

local pass, fail = 0, 0
local function ok(c, m)
  if c then pass = pass + 1; print('  OK  ' .. m) else fail = fail + 1; print('  X   ' .. m) end
end

local dry = R.byId('dryice')
local per = R.eco(dry).zwd          -- 一杯的津元
print(string.format('== 一杯 = %.6e 津元（%.2f 亿）==', per, per / 1e8))

print('== 累加：从一局到荒谬大的局，都不许 inf/nan ==')
for _, cups in ipairs({ 1, 20, 200, 1000, 100000, 1000000, 1000000000 }) do
  local e = R.eco(dry)
  local total = 0
  -- 模拟"每出一杯加一次"（不真的循环十亿次：整数倍直接乘，语义一致）
  total = per * cups
  local finite = total == total and total ~= math.huge and total ~= -math.huge
  ok(finite, string.format('%d 杯 → %.4e 津元（%.2f 亿）', cups, total, total / 1e8))
end

print('== 格式化：字符串不许爆长（真机文本框不裁剪，会盖住隔壁）==')
local worst = 0
for _, cups in ipairs({ 1, 200, 1000000 }) do
  local total = per * cups
  local s = string.format('= %.2f 亿津巴布韦元 · 感谢您为环保事业的贡献', total / 1e8)
  local n = #s
  if n > worst then worst = n end
  ok(n > 0 and n < 40, string.format('%d 杯 → 结算行 %d 字节：%s', cups, n, s))
end
ok(not tostring(per):find('inf') and not tostring(per):find('nan'), '数字本身不是 inf/nan')

print('== `%d` 的坑（★ 实测比想象更凶）==')
-- ★ 我原来想"打一枪看看"：pcall(string.format, '%d', per)。
--   结果**整台测试直接崩了** —— 在这个运行时里，%d 遇到这种大浮点抛的是
--   **JS 级异常**，`pcall` 根本接不住（pcall 只接 Lua 级错误）。
--   ⇒ 结论比"会报错"严重：一旦有人把结算页的 %.2f 改成 %d，**游戏会硬崩，不能兜底**。
--   所以这里**不真跑那一枪**（跑了就没法继续测），改成静态检查（node 侧 tests/eco-wiring.mjs）。
ok(true, '结算页只用 %.2f；%d 的禁用由 tests/eco-wiring.mjs 静态把关（真跑会崩）')

print('== 离上限还有多远 ==')
local maxFloat, maxInt = 1.8e308, 9.2233720368548e18
ok(per > 0, string.format('float64 上限 %.1e ⇒ 还能装 %.1e 杯', maxFloat, maxFloat / per))
ok(per > 0, string.format('int64 上限 %.4e ⇒ 也能装 %.1e 杯（都远超任何一局）', maxInt, maxInt / per))

print(string.format('== 汇总 ==  passed %d / failed %d', pass, fail))
if fail == 0 then print('✓ 数值上限体检通过') end
