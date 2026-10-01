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
    -- ★★ 2026-10-01 用户在网页原型上圈定：**口径 100 · 底径 69.2 · 杯高 198**（斜率 4.40°）
    --   即"更高更直的直筒杯"（原稿是 100 高 / 8.75°）。
    --   ★ 这三个是**主量**，斜率由它们推出（见 P.cupSlopeDeg）——
    --     反过来写（改杯高忘了改斜率）会得到一只形状不对的杯子。
    mouthW   = 100,         -- 杯口（上，宽）★ 主量
    baseW    = 69.2,        -- 杯底（下，窄）★ 主量（原来是"由 slopeDeg 推"，现在反过来）
    h        = 198,         -- 杯身高 ★ 主量
    slopeDeg = 4.45,        -- 由上面三个推出（198 高 ⇒ atan(15.4/198)=4.45°；测试断言它与主量一致）
    baseRimH = 2,           -- 杯底亮边高（0 = 不画）
    -- 三角方案的"尖端留白"补偿：千星三角图元转 180° 后，尖点比控件框**多伸一段**。
    --   P.cone 实测：三角高 ~194 时多伸 24 ⇒ 比例 0.1237。
    --   杯子这个三角高得多（口径 100/4.40° ⇒ 全锥高 650），留白是固定值还是按比例
    --   **只能真机标定**（模拟器不模拟图元留白）。标定前先用这个比例算，宁可盖多不盖少。
    tipPadRatio = 24 / 194,
    mode     = 'tri',       -- 'tri' = 三角形+遮挡（默认） / 'band' = 叠条（兜底，32 条）
    wTop     = 100,         -- 旧名，保留兼容；语义等同 mouthW
    inset    = 3,           -- 内壁相对外壁内缩
    lipH     = 8,           -- 杯口亮边高
    shineW   = 4,           -- 高光宽
  },
  -- 画布底色（遮挡块常用的"背后颜色"；道具挂在卡片上时要换成卡片色）
  MASK_CANVAS = { 10, 14, 24 },
  -- 柠檬锤尺寸（设计像素；与杯子同一套 ⇒ 相对大小由结构保证）
  --   锤头 62 / 杯口 100 = 62%：能进杯口，又不至于细得像筷子
  --   杆长 150：插到底（行程 210）时杆仍露在杯口外面
  hammer = { head = { w = 62, h = 16 }, stem = { w = 14, h = 150 }, gap = 22, plunge = 210 },
  cone = {
    -- ★ 2026-10-01 用户在网页原型上圈定（预设"火炬·细高"）：
    --   造型要求"更细、更陡、整体更小"，且整支点着后要像**火炬**（见 qilin 注释第 ⑤ 层）。
    --   锥面收进量 (w - tipW)/2/h = (104-6)/2/214 ≈ 0.229（旧炮管是 0.467，明显更"喇叭"）。
    w        = 104, h = 214,  -- 锥体（三角）顶宽 / 高
    mouthH   = 18,            -- 筒口高
    mouthW   = 120,           -- 筒口宽（比锥顶宽，形成"沿"）
    gripH    = 34,            -- 握把高
    gripW    = 84,            -- 握把宽
    tipW     = 6,             -- 锥尖宽（不是 0，免得看不见）→ 决定"盖住多少"
    maskTint = { 10, 14, 24 },-- 遮挡块颜色（≈画布底色；盖块靠"同色"假装不存在）
  },
  fire = {
    cols = 16, rows = 27,     -- 网格（用户选定）
    -- ★ 每格尺寸**不在这里写死**（2026-10-01 用户圈定）：格宽 = 筒口宽 / 列数，
    --   即"火的下部与火炬上部对齐、且火底宽正好等于筒口宽"。
    --   两个数分开写就会漂移（网页上圈的是 7.5×5.625 = 120/16 × 0.75），所以只留关系、不留数。
    aspect = 0.75,            -- 每格高 / 宽（4:3；字形不能单独拉伸，所以这是硬比例）
    sourceRows = 3,           -- 底部几行是火源
    decayMax = 3,             -- 每帧最大衰减
    exponent = 0.9,           -- 三角包络指数（越大越瘦）
  },
}

-- ★ 由"筒口宽"推出火焰格尺寸（唯一真相在这条式子里）
function P.fireCellW() return P.spec.cone.mouthW / P.spec.fire.cols end
function P.fireCellH() return P.fireCellW() * P.spec.fire.aspect end
function P.fireSize() return P.spec.fire.cols * P.fireCellW(), P.spec.fire.rows * P.fireCellH() end

-- ★ 对齐（2026-10-01 用户圈定）：火的**底边**要正好落在**筒口顶边**上。
--   传 P.cone 的返回值 + 火的根控件，返回"火根中心该放的 y"（画布坐标）。
--   为什么给函数而不是让调用者自己算：一共三个量（scale / mouthTopY / 火高），漏乘一个就错位。
function P.fireY(cone, fireRootH)
  local sc = cone.scale or 1
  return (cone.rootY or 0) + (cone.mouthTopY or 0) * sc + (fireRootH or 0) / 2
end


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
  if s.baseW then return s.baseW end                    -- ★ 主量优先
  return (s.wTop or s.mouthW) - 2 * P.slopeRun(s.h, s.slopeDeg or P.cupSlopeDeg(s))
end

-- ★ 斜率由三个主量推出（口径/底径/杯高）——改杯高忘了改斜率的坑就堵在这里
function P.cupSlopeDeg(s)
  s = s or P.spec.cup
  local run = ((s.mouthW or s.wTop) - P.cupBottomWidth(s)) / 2
  if run <= 0 or s.h <= 0 then return 0 end
  return math.atan(run / s.h) * 180 / math.pi
end

