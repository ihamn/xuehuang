-- props.lua —— 实物视觉件：杯子 / 炮筒 / 火
--
-- 设计依据（都来自 preview/design 里已定稿的稿子，改这里必须同步改稿）：
--   · 形状-杯子.html  侧壁斜率**离垂直 8.75°**（口径 100 → 底径 69.2，高 100）；
--                     液体**液面水平**、两侧贴杯内壁（不能做成内接梯形 —— 那是"杯里套小杯"的错）
--   · 形状-炮筒.html  锥体 + 筒口 + 握把，**简化版**（用户要求"炮筒简单一点"）
--   · 火-尺寸15x25与12x20.html  DOOM 火焰算法，**16 列 × 27 行 = 432 个方块**，显示 12×20
--
-- ★ 三条硬约束（踩过的，别再犯）：
--   1. 素材库没有杯子/炮筒/火的现成图 → 只能用基础形状拼：100001 方块（可拉伸不糊）
--   2. 控件坐标是**相对父控件中心**的偏移，超出父矩形会被裁 → 长出去的东西（火焰）必须挂在
--      装得下它的容器里，或直接挂根节点
--   3. `math.random` 被沙箱拦 → 自带 LCG 伪随机（顺带可复现）

-- ★ H（宿主封装）必须自己 require：铺平后每个模块是独立作用域，H 不是全局变量
local H = require('host')

local P = {}

-- ══════════════════════════════════════════════════════════
-- 一、规格（全部设计像素；改数这里一处）
-- ══════════════════════════════════════════════════════════
P.spec = {
  cup = {
    slopeDeg = 8.75,        -- 侧壁离垂直的角度（基准数）
    h        = 100,         -- 杯身高
    -- ★ 两个明确命名的口径（2026-09-27 定稿）：**上宽下窄**
    --   上 = 杯口/口径（看得见的那头，宽）；下 = 杯底（收进去的那头，窄）。
    --   要改方向就改这两个值 —— 不许再用 "wTop 减点东西" 那种推法（我因此反了 3 次）。
    mouthW   = 100,         -- 杯口（上，宽）
    wTop     = 100,         -- 旧名，保留兼容；语义等同 mouthW
    inset    = 3,           -- 内壁相对外壁内缩（液体裁切用）
    lipH     = 8,           -- 杯口亮边高
    shineW   = 4,           -- 高光宽
  },
  cone = {
    w        = 160, h = 182,  -- 锥体（三角）顶宽 / 高
    mouthH   = 20,            -- 筒口高
    mouthW   = 180,           -- 筒口宽（比锥顶宽，形成"沿"）
    gripH    = 26,            -- 握把高
    gripW    = 140,           -- 握把宽
    tipW     = 10,            -- 锥尖宽（不是 0，免得看不见）→ 决定"盖住多少"
    maskTint = { 10, 14, 24 },-- 遮挡块颜色（≈画布底色；盖块靠"同色"假装不存在）
  },
  fire = {
    cols = 16, rows = 27,     -- 网格（用户选定）
    cellW = 4, cellH = 3,     -- 每格设计像素 → 显示 64×81（比例同 12:20）
    sourceRows = 3,           -- 底部几行是火源
    decayMax = 3,             -- 每帧最大衰减
    exponent = 0.9,           -- 三角包络指数（越大越瘦）
  },
}

-- 25 级调色板：冷 → 热（DOOM 那套），带 A 通道做"火梢渐隐"
P.PAL = {
  {  7,  7, 15,   0 }, { 26, 10, 10,  40 }, { 60, 12, 10,  90 }, {100, 15, 12, 140 },
  {140, 20, 12, 180 }, {176, 28, 12, 210 }, {206, 40, 12, 235 }, {226, 58, 12, 250 },
  {238, 78, 14, 255 }, {246,100, 16, 255 }, {250,120, 18, 255 }, {252,140, 22, 255 },
  {254,158, 26, 255 }, {255,172, 34, 255 }, {255,186, 48, 255 }, {255,198, 66, 255 },
  {255,208, 86, 255 }, {255,216,108, 255 }, {255,224,132, 255 }, {255,232,158, 255 },
  {255,238,182, 255 }, {255,244,206, 255 }, {255,249,226, 255 }, {255,252,242, 255 },
  {255,255,255, 255 },
}
local NLEV = #P.PAL

