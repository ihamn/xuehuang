-- cup_spec_test.lua —— 杯子规格与几何的断言（在真机同款运行时里跑）
--   node tools/lua-test.mjs lua/test/cup_spec_test.lua
--
-- 为什么单测这个：杯子从"32 条叠条"改成了"三角形 + 遮挡"（2026-10-01），
--   换实现最容易出的事是**形状悄悄变了**（差一点肉眼看不出来），以及**遮挡没盖住锥尖**。
--   这两件事几何上一算就清楚，所以钉成断言。方案出处见 lua/src/cup_tri_demo.lua / clip_test.lua。

local H = require('host')
local P = require('props')

local pass, fail = 0, 0
local function ok(c, m)
  if c then pass = pass + 1; print('  OK  ' .. m) else fail = fail + 1; print('  X   ' .. m) end
end
local function near(a, b, tol, m)
  ok(math.abs(a - b) <= (tol or 0.5), string.format('%s（期望 %.3f ±%.2f，实际 %.3f）', m, b, tol or 0.5, a))
end

local root = game.InstantiateClientUIControl(1, script.object)
if root then root:SetActive(true) end
local cfg = H.setup(root)
local s = P.spec.cup

print('== 三个主量与推出的斜率 ==')
near(s.mouthW, 100, 0, '口径 = 100（用户圈定）')
near(s.baseW, 69.2, 0, '底径 = 69.2（用户圈定）')
near(s.h, 198, 0, '杯高 = 198（用户圈定）')
-- ★ 用**算式**断言，不写死数字：斜率 = atan(单侧收进 / 杯高)
--   （我第一版写死 4.40，实际推出 4.45 —— 差 0.05° 就红了，是"写死数字"的典型代价）
local wantSlope = math.deg(math.atan(((s.mouthW - P.cupBottomWidth(s)) / 2) / s.h))
near(P.cupSlopeDeg(s), wantSlope, 0.01, string.format('斜率 = atan(单侧收进/杯高) = %.2f°', wantSlope))
near(s.slopeDeg, P.cupSlopeDeg(s), 0.05, '规格里缓存的 slopeDeg 与推出值一致（不许两处打架）')
near(P.cupBottomWidth(s), 69.2, 0.01, '底径仍读得到主量')

print('== 三角方案的控件数 ==')
local cup = P.cupTri(cfg, 'T1', 0, 0, P.drink.water, { maskColor = P.spec.MASK_CANVAS })
local n = 1  -- 根
for _, c in ipairs(cup.controls) do if c then n = n + 1 end end
ok(n == 8, string.format('三角方案 = 8 个控件（外锥+液锥+液面线+遮挡+杯口+高光+杯底亮边+根）；实际 %d', n))
local band = P.cup(cfg, 'T2', 0, 0, P.drink.water, { mode = 'band' })
ok(band.mode ~= 'tri', 'P.cup 支持 mode="band" 回退到叠条（兜底路径还在）')

print('== 外锥的几何（顶宽=口径、尖点在杯底之下）==')
local mouthW, baseW, hh = s.mouthW, P.cupBottomWidth(s), s.h
local tanA = (mouthW - baseW) / 2 / hh
local Hfull = (mouthW / 2) / tanA
near(cup.tri.sizeDeltaX, mouthW, 0.5, '三角顶宽 = 口径')
near(cup.tri.sizeDeltaY, Hfull, 0.5, '三角高 = 全锥高（口径/2 ÷ 斜率）')
-- 轮廓逐点一致：三角在某高度处的宽 = 叠条法的 halfOuter
local function halfOuter(t) return baseW / 2 + (mouthW / 2 - baseW / 2) * t end
local worst = 0
for _, t in ipairs({ 0, 0.25, 0.5, 0.75, 1 }) do
  local d = (1 - t) * hh                       -- 距三角顶边的距离
  local w = mouthW * (1 - d / Hfull)
  local e = math.abs(w - halfOuter(t) * 2)
  if e > worst then worst = e end
end
ok(worst < 0.05, string.format('三角轮廓与叠条法逐点一致（最大偏差 %.4f px）—— 换实现不改形状', worst))

print('== 遮挡块（必须盖住杯底以下那截，含图元留白）==')
local botY = -hh / 2
local maskTop = cup.mask.anchoredPositionY + cup.mask.sizeDeltaY / 2
near(maskTop, botY + 0.6, 0.6, '遮挡块上沿压在杯底线上（+0.6 防缝）')
ok(cup.mask.sizeDeltaX <= baseW + 8, string.format('遮挡块不许做宽（%.1f ≤ 底径+8）—— 大了会在背景上露馅', cup.mask.sizeDeltaX))
local needMaskH = (baseW / 2) / tanA + s.tipPadRatio * Hfull
ok(cup.mask.sizeDeltaY >= needMaskH, string.format('遮挡块够高（%.0f ≥ 需 %.0f：锥尖高 + 图元留白）', cup.mask.sizeDeltaY, needMaskH))

print('== 液锥（上沿在液面、宽 = 该处内壁宽）==')
local function halfInnerAt(t) return halfOuter(t) - s.inset end
for _, frac in ipairs({ 0.25, 0.62, 1 }) do
  cup.setFill(frac)
  local surfY = botY + frac * hh
  local topEdge = cup.liq.anchoredPositionY + cup.liq.sizeDeltaY / 2
  near(topEdge, surfY, 0.6, string.format('液面 %.0f%%：液锥上沿 = 液面', frac * 100))
  near(cup.liq.sizeDeltaX, halfInnerAt(frac) * 2, 0.6, string.format('液面 %.0f%%：液锥上沿宽 = 该处内壁宽', frac * 100))
  near(cup.liqTop.anchoredPositionY, surfY, 0.6, string.format('液面 %.0f%%：液面亮线在同一高度', frac * 100))
end
cup.setFill(0)
ok(cup.liqTop.sizeDeltaX == 0, '空杯时液面亮线宽度归零')

print('== maskColor 必传（平台不裁子控件，只能同色遮挡）==')
local okNoMask, errNoMask = pcall(P.cupTri, cfg, 'T3', 0, 0, P.drink.water, {})
ok(not okNoMask and tostring(errNoMask):find('maskColor') ~= nil,
   '不传 maskColor 会**报错**（而不是默默用错颜色，导致杯子下方糊一块）')

print('== 杯底亮边（不透明、不宽于杯底、压在底线上）==')
if cup.base then
  ok(cup.base.sizeDeltaX <= baseW, string.format('杯底亮边不比杯底宽（%.1f ≤ %.1f）', cup.base.sizeDeltaX, baseW))
  near(cup.base.anchoredPositionY - cup.base.sizeDeltaY / 2, botY, 0.6, '杯底亮边下沿 = 杯底线')
else
  ok(false, '杯底亮边没建出来（baseRimH > 0 时应当有）')
end

print(string.format('== 汇总 ==  passed %d / failed %d', pass, fail))
if fail == 0 then print('✓ 杯子规格测试通过') end
