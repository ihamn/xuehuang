-- skin.lua —— 视觉层（唯一数值源）
--
-- ★★ 为什么单独一层：之前每加一个界面就随手写数（框高 34、字号 24、位置 -320…），
--   结果反复出现"字被裁""色块像塑料""间距不齐"，换风格要改十几个地方。
--   现在**所有尺寸/颜色/字号/间距/图标号只写在这里**（配套：雪皇-视觉规范.md），
--   `view.lua` 只负责"哪个数据放哪个位置"，不许出现魔法数字。
--
-- ★★ 视觉规则（用户逐轮定的，改动前先读）：
--   ① 有**整屏黑色打底**，UI 压在其上（不是"UI 直接压在游戏画面上"）
--   ② 按钮要**撑满可用空间**（左区 1391 / 纵向用到 824），不留大片空白
--   ③ 字号要**内敛**：不靠粗体、不靠透明度差拉层次
--   ④ **步骤**（该做什么）比**区域名**略大一档：step 28 > title 26
--   ⑤ 工位卡 = 【名称行 + 图标列】保留原色；**其余内容区加底衬**（方案 A）
--      底衬 = 卡片原色 **提亮 +40**（"浅半档"）—— ⚠️ 是**提亮**，不是压暗（压暗是我理解反了）
--      内容区与名称行之间有一条 **2px 半透明白分隔线**；底衬**固定铺满**，不跟字数伸缩
--      底衬底边**上收 radius(14)**，否则直角会切掉卡片圆角（实测出现过）

local H = require('host')

local SK = {}