-- 饮料配色（按**真实颜色**，不是按"分区印象"；例：溴水是黄褐，不是紫）
P.drink = {
  lemon  = { 234, 243, 160 },   -- 干冰干柠檬水   淡黄绿
  brom   = { 240, 180,  68 },   -- 千溴水         黄褐
  coffee = { 138,  90,  52 },   -- 现萃速溶咖啡   深褐
  peach  = { 247, 168, 120 },   -- 蟠桃四季春     桃色
  milk   = { 191, 233, 168 },   -- 牛顿苹果奶绿   奶绿
  water  = { 143, 208, 255 },   -- 通用"水"（步骤演示用）
}

-- ══════════════════════════════════════════════════════════
-- 二、伪随机（LCG）—— math.random 被沙箱拦，必须自带
-- ══════════════════════════════════════════════════════════
local rngState = 20260927
local function rnd(n)                 -- 返回 0..n-1
  rngState = (rngState * 1103515245 + 12345) % 2147483648
  return math.floor(rngState / 65536) % n
end
function P.seedRng(s) rngState = s or 20260927 end

-- ══════════════════════════════════════════════════════════
-- 三、几何计算（照稿子里的公式）
-- ══════════════════════════════════════════════════════════

-- 侧壁内收量：高 h、离垂直 slopeDeg 度 → 每侧水平内收
function P.slopeRun(h, slopeDeg)
  local rad = (slopeDeg or P.spec.cup.slopeDeg) * math.pi / 180
  return h * math.tan(rad)
end

-- 杯底宽（由斜率算出来，不手填）
function P.cupBottomWidth(s)
  s = s or P.spec.cup
  return s.wTop - 2 * P.slopeRun(s.h, s.slopeDeg)
end

