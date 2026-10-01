-- host.lua —— 脚本与"千星客户端控件"打交道的那一层
--
-- 职责：**只做"怎么把控件建出来、怎么找到模板"，不管"画什么"**。
-- 从 hello.lua（M0 的验证脚本）里提炼出来的，那些能力都在真机上验过：
--   · 双空间扫描控件模板索引（真机索引是大数字，形如 1073741855）
--   · 解析图片素材号（脚本变量 artImage > ART 表 > 在画布里借一张配好图的控件）
--   · 隐藏"没配图的图片控件"（引擎会给它画一个"?"）
--   · 拿画布尺寸、拿挂载根控件
--
-- 真机契约（别改回去）：
--   ① `game.InstantiateClientUIControl` 在 **OnInit 阶段返回 nil** → 建控件必须在 OnStart 及之后
--   ② 不调 `script:EnableUpdate(true)` 就**收不到 OnUpdate**
--   ③ `game` 的全局函数用**点号**调用（冒号会多传隐式 game 实参）
--   ④ 运行期只改属性，不新建/销毁（模板子节点不能动态创建）→ 一律控件池

local D = require('diag')      -- ★ 诊断构建才存在；回退时一并删除
local H = {}

-- ── 日志：不依赖控件的通道（诊断必须走 print）──
local function fmt(f, ...)
  if type(f) ~= 'string' then return tostring(f) end
  local args, ai, out = { ... }, 1, {}
  local i = 1
  while true do
    local s, e = string.find(f, '%%[-+ #0]*%d*%.?%d*[sdf]', i)
    if not s then out[#out + 1] = string.sub(f, i); break end
    out[#out + 1] = string.sub(f, i, s - 1)
    local v = args[ai]; ai = ai + 1
    out[#out + 1] = (v == nil) and '(nil)' or tostring(v)
    i = e + 1
  end
  return table.concat(out)
end
function H.fmt(...) return fmt(...) end
function H.say(tag, ...)
  local ok, line = pcall(fmt, ...)
  if not ok then line = tostring((...)) end
  if print then pcall(print, '[' .. tostring(tag or '雪皇') .. '] ' .. line) end
end

function H.param(name, dflt)
  local v = script and script:GetParam(name)
  if v == nil then return dflt end
  return v
end

-- ★ 图片素材号（资产号）：和"控件模板索引"是两套数字，别混
--   用户 2026-09-26 从编辑器里点出来的编号
H.ART = {
  box      = 100001,   -- 基本方形（底衬通用：工位底板 / 打包台 / 进度条 / 卡片底；可拉伸不糊）
  roundbox = 100182,   -- 圆角方形（只用于接近正方形的场合；拉长会糊）
  mark     = 100122,   -- ⚠ 标识
  back     = 100109,   -- 返回箭头
  info     = 100115,   -- 详情 i 图标
}

-- ── 画布 ──
function H.canvas()
  local w, h = game.GetUICanvasSize()
  return w or 1280, h or 720
end

-- 挂载根控件：脚本挂在客户端控件容器上，子控件就挂在它这棵树上
function H.root()
  local r = script and script.object
  if r then return r end
  local rs = game.GetClientUIRoots()
  return rs and rs[1]
end

-- ── 控件类型判定（typeof 返回运行时类型名）──
function H.kindOf(c)
  if not c or not typeof then return '' end
  local ok, t = pcall(typeof, c)
  if not ok or not t then return '' end
  return tostring(t)
end
function H.isImage(c) return H.kindOf(c):find('Image', 1, true) ~= nil end
function H.isText(c) return H.kindOf(c):find('TextBox', 1, true) ~= nil end
function H.isCursor(c) return H.kindOf(c):find('Cursor', 1, true) ~= nil end
function H.isContainer(c) return H.kindOf(c):find('Container', 1, true) ~= nil end

-- ── 模板索引自动识别 ──
--   真机的控件模板索引是**大数字**（和关卡目录同一个 ID 空间，形如 1073741855）。
--   只扫 1~32 是错的（zuma 和我都为这个白查过一轮）。
local BASE = 1073741824                 -- 2^30
local SMALL_MAX, BIG_MAX = 32, 1023

-- 试着用某个索引建一个控件；建出来就按类型归类并**立刻销毁**（探针不占控件预算）
local function tryPrefab(idx, found, parent)
  local ok, c = pcall(game.InstantiateClientUIControl, idx, parent)
  if not ok or not c then return nil end
  local t = H.kindOf(c)
  if DestroyClientUIControl then pcall(DestroyClientUIControl, c) end
  if t:find('Image', 1, true) and not found.img then found.img = idx end
  if t:find('TextBox', 1, true) and not found.text then found.text = idx end
  if t:find('Cursor', 1, true) and not found.cursor then found.cursor = idx end
  if t:find('Container', 1, true) and not found.panel then found.panel = idx end
  return t
end

-- 返回 { img=?, text=?, cursor=?, panel=? }
function H.detectPrefabs(parent)
  local found, probe = {}, {}
  for i = 1, SMALL_MAX do
    local t = tryPrefab(i, found, parent)
    if t and t ~= '' then probe[#probe + 1] = i .. '=' .. t end
  end
  if not (found.img and found.text) then
    for i = BASE + 1, BASE + BIG_MAX do
      local t = tryPrefab(i, found, parent)
      if t and t ~= '' and #probe < 12 then probe[#probe + 1] = i .. '=' .. t end
      if found.img and found.text and found.cursor then break end
    end
  end
  H.probeLog = probe
  return found
end

-- ── 在画布里"借"一个素材号（用户只要在画布里摆一张配好图的控件，脚本就能拿到号）──
function H.adoptImageId(root)
  local found, seen = {}, {}
  local function walk(ctrl, depth)
    if not ctrl or depth > 4 or seen[ctrl] then return end
    seen[ctrl] = true
    local ok, kids = pcall(function() return ctrl:GetChildren() end)
    if not ok or type(kids) ~= 'table' then return end
    for i = 1, #kids do
      local ch = kids[i]
      local id = nil
      pcall(function() id = ch.imageId end)
      -- 只认正整数：0 = 没配图（真机/模拟器都这么给），捡了 0 等于没设 → 全画成"?"
      if type(id) == 'number' and id > 0 and H.isImage(ch) then
        found[#found + 1] = { id = id, name = tostring(ch.name), t = H.kindOf(ch) }
      end
      walk(ch, depth + 1)
    end
  end
  walk(root, 0)
  local up = root
  for _ = 1, 3 do
    if not up then break end
    -- ★ `parent` 是**字段**（官方注解：`---@field parent ClientUIBaseControl # 父控件`）。
    --   我原来写的是 `up:GetParent()` —— 官方注解里**没有这个方法**，真机上会被 pcall 吞掉，
    --   于是"往上几层找配好图的控件"整段静默失效。本地模拟器恰好有这个方法，所以本地看着是好的。
    local ok, p = pcall(function() return up.parent end)
    up = ok and p or nil
    walk(up, 0)
  end
  local okr, roots = pcall(game.GetClientUIRoots)
  if okr and type(roots) == 'table' then for i = 1, #roots do walk(roots[i], 0) end end
  return found
end

-- ── 隐藏"没配图的图片控件"（引擎会给它画一个"?"，而它不在我们控制之内）──
--   只关没配图的；用户在编辑器里刻意配好图的不动。
function H.hideBlankImages(root, quiet)
  local hidden = 0
  local function walk(c, depth)
    if not c or depth > 3 then return end
    local ok, kids = pcall(function() return c:GetChildren() end)
    if not ok or type(kids) ~= 'table' then return end
    for i = 1, #kids do
      local k = kids[i]
      if H.isImage(k) then
        local id = nil
        pcall(function() id = k.imageId end)
        if id == nil or id == 0 then
          pcall(function() k:SetVisible(false) end)
          local ok2 = pcall(function() k:SetActive(false) end)
          if ok2 then hidden = hidden + 1 end
        end
      end
      walk(k, depth + 1)
    end
  end
  walk(root, 0)
  if not quiet and hidden > 0 then H.say('host', '隐藏了 %s 个没配图的图片控件（它们会被画成"?"）', hidden) end
  return hidden
end

-- ── 一次性初始化：模板索引 + 素材号 + 枚举 ──
--   返回 hostCfg：{ img=索引, text=索引, cursor=索引, panel=索引, art=素材号, src=图片来源 }
function H.setup(root)
  local cfg = {}
  cfg.root = root
  cfg.canvasW, cfg.canvasH = H.canvas()

  local w, h = cfg.canvasW, cfg.canvasH
  H.say('host', 'BUILD=%s canvas=%sx%s', 'xuehuang-core', tostring(w), tostring(h))

  -- ★★ 挂载点（客户端控件容器）：**只激活，不要动它的尺寸！**
  --   我原来无条件 `root:SetSizeDelta(画布宽, 画布高)`（抄 zuma 的"容器 0x0 会被裁掉"经验），
  --   但用户的容器是**锚点拉满式**布局（Min(0,0) / Max(1,1) / 中心(0.5,0.5)，1600x900 居中），
  --   对锚点拉满的控件强行改 sizeDelta 会触发重新布局 → **整块 UI 被推歪**
  --   （用户截图里 UI 偏右偏上、订单栏被切，就是这个造成的）。
  --   现在只在"容器小得离谱"时才补尺寸，正常情况一个字都不碰。
  pcall(function() root:SetActive(true) end)
  do
    local cw, ch = nil, nil
    pcall(function() cw, ch = root:GetSizeDelta() end)
    if type(cw) ~= 'number' or cw < 8 or type(ch) ~= 'number' or ch < 8 then
      local ok, err = pcall(function() root:SetSizeDelta(w, h) end)
      H.say('host', '容器尺寸过小（%sx%s）→ 兜底设为 %sx%s -> %s',
            tostring(cw), tostring(ch), tostring(w), tostring(h), ok and 'ok' or tostring(err))
    else
      H.say('host', '容器尺寸正常（%sx%s）→ 不动它（锚点拉满的容器改了会推歪整块 UI）',
            tostring(cw), tostring(ch))
    end
  end
  -- ★★ 光标常驻（官方 API：ContainerControl.showCursor "是否显示常驻光标；
  --   **CursorEvent 相关方法都需设置该参数为真后才可正常使用**"）。
  --   不设它，玩家要**按住 Alt** 才看得见光标。编辑器里等价开关：容器节点控件 → 功能设置 → 显示常驻光标。
  do
    local ok, err = pcall(function() root.showCursor = true end)
    H.say('host', '显示常驻光标 showCursor=true -> %s%s', ok and 'ok' or '失败：', ok and '' or tostring(err))
  end

  -- ★★ 屏蔽"输入穿透到角色"（用户反馈：**鼠标点击会让角色攻击**；按键也会传给角色）
  --   官方 ContainerControl 的两个字段（原话）：
  --     · disableKeyEventPassthrough    "是否屏蔽按键事件穿透"
  --     · disableCursorEventPassthrough "是否屏蔽区域内点击事件穿透"
  --   设成 true 后：在容器范围内按的键/点的鼠标**只给 UI**，不会再触发角色的攻击/技能。
  --   这是"UI 抢输入"的正解 —— 不设的话，玩家边点工位边砍空气。
  --   编辑器里的等价开关：容器节点控件 → 功能设置 → 屏蔽按键/点击事件穿透。
  do
    local ok1, e1 = pcall(function() root.disableKeyEventPassthrough = true end)
    local ok2, e2 = pcall(function() root.disableCursorEventPassthrough = true end)
    H.say('host', '屏蔽输入穿透：按键=%s%s  点击=%s%s',
      ok1 and 'ok' or '失败(', ok1 and '' or tostring(e1),
      ok2 and 'ok' or '失败(', ok2 and '' or tostring(e2))
  end
  -- 手柄导航隔离（避免摇杆在 UI 控件间乱跳；UI 里我们只用键鼠）
  do
    local ok, err = pcall(function() root.isolateNavigation = true end)
    H.say('host', '隔离手柄导航 isolateNavigation=true -> %s%s', ok and 'ok' or '失败：', ok and '' or tostring(err))
  end

  -- textStyle=1：允许脚本覆盖字号/颜色（默认不覆盖，用模板里配好的样式）
  H.forceTextStyle = tonumber(tostring(H.param('textStyle', 0))) ~= 0
  H.say('host', '文字样式：%s', H.forceTextStyle and '脚本覆盖字号/颜色' or '用模板默认（不覆盖）')

  do -- __SPACE：把挂载控件的真实位置/尺寸打进日志（坐标系的原点就在这里）
    local info = H.probeSpace(root)
    cfg.spaceW = (type(info.cw) == 'number' and info.cw > 1) and info.cw or nil
    cfg.spaceH = (type(info.ch) == 'number' and info.ch > 1) and info.ch or nil
    cfg.spaceX, cfg.spaceY = info.cx, info.cy
    H.say('host', '__SPACE space=%sx%s at (%s,%s)',
          tostring(cfg.spaceW), tostring(cfg.spaceH), tostring(cfg.spaceX), tostring(cfg.spaceY))
    for i = 1, #info.parents do H.say('host', '__SPACE %s', info.parents[i]) end
  end

  local auto = tonumber(tostring(H.param('autoPrefabs', 1))) ~= 0
  local found = auto and H.detectPrefabs(root) or {}
  cfg.img    = H.param('imgPrefab', found.img)
  cfg.text   = H.param('textPrefab', found.text)
  cfg.cursor = H.param('cursorPrefab', found.cursor)
  cfg.panel  = H.param('panelPrefab', found.panel)
  H.say('host', '自动认模板：img=%s text=%s cursor=%s panel=%s（控件模板索引，1073741xxx 那串）',
        tostring(found.img), tostring(found.text), tostring(found.cursor), tostring(found.panel))
  if not cfg.img or not cfg.text then
    error('没认出必需的控件模板（img/text）。请在【界面控件组管理 → 界面控件组库 → 客户端控件模板 → '
      .. '添加客户端控件 → 存为模板】里建"图片控件"和"文本框控件"，或在脚本变量里填 imgPrefab/textPrefab。'
      .. '（真机索引是大数字，形如 1073741855）')
  end

  -- 图片类型：Basic 按原图尺寸画（会显得小），Stretch 铺满控件
  local okE, e = pcall(function() return Enum.ImageType.Stretch end)
  cfg.imageTypeStretch = (okE and e) or nil
  local okE2, e2 = pcall(function() return Enum.ImageType.Basic end)
  cfg.imageTypeBasic = (okE2 and e2) or nil

  -- 素材号：脚本变量 > ART 表 > 在画布里借
  -- ★ 素材号可覆盖：脚本变量 artImage
  --     artImage=0        → **完全不贴图**（控件只填色；排查"深色小块是不是图片"用）
  --     artImage=100181   → 换别的素材号
  --     不填              → 用内置 ART.box
  local artRaw = tostring(H.param('artImage', ''))
  local artVar = tonumber(artRaw)
  if artRaw ~= '' and artVar == 0 then
    cfg.art, cfg.artSrc = nil, '脚本变量 artImage=0（不贴图，只填色）'
  elseif artVar then
    cfg.art, cfg.artSrc = artVar, '脚本变量 artImage=' .. artRaw
  else
    cfg.art, cfg.artSrc = H.ART.box, '内置 ART（基本方形 ' .. tostring(H.ART.box) .. '）'
  end
  local cand = H.adoptImageId(root)
  cfg.borrowed = cand
  if #cand > 0 then
    H.say('host', '画布里配好图的控件：%s（素材号 %s）', tostring(cand[1].name), tostring(cand[1].id))
  end
  H.say('host', '用素材号 = %s（来源：%s）', tostring(cfg.art), tostring(cfg.artSrc))

  H.hideBlankImages(root, true)
  return cfg
end

-- ── 量出挂载控件的真实位置/尺寸（★★ 关键：坐标系的原点是**挂载控件的中心**，
--   而不是画布中心！用户截图证实：容器在画布右侧、还是竖长的，
--   于是我按"画布中心为原点"算的所有坐标整体偏右偏上，右侧订单栏还被切掉。
--   所以必须先问清楚"我这个父控件到底占哪儿"。──
function H.probeSpace(root)
  local info = { cw = nil, ch = nil, cx = nil, cy = nil, parents = {} }
  pcall(function() info.cw, info.ch = root:GetSizeDelta() end)
  pcall(function() info.cx, info.cy = root:GetAnchoredPosition() end)
  -- 往上找几层，看有没有更大的容器（挂载点可能不是根）
  local up, depth = root, 0
  while up and depth < 4 do
    local w, h, x, y, nm = nil, nil, nil, nil, nil
    pcall(function() w, h = up:GetSizeDelta() end)
    pcall(function() x, y = up:GetAnchoredPosition() end)
    pcall(function() nm = tostring(up.name) end)
    info.parents[#info.parents + 1] = string.format('L%s name=%s pos=(%s,%s) size=(%s,%s)',
      tostring(depth), tostring(nm), tostring(x), tostring(y), tostring(w), tostring(h))
    local ok, par = pcall(function() return up.parent end)
    up = ok and par or nil
    depth = depth + 1
  end
  return info
end

-- ── 建一个控件（运行期只调属性；不要每帧建/销毁）──
--   cfg：H.setup 的返回值；kind：'img' | 'text'
function H.spawn(cfg, kind, name, parent)
  local idx = (kind == 'text') and cfg.text or cfg.img
  -- ★ 第 4 个参数 parent：**可选**。不传就等于老行为（挂在 cfg.root 下）。
  --   加它的原因：视觉件（杯子/炮筒/火）是**嵌套**结构 —— 子控件必须挂在自己的根下，
  --   否则坐标全变成相对画布中心，整个东西会散开（而且 432 个火焰格子还会淹了根节点）。
  local c = game.InstantiateClientUIControl(idx, parent or cfg.root)
  if not c then error('建控件失败：kind=' .. tostring(kind) .. ' 索引=' .. tostring(idx)) end
  -- ★★ 新建控件**默认 active=false**（实测：建完不显式激活的话，真实状态就是 active=false，
  --   即使你从没隐藏过它）。曾经 H.spawn 里只写了一句 c:SetActive(true)，被静默吞掉 →
  --   整个 UI 只有图片/少量控件可见，表现是"进去啥都没有"。
  --   所以这里**双重设置 + 回读**，确保新建的控件一定是激活的。
  pcall(function() c:SetActive(true) end)
  pcall(function() c:SetVisible(true) end)
  do
    local a = nil
    pcall(function() a = c.active end)
    if a ~= true then
      pcall(function() c.active = true end)          -- 有的绑定支持直接写字段
      pcall(function() c:SetActive(true) end)
    end
  end
  if name then pcall(function() c.name = name end) end
  if kind ~= 'text' and cfg.art then
    local ok = pcall(function() c:SetImage(Enum.ImageSource.StaticReference, cfg.art) end)
    if ok and cfg.imageTypeStretch then pcall(function() c.imageType = cfg.imageTypeStretch end) end
  end
  if kind == 'text' then
    -- ★★ 文本框模板自带**不透明背景色**（`bgColor`），不关掉的话每个文字后面都会拖一个
    --   深色小方块 —— 用户看到的"四个深色小块"就是这个（我原以为文本框是透明的）。
    --   设成全透明，字才能直接落在工位方块上。
    pcall(function() c.bgColor = Color.FromRGBA(0, 0, 0, 0) end)
    -- ★★ 对齐必须**显式设置**！官方注解里文本框的 horizontalAlignment / verticalAlignment
    --   是读写字段，但**默认值取决于编辑器里那个模板控件**（模拟器里默认就是 nil）。
    --   模板若是"垂直靠上/水平靠左"，我按"居中"算的位置就会把文字推出控件框 → 完全看不见。
    --   （这就是"HUD 文字不显示、但工位文字正常"的根源：两者只是模板默认对齐的表现不同。）
    pcall(function() c.horizontalAlignment = Enum.TextHorizontalAlignment.Middle end)
    pcall(function() c.verticalAlignment = Enum.TextVerticalAlignment.Middle end)
    -- ★★ 描边要关掉：模板里默认是**开着**的（我在 studio 快照里读到 enableOutline=true），
    --   描边会把字往外扩几个像素 → 框高刚好等于字号时就被裁掉。我不需要描边。
    pcall(function() c.enableOutline = false end)
  end
  return c
end

-- ── 绘制小工具：一个"带边色的区块" ──
--   平台没有"描边"字段，边框只能自己画：底 + 一条细色条（色条比底更亮/更饱和）。
--   这是原神式 UI 的关键做法 —— 深底 + 小面积亮色，而不是大色块铺满。
--   edge：'top' | 'left' | 'bottom' | nil（无边框）
function H.spawnBox(cfg, name, x, y, w, h, bg, edge, edgeCol, edgeThick)
  local box = H.spawn(cfg, 'img', name)
  H.setPos(box, x, y); H.setSize(box, w, h)
  if bg then H.setColor(box, bg[1], bg[2], bg[3], bg[4] or 255) end
  local strip = nil
  if edge and edgeCol then
    local t = edgeThick or 5
    local sw, sh, sx, sy = w, t, x, y
    if edge == 'top' then sy = y + h / 2 - t / 2
    elseif edge == 'bottom' then sy = y - h / 2 + t / 2
    elseif edge == 'left' then sw, sh = t, h; sx = x - w / 2 + t / 2; sy = y
    elseif edge == 'right' then sw, sh = t, h; sx = x + w / 2 - t / 2; sy = y
    end
    strip = H.spawn(cfg, 'img', name .. '_edge')
    H.setPos(strip, sx, sy); H.setSize(strip, sw, sh)
    H.setColor(strip, edgeCol[1], edgeCol[2], edgeCol[3], edgeCol[4] or 255)
  end
  return box, strip
end

-- 隐藏一个区块（底 + 它的边条）
function H.hideBox(box, strip, ...)
  H.hide(box); H.hide(strip)
  for _, extra in ipairs({ ... }) do H.hide(extra) end
end

-- ── 给文本控件"按字号配够尺寸" ──
--   ★★ 这是"HUD 文字不显示"的真凶修复：
--     我把 HUD 标题的框高写成 34px，而字号是 24（模板还开着描边）→ 字被裁掉。
--     工位文字能显示，只是因为它们的框子（56px 配 15 号字）留了余量。
--   规则：**框高 >= 字号 × 2**（留出描边/行距/渲染误差的余量）。
function H.fitText(c, size, w)
  if not c then return c end
  size = math.floor((tonumber(size) or 20) + 0.5)
  local h = size * 2
  if h < 24 then h = 24 end
  D.try('host.fitText.size', c, size, function() c:SetSizeDelta(w or (size * 12), h) end)
  D.try('host.fitText.font', c, size, function() c.fontSize = size end)
  return c
end

-- 改属性的小工具（一律 pcall 包住：某个字段在某个控件上不支持时不要炸整帧）
function H.setPos(c, x, y)
  if c then D.try('host.setPos', c, x, function() c:SetAnchoredPosition(x, y) end) end
  return c
end
function H.setSize(c, w, h)
  if c then D.try('host.setSize', c, w, function() c:SetSizeDelta(w, h) end) end
  return c
end
function H.setColor(c, r, g, b, a)
  if c then
    D.try('host.setColor', c, r, function() c.imageColor = Color.FromRGBA(r, g, b, a or 255) end)
  end
  return c
end
function H.setText(c, s)
  if c then D.try('host.setText', c, s, function() c.text = tostring(s) end) end
  return c
end
-- ★★ 文字样式：**默认什么都不设**，用文本框模板里编辑器配好的字号/颜色。
--   为什么要这样（真机教训）：我原来每帧都写 fontSize + fontColor，而这两个字段都是
--   "Tweenable"（带补间），在真机上用脚本反复赋值有可能把模板里配好的样式覆盖成看不见的状态 ——
--   表现就是"方框（图片控件）都正常、一个字的都不显示"。
--   需要覆盖时用脚本变量 textStyle=1 打开（那时才写 fontSize/fontColor）。
function H.setFont(c, size, r, g, b, a)
  if not c then return c end
  -- ★ 真机拒绝**非整数**字号（新版模拟器会直接报错：integer expected）。
  --   我们的字号理论上都是整数，但"乘过缩放"之后就可能是 23.56 这种 —— 一律取整。
  if type(size) == 'number' then size = math.floor(size + 0.5) end
  if not H.forceTextStyle then return c end
  D.try('host.setFont.size', c, size, function() c.fontSize = size end)
  if r then D.try('host.setFont.color', c, r, function() c.fontColor = Color.FromRGBA(r, g, b, a or 255) end) end
  return c
end
-- 文字控件的"用颜色显隐"：把 fontColor 的 alpha 设 0/255
--   ★★ 为什么不用 SetActive：实测对某批控件 SetActive(true) 被**无声吞掉**
--      （H.show 回读 true，控件实际 false）→ 菜单大字死活不显示。
--      而 `Color.FromRGBA` 的 alpha 一直是可靠的（bgColor 设透明就在用），
--      所以这里用 alpha 做显隐兜底：反正文字不显示时也不占视觉。
function H.setAlpha(c, a)
  if not c then return end
  local rgb = c.__rgb                       -- 自定义字段挂不上控件，用 host 侧的表记
  local base = H._colorOf and H._colorOf[c] or nil
  if not base then
    -- 没有记录过颜色：就地读一次（读不到就用白色）
    local r, g, b = 255, 255, 255
    pcall(function()
      local col = c.fontColor
      if col then r, g, b = col.R, col.G, col.B end
    end)
    base = { r, g, b }
  end
  D.try('host.setAlpha.color', c, a, function() c.fontColor = Color.FromRGBA(base[1], base[2], base[3], a or 255) end)
end

-- 记住颜色（setFont/setStyle 时调），供 setAlpha 恢复用
H._colorOf = {}
function H.rememberColor(c, rgb)
  if c and rgb then H._colorOf[c] = { rgb[1], rgb[2], rgb[3] } end
end

-- 显示/隐藏控件
--   ★★ 血泪教训（实测复现，probe 结论）：
--      ① 用 `SetActive(false)` 隐藏过的控件，之后 `SetActive(true)` **回不来**（会锁死）
--      ② 顺序也很讲究：`SetVisible(true)` 之后紧跟 `SetActive(true)`，**visible 会被回滚成 false**
--         （probe: hide>false show>false set>true act=true —— 单独 SetVisible 能亮，
--          放在 H.show 里就不行）
--      ⇒ 最终口径：**显示时只动 visible；隐藏时只动 visible**。永远不碰 active=false。
--        新建控件本来就 active=true（H.spawn 里已确保），所以够用。
function H.show(c, on)
  if not c then return end
  if on then
    D.try('host.show.active', c, true, function() c.active = true end)
    D.try('host.show.visible', c, true, function() c:SetVisible(true) end)
  else
    D.try('host.show.visible', c, false, function() c:SetVisible(false) end)
  end
end
-- ★ 隐藏：**只**设 visible=false（可逆）；绝不下 active=false
H.hide = function(c)
  if not c then return end
  D.try('host.hide.visible', c, false, function() c:SetVisible(false) end)
end

-- 颜色快捷（RGB）
function H.rgb(r, g, b, a) return Color.FromRGBA(r, g, b, a or 255) end

return H