-- ══════════════════════════════════════════════════════════
-- 四-A、杯子：**叠条法**（兜底方案）逼近网页稿的梯形玻璃杯
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
function P.cupBands(cfg, name, x, y, drink)
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
-- 四-D、柠檬锤：**T 形 = 锤头（横，在下）+ 锤杆（竖，在上）两个方块**
--   ★ 方向：**锤头在下**（倒 T）—— 真正的捣锤就是这样；上一版我放在上面，用户报"放反了"。
--   ★ 尺寸以**杯子的设计像素**为准（锤头 62 能进 100 的杯口 = 62%，杆长 150 插到底还露在外面）：
--     两者用同一套设计像素、同一个缩放 ⇒ "大小匹配"是结构保证的，不靠记数字。
--   ★ 动作：**垂直下锤**（不是绕顶端摆）—— 捣锤本来就是这么用的，
--     顺带省掉"枢轴容器"（千星的旋转绕控件中心，想绕顶端转就得多挂一层）。
function P.lemonHammer(cfg, name, x, y, opts)
  opts = opts or {}
  local HM = P.spec.hammer
  local sc = opts.scale or 1
  local nm = name or 'Hammer'
  local root = H.spawn(cfg, 'img', nm .. 'Root')
  H.setSize(root, HM.head.w * sc, (HM.head.h + HM.stem.h) * sc)
  H.setPos(root, x or 0, y or 0)

  local head = H.spawn(cfg, 'img', nm .. 'Head', root)
  H.setSize(head, HM.head.w * sc, HM.head.h * sc)
  H.setPos(head, 0, -((HM.head.h + HM.stem.h) * sc) / 2 + HM.head.h * sc / 2)   -- 贴根的下沿
  H.setColor(head, 242, 226, 122, 255)                                          -- 柠檬黄

  local stem = H.spawn(cfg, 'img', nm .. 'Stem', root)
  H.setSize(stem, HM.stem.w * sc, HM.stem.h * sc)
  H.setPos(stem, 0, -((HM.head.h + HM.stem.h) * sc) / 2 + HM.head.h * sc + HM.stem.h * sc / 2)
  H.setColor(stem, 217, 199, 163, 255)                                          -- 浅木色

  -- 下锤：t 从 0 → 1 → 0（一个来回）。真机上由 view 在 OnUpdate 里推进。
  local baseY = y or 0
  local function plunge(t)
    t = math.max(0, math.min(1, t or 0))
    local d = HM.plunge * sc * math.sin(t * math.pi)      -- sin 曲线：下去再上来
    H.setPos(root, x or 0, baseY - d)
  end
  return { root = root, head = head, stem = stem, plunge = plunge, controls = { head, stem },
           headW = HM.head.w, stemH = HM.stem.h, scale = sc }
end

-- ══════════════════════════════════════════════════════════
-- 四-C、干冰：**真堆叠的冰堆 + 下沉的白雾 + 从下往上的结霜**（2026-10-01）
--
-- 玩法出处：干冰干柠檬水的第 2、3 步（柠檬锤连按 6+6 下，见 recipes.lua）。
-- 视觉来历（网页原型上验证过，这里搬进游戏）：
--   · **真堆叠**：`P.PILE` 11 块、5 层，**层高严格递增**、上层压在下一层的缝上、底宽顶窄。
--     千星和浏览器一样"**后画的盖住先画的**"（README 的 Z 序事实）⇒ 只要按层序 spawn，
--     上层自然压住下层，不需要任何层级参数。
--   · **雾往下淌**：干冰的白雾是冷而重的（CO₂ 比空气重）。TPT `CO2.cpp` 也是
--     `Gravity 0.1`（重气体往下沉）—— 上一版让雾往上飘，跟自己抄的来源都矛盾。
--   · **结霜从下往上依次铺开**（下层先结），不是一瞬间全白。
--
-- 物性参数**真从开源项目里拿的**（不是"参考一下"）：
--   · 雾  TPT `src/simulation/elements/FOG.cpp`：TYPE_GAS|PROP_LIFE_DEC、Loss 0.70、
--         Gravity 0、Diffusion 0.99 ⇒ 有寿命会散、会扩散
--   · 干冰 TPT `DRIC.cpp`：Weight 100（重 ⇒ 沉底）、Loss 0.00（不自散）、
--         HighTemperature 195.65K = -77.5℃ → PT_CO2（升华）
--   · CO₂ TPT `CO2.cpp`：LowTemperature 194.65K = **-78.5℃** → PT_DRIC（沉积成干冰）
--   · 同一温度 Sandboxels（开源）`carbon_dioxide: { tempLow: -78.5, stateLow: "dry_ice" }`
--     ⇒ **两个独立来源同一个数**
--   · 冰受压 TPT `ICEI.cpp`：HighPressure 0.8 → PT_SNOW（"Crushes under pressure"）
-- ══════════════════════════════════════════════════════════
P.SUBST = {
  -- 雾：dir = -1 表示**往下淌**（干冰雾）；lossTpt 是 TPT 原值（引用），
  -- fadePerSec 是**我们映射后的调参**（照搬 0.70/秒 会半路就散光）。两个数分开放。
  -- 白气用**碎絮**拼，不用大块（2026-10-01 用户："太廉价"）：
  --   几根大圆角色块 ⇒ 一眼就是"贴了几张卡片"。碎絮 = 小块 + 大小/旋角/速度/透明度都错开
  --   + 从**杯沿两侧**溢出 ⇒ 叠起来才有"一团"的感觉。千星只有扁平块 ⇒ 两边画法一致。
  -- 白气的**路径**（2026-10-01 用户："冒的位置不太对"）：干冰在杯底 ⇒ 雾先在**杯内**从冰上
  --   顶起来（被杯壁收着）→ 装满后**溢过杯沿**→ 再顺**杯壁外侧往下淌**（CO₂ 比空气重）。
  --   risePx 是"杯内上升"速度，**本项目调参**；dir/fallPx 只管"杯外下落"，来自 TPT。
  -- ★ 2026-10-01 用户：「我们要的应该是**飘动的雾气**」——搜 smoke/流体都搜偏了。
  --   飘动的关键是 **drift（左右漂移）**：sparticles 的文档写得很准——
  --   "每个粒子会左右漂移多少，产生**漂浮或被风吹**的效果"；再叠**视差分层**就有纵深。
  --   所以雾不是"直着往下掉"，而是**慢慢左右飘 + 缓缓下沉 + 悬停**。
  fog    = { dir = -1, risePx = 0.9, fallPx = 0.34, driftAmp = { 4, 14 }, driftHz = { 0.25, 0.55 },
             layers = 3, layerSpeed = { 1.0, 0.65, 0.4 }, layerAlpha = { 1.0, 0.7, 0.45 },
             layerSize = { 1.0, 0.8, 0.6 },
             -- ★ 双尺度：大而极淡的**晕** + 小而亮的**芯**。只用一种尺寸 ⇒ 一串珠子；
             --   两种叠起来才有"一团"的观感（粒子烟雾的常规做法）。
             haloEvery = 3, haloScale = 1.9, haloAlpha = 0.35, haloSpeed = 0.6,
             spreadPerSec = 0.5, fadePerSec = 0.30,
             lossTpt = 0.70, gravity = 0.1,
             -- ★ 2026-10-01 用户「冒的太少」⇒ 片数 14→30、尺寸放大、浓度提高，
             --   白气在杯沿**多停一会儿**（overSpeed 调慢）⇒ 杯口形成一层浓罩
             wisps = 30, wispW = { 14, 34 }, wispWMax = 44, wispH = { 10, 22 }, wispA = 0.62,
             overSpeed = 0.55, driftPx = { 0.06, 0.16 },
             -- ★ 2026-10-01：白气用**圆**（100002），不用方块 —— 方块再小也带棱角，
             --   圆形叠起来才像雾。片数不变，只是换了形状（浏览器侧用 border-radius:50%）。
             art = 100002,
             src = 'TPT FOG.cpp(Loss 0.70) + CO2.cpp(Gravity 0.1 重气体)' },
  bubble = { risePx = 0.8, src = 'TPT CO2.cpp（重气体）/ 液体浮力 ⇒ 速度为本项目调参' },
  dryice = { weight = 100, loss = 0, depositC = -78.5, sublimeC = -77.5,
             src = 'TPT DRIC.cpp + Sandboxels carbon_dioxide（两处 -78.5 一致）' },
  ice    = { crushPressure = 0.8, src = 'TPT ICEI.cpp' },
}