-- ══════════════════════════════════════════════════════════
-- 四、杯子：**叠条法**逼近网页稿的梯形玻璃杯
--
-- ★★ 为什么必须"叠条"（这是"和网页一样"的唯一路子）：
--   网页稿（SVG）用的是「多边形 + 描边 + 半透明填充 + 渐变 + 裁切」。
--   千星**一样都没有** —— 图元只有 方块/圆/三角/五角星/圆环，没有多边形、没有描边、没有渐变。
--   所以画梯形只能把梯形**横向切成 N 条**，每条一个方块、宽度按该行高度插值。
--   条数够多（本体 32 条）看着就是连续梯形；条数少了会露台阶。
--
-- ★ 另一条路（更省控件、也才是真正的"一模一样"）：**用素材库里的成品图**。
--   在编辑器「界面控件组管理 → 素材库」里选一张杯子图，把素材号写进 cfg.cupArt；
--   有 cupArt 时本体直接贴图，这里只画"液体 + 进度"。官方没给素材号一览表，
--   哪个号是杯子只能你在编辑器里挑（我没法凭猜写一个号 —— 假素材号会显示成空白）。
-- ══════════════════════════════════════════════════════════
function P.cup(cfg, name, x, y, drink)
  local s = P.spec.cup
  local root = H.spawn(cfg, 'img', name or 'CupRoot')
  H.setPos(root, x or 0, y or 0)

  drink = drink or P.drink.water

  -- ★★ 锥度：**上宽下窄**（2026-09-27 用户定稿）
  --   上（杯口/口径）= mouthW = 100（宽）｜下（杯底）= baseW = 69.2（窄）
  --   ★ 为了不再出现"上下说反"的来回，这里**用两个明确命名的量**，
  --     不再靠 "wTop/wBot + 谁减谁" 推方向。要改方向就改这两个值。
  local mouthW = s.mouthW or s.wTop                     -- 杯口（上，宽）
  local baseW  = s.baseW or P.cupBottomWidth(s)          -- 杯底（下，窄）
  local hh = s.h
  local BANDS = 32
  local LQ = 16
  local bandH = hh / BANDS

  local halfIn = P.slopeRun(hh, s.slopeDeg)
  local rootH = hh + s.lipH
  local rootTop = rootH / 2
  local bodyTop = rootTop - s.lipH                  -- 杯身顶沿
  local bodyBot = bodyTop - hh                      -- 杯身底沿

  H.setSize(root, math.max(mouthW, baseW), rootH)   -- 根按**宽的那头**给，免得裁到
  H.setColor(root, 0, 0, 0, 0)                      -- 根控件只当容器

  -- t: 0=底（窄） 1=顶（宽）
  local function halfOuter(t) return baseW / 2 + (mouthW / 2 - baseW / 2) * t end
  local function halfInner(t) return halfOuter(t) - s.inset end

  -- 壁线/亮边要用的两个量（名字明确，避免再搞混）
  local wallMidX = (mouthW / 2 + baseW / 2) / 2      -- 侧壁中点的半宽

  -- ① 玻璃本体：32 条横条，自下而上，宽度按行插值 → 连起来是梯形
  for i = 1, BANDS do
    local b = H.spawn(cfg, 'img', 'CupBody' .. i, root)
    local t = (i - 0.5) / BANDS
    H.setSize(b, halfOuter(t) * 2, bandH + 0.6)
    H.setColor(b, 224, 240, 255, 78)
    H.setPos(b, 0, bodyBot + (i - 0.5) * bandH)
  end

  -- ② 两侧壁线：**已砍掉**（2026-09-27 用户定）
  --   ★ 为什么砍：斜条是"绕自身中心旋转"摆的，而杯身是"逐条算宽度"叠出来的 ——
  --     两者只在一个点上吻合、其余必然错开，结果**画面里叠了两个梯形**
  --     （用户原话："杯子叠了两层，一层上窄一层上宽"）。
  --     梯形轮廓已经由杯身 32 条自己构成，斜线纯属多余。
  --   ★ 以后要做"描边"效果，正确做法是**加宽遮挡/描边块**，而不是指望一根旋转细条能贴合斜边。

  -- ③ 液体：也是叠条（16 条），自下而上按当前液面点亮
  local liqBands = {}
  for i = 1, LQ do
    local b = H.spawn(cfg, 'img', 'CupLiq' .. i, root)
    H.setColor(b, drink[1], drink[2], drink[3], 240)
    H.setSize(b, 0, 0); H.setPos(b, 0, 0)
    liqBands[i] = b
  end
  local liqTop = H.spawn(cfg, 'img', 'CupLiqTop', root)   -- 液面亮线（水平）
  H.setColor(liqTop, 255, 255, 255, 130)
  H.setSize(liqTop, 0, 0)

  local function setFill(frac)
    frac = math.max(0, math.min(1, frac or 0))
    for i = 1, LQ do
      local b = liqBands[i]
      local t0 = (i - 1) / LQ
      local vis = frac - t0
      if vis <= 0.002 then
        H.setSize(b, 0, 0); H.setPos(b, 0, 0)
      else
        local cover = math.min(vis, 1 / LQ)
        local tm = t0 + cover / 2
        H.setSize(b, halfInner(tm) * 2, cover * hh + 0.6)
        H.setPos(b, 0, bodyBot + tm * hh)
      end
    end
    if frac <= 0.002 then
      H.setSize(liqTop, 0, 0); H.setPos(liqTop, 0, 0)
    else
      H.setSize(liqTop, halfInner(frac) * 2, 2)
      H.setPos(liqTop, 0, bodyBot + frac * hh)
    end
  end
  setFill(0)

  -- ④ 杯口亮边（在最上面那条带的位置）
  local lip = H.spawn(cfg, 'img', 'CupLip', root)
  H.setSize(lip, mouthW + 4, s.lipH)
  H.setColor(lip, 234, 243, 255, 255)
  H.setPos(lip, 0, rootTop - s.lipH / 2)

  -- ⑤ 左侧高光（**竖直**，不再用旋转斜条）
  --   ★ 原来它是转 8.75° 的斜条 —— 和杯壁斜线犯同一个毛病：绕中心旋转，必然和梯形边缘错开，
  --     画面上就是"多一条斜线"。竖直块落在杯身内部，不会和轮廓打架。
  local shine = H.spawn(cfg, 'img', 'CupShine', root)
  H.setSize(shine, s.shineW, hh * 0.82)
  H.setColor(shine, 255, 255, 255, 130)
  H.setPos(shine, -(mouthW / 2 - s.inset - s.shineW - 6), (bodyTop + bodyBot) / 2)

  return { root = root, liq = liqBands[1], setFill = setFill, lip = lip, shine = shine,
           mouthW = mouthW, baseW = baseW, bands = BANDS + LQ + 1,
           geo = { h = hh, mouth = mouthW, base = baseW, inset = s.inset, slopeDeg = s.slopeDeg } }
end

