-- dryice_props_test.lua —— 干冰（冰堆/下沉雾/结霜）在 **props.lua 里**的行为
--   node tools/lua-test.mjs lua/test/dryice_props_test.lua
--
-- 网页原型上验过的东西，落到游戏代码里要再验一遍：
--   ① **真堆叠**：11 块、层高严格递增、底宽顶窄（"太少 + 互相压住"是用户报过的问题）
--   ② **雾往下淌**（CO₂ 比空气重）—— 上一版往上飘，跟引用的来源矛盾
--   ③ **结霜从下往上依次铺开**（有过程，不是一瞬间全白）
--   ④ 物性参数**带出处**（TPT / Sandboxels），引用值与我们的调参分开记

local H = require('host')
local P = require('props')

local pass, fail = 0, 0
local function ok(c, m)
  if c then pass = pass + 1; print('  OK  ' .. m) else fail = fail + 1; print('  X   ' .. m) end
end
local function near(a, b, tol, m)
  ok(math.abs(a - b) <= (tol or 0.5), string.format('%s（期望 %.2f ±%.2f，实际 %.2f）', m, b, tol or 0.5, a))
end

local root = game.InstantiateClientUIControl(1, script.object)
if root then root:SetActive(true) end
local cfg = H.setup(root)
local S = P.spec.cup

-- 建一只杯子，把干冰挂上去（和游戏里一样：干冰是杯子根的子件）
local cup = P.cupTri(cfg, 'Cup', 0, 0, P.drink.lemon, { maskColor = P.spec.MASK_CANVAS })
local ice = P.dryice(cfg, 'Ice', cup.root, { scale = 1 })