-- ══════════════════════════════════════════════════════════
-- 一、数值标记（唯一来源）
-- ══════════════════════════════════════════════════════════
SK.T = {
  -- 基准（真机画布 1815×900，≈2.02:1）
  designW = 1815, designH = 900,
  safe = 24,
  gap = { xs = 4, s = 8, m = 16, l = 24, xl = 32 },

  -- 字号阶梯（框高必须 >= 字号 × 1.6，否则字被裁 —— layout-lint 会查）
  font = { display = 32, step = 28, title = 26, head = 20, body = 16, small = 13, tiny = 11 },

  -- 控件尺寸
  --   横向 24 + 左列 380 + 16 + 中列 1032 + 16 + 右列 388 + 24 = 1880（= 真机画布宽）
  --   纵向 24 + 72 + 26 + 208 + 26 + 208 + 26 + 176 + 24 = 790
  size = {
    stationW = 508, stationH = 208,     -- 中列 2×2（1032 = 508*2 + 16）
    -- 打包台 168（原为 176）：留一点纵向余量，底部不再放别的行
    packW = 1032, packH = 168,
    -- 左列
    colLW = 380, orderW = 348, orderH = 104,
    dataW = 380, dataH = 190,
    -- 右列
    colRW = 388, bookW = 388, bookH = 470, keysW = 388, keysH = 300,
    hudW = 1832, hudH = 72,
    panelW = 380, panelH = 560,
    iconS = 22, iconL = 30, iconBig = 80, iconMid = 64,
    barH = 8, edgeW = 6,
    nameRowH = 72,
    pad = 12,
    radius = 14,
    dividerH = 2,
  },

  -- 版式位置（设计坐标：原点在画布中心，y 向上）
  --   横向 24 + 1391 + 24 + 352 + 24 = 1815（正好填满真机画布宽）
  --   纵向 24 + 72 + 32 + 208 + 32 + 208 + 32 + 192 + 24 = 824
  at = {
    leftW = 1367,
    gapLR = 48,                                       -- 左区与订单面板之间的间隙
    leftX = -(1815 / 2) + 24 + 1367 / 2,              -- 左区中心 = -200
    -- ★ 左区左边缘 = 左区中心 - 左区宽/2
    --   ⚠️ 我第一版写成 `-((1815/2) - 24 - 1391)` = **507.5**（少减半个左区宽、符号也错）
    --      → 所有"相对左边缘"的控件整体右移 → 全跑到画布外。是 layout-lint 抓出来的。
    leftL = -(1815 / 2) + 24,

    hudY = 450 - 24 - 72 / 2,                        -- 354
    hudPad = 24,
    -- HUD 内部（相对左区左边缘）
    hudIconX = 30, hudTitleX = 54,
    hudClockX = 300, hudClockW = 180,
    -- 三项数据：图标 22 + 数字 46 + 说明 70 = 138，间距 190（不重叠）
    hudStatX = 544, hudStatGap = 190,
    hudTipW = 200, hudTipR = 28,

    panelL = (1815 / 2) - 24 - 352,                  -- 面板左边缘 528.5（设计坐标）
    panelY = 450 - 24 - 72 - 32 - (736 / 2),         -- 面板中心 y = -14
    panelHeadY = 736 / 2 - 36,                       -- 相对面板中心

    -- 订单卡（相对面板中心）
    orderTop = (736 / 2) - 64,                       -- 第一张卡的中心 y
    orderStep = 136 + 16,                            -- 卡高 + 间距
    orderInX = 16,                                   -- 卡内左内边距

    stationX = -(1815 / 2) + 24 + 672 / 2,
    stationX2 = -(1815 / 2) + 24 + 1367 - 672 / 2,
    stationY = 220, stationY2 = 220 - 208 - 32,
    packX = -(1815 / 2) + 24 + 1367 / 2,
    packY = 220 - 208 - 32 - 208 - 32 - 192 / 2,
  },

  -- 配色
  color = {
    shake = { 58, 122, 220 }, fire = { 232, 126, 52 },
    chem = { 158, 106, 224 }, brew = { 52, 176, 128 }, pack = { 40, 192, 176 },

    hudBg = { 14, 17, 26, 246 }, panelBg = { 24, 29, 46, 247 },
    cardBg = { 35, 43, 66 }, slotBg = { 18, 21, 31 },

    text = { 238, 243, 252 }, dim = { 176, 190, 216 }, gold = { 255, 214, 130 },
    good = { 122, 232, 160 }, warn = { 255, 196, 96 }, bad = { 255, 122, 132 },
    onColor = { 255, 255, 255 },
  },

  -- 图标素材号
  --   ★ 工位图标（用户逐个在编辑器素材库里找出来的，2026-09-27 定稿）
  --     素材库里**没有**雪克杯/烧瓶/量筒/茶壶这类"工具"图标，所以按**语义**选：
  icon = {
    -- 工位
    shake = 102004,   -- 冰元素 → 捣锤区（这区做的正是干冰："压缩至出现固态干冰"）
    fire  = 102002,   -- 火元素 → 火系区（喷火枪烤甜筒）
    chem  = 102015,   -- 护盾+雷 → 化学区（没有烧瓶/量筒，用雷元素顶上；"别的真没了"）
    brew  = 102041,   -- 壶/罐 → 萃茶区（泡茶/滤咖啡）；备选 102027（像咖啡滤网）
    pack  = 102028,   -- 装箱 → 打包台（封杯出餐）

    -- 通用功能
    ok = 100102, no = 100101, next = 100103, prev = 100104, back = 100109,
    plus = 100107, minus = 100108, info = 100115, ask = 100113, warn = 100122,
    play = 100181, pin = 100131, lock = 100132,
  },

  -- 底衬深度（规则 ⑤）：卡片原色 **提亮** 这个量。40 = "浅半档"
  --   ⚠️ 这是**加法提亮**，不是乘法压暗 —— 我曾在方向上搞反，用户明确指出"是低半档"。
  chipLift = 40,
  chipAlpha = 255,
  dividerCol = { 255, 255, 255, 51 },   -- 分隔线（半透明白 ~20%）
}

local T = SK.T