-- ══════════════════════════════════════════════════════════
-- 五、炮筒：锥体 = **一个三角形（转 180°）**，尖头收钝只用一个不大的盖块
--
-- ★ 三角朝向（实测，见 preview/design/prims.png）：
--   三角形图元**顶点在上、底边在下**；转 180° 才是尖朝下。
-- ★ 这一版和"12 层叠条"的区别：控件 12 → 2，边缘是真三角形（不是台阶）。
-- ★ 盖块尺寸怎么来的（关键，别再用错的算法）：
--   要"露出 182 高、底宽 10" ⇒ 不能按 顶宽/底宽 直接放大三角（那会得到 2912 高的怪物）。
--   正确做法：**盖块很小**，只压住尖头最后那一小段。
--     三角总高 Htri = h / (1 - tipW/w)   ← 注意分母是 1 减去"宽度比"，不是宽度比本身
--   （我上一版把公式写成 h × w/tipW，直接把三角放大 16 倍 —— 那才是"一根竖条"的原因。）
-- ══════════════════════════════════════════════════════════
function P.cone(cfg, name, x, y, opts)
  opts = opts or {}
  local c = P.spec.cone
  local root = H.spawn(cfg, 'img', name or 'ConeRoot')
  H.setPos(root, x or 0, y or 0)
  local rootH = c.mouthH + c.gripH + c.h + 20        -- 留 20 给锥尖的余量
  H.setSize(root, c.mouthW, rootH)
  H.setColor(root, 0, 0, 0, 0)                      -- 根只当容器

  -- ★★ 坐标口径（这次是量出来的，别再猜）：
  --   子控件的 anchoredPositionY 是**相对根控件中心**的偏移 —— 不是"根的上沿"。
  --   我前三版一直按"上沿 y=0"排，结果**每个部件都偏了 rootH/2**（228 高的根偏 114），
  --   表现是"筒口沉在中间、握把跑到锥体上"这种错乱。
  --   所以：先算 rootCenterYTop = +rootH/2（上沿），再自上而下排：
  --     筒口沿 → 筒口内壁 → 握把 → 锥体 → 锥尖（锥尖朝下）
  local topY = rootH / 2

  local cA = opts.color or { 224, 176, 114 }        -- 烤脆筒
  local art = cfg.artCone or cfg.art or 100003      -- 三角形素材号（顶点在上）

  -- 自上而下的条带（每段给"上沿/下沿"）
  local mouthTop, mouthBot = topY, topY - c.mouthH
  local gripTop,  gripBot  = mouthBot, mouthBot - c.gripH
  local coneTop,  coneBot  = gripBot, gripBot - c.h

  -- 三角总高：露出 c.h 高、底宽从 w 收到 tipW ⇒ Htri = c.h / (1 - tipW/w)（≈194）
  local wRatio = c.tipW / c.w
  local Htri = c.h / math.max(0.01, 1 - wRatio)
  local tipRun = Htri - c.h                          -- 要收掉的那一小段（≈12）

  -- ① 盖块（先画）：把锥体在 coneBot 处割平
  local mH = tipRun * 4 + 60
  local mask = H.spawn(cfg, 'img', 'ConeMask', root)
  H.setSize(mask, c.w + 20, mH)
  -- 三角转 180° 后实际尖点比 sizeDeltaY/2 多伸一小段（图元自带留白），所以顶边上抬 24
  H.setPos(mask, 0, coneBot + 24 - mH / 2)
  H.setColor(mask, c.maskTint[1], c.maskTint[2], c.maskTint[3], 255)

  -- ② 锥体（后画）：三角形转 180°，**底边对齐锥顶** ⇒ 中心 = coneTop − Htri/2
  local cfgTri = { root = root, img = cfg.img, text = cfg.text, art = art }
  local tri = H.spawn(cfgTri, 'img', 'ConeTri', root)
  H.setSize(tri, c.w, Htri)
  H.setPos(tri, 0, coneTop - Htri / 2)
  pcall(function() tri.localRotationZ = 180 end)
  H.setColor(tri, cA[1], cA[2], cA[3], 255)

  -- ③ 握把
  local grip = H.spawn(cfg, 'img', 'ConeGrip', root)
  H.setSize(grip, c.gripW, c.gripH)
  H.setColor(grip, 47, 58, 82, 255)
  H.setPos(grip, 0, (gripTop + gripBot) / 2)

  -- ④ 筒口沿
  local mouth = H.spawn(cfg, 'img', 'ConeMouth', root)
  H.setSize(mouth, c.mouthW, c.mouthH)
  H.setColor(mouth, 242, 215, 166, 255)
  H.setPos(mouth, 0, (mouthTop + mouthBot) / 2)

  -- ⑤ 筒口内壁（深色；点火时更亮一档）
  local inner = H.spawn(cfg, 'img', 'ConeInner', root)
  H.setSize(inner, c.mouthW - 40, c.mouthH * 0.45)
  H.setColor(inner, opts.lit and 255 or 90, opts.lit and 138 or 58, opts.lit and 43 or 28, 255)
  H.setPos(inner, 0, (mouthTop + mouthBot) / 2)

  -- ⑥ 高光（左侧一条，让锥体有体积感）
  local shine = H.spawn(cfg, 'img', 'ConeShine', root)
  H.setSize(shine, 8, c.h * 0.72)
  H.setColor(shine, 255, 255, 255, 90)
  H.setPos(shine, -c.w * 0.22, coneTop - c.h * 0.42)

  return { root = root, mouth = mouth, inner = inner, grip = grip, shine = shine,
           tri = tri, mask = mask, mouthW = c.mouthW, mouthTopY = mouthTop }