-- 冰堆布局：[x, y(相对杯底往上), w, h, rot]，**按层序**（底层在前 ⇒ 后画的上层压住下层）
P.PILE = {
  -- 第一层：铺满杯底（3 块，留缝）
  { -22,  3, 21, 12,  -8 }, { -1,  3, 22, 13,   5 }, { 20,  3, 20, 12,  13 },
  -- 第二层：压在缝上（2 块）
  { -12, 14, 21, 12,  -3 }, { 10, 14, 22, 12,   8 },
  -- 第三层（3 块）
  { -18, 25, 16, 11,  11 }, { -1, 25, 20, 12,  -6 }, { 15, 25, 15, 10,   7 },
  -- 第四层（2 块）
  {  -9, 35, 18, 11,   4 }, {  9, 35, 16, 10, -10 },
  -- 顶层：收尖
  {  -1, 44, 14,  9,   6 },
}

-- 基础图元号（README 第 4 条）：方块/圆/三角/四角星/五角星/圆环
P.ART = { square = 100001, circle = 100002, triangle = 100003, star4 = 100004, star5 = 100005, ring = 100006 }

-- 像素白气用的**字符**（2026-10-01 口径对齐：用户说的 ● 是**文字字符**，不是圆图元）
--   · 一个文本框里放一串 ● ⇒ **一行只占 1 个控件**（与火焰用 ■ 同一招，省开销）
--   · 用 ● 比 ░▒▓█ 更适合雾：**圆点本身就是"粒子"**
--   · 浓度不靠字形深浅，靠**点的疏密**（Bayer 有序抖动）⇒ 单字符也能表达渐变
--   · 空档必须用 **U+3000**（与 ●○ 等宽；普通空格会错位）
--
-- ★★ 源码里**不许出现非 ASCII 字节**（千星会转义 ⇒ 真机加载失败，README 记过这条）
--    ⇒ 字符一律用**字节**写：U+3000 = E3 80 80、U+25CF ● = E2 97 8F、U+25CB ○ = E2 97 8B
P.GLYPH = {
  space  = string.char(0xE3, 0x80, 0x80),   -- U+3000（空档）
  dot    = string.char(0xE2, 0x97, 0x8F),   -- U+25CF ●（密）
  ring   = string.char(0xE2, 0x97, 0x8B),   -- U+25CB ○（疏）
  square = string.char(0xE2, 0x96, 0xA0),   -- U+25A0 ■（火焰那套在用）
}
-- 抖动阈值（按**实测**定：密度 max 0.45 / 中位 0.044 / 90 分位 0.109）
P.DOT_TONE = { full = { 0.050, 0.050 }, half = { 0.012, 0.030 } }
-- 4×4 有序抖动矩阵（Bayer）
P.BAYER = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }

-- 密度 → 字符（与网页同一套规则）：两级抖动
function P.dotOf(v, i, j)
  local T = P.DOT_TONE
  if not v or v <= 0.001 then return P.GLYPH.space end
  local b = P.BAYER[((j or 0) % 4) * 4 + ((i or 0) % 4) + 1] / 16
  if v > T.full[1] + b * T.full[2] then return P.GLYPH.dot end
  if v > T.half[1] + b * T.half[2] then return P.GLYPH.ring end
  return P.GLYPH.space