-- ══════════════════════════════════════════════════════════
-- ★★ 画布自适应（踩过大坑，务必看清）
--   问题：编辑器里那个「客户端控件容器」的锚点是 Min(0,0)/Max(1,1) → **跟着设备拉伸**，
--         而设备预设有一堆（16:9 / 21:9 / 19.5:9 / 4:3 …），宽高都不同。
--         我原来把坐标全按"画布中心 + 写死 1815 宽"算 →
--         ① 换设备整块 UI 左右漂移（用户截图：左边露黑边）
--         ② 宽画布上订单面板被挤出去，和工位卡重叠
--   做法：
--     · **尺寸只按高度缩放**（元件保持像素大小，不跟着宽度变胖）
--     · **左右分区各自锚边**：左区贴左边距、订单面板贴右边距 → 中间自动留空档
--       （宽画布多出来的空间落在中间，不会挤到面板，也不会溢出被切）
--   ⚠️ 只做一次（幂等），否则每帧乘一次会越缩越小。
function SK.fitCanvas(canvasW, canvasH)
  if SK._fitted then return SK._scale end
  local cw = tonumber(canvasW) or T.designW
  local ch = tonumber(canvasH) or T.designH
  if cw < 8 then cw = T.designW end
  if ch < 8 then ch = T.designH end
  SK._fitted = true
  SK._canvasW, SK._canvasH = cw, ch

  -- ① 尺寸与字号：**只按高度**缩放
  local s = ch / T.designH
  if s <= 0 then s = 1 end
  SK._scale = s
  local function scale(t)
    for k, val in pairs(t) do
      if type(val) == 'number' then t[k] = val * s
      elseif type(val) == 'table' then scale(val) end
    end
  end
  scale(T.size)
  scale(T.gap)
  for k, fsz in pairs(T.font) do
    local v = math.floor(fsz * s + 0.5)
    if v < 10 then v = 10 end
    T.font[k] = v
  end

  -- ② 位置：**按实际画布重算 —— 三列布局**（还原原版：左=等候区+营业数据 / 中=工位 / 右=产品手册+快捷键）
  --   横向：24 + 左列 380 + 间隙 16 + 中列 1032 + 间隙 16 + 右列 388 + 24 = 1880
  local m  = T.safe * (ch / T.designH)      -- 边距（按高度缩放）
  local gp = 16 * (ch / T.designH)          -- 列间隙
  local colLW = T.size.colLW
  local colRW = T.size.colRW
  local colL = -cw / 2 + m                            -- 左列左边缘（贴左）
  local colR = cw / 2 - m                             -- 右列右边缘（贴右）
  -- 中列 = 剩下的宽度（画布越宽，中列越宽）
  local midW = (colR - colRW - gp) - (colL + colLW + gp)
  if midW < 400 then midW = 400 end                    -- 画布太窄时保底
  -- 工位卡宽 = (中列 - 列间隙)/2
  local cardW = (midW - gp) / 2
  local cardH = T.size.stationH
  T.size.stationW = cardW
  T.size.packW    = midW
  T.size.hudW     = cw - 2 * m                       -- HUD 条：横跨三列，两侧留边距
  T.size.orderW   = colLW - 2 * gp
  T.size.orderH   = T.size.orderH
  T.size.panelW   = colRW

  local A = T.at
  -- 三列的中心 x
  A.colLC = colL + colLW / 2
  A.colRC = colR - colRW / 2
  A.midC  = colL + colLW + gp + midW / 2
  A.colLL = colL
  A.colRL = colR - colRW
  A.panelX = A.colLC
  A.midL  = colL + colLW + gp
  A.midW  = midW
  A.colLW = colLW
  A.colRW = colRW
  -- （小票行的几何已随"小票不参与操作"一起删除，见 view.lua 5.5 节的说明）
  -- 纵向：HUD 贴顶 → 中列 2×2 工位 → 打包台
  A.hudX      = 0                                    -- HUD 居中（宽度已扣边距）
  A.hudY      = ch / 2 - m - T.size.hudH / 2
  local topY  = A.hudY - T.size.hudH / 2 - 26 * (ch / T.designH)   -- 第一行工位中心
  A.stationY  = topY - cardH / 2        -- 第一行工位中心
  A.stationY2 = A.stationY - cardH - gp -- 第二行工位中心
  A.packY     = A.stationY2 - cardH / 2 - gp - T.size.packH / 2
  A.stationX  = A.midL + cardW / 2
  A.stationX2 = A.midL + midW - cardW / 2
  A.packX     = A.midC
  -- 左列：等候区（贴列顶）+ 营业数据（在它下面）
  A.orderTop  = A.hudY - T.size.hudH / 2 - 26 * (ch / T.designH) - T.size.orderH / 2 - 30
  A.orderStep = T.size.orderH + 8 * (ch / T.designH)
  A.panelL    = A.colLL
  A.panelY    = A.orderTop - 5 * A.orderStep / 2 - 30               -- 等候区面板中心
  A.panelHeadY = 24 * (ch / T.designH)
  -- 左列两块：**从上往下顺序堆叠**（不再互相推导，避免任一处改动就伸出屏幕）
  --   内容顶 = HUD 底边 - 间隙；等候区紧贴其下；营业数据再接在等候区下面
  local contentTop = A.hudY - T.size.hudH / 2 - 26 * (ch / T.designH)
  A.panelY = contentTop - T.size.panelH / 2                      -- 等候区面板中心
  A.dataY  = contentTop - T.size.panelH - gp - T.size.dataH / 2  -- 营业数据面板中心
  -- 订单卡：第 1 张贴着面板顶（留出头高 56），往下排
  A.orderTop  = T.size.panelH / 2 - 56 - T.size.orderH / 2
  A.orderStep = T.size.orderH + 8 * (ch / T.designH)

  -- 右列：产品手册（上）+ 快捷键（下）
  A.bookY = A.hudY - T.size.hudH / 2 - 26 * (ch / T.designH) - T.size.bookH / 2
  A.keysY = A.bookY - T.size.bookH / 2 - gp - T.size.keysH / 2
  A.hudTitleX  = 54 * (ch / T.designH)
  A.hudClockX  = 300 * (ch / T.designH)
  A.hudStatX   = 560 * (ch / T.designH)
  A.hudStatGap = 172 * (ch / T.designH)
  A.hudTipW    = 260 * (ch / T.designH)
  A.hudTipR    = 28 * (ch / T.designH)
  A.orderInX   = 14 * (ch / T.designH)
  return s