end

-- ══════════════════════════════════════════════════════════
-- 六、火：DOOM 火焰算法（16×27 格 = 432 个方块）
--   核心三句：底部点火 → 每帧把热量**随机地**往上传播并衰减 → 每格按热量取纯色
--   "左右随机偏一格"就是火舌自己扭的原因；抛物线包络把它剪成上下尖的三角
-- ══════════════════════════════════════════════════════════
function P.fire(cfg, name, x, y, opts)
  opts = opts or {}
  local s = P.spec.fire
  local cols, rows = s.cols, s.rows
  local root = H.spawn(cfg, 'img', name or 'FireRoot')
  H.setSize(root, cols * s.cellW, rows * s.cellH)
  H.setPos(root, x or 0, y or 0)
  H.setColor(root, 0, 0, 0, 0)                  -- 容器透明

  -- 建 432 个格子（一次建好进池，运行期只改颜色）
  local cells = {}
  for r = 1, rows do
    for c = 1, cols do
      local cell = H.spawn(cfg, 'img', 'Fx' .. r .. '_' .. c, root)
      H.setSize(cell, s.cellW, s.cellH)
      -- 坐标：以容器中心为原点（左下角第一格）
      H.setPos(cell,
        (c - 0.5) * s.cellW - cols * s.cellW / 2,
        (rows - r + 0.5) * s.cellH - rows * s.cellH / 2)
      H.setColor(cell, 0, 0, 0, 0)
      cells[r * cols + c] = cell
    end
  end

  -- 热量表
  local heat = {}
  local halfPx = math.floor(cols / 2)
  local cx = (cols - 1) / 2
  local function halfAt(r)                       -- r: 1=顶 rows=底
    local t = (rows - r) / math.max(1, rows - 1) -- 0=底 1=顶
    -- ★ 用 `^` 而不是 math.pow：沙箱里**没有 math.pow**（Lua 5.3 起已移除该函数），踩过
    local h = halfPx * ((1 - t) ^ s.exponent)
    if h < 0.5 then h = 0.5 end
    return h
  end
  local function allowed(c, r)                   -- c 从 0 起
    return math.abs(c - cx) <= halfAt(r)
  end
  local function seed()
    for r = rows - s.sourceRows + 1, rows do
      for c = 0, cols - 1 do
        if allowed(c, r) then heat[r * cols + c + 1] = NLEV end
      end
    end
  end
  for i = 1, cols * rows do heat[i] = 1 end
  seed()

  local function stepFire()
    seed()
    for r = rows, 2, -1 do
      local up = r - 1
      for c = 0, cols - 1 do
        local v = heat[r * cols + c + 1]
        local idxUp = up * cols + c + 1
        if v <= 1 then heat[idxUp] = 1
        else
          local d = rnd(s.decayMax)
          local nx = c + rnd(3) - 1
          if nx < 0 then nx = 0 elseif nx >= cols then nx = cols - 1 end
          local tgt = up * cols + nx + 1
          if not allowed(nx, up) then
            heat[tgt] = 1                          -- 出包络就不给过 → 剪成三角
          else
            local nv = v - d
            if nv < 1 then nv = 1 end
            heat[tgt] = nv
          end
        end
      end
    end
  end

  local dirty = true
  local function drawFire()
    for r = 1, rows do
      for c = 1, cols do
        local v = heat[r * cols + c]
        local col = P.PAL[v] or P.PAL[1]
        H.setColor(cells[r * cols + c], col[1], col[2], col[3], col[4])
      end
    end
  end

  drawFire()
  return {
    root = root, cells = cells, heat = heat,
    step = stepFire, draw = drawFire,
    cols = cols, rows = rows, blockCount = cols * rows,
  }
end

return P
