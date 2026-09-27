-- logic_test.lua —— 纯逻辑层的自测（不需要游戏界面，在本地就能跑）
--   node tools/lua-test.mjs lua/test/logic_test.lua
--
-- 为什么先写测试：网页版那 2900 行里，最难查的 bug（重复小票、名额挤掉同单第二杯、
-- 打烊时耐心清零把单删掉）都是**逻辑规则**错了，而不是界面错了。
-- 这些规则搬到 Lua 之后必须能有同样的"几秒跑一局"的自测能力，否则千星上只能靠人肉试。

local CFG = require('config')
local R = require('recipes')

local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1; print('  OK  ' .. msg)
  else fail = fail + 1; print('  X   ' .. msg) end
end
local function eq(a, b, msg) ok(a == b, string.format('%s（期望 %s，实际 %s）', msg, tostring(b), tostring(a))) end

print('== 配置 ==')
local m = CFG.mode('quick')
eq(m.days, 1, '5 分钟局是 1 天')
eq(m.total, 300, '5 分钟局总时长 300s')
eq(CFG.mode('fast').days, 5, '10 分钟局是 5 天')
eq(CFG.kitchen.maxWip, 3, '在制名额上限 3')
ok(CFG.mode('quick').arriveScale > 1, '5 分钟局人数更稀（arriveScale > 1）')

print('== 配方 ==')
ok(#R.list >= 6, '产品数 >= 6（实际 ' .. #R.list .. '）')
local allKindOk, tapN, mashN, holdN = true, 0, 0, 0
for _, r in ipairs(R.list) do
  ok(#r.steps >= 2, r.name .. ' 至少 2 步')
  local last = r.steps[#r.steps]
  if r.serveNow then
    ok(last.st ~= 'pack', r.name .. '（做完即出）最后一步不是打包')
  else
    ok(last.st == 'pack', r.name .. ' 最后一步是打包')
  end
  for _, s in ipairs(r.steps) do
    if not (s.st == 'shake' or s.st == 'fire' or s.st == 'chem' or s.st == 'brew' or s.st == 'pack') then allKindOk = false end
    if s.kind == 'tap' then tapN = tapN + 1
    elseif s.kind == 'mash' then mashN = mashN + 1; if not (s.taps and s.taps >= 2) then allKindOk = false end
    elseif s.kind == 'hold' then holdN = holdN + 1
    else allKindOk = false end
  end
end
ok(allKindOk, '每一步都落在真实工位上，且手法合法（tap/mash/hold 且 mash 有次数）')
ok(tapN > 0 and mashN > 0 and holdN > 0, string.format('三种手法都用到（tap %d / mash %d / hold %d）', tapN, mashN, holdN))
ok(R.byId('qilin').serveNow == true, '火麒麟是"做完即出"')
local coffeeSlots = 0
for _, s in ipairs(R.byId('instcoffee').steps) do if s.noSlot then coffeeSlots = coffeeSlots + 1 end end
eq(coffeeSlots, 3, '速溶咖啡前三步不占名额')
ok(R.byId('dryice').heavy == true, '干冰是重活')
ok(R.byId('qilin').heavy ~= true, '火麒麟不是重活（快消）')

print('== 加权查表 ==')
eq(R.pickWeighted({ { n = 1, p = 1 } }, 0.99).n, 1, '单项权重必然命中')
eq(R.pickWeighted({ { n = 1, p = 0.5 }, { n = 2, p = 0.5 } }, 0.25).n, 1, '0.25 落在第一项')
eq(R.pickWeighted({ { n = 1, p = 0.5 }, { n = 2, p = 0.5 } }, 0.75).n, 2, '0.75 落在第二项')
eq(R.pickWeighted(CFG.cups, 0.0).n, 1, '杯数分布边界：0 → 1 杯')
eq(R.pickWeighted(CFG.cups, 0.999).n, 4, '杯数分布边界：0.999 → 4 杯')

print('== 汇总 ==')
print(string.format('  通过 %d 项，失败 %d 项', pass, fail))
if fail > 0 then print('  TEST-ERROR 有失败项') end