end

SK._scale = 1
SK._fitted = false

-- ══════════════════════════════════════════════════════════
-- 二、颜色工具
-- ══════════════════════════════════════════════════════════

-- 内容区底衬的颜色：卡片原色 **提亮** chipLift（"浅半档"）
--   ⚠️ 方向别搞反：是提亮，不是压暗。
function SK.chip(col, d)
  d = d or T.chipLift
  return { math.min(255, col[1] + d), math.min(255, col[2] + d), math.min(255, col[3] + d), T.chipAlpha }
end

-- 压暗（备用：给"进度条槽"之类需要更暗的地方）
function SK.darken(col, k)
  k = k or 0.5
  return { math.floor(col[1] * k), math.floor(col[2] * k), math.floor(col[3] * k) }
end

-- 提亮（等价于 SK.chip，保留名字方便阅读）
function SK.lift(col, d)
  return SK.chip(col, d)
end

function SK.accent(id)
  return T.color[id] or T.color.text
end

-- ══════════════════════════════════════════════════════════
-- 三、绘图 helper
-- ══════════════════════════════════════════════════════════

-- 一块纯色矩形（真机没有原生圆角，靠素材号决定外观；这里统一用 100001 方形）
function SK.bg(cfg, name, x, y, w, h, col)
  local c = H.spawn(cfg, 'img', name)
  H.setPos(c, x, y); H.setSize(c, w, h)
  H.setColor(c, col[1], col[2], col[3], col[4] or 255)
  return c
end

-- 工位卡（方案 A）：名称行 + 图标列保留原色；其余整块加"同色系提亮"底衬
--   返回一张表（各内容元素的坐标），调用方往里填文字/图标/进度条
--   ⚠️ 底色**不做状态变色**（曾经"有活就提亮"和内容区提亮打架 → 颜色发花）
--
--   ★ 精致度（用户："边缘生硬、没层次、没有原版精致"）：引擎没有原生圆角/描边，
--     用**叠块**做层次 —— 原版 UI 的立体感就是这么来的：
--       ① 最外描边（底色压暗 0.72）→ 像"卡片有边框"
--       ② 卡片底（纯原色，比描边小 4px，于是露出一圈边）
--       ③ 顶部高光条（底色提亮 46，3px）→ 像"上缘受光"，立体感的关键
--       ④ 内容区提亮底衬 + 2px 分隔线
function SK.stationCard(cfg, name, x, y, col, active)
  local w = T.size.stationW
  local h = T.size.stationH
  local outline = SK.bg(cfg, name .. '_edge', x, y, w, h, SK.darken(col, 0.72))  -- ① 描边
  local card = SK.bg(cfg, name .. '_box', x, y, w - 4, h - 4, col)               -- ② 卡片
  local hi = SK.bg(cfg, name .. '_hi', x, y + h / 2 - 6, w - 12, 3, SK.chip(col, 46)) -- ③ 高光

  local iw = T.size.pad + T.size.iconBig + T.size.pad
  local x0 = x - w / 2
  local y0 = y + h / 2
  local dx = x0 + iw
  local dy = y0 - T.size.nameRowH
  local dw = w - iw
  local dh = h - T.size.nameRowH
  local ph = dh - T.size.radius
  local panel = SK.bg(cfg, name .. '_panel', dx + dw / 2, dy - ph / 2, dw - 2, ph, SK.chip(col))
  local divider = SK.bg(cfg, name .. '_line',
    dx + dw / 2, dy + T.size.dividerH / 2, dw - 2, T.size.dividerH, T.dividerCol)

  local t = {}
  t.box = card
  t.outline = outline
  t.hi = hi
  t.panel = panel
  t.divider = divider
  t.nameX = dx
  t.nameY = y0 - T.size.nameRowH / 2
  t.iconX = x0 + T.size.pad + T.size.iconBig / 2
  t.iconY = y
  t.stepX = dx + T.size.pad            -- ★ 左边界（SK.textL 收左边界）
  t.stepY = dy - 46                    -- 步骤文字所在的 y
  t.stepW = dw - T.size.pad * 2        -- 步骤文字框宽（= 进度条同宽，正好在内容区内）
  t.barX = dx + T.size.pad            -- ★ 左边界（SK.bar 收左边界）
  t.barY = y - h / 2 + T.size.pad + T.size.barH / 2
  t.barW = dw - T.size.pad * 2
  t.keyX = x + w / 2 - T.size.pad - 17
  t.keyY = y0 - T.size.nameRowH / 2
  return t