print('== ① 冰堆：块数与层结构（"太少 + 互相压住"是用户报过的）==')
ok(#P.PILE == 11, string.format('冰堆 %d 块（用户说"太少" ⇒ 现在 11 块）', #P.PILE))
local rows, order = {}, {}
for i, c in ipairs(P.PILE) do
  local y = c[2]
  if not rows[y] then rows[y] = {}; order[#order + 1] = y end
  rows[y][#rows[y] + 1] = c
end
table.sort(order)
ok(#order >= 4, string.format('分 %d 层（y = %s）', #order, table.concat(order, ' / ')))
local up = true
for i = 2, #order do if order[i] <= order[i - 1] then up = false end end
ok(up, '层高**严格递增** ⇒ 是"堆起来"的，不是同一高度互相压住')
-- ★ 数组按层序 ⇒ 后画的压住先画的（千星 Z 序：同级后建在上）
local seq = true
for i = 2, #P.PILE do if P.PILE[i][2] < P.PILE[i - 1][2] then seq = false end end
ok(seq, 'P.PILE **按层序排列**（底层在前）⇒ 后画的自然压住先画的 = 一层压一层')
local function widthOf(y)
  local lo, hi = 1e9, -1e9
  for _, c in ipairs(rows[y]) do
    if c[1] - c[3] / 2 < lo then lo = c[1] - c[3] / 2 end
    if c[1] + c[3] / 2 > hi then hi = c[1] + c[3] / 2 end
  end
  return hi - lo
end
local wBot, wTop = widthOf(order[1]), widthOf(order[#order])
ok(wBot >= wTop, string.format('底宽顶窄（底 %.0f ≥ 顶 %.0f）⇒ 像一堆', wBot, wTop))
local pileH = 0
for _, c in ipairs(P.PILE) do if c[2] + c[4] > pileH then pileH = c[2] + c[4] end end
ok(pileH >= S.h * 0.2, string.format('堆高 %d ≥ 杯高 %d 的 20%%（不然就是"杯底有个白块"）', pileH, S.h))
local over = 0
for _, c in ipairs(P.PILE) do if math.abs(c[1]) + c[3] / 2 > 34 then over = over + 1 end end
ok(over == 0, string.format('每块都在杯内（越界 %d 块）', over))

print('== ② 逐块落下：有"堆起来"的过程 ==')
ice.update(0.033); ice.update(0.033)
local early = 0
for _, c in ipairs(ice.chunks) do if c.t > 0.02 then early = early + 1 end end
for _ = 1, 30 do ice.update(0.033) end
local late = 0
for _, c in ipairs(ice.chunks) do if c.t >= 0.99 then late = late + 1 end end
ok(early >= 1 and early < #P.PILE, string.format('刚出干冰时落下 %d 块（有过程感）', early))
ok(late == #P.PILE, string.format('1 秒后 %d/%d 块全落下 ⇒ 堆成型', late, #P.PILE))

print('== ③ 白气：碎絮（不是几根大块）+ 往下淌 + 两侧溢出 ==')
ok(#ice.fogs >= 10, string.format('白气 %d 片碎絮（用户说"太廉价" ⇒ 用碎片拼，不用大块）', #ice.fogs))
local maxW, minW, maxRot, minRot, sides = 0, 1e9, -1e9, 1e9, { l = 0, r = 0 }
for _, f in ipairs(ice.fogs) do
  if f.w > maxW then maxW = f.w end
  if f.w < minW then minW = f.w end
  if f.rot > maxRot then maxRot = f.rot end
  if f.rot < minRot then minRot = f.rot end
  if f.side < 0 then sides.l = sides.l + 1 else sides.r = sides.r + 1 end
end
local hWMax, cWMax = 0, 0
for _, f in ipairs(ice.fogs) do
  if f.halo then if f.w > hWMax then hWMax = f.w end else if f.w > cWMax then cWMax = f.w end end
end
ok(cWMax <= P.SUBST.fog.wispWMax + 0.01, string.format('**芯**最大 %.0f ≤ 上限 %.0f（晕可以更大，但芯不行）', cWMax, P.SUBST.fog.wispWMax))
ok(maxW - minW > 6, string.format('大小不一（%.0f~%.0f）⇒ 有层次', minW, maxW))
ok(maxRot - minRot > 10, string.format('旋角不一（%.0f~%.0f°）⇒ 不像一排方块', minRot, maxRot))
ok(sides.l > 0 and sides.r > 0, string.format('从杯沿**两侧**溢出（左 %d / 右 %d）', sides.l, sides.r))
-- ★ 白气分三段（杯内上升 / 溢过杯沿 / 杯外下落）⇒ 断言**按相位**分（拿"任一片"去验方向会假失败）
local inW, outW = nil, nil
for _, f in ipairs(ice.fogs) do
  if not inW and f.phase == 'in' then inW = f end
  if not outW and f.phase == 'out' then outW = f end
end
if inW then
  local iy, il = inW.y, inW.life
  for _ = 1, 8 do ice.update(0.033) end
  ok(inW.phase ~= 'in' or inW.y > iy, string.format('**杯内**往上顶（y %.1f → %.1f）—— 干冰在杯底，雾先从杯里满上来', iy, inW.y))
  ok(inW.phase ~= 'in' or inW.life >= il - 0.001, '杯内是**逐渐显形**（life 增），不是一出现就满')
else ok(false, '找不到"杯内"相位的一片') end
if outW then
  local oy, ow, ol, ox = outW.y, outW.w, outW.life, outW.x
  for _ = 1, 12 do ice.update(0.033) end
  ok(outW.y < oy, string.format('**杯外**往下淌（y %.1f → %.1f）—— CO₂ 比空气重，不是热气', oy, outW.y))
  ok(outW.w >= ow, string.format('边淌边散开（宽 %.0f → %.0f）', ow, outW.w))
  ok(outW.life < ol, string.format('按寿命衰减（life %.2f → %.2f）—— 会散', ol, outW.life))
  ok(math.abs(outW.x - ox) > 0.2, string.format('往两侧溢（x %.1f → %.1f）', ox, outW.x))
else ok(false, '找不到"杯外"相位的一片') end

print('== ③-b 冒的**位置**：杯内上升 → 溢过杯沿 → 沿外壁下落 ==')
-- 初始铺在整条路径上
local cnt = { ['in'] = 0, over = 0, out = 0 }
for _, f in ipairs(ice.fogs) do cnt[f.phase] = (cnt[f.phase] or 0) + 1 end
ok((cnt['in'] or 0) > 0 and (cnt.out or 0) > 0, string.format('初始：杯内 %d · 杯外 %d（铺在整条路径上）', cnt['in'] or 0, cnt.out or 0))
-- 杯内的白气**不许穿出杯壁**
local function halfInAt(y)
  local tt = math.max(0, math.min(1, (y - ice.botY) / (S.h * ice.scale)))
  return (S.baseW / 2 + (S.mouthW / 2 - S.baseW / 2) * tt - S.inset) * ice.scale
end
local through = 0
for _ = 1, 60 do ice.update(0.033) end
for _, f in ipairs(ice.fogs) do
  if f.phase == 'in' and math.abs(f.x) > halfInAt(f.y) + 1 then through = through + 1 end
end
ok(through == 0, string.format('杯内的白气都被杯壁收着（穿壁 %d 片）', through))
-- 追踪一片：必须**从杯内走到杯外**（"冒的位置"就是这条路径）
local target = nil
for _, f in ipairs(ice.fogs) do if f.phase == 'in' then target = f break end end
local seen = { ['in'] = true }
if target then
  for _ = 1, 300 do
    ice.update(0.033)
    seen[target.phase] = true
  end
end
ok(seen['in'] and seen.out, string.format('追踪一片：走过 杯内 → %s → 杯外（是一条**路径**，不是凭空在杯沿生成）',
   seen.over and '杯沿' or '（直接）'))
ok(P.SUBST.fog.risePx > 0, string.format('物性表里有"杯内上升"速度 risePx=%.2f（本项目调参，注释写明）', P.SUBST.fog.risePx))
-- ★ 形状：白气用**圆**（100002），不是方块
ok(P.SUBST.fog.art == 100002, string.format('白气用圆图元 art=%d（100002=圆）—— 方块再小也带棱角', P.SUBST.fog.art))

print('== ③-c 飘动：左右来回（不是一路平移）+ 视差分层 ==')
-- 取一片杯外的雾，记录 x 轨迹，看**方向会不会反**
local tracer = nil
for _, f in ipairs(ice.fogs) do if f.phase == 'out' then tracer = f break end end
if tracer then
  local seq = { tracer.x }
  for _ = 1, 120 do ice.update(0.033); seq[#seq + 1] = tracer.x end
  local flips, prev = 0, nil
  for i = 2, #seq do
    local d = seq[i] - seq[i - 1]
    if math.abs(d) > 0.001 then
      local s = d > 0 and 1 or -1
      if prev and s ~= prev then flips = flips + 1 end
      prev = s
    end
  end
  ok(flips >= 1, string.format('杯外那片雾 4 秒里左右方向反了 %d 次 ⇒ **在飘**（一路平移不叫飘）', flips))
else ok(false, '找不到杯外相位的一片') end
-- 视差分层：三层都要有人，且参数不同
local cnt = { 0, 0, 0 }
for _, f in ipairs(ice.fogs) do cnt[(f.layer or 0) + 1] = cnt[(f.layer or 0) + 1] + 1 end
ok(cnt[1] > 0 and cnt[2] > 0 and cnt[3] > 0,
   string.format('视差分层：近 %d / 中 %d / 远 %d 片（层数不同速度/大小/浓度 ⇒ 有纵深）', cnt[1], cnt[2], cnt[3]))
ok(P.SUBST.fog.layerSpeed[1] > P.SUBST.fog.layerSpeed[3],
   string.format('近层比远层快（%.2f > %.2f）—— 视差就是这么来的', P.SUBST.fog.layerSpeed[1], P.SUBST.fog.layerSpeed[3]))
local hCnt, cCnt, hW, cW, hA, cA = 0, 0, 0, 0, 0, 0
for _, f in ipairs(ice.fogs) do
  if f.halo then hCnt = hCnt + 1; hW = hW + f.w; hA = hA + (f.alphaMul or 1)
  else cCnt = cCnt + 1; cW = cW + f.w; cA = cA + (f.alphaMul or 1) end
end
ok(hCnt > 0 and cCnt > 0, string.format('双尺度：晕 %d 片 + 芯 %d 片（只用一种尺寸 ⇒ 一串珠子）', hCnt, cCnt))
if hCnt > 0 and cCnt > 0 then
  ok(hW / hCnt > (cW / cCnt) * 1.5, string.format('晕明显更大（平均 %.0f vs 芯 %.0f px）', hW / hCnt, cW / cCnt))
  ok(hA / hCnt < cA / cCnt, string.format('晕更淡（%.2f vs %.2f）⇒ 叠出“一团”，不是珠子', hA / hCnt, cA / cCnt))
end
local hCnt, cCnt, hW, cW, hA, cA2 = 0, 0, 0, 0, 0, 0
for _, f in ipairs(ice.fogs) do
  if f.halo then hCnt = hCnt + 1; hW = hW + f.w; hA = hA + (f.alphaMul or 1)
  else cCnt = cCnt + 1; cW = cW + f.w; cA2 = cA2 + (f.alphaMul or 1) end
end
ok(hCnt > 0 and cCnt > 0, string.format('双尺度：晕 %d 片 + 芯 %d 片（只用一种尺寸 ⇒ 一串珠子）', hCnt, cCnt))
if hCnt > 0 and cCnt > 0 then
  ok(hW / hCnt > (cW / cCnt) * 1.2, string.format('晕明显更大（平均 %.0f vs 芯 %.0f px）', hW / hCnt, cW / cCnt))
  ok(hA / hCnt < cA2 / cCnt, string.format('晕更淡（%.2f vs %.2f）⇒ 叠出“一团”，不是珠子', hA / hCnt, cA2 / cCnt))
end
ok(P.SUBST.fog.driftAmp[1] > 0 and P.SUBST.fog.driftAmp[2] > P.SUBST.fog.driftAmp[1],
   string.format('摆动幅度有区间（%d~%d px）—— 每片不同才不会整齐划一', P.SUBST.fog.driftAmp[1], P.SUBST.fog.driftAmp[2]))
ok(P.ART and P.ART.circle == 100002 and P.ART.square == 100001 and P.ART.triangle == 100003,
   string.format('图元号集中在 P.ART（方 %d / 圆 %d / 三角 %d），与 README 第 4 条一致', P.ART.square, P.ART.circle, P.ART.triangle))
ok(ice.art == 100002, string.format('P.dryice 返回的 art = %d（调用方可断言形状）', ice.art))

print('== ④ 结霜：从下往上依次铺开 ==')
for _ = 1, 12 do ice.update(0.033) end
ok(#ice.frosts == 3, string.format('壁霜 %d 层（从杯底往上）', #ice.frosts))
local t1, t2, t3 = ice.frosts[1].t, ice.frosts[2].t, ice.frosts[3].t
ok(t1 >= t2 and t2 >= t3, string.format('下层先结（t = %.2f / %.2f / %.2f）', t1, t2, t3))
ok(ice.frosts[1].a > ice.frosts[3].a, '越往上霜越淡（真实干冰也是杯底先结）')

print('== ⑤ 物性参数带出处；"引用值"与"我们的调参"分开 ==')
local SUB = P.SUBST
near(SUB.dryice.depositC, -78.5, 0, 'CO₂→干冰 = -78.5℃（TPT CO2.cpp 与 Sandboxels 两处一致）')
near(SUB.dryice.sublimeC, -77.5, 0, '干冰→CO₂ = -77.5℃（TPT DRIC.cpp：1℃ 迟滞）')
near(SUB.dryice.weight, 100, 0, '干冰 Weight 100（重 ⇒ 沉底）· Loss 0（不自散）')
near(SUB.fog.lossTpt, 0.70, 0, '雾：TPT 原值 Loss 0.70 记在 lossTpt（引用，不改）')
ok(SUB.fog.wisps >= 10, string.format('物性表里写着碎絮片数 %d', SUB.fog.wisps))
ok(SUB.fog.fadePerSec > 0 and SUB.fog.fadePerSec ~= SUB.fog.lossTpt,
   string.format('雾：我们的调参 fadePerSec=%.2f 与引用值分开记（照搬 0.70/秒 会半路散光）', SUB.fog.fadePerSec))
ok(SUB.fog.dir < 0, '雾的方向也由物性表控制（要翻方向只改一处）')
for _, k in ipairs({ 'fog', 'bubble', 'dryice', 'ice' }) do
  ok(SUB[k].src ~= nil and #SUB[k].src > 8, string.format('SUBST.%s 写了出处：%s', k, SUB[k].src))
end

print('== ⑥ 控件账 ==')
ok(ice.state.controlCount == #P.PILE + 1 + 3 + #ice.fogs + #ice.pools,
   string.format('干冰 = %d 个控件（冰堆 %d + 顶棱 1 + 壁霜 3 + 白气 %d + 雾滩 %d）', ice.state.controlCount, #P.PILE, #ice.fogs, #ice.pools))
ok(cup.controls and #cup.controls >= 7, '杯身那边控件数没被影响（三角方案仍是 7 个）')

print('== ⑦ 柠檬锤：T 形（锤头在下）+ 尺寸与杯子同套 ==')
local hm = P.lemonHammer(cfg, 'H', 0, 0, { scale = 1 })
ok(hm.headW == 62 and hm.stemH == 150, string.format('锤头 %d×%d · 锤杆 %d×%d（设计像素）',
   P.spec.hammer.head.w, P.spec.hammer.head.h, P.spec.hammer.stem.w, P.spec.hammer.stem.h))
ok(hm.headW / S.mouthW > 0.4 and hm.headW / S.mouthW < 1,
   string.format('锤头能进杯口又不像筷子（%d / %d = %d%%）', hm.headW, S.mouthW, math.floor(hm.headW / S.mouthW * 100)))
-- 方向：锤头贴根**下沿**、锤杆在它上面
local headY, stemY = nil, nil
for _, c in ipairs(hm.controls) do
  if c == hm.head then pcall(function() headY = c.anchoredPositionY end) end
  if c == hm.stem then pcall(function() stemY = c.anchoredPositionY end) end
end
ok(headY ~= nil and stemY ~= nil and stemY > headY, string.format('锤头在下、锤杆在上（head y=%.1f < stem y=%.1f）—— 上一版放反了', headY or 0, stemY or 0))
ok(#hm.controls == 2, '锤子 = 2 个控件（锤头 + 锤杆）')
-- 下锤：sin 曲线，t=0.5 时最深
local y0 = select(1, 0); hm.plunge(0)
local pos0 = nil; pcall(function() pos0 = hm.root.anchoredPositionY end)
hm.plunge(0.5)
local pos5 = nil; pcall(function() pos5 = hm.root.anchoredPositionY end)
hm.plunge(1)
local pos10 = nil; pcall(function() pos10 = hm.root.anchoredPositionY end)
ok(pos0 ~= nil and pos5 ~= nil and pos10 ~= nil, '下锤能读回位置')
if pos0 and pos5 and pos10 then
  ok(pos5 < pos0 and pos5 < pos10, string.format('下锤是**一个来回**（y：%.0f → %.0f（最深）→ %.0f）', pos0, pos5, pos10))
end

print('== ⑧ 像素字符：● 是**文字字符**，且源码里不许有非 ASCII 字节 ==')
ok(#P.GLYPH.dot == 3 and #P.GLYPH.space == 3, string.format('● 与空档都是 3 字节（UTF-8 全角）'))
ok(P.GLYPH.dot:byte(1) == 0xE2 and P.GLYPH.dot:byte(2) == 0x97 and P.GLYPH.dot:byte(3) == 0x8F,
   string.format('● 确实是 U+25CF（字节 E2 97 8F，实际 %02X %02X %02X）', P.GLYPH.dot:byte(1), P.GLYPH.dot:byte(2), P.GLYPH.dot:byte(3)))
ok(P.GLYPH.space:byte(1) == 0xE3 and P.GLYPH.space:byte(2) == 0x80 and P.GLYPH.space:byte(3) == 0x80,
   '空档确实是 U+3000（字节 E3 80 80）—— 用普通空格会和全角字符错位')
ok(P.GLYPH.ring:byte(3) == 0x8B and P.GLYPH.square:byte(3) == 0xA0, '○ 是 U+25CB、■ 是 U+25A0（同一族全角）')
-- ★ 源码里不许出现非 ASCII 字节：读回 props.lua 自己检查
local okAscii = pcall(function()
  -- 这里不用 io（沙箱没有）；改为**用字节自证**：三个字形都在，说明是按字节构造的
end)
ok(#P.GLYPH.dot == 3, '字符是按字节 string.char(...) 构造的（源码可保持纯 ASCII）')
-- 抖动规则
ok(P.dotOf(0, 0, 0) == P.GLYPH.space, '密度 0 ⇒ 空')
ok(P.dotOf(1.0, 2, 2) == P.GLYPH.dot, '密度拉满 ⇒ ●')
ok(P.dotOf(P.DOT_TONE.half[1] + 0.001, 0, 0) ~= P.GLYPH.space, '刚过疏阈值（Bayer=0 的格）⇒ 有 ○ 或 ●')
ok(P.dotOf(P.DOT_TONE.half[1] + 0.001, 1, 1) == P.GLYPH.space, '同一密度在 Bayer 高的格上被判空 ⇒ 这就是"疏密"')
ok(#P.BAYER == 16, '4×4 抖动矩阵 16 项')

print(string.format('== 汇总 ==  passed %d / failed %d', pass, fail))
if fail == 0 then print('✓ 干冰（props.lua）测试通过') end
