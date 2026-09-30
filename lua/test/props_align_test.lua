-- props_align_test.lua —— 实物件"对齐关系"的自测（在真机同款运行时里跑）
--   node tools/lua-test.mjs lua/test/props_align_test.lua
--
-- 为什么单测这个：用户 2026-10-01 圈定了两条关系 ——
--   ① 火的下部与火炬上部**对齐**（火的底边 = 筒口顶边）
--   ② 火的底宽 = 筒口宽
-- 这两条都是"看起来只是有点歪/有点小"的那种错，肉眼在真机上很难判，
-- 但**几何上一算就清楚**。所以把它钉成断言：谁改坏了，本地立刻红。

local H = require('host')
local P = require('props')

local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1; print('  OK  ' .. msg)
  else fail = fail + 1; print('  X   ' .. msg) end
end
local function near(a, b, tol, msg)
  ok(math.abs(a - b) <= (tol or 0.5),
     string.format('%s（期望 %.3f ±%.2f，实际 %.3f）', msg, b, tol or 0.5, a))
end

-- 建挂载点（和真机一样：脚本挂在客户端控件容器上）
local root = game.InstantiateClientUIControl(1, script.object)
if root then root:SetActive(true) end
local cfg = H.setup(root)

print('== 规格（用户圈定值）==')
near(P.spec.cone.mouthW, 120, 0, '筒口宽 = 120')
near(P.spec.cone.mouthH, 18, 0, '筒口高 = 18')
near(P.spec.cone.gripW, 84, 0, '握把宽 = 84')
near(P.spec.cone.gripH, 34, 0, '握把高 = 34')
near(P.spec.cone.w, 104, 0, '锥体顶宽 = 104')
near(P.spec.cone.h, 214, 0, '锥体高 = 214')
near(P.spec.cone.tipW, 6, 0, '锥尖宽 = 6')
near(P.spec.fire.cols, 16, 0, '火 16 列')
near(P.spec.fire.rows, 27, 0, '火 27 行')

print('== 由筒口推出的格子（唯一真相）==')
near(P.fireCellW(), 7.5, 0.001, '每格宽 = 筒口宽 / 16 = 7.5')
near(P.fireCellH(), 5.625, 0.001, '每格高 = 宽 × 0.75 = 5.625')
local fw, fh = P.fireSize()
near(fw, 120, 0.001, '火宽 = 120（= 筒口宽）')
near(fh, 151.875, 0.001, '火高 = 151.875')

print('== 对齐：火底边 = 筒口顶边（三种 scale 都要成立）==')
for _, sc in ipairs({ 1, 0.5, 0.33 }) do
  local g = P.torchWithFire(cfg, 'T' .. tostring(sc), 0, 0, { scale = sc })
  near(g.fireBottomY, g.mouthTopY, 0.5, string.format('scale=%.2f：火底边与筒口顶边重合', sc))
  near(g.fire.w, P.spec.cone.mouthW * sc, 0.5, string.format('scale=%.2f：火宽 = 筒口宽', sc))
  near(g.fire.h, 27 * 5.625 * sc, 0.5, string.format('scale=%.2f：火高按同一 scale 缩', sc))
end

print('== 对齐不是"碰巧"：把火抬高就应当不重合 ==')
do
  local sc = 0.5
  local cone = P.cone(cfg, 'AloneTorch', 0, 0, { scale = sc })
  local fireH = 27 * P.fireCellH() * sc
  local wrongY = P.fireY(cone, fireH) + 10          -- 故意抬 10px
  local fire = P.fire(cfg, 'AloneFire', 0, wrongY, { scale = sc })
  local mouthTop = (cone.mouthTopY or 0) * sc
  local fireBottom = wrongY - fire.h / 2
  ok(math.abs(fireBottom - mouthTop) > 9, string.format('抬高 10px 后确实不重合（差 %.1fpx）—— 判据是敏感的', fireBottom - mouthTop))
end

print(string.format('== 汇总 ==  passed %d / failed %d', pass, fail))
if fail == 0 then print('✓ 对齐测试通过') end