end

-- 文字：**自动按字号配足框高**（框高 = 字号 × 1.8）
--   ⚠️ 不许再手写矮框 —— 那是"HUD 文字不显示"的真凶，layout-lint 会查
--
--   ★★ 坐标口径（踩过坑，务必看清）：
--      真机把文字按**左对齐**画，所以"文字从框左边开始"。为了让**框位置 = 文字位置**：
--        `SK.textL(..., leftX, ...)`  → 把框的**左边缘**放在 leftX（框范围 leftX .. leftX+w）
--        `SK.textC(..., centerX, ...)` → 以 centerX 为**框中心**
--      我上一版把 leftX 当成了"框中心"（`H.setPos(c, leftX)`），
--      结果框整体左移半个宽度、伸出容器外（lint 报"顾客名出界"，真机也偏）。
function SK.textL(cfg, name, leftX, y, w, fontKey, col)
  local c = H.spawn(cfg, 'text', name)
  local size = T.font[fontKey] or fontKey or T.font.body
  H.setPos(c, leftX + w / 2, y)          -- 框中心 = 左边缘 + 半个宽
  H.fitText(c, size, w)
  if col then H.setFont(c, size, col[1], col[2], col[3]) end
  c.horizontalAlignment = Enum.TextHorizontalAlignment.Left
  return c
end

-- 居中：以 centerX 为框中心
function SK.textC(cfg, name, centerX, y, w, fontKey, col)
  return SK.textL(cfg, name, centerX - w / 2, y, w, fontKey, col)
end

-- 图标（图片控件 + SetImage 素材号）
function SK.icon(cfg, name, x, y, artId, size, col)
  local c = H.spawn(cfg, 'img', name)
  size = size or T.size.iconS
  H.setPos(c, x, y); H.setSize(c, size, size)
  if artId then pcall(function() c:SetImage(Enum.ImageSource.StaticReference, artId) end) end
  if col then H.setColor(c, col[1], col[2], col[3], 255) end
  return c
end

-- 进度条：槽 + 填充（固定高度）
--   ★★ 参数 `x` = **槽的左边界**（不是中心！）
--      这条 API 我第一版语义混乱：槽内部用中心、填充却按左边界算 →
--      **槽本身偏出卡片半个宽度**（实测槽 -1039..-495，而卡片只有 -883..-211），
--      表现就是"进度条跑到卡片外面、看着粗糙"。
--      现在统一：**进左边界，内部自己算中心**，从根上杜绝再错。
function SK.bar(cfg, name, left, y, w, col)
  local cx = left + w / 2                       -- 槽中心
  local slot = SK.bg(cfg, name, cx, y, w, T.size.barH, { 0, 0, 0 })
  local fill = H.spawn(cfg, 'img', name .. '_f')
  H.setPos(fill, left, y); H.setSize(fill, 1, T.size.barH)
  local c = col or T.color.good
  H.setColor(fill, c[1], c[2], c[3], 255)
  return { slot = slot, fill = fill, left = left, y = y, maxW = w - 2 }
end

-- 按比例设进度（从左侧生长）
function SK.barSet(bar, frac, col)
  if not bar or not bar.fill then return end
  frac = math.max(0, math.min(1, frac or 0))
  local fw = math.max(1, math.floor(bar.maxW * frac))
  pcall(function() bar.fill:SetSizeDelta(fw, T.size.barH) end)
  pcall(function() bar.fill:SetAnchoredPosition(bar.left + fw / 2, bar.y) end)
  if col then H.setColor(bar.fill, col[1], col[2], col[3], 255) end
end

return SK