end

-- 自带 LCG（千星禁 math.random ⇒ 随机也得自己造）
local lcg = 12345
local function rnd()
  lcg = (lcg * 1103515245 + 12345) % 2147483648
  return lcg / 2147483648
end

-- 建一堆干冰（挂在**杯子根**下 ⇒ 跟着杯子缩放/移动；晚于杯身 spawn ⇒ 压在杯身之上）
--   opts: { scale, frost = true, fog = true }
function P.dryice(cfg, name, cupRoot, opts)
  opts = opts or {}
  local S = P.spec.cup
  local sc = opts.scale or 1
  local hh = S.h
  local botY = -hh * sc / 2          -- 杯底（相对杯子根中心）
  local nm = name or 'DryIce'

  local chunks, frosts, fogs, pools = {}, {}, {}, {}
  local state = { t = 0, controlCount = 0 }

  -- ① 冰堆：**按层序** spawn ⇒ 后画的压住先画的
  for i, c in ipairs(P.PILE) do
    local el = H.spawn(cfg, 'img', nm .. 'Chunk' .. i, cupRoot)
    H.setSize(el, 0, 0); H.setPos(el, 0, 0)
    H.setColor(el, 244, 251, 255, 0)
    pcall(function() el.localRotationZ = c[5] end)
    chunks[i] = { el = el, x = c[1] * sc, y = c[2] * sc, w = c[3] * sc, h = c[4] * sc, rot = c[5], t = 0 }
  end
  -- 堆顶亮棱
  local topEl = H.spawn(cfg, 'img', nm .. 'Top', cupRoot)
  H.setSize(topEl, 0, 0); H.setPos(topEl, 0, 0); H.setColor(topEl, 255, 255, 255, 0)

  -- ② 杯壁结霜：3 层，从下往上（越往上越薄越淡），依次铺开
  if opts.frost ~= false then
    for w = 1, 3 do
      local el = H.spawn(cfg, 'img', nm .. 'Frost' .. w, cupRoot)
      H.setSize(el, 0, 0); H.setPos(el, 0, 0)
      H.setColor(el, 226, 240, 255, 0)
      frosts[w] = { el = el, y0 = botY + (6 + (w - 1) * 16) * sc, h = 15 * sc,
                    w = (S.baseW + 6 - (w - 1) * 3) * sc, a = 0.34 - (w - 1) * 0.07, t = 0 }
    end
  end

  -- ③ 雾瀑 + 雾滩：从杯口**往下淌**，边淌边铺开，按寿命淡出后在杯口重生
  if opts.fog ~= false then
    local cfgCirc = { root = cfg.root, img = cfg.img, text = cfg.text, art = (P.SUBST.fog.art or 100002) }
    -- 雾滩：杯子下面几片**扁的椭圆**（干冰雾沉到台面上），也是碎片拼的
    for pk = 1, 4 do
      local el = H.spawn(cfgCirc, 'img', nm .. 'Pool' .. pk, cupRoot)
      H.setSize(el, 0, 0); H.setPos(el, 0, 0)
      H.setColor(el, 233, 244, 255, 0)
      pools[pk] = { el = el, x = ({ -30, -4, 20, 34 })[pk] * sc, y = (-30 - (pk - 1) * 4) * sc,
                    w = ({ 70, 92, 64, 44 })[pk] * sc, h = ({ 11, 14, 10, 8 })[pk] * sc,
                    a = ({ 0.30, 0.22, 0.26, 0.20 })[pk] }
    end
    -- 白气碎絮：从杯沿**两侧**溢出，14 片
    local F = P.SUBST.fog
    for f = 1, F.wisps do
      local el = H.spawn(cfgCirc, 'img', nm .. 'Wisp' .. f, cupRoot)
      H.setSize(el, 0, 0); H.setPos(el, 0, 0)
      H.setColor(el, 236, 246, 255, 0)
      local side = (f % 2 == 0) and -1 or 1
      local layer = f % F.layers          -- ★ 视差分层：0=近（大/快/浓），2=远（小/慢/淡）
      local isHalo = (f % F.haloEvery == 0)   -- ★ 三分之一做"晕"（大、极淡、慢）
      local sc2 = (isHalo and F.haloScale or 1) * F.layerSize[layer + 1]
      local a2 = (isHalo and F.haloAlpha or 1) * F.layerAlpha[layer + 1]
      local v2 = (isHalo and F.haloSpeed or 1) * F.layerSpeed[layer + 1]
      local wi = {
        el = el, side = side, layer = layer, halo = isHalo, alphaMul = a2,
        w = (F.wispW[1] + rnd() * (F.wispW[2] - F.wispW[1])) * sc2 * sc,
        h = (F.wispH[1] + rnd() * (F.wispH[2] - F.wispH[1])) * sc2 * sc,
        rot = (rnd() - 0.5) * 26,
        -- 摆动（飘）：幅度/频率/初相各自不同 ⇒ 不会整齐划一地摆
        amp = (F.driftAmp[1] + rnd() * (F.driftAmp[2] - F.driftAmp[1])) * sc,
        hz = F.driftHz[1] + rnd() * (F.driftHz[2] - F.driftHz[1]),
        ph = rnd() * 6.2831853,
        baseX = 0,
        drift = side * (F.driftPx[1] + rnd() * (F.driftPx[2] - F.driftPx[1])) * v2 * sc,
        fall = F.fallPx * (0.75 + rnd() * 0.6) * v2 * sc,
        grow = (0.06 + rnd() * 0.10) * sc2 * sc,
        life = 1,
      }
      -- 初始把 14 片铺在整条路径上（三分之一已在杯外下落，其余在杯内沿高度铺开）
      if f % 4 == 0 then
        wi.phase = 'out'
        wi.x = side * (S.mouthW / 2 + 4 + rnd() * 20) * sc
        wi.y = (hh / 2 - 24 - rnd() * 34) * sc
      else
        wi.phase = 'in'
        local tt = 0.10 + (f / F.wisps) * 0.82
        wi.y = botY + tt * hh * sc
        wi.x = side * math.max(6, (S.baseW / 2 + (S.mouthW / 2 - S.baseW / 2) * tt - S.inset) - 6 - rnd() * 6) * sc
        wi.life = 0.35 + rnd() * 0.4
      end
      wi.baseX = wi.x                       -- 摆动绕这个位置（"飘"是绕着走，不是一路平移）
      pcall(function() wi.el.localRotationZ = wi.rot end)
      fogs[f] = wi
    end
  end

  local function update(dt)
    dt = dt or 0.033
    state.t = state.t + dt
    -- ① 冰堆逐块落下（每块间隔 0.06s，从上方 10px 掉进来）
    for i = 1, #chunks do
      local c = chunks[i]
      local want = (state.t - 0.05 - (i - 1) * 0.06) / 0.16
      if want < 0 then want = 0 elseif want > 1 then want = 1 end
      if want > c.t then
        c.t = want
        local drop = (1 - c.t) * 10 * sc
        H.setSize(c.el, c.w * c.t, c.h * c.t)
        H.setPos(c.el, c.x, botY + c.y + c.h / 2 - drop)
        H.setColor(c.el, 244, 251, 255, math.floor(math.min(1, c.t * 1.4) * 255))
      end
    end
    -- 堆顶亮棱（最上一块落够 60% 才亮）
    local top = chunks[#chunks]
    if top and top.t > 0.6 then
      H.setSize(topEl, top.w * 0.8, 3 * sc)
      H.setPos(topEl, top.x, botY + top.y + top.h - 1 * sc)
      H.setColor(topEl, 255, 255, 255, 255)
    end
    -- ② 结霜：下层先结、上层后结
    for w = 1, #frosts do
      local fr = frosts[w]
      if fr.t < 1 then
        fr.t = math.min(1, fr.t + dt * (1.2 - (w - 1) * 0.25))
        H.setSize(fr.el, fr.w, fr.h * fr.t)
        H.setPos(fr.el, 0, fr.y0 + fr.h / 2)
        H.setColor(fr.el, 226, 240, 255, math.floor(fr.a * fr.t * 255))
      end
    end
    -- ③ 白气碎絮：三段循环 —— 杯内上升 → 溢过杯沿 → 沿杯壁外侧下落
    local F = P.SUBST.fog
    for i = 1, #fogs do
      local fo = fogs[i]
      if fo.phase == 'in' then
        -- ① 杯内：从冰上往上顶，被杯壁收着（不许穿出内壁），逐渐显形
        fo.y = fo.y + F.risePx * dt * 60 * sc
        local tt = math.max(0, math.min(1, (fo.y - botY) / (hh * sc)))
        local lim = math.max(6, (S.baseW / 2 + (S.mouthW / 2 - S.baseW / 2) * tt - S.inset) - 6) * sc
        fo.baseX = fo.baseX + fo.drift * 0.25 * dt * 60
        fo.x = fo.baseX + math.sin(state.t * fo.hz * 6.2831853 + fo.ph) * fo.amp * 0.5   -- 杯里也在飘（幅度减半）
        if math.abs(fo.x) > lim then fo.x = (fo.x < 0 and -1 or 1) * lim; fo.baseX = fo.x end   -- ★ 被杯壁挡住
        fo.life = math.min(1, fo.life + dt * 1.6)
        if fo.y >= hh * sc / 2 - 5 * sc then                                     -- 装满了 ⇒ 溢过杯沿
          fo.phase = 'over'
          fo.y = hh * sc / 2 - 3 * sc
          fo.x = fo.side * (S.mouthW / 2 - 5) * sc
        end
      elseif fo.phase == 'over' then
        fo.y = fo.y + F.risePx * 0.25 * dt * 60 * sc
        fo.x = fo.x + fo.side * P.SUBST.fog.overSpeed * dt * 60 * sc   -- 慢 ⇒ 杯沿多停，形成浓罩
        if math.abs(fo.x) >= (S.mouthW / 2 + 6) * sc then fo.phase = 'out' end
      else
        -- ③ 杯外：**飘**（左右慢摆 = "飘动的雾气"的核心）+ 缓缓下沉 + 边散边转
        fo.y = fo.y + F.dir * fo.fall * dt * 60
        fo.baseX = fo.baseX + fo.drift * dt * 60                                  -- 整体慢慢漂（风）
        fo.x = fo.baseX + math.sin(state.t * fo.hz * 6.2831853 + fo.ph) * fo.amp   -- ★ 左右摆动
        local wCap = F.wispWMax * (fo.halo and F.haloScale or 1)                     -- 晕可以更大
        if fo.w < wCap then fo.w = math.min(wCap, fo.w + fo.grow * dt * 60) end
        fo.rot = fo.rot + math.sin(state.t * fo.hz * 2 + fo.ph) * 0.6 * dt * 60
        fo.life = fo.life - F.fadePerSec * dt * (1 - (fo.layer or 0) * 0.15)
        if fo.life <= 0 or fo.y < botY - 40 * sc then
          -- 回杯底重新来一遍（side 不变，看的人不会觉得"突然换边"）
          local side = fo.side
          -- ★ 重生时必须**重新套用"晕/芯"与分层缩放**：我第一版漏了，
          --   晕重生一次就退化成芯的尺寸（测试里"晕更大"的均值变成 33 vs 33 才发现）
          local rsc = (fo.halo and F.haloScale or 1) * F.layerSize[(fo.layer or 0) + 1]
          fo.phase = 'in'
          fo.y = botY + (0.10 + rnd() * 0.8) * hh * sc
          fo.x = side * math.max(6, (S.baseW / 2 - S.inset) - 6) * sc
          fo.w = (F.wispW[1] + rnd() * (F.wispW[2] - F.wispW[1])) * rsc * sc
          fo.h = (F.wispH[1] + rnd() * (F.wispH[2] - F.wispH[1])) * rsc * sc
          fo.rot = (rnd() - 0.5) * 26
          fo.drift = side * (F.driftPx[1] + rnd() * (F.driftPx[2] - F.driftPx[1])) * sc
          fo.fall = F.fallPx * (0.75 + rnd() * 0.6) * sc
          fo.grow = (0.06 + rnd() * 0.10) * rsc * sc
          fo.life = 0.35
          pcall(function() fo.el.localRotationZ = fo.rot end)
        end
      end
      H.setSize(fo.el, fo.w, fo.h)
      H.setPos(fo.el, fo.x, fo.y)
      -- 杯内的白气隔着杯壁看 ⇒ 再虚一档
      local alpha = fo.life * F.wispA * (fo.phase == 'in' and 0.7 or 1) * (fo.alphaMul or F.layerAlpha[(fo.layer or 0) + 1])
      H.setColor(fo.el, 236, 246, 255, math.floor(math.max(0, math.min(1, alpha)) * 255))
    end
    -- 雾滩：几片扁的，随冰堆一起显形
    local pt = math.min(1, state.t / 1.0)
    for pk = 1, #pools do
      local pf = pools[pk]
      H.setSize(pf.el, pf.w, pf.h)
      H.setPos(pf.el, pf.x, botY + pf.y)
      H.setColor(pf.el, 233, 244, 255, math.floor(pf.a * pt * 255))
    end
  end

  state.controlCount = #chunks + 1 + #frosts + #fogs + #pools   -- 冰堆 + 顶棱 + 壁霜 + 雾碎絮 + 雾滩
  local controls = {}
  for i = 1, #chunks do controls[#controls + 1] = chunks[i].el end
  controls[#controls + 1] = topEl
  for w = 1, #frosts do controls[#controls + 1] = frosts[w].el end
  for i = 1, #fogs do controls[#controls + 1] = fogs[i].el end
  for pk = 1, #pools do controls[#controls + 1] = pools[pk].el end

  return { update = update, controls = controls, chunks = chunks, frosts = frosts, fogs = fogs, pools = pools,
           art = (P.SUBST.fog.art or 100002),
           state = state, botY = botY, scale = sc }
end

-- ══════════════════════════════════════════════════════════
-- 四-B、杯子：**三角形 + 遮挡**（默认方案；2026-10-01）
--
-- 方案出处（都在本仓，别再从头试一遍）：
--   · `lua/src/clip_test.lua`   —— 前置实测：① 父控件**不裁**子控件（实测读回 600×600）
--                                    ⇒ 只能遮挡；② 遮挡块靠**背景色**，只在纯色背景成立。
--   · `lua/src/cup_tri_demo.lua` —— 电脑端的探索版（思路对，但**几何算错了**：
--                                    它写 `Htri = hh/ratio`，正确是 `hh/(1-ratio)`，
--                                    实测"距顶 100px 处宽 38.8"（杯子要求 69.2），
--                                    而且遮挡块只比尖点高 1px ⇒ 等于没盖住）。
--   这里用的是**验证过的几何**（网页原型上逐点比对叠条法，偏差 0.000px）：
--     三角顶宽 = 口径，尖点在杯底之下；液体的三角上沿放在**液面**，尖点同样由遮挡盖住。
--
-- 控件数：外锥 + 液锥 + 遮挡 + 液面线 + 杯口 + 高光 + 杯底亮边 + 根 = 8（叠条法是 52）
--
-- ★ 三条实现铁律（踩过）：
--   ① 出三角形必须走 `cfg.art`（H.spawn 内部 SetImage(StaticReference, art)）；
--      在脚本里直接 tri:SetImage(...) 沙箱不生效 → 画出来全是方块。
--   ② 三角图元默认**顶点在上** ⇒ 杯子要"宽上窄下"，必须 `localRotationZ = 180`。
--   ③ 图元转 180° 后尖点比控件框**多伸一段**（P.cone 实测 24/194）⇒ 遮挡块要按
--      `tipPadRatio` 多盖一截，否则杯子底下会露出一个小尖。
-- ══════════════════════════════════════════════════════════
function P.cupTri(cfg, name, x, y, drink, opts)
  opts = opts or {}
  -- ★ maskColor **必传**：遮挡块颜色 = 杯子背后的颜色。平台不裁子控件，只能同色遮挡；
  --   给错颜色就会在杯子下方露出一块异色（用户真机上报过"杯子下方被挡住"）。
  if not opts.maskColor then
    error('P.cupTri 需要 opts.maskColor（遮挡块颜色 = 杯子背后的颜色；画布上用 P.spec.MASK_CANVAS）')
  end
  local s = P.spec.cup
  local mouthW, baseW, hh = s.mouthW, P.cupBottomWidth(s), s.h
  local tanA = (mouthW - baseW) / 2 / hh
  local sc = opts.scale or 1
  local nm = name or 'Cup'
  drink = drink or P.drink.water
  local mc = opts.maskColor

  local root = H.spawn(cfg, 'img', nm .. 'Root')
  H.setSize(root, mouthW * sc, hh * sc)
  H.setPos(root, x or 0, y or 0)
  local topY, botY = hh * sc / 2, -hh * sc / 2

  -- ① 外锥：顶宽 = 口径，上沿贴杯口，尖点在杯底之下很远
  local Hfull = (mouthW / 2) / tanA * sc
  local tri = H.spawn(cfg, 'img', nm .. 'BodyTri', root)
  H.setSize(tri, mouthW * sc, Hfull)
  H.setPos(tri, 0, topY - Hfull / 2)
  pcall(function() tri.localRotationZ = 180 end)
  H.setColor(tri, 224, 240, 255, 110)

  -- ② 液锥（上沿放在液面、宽 = 该处内壁宽；尖点同样在杯底之下）
  local liq = H.spawn(cfg, 'img', nm .. 'LiqTri', root)
  H.setSize(liq, 0, 0); H.setPos(liq, 0, 0)
  H.setColor(liq, drink[1], drink[2], drink[3], 240)

  -- ③ 液面亮线（水平）
  local liqTop = H.spawn(cfg, 'img', nm .. 'LiqTop', root)
  H.setSize(liqTop, 0, 0); H.setPos(liqTop, 0, 0)
  H.setColor(liqTop, 255, 255, 255, 130)

  -- ④ 遮挡块：盖住"杯底以下"那一截（含图元留白）
  local tipPad = s.tipPadRatio * Hfull
  local maskH = (baseW / 2) / tanA * sc + tipPad + 8
  local mask = H.spawn(cfg, 'img', nm .. 'Mask', root)
  H.setSize(mask, (baseW + 4) * sc, maskH)
  H.setPos(mask, 0, botY + 0.6 - maskH / 2)          -- 上沿压在杯底线上（+0.6 防缝）
  H.setColor(mask, mc[1], mc[2], mc[3], mc[4] or 255)

  -- ⑤ 杯口亮边（实色；杯口看着像玻璃口，不靠半透明）
  local lip = H.spawn(cfg, 'img', nm .. 'Lip', root)
  H.setSize(lip, (mouthW + 4) * sc, s.lipH * sc)
  H.setPos(lip, 0, topY - s.lipH * sc / 2)
  H.setColor(lip, 234, 243, 255, 255)

  -- ⑥ 左侧竖直高光（竖直块，不用旋转斜条 —— 旋转斜条贴不上叠条/三角的边）
  local shine = H.spawn(cfg, 'img', nm .. 'Shine', root)
  H.setSize(shine, s.shineW * sc, hh * 0.82 * sc)
  H.setPos(shine, -(mouthW / 2 - s.inset - s.shineW - 6) * sc, 0)
  H.setColor(shine, 255, 255, 255, 130)

  -- ⑦ 杯底亮边（可选件；把"遮挡的切边"变成一条设计好的边）
  local base = nil
  if s.baseRimH and s.baseRimH > 0 then
    base = H.spawn(cfg, 'img', nm .. 'Base', root)
    -- 比杯底窄 2px、下沿正好压在底线上（宽了会两边凸出，高了会飘在半空）
    H.setSize(base, (baseW - 2) * sc, s.baseRimH * sc)
    H.setPos(base, 0, botY + s.baseRimH * sc / 2)
    H.setColor(base, 207, 224, 245, 255)             -- 实色（半透明压在玻璃/液体上会糊）
  end

  local function halfInnerAt(t)
    local hOut = baseW / 2 + (mouthW / 2 - baseW / 2) * t
    return hOut - s.inset
  end
  local function setFill(frac)
    frac = math.max(0, math.min(1, frac or 0))
    local surfY = botY + frac * hh * sc
    if frac <= 0.002 then
      H.setSize(liq, 0, 0); H.setPos(liq, 0, 0)
      H.setSize(liqTop, 0, 0); H.setPos(liqTop, 0, 0)
    else
      local half = halfInnerAt(frac)
      local w = half * 2 * sc
      local hL = half / tanA * sc                     -- 内侧与外侧平行 ⇒ 斜率相同
      H.setSize(liq, w, hL)
      H.setPos(liq, 0, surfY - hL / 2)
      H.setSize(liqTop, w, 2)
      H.setPos(liqTop, 0, surfY)
    end
  end
  setFill(0)

  return {
    root = root, setFill = setFill, tri = tri, liq = liq, liqTop = liqTop,
    mask = mask, lip = lip, shine = shine, base = base,
    controls = { tri, liq, liqTop, mask, lip, shine, base },
    mouthW = mouthW, baseW = baseW, mode = 'tri',
    geo = { h = hh, mouth = mouthW, base = baseW, inset = s.inset,
            slopeDeg = P.cupSlopeDeg(s), triH = Hfull, tipPad = tipPad },
  }
end

-- ★ 对外入口：默认走三角方案；`opts.mode = 'band'` 回退到叠条（兜底/对照用）
function P.cup(cfg, name, x, y, drink, opts)
  opts = opts or {}
  if (opts.mode or P.spec.cup.mode) == 'band' then
    return P.cupBands(cfg, name, x, y, drink)
  end
  return P.cupTri(cfg, name, x, y, drink, opts)
end

-- ══════════════════════════════════════════════════════════
-- 五、炮筒：锥体 = **一个三角形（转 180°）**，尖头收钝只用一个不大的盖块

--   ★ 它**既是枪筒，也是甜筒**（cone 的双关；见 雪皇的后厨.html 里 qilin 那条注释）：
--     ★ 出餐交付的就是**这支冒火的枪筒本身**（枪筒=甜筒=这道产品；不是另装一杯）。
--     ★★ 造型还要往**火炬**靠（2026-10-01 用户明确）：更细、更陡、整体更小，别做成粗短炮管。
--        "火炬"不只是形容，它自己又开了一串 neta：现实里的火炬冰淇淋 / 奥运火炬传递 /
--        《火炬之光》Torchwood 之类 —— 详见 雪皇的后厨.html 里 qilin 注释的第 ⑤ 条。
--        ⚠️ 具体尺寸待用户从 preview/手机按键-微量测试.html 第 ③-b 节的 4 档里圈定后写回 P.spec.cone。--       演出：枪筒冒火 → 整支带火递给客人（serveNow，一步到位，没有打包台）。--     产品「白芝麻火麒麟」同时恶搞冰淇淋（黑芝麻冰麒麟）与 neta 名枪（火麒麟），
--     所以这道工序是"掏出枪筒 → 用喷火枪烤"，做完直出（serveNow）。
--     画它的时候别只画成"一根枪管"：它同时是那支要被烤的甜筒。--
-- ★ 三角朝向（实测，见 preview/design/prims.png）：
--   三角形图元**顶点在上、底边在下**；转 180° 才是尖朝下。
-- ★ 这一版和"12 层叠条"的区别：控件 12 → 2，边缘是真三角形（不是台阶）。
-- ★ 盖块尺寸怎么来的（关键，别再用错的算法）：
--   要"露出 182 高、底宽 10" ⇒ 不能按 顶宽/底宽 直接放大三角（那会得到 2912 高的怪物）。
--   正确做法：**盖块很小**，只压住尖头最后那一小段。
--     三角总高 Htri = h / (1 - tipW/w)   ← 注意分母是 1 减去"宽度比"，不是宽度比本身
--   （我上一版把公式写成 h × w/tipW，直接把三角放大 16 倍 —— 那才是"一根竖条"的原因。）
-- ══════════════════════════════════════════════════════════
-- ★ 等比缩放（2026-10-01）：把"已经建好的零件"统一乘一个比例。
--   为什么不把比例乘进规格数字：P.spec 是与 preview/design/*.html **对齐的唯一真相**，
--   乘进去以后就再也对不上设计稿了。缩放只发生在"落地那一刻"。
function P.scaleParts(controls, sc)
  for _, ctl in ipairs(controls) do
    pcall(function()
      local x, y = ctl.anchoredPositionX or 0, ctl.anchoredPositionY or 0
      local w, h = ctl.sizeDeltaX or 0, ctl.sizeDeltaY or 0
      H.setPos(ctl, x * sc, y * sc)
      H.setSize(ctl, w * sc, h * sc)
    end)
  end
end

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
  -- ★ 遮挡块颜色（opts.maskColor）：默认是画布底色；**落在彩色卡片上时必须传卡片色**，
  --   否则"假装不存在"的遮挡块会显出一块深色方块（放在卡片上的第一眼瑕疵就是这个）。
  local mc = opts.maskColor or c.maskTint
  H.setColor(mask, mc[1], mc[2], mc[3], mc[4] or 255)

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

  -- ★ 等比缩放：opts.scale 直接给比例，或 opts.fitH 给"目标总高"（界面里更常用）
  local sc = opts.scale or (opts.fitH and (opts.fitH / rootH)) or 1
  if sc ~= 1 then
    H.setSize(root, c.mouthW * sc, rootH * sc)
    P.scaleParts({ mask, tri, grip, mouth, inner, shine }, sc)
  end

  return { root = root, mouth = mouth, inner = inner, grip = grip, shine = shine,
           tri = tri, mask = mask, mouthW = c.mouthW, mouthTopY = mouthTop,
           nativeW = c.mouthW, nativeH = rootH, scale = sc, rootY = y or 0 }
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
  local cw, ch = P.fireCellW(), P.fireCellH()      -- ★ 由筒口宽推导（见 P.fireCellW）
  H.setSize(root, cols * cw, rows * ch)
  H.setPos(root, x or 0, y or 0)
  H.setColor(root, 0, 0, 0, 0)                  -- 容器透明

  -- 建 432 个格子（一次建好进池，运行期只改颜色）
  local cells = {}
  for r = 1, rows do
    for c = 1, cols do
      local cell = H.spawn(cfg, 'img', 'Fx' .. r .. '_' .. c, root)
      H.setSize(cell, cw, ch)
      -- 坐标：以容器中心为原点（左下角第一格）
      H.setPos(cell,
        (c - 0.5) * cw - cols * cw / 2,
        (rows - r + 0.5) * ch - rows * ch / 2)
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

  -- ★ 等比缩放（opts.scale）：与 P.cone 用**同一个 scale** 才能保持"火宽 = 筒口宽"。
  --   注意是 432 个格子，只在这里跑一次（运行期不再动尺寸）。
  local sc = opts.scale or 1
  if sc ~= 1 then
    H.setSize(root, cols * cw * sc, rows * ch * sc)
    P.scaleParts(cells, sc)
  end

  drawFire()
  return {
    root = root, cells = cells, heat = heat,
    step = stepFire, draw = drawFire,
    cols = cols, rows = rows, blockCount = cols * rows,
    scale = sc, w = cols * cw * sc, h = rows * ch * sc,
  }
end

-- ══════════════════════════════════════════════════════════
-- 七、★ 一次把"火炬 + 火"建好并**对齐**（推荐入口）
--   用户 2026-10-01 圈定的关系：**火的下部与火炬上部对齐**（火底边 = 筒口顶边），
--   且 **火宽 = 筒口宽**（同一 scale 下自然成立）。
--   为什么不把这三件事留给调用者：要乘的 scale 有三个地方（筒口顶边 / 火高 / 火宽），
--   漏乘一个就错位，而且错位了"看起来只是有点歪"，很难查 —— 所以收成一个入口。
--   返回 { cone=…, fire=…, scale=…, mouthTopY=…, fireBottomY=… }，便于断言与调试。
function P.torchWithFire(cfg, name, x, y, opts)
  opts = opts or {}
  local sc = opts.scale or 1
  name = name or 'Torch'
  local cone = P.cone(cfg, name .. 'Torch', x, y, opts)
  local fireH = P.spec.fire.rows * P.fireCellH() * sc
  local fireY = P.fireY(cone, fireH)                       -- 火根中心 y（底边贴筒口顶边）
  local fire = P.fire(cfg, name .. 'Fire', x, fireY, { scale = sc })
  return {
    cone = cone, fire = fire, scale = sc,
    mouthTopY = (y or 0) + (cone.mouthTopY or 0) * sc,
    fireBottomY = fireY - fireH / 2,
    fireH = fireH,
  }
end

return P
