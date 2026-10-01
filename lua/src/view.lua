-- view.lua —— 表现层：把逻辑层的状态画成控件
--
-- ★★ 数值全部来自 skin.lua（见《雪皇-视觉规范.md》）；**这个文件不许出现魔法数字**。
--   要改风格 → 改 skin.lua；要改布局 → 改 skin.lua 的 at 表 + 这里的相对摆放。
--
-- 视觉规则（用户逐轮定的）：
--   ① 整屏黑色打底，UI 压在其上            ② 按钮撑满空间，不留大片空白
--   ③ 字号内敛，不靠粗体拉层次              ④ 步骤(28) 比区域名(26) 略大一档
--   ⑤ 工位卡：名称行+图标列=原色；内容区=**提亮 +40** 底衬；2px 分隔线
--   ★ 底色**不用状态变色**（曾经"有活就提亮"和内容区提亮打架 → 颜色发花，用户一眼看出）
--
-- Z 序（实测确定）：**后建的在上**（同级子节点，索引大的画在上面）。
--   ⇒ 建池顺序 = 从底层到顶层：Backdrop → 工位 → 打包台 → 面板 → 订单卡 → HUD → 菜单大字。
--   ⚠️ 我一度按"先建的在上"建，结果 HUD 盖住了菜单大字。别再用 SetAsLastSibling/SetAsFirstSibling
--      （模拟器实测都不改渲染顺序）。
--
-- 平台约束（都是踩过的坑）：
--   · **控件池**：运行期只改属性，绝不新建/销毁
--   · 新建控件默认"**纯白 + 不可见**"→ 建完立刻设色；要显示的显式 SetActive(true)
--   · 坐标原点是**父控件中心**，单位屏幕像素（设计单位 × scale）
--   · 文本框对齐/框高由 H.spawn + H.fitText 处理（框太矮会裁字）
--   · 文字只用中文/ASCII（原神没 emoji 字体 → 豆腐块；tools/font-audit.mjs 会拦）

local H = require('host')
local P = require('props')   -- 实物视觉件（杯子/炮筒/火）
local STATE = require('state')
local CFG = require('config')
local SK = require('skin')
local K = require('kitchen')   -- 只为读"当前这步的进度"（只读快照，不碰玩法状态）
local D = require('diag')      -- ★ 诊断构建才存在；回退时一并删除
local IN = require('input')    -- 只为读"实际绑定的键位"（让界面显示和真按键一致）

local V = {}

local T = SK.T
local AT = T.at

-- 工位定义（id 要和 recipes.lua / kitchen.lua 里的字符串一致）
--   ★ 键位**从 input.lua 的实际绑定读**（IN.primary），没有才退回默认 ——
--     这样"界面上印的键"永远等于"真按得响的键"，不会再出现显示与实际不一致。
--   ★ 原版网页版键位是助记字母 B/H/C/P + 空格；但千星 enum **没有 B 和 C**，
--     所以捣锤用 Z（B 的邻居）、化学用 V（C 的邻居），H/P/空格 与原版一致。
--     换键只改 input.lua 的 IN.CAND（唯一来源），这里会自动跟着变。
-- ★ 键位**延迟读取**：V.STATIONS 在模块加载时求值，而 IN.primary 要等 boot 时才填好，
--   所以这里用**函数**而不是值 —— 界面渲染时再取，才能拿到真正绑上的键。
local function keyOf(act, fallback)
  local t = IN and IN.primary
  local k = t and t[act]
  if k == nil or k == '' then return fallback end
  if k == 'SPACE' then return '空格' end
  return tostring(k)
end

V.STATIONS = {
  { id = 'shake', name = '捣锤区', key = function() return keyOf('shake', 'Y') end, icon = T.icon.shake },
  { id = 'fire',  name = '火系区', key = function() return keyOf('fire', 'H') end, icon = T.icon.fire },
  { id = 'chem',  name = '化学区', key = function() return keyOf('chem', 'K') end, icon = T.icon.chem },
  { id = 'brew',  name = '萃茶区', key = function() return keyOf('brew', 'P') end, icon = T.icon.brew },
}
V.PACK = { id = 'pack', name = '打包台', key = function() return keyOf('pack', '空格') end, icon = T.icon.pack }
V.STATION_NAME = { shake = '捣锤区', fire = '火系区', chem = '化学区', brew = '萃茶区', pack = '打包台' }

local MAX_ORDERS = 5
local C = T.color

-- ── 每帧只改"变了"的属性（控件池的基本盘：少调 API 少出错）──
local txtCache, styleCache = {}, {}
local function setText(c, s)
  if not c then return end
  s = tostring(s)
  -- ★ forceWrite=1 时无视缓存，每帧强制写（作者给的排查技巧）
  if not D.forceWrite and txtCache[c] == s then D.cacheSkip('view.setText', c, s) return end
  txtCache[c] = s
  D.try('view.setText', c, s, function() c.text = s end)
end
local function setStyle(c, size, col)
  if not c then return end
  local key = tostring(size) .. '|' .. (col and (col[1] * 65536 + col[2] * 256 + col[3]) or 'd')
  if not D.forceWrite and styleCache[c] == key then D.cacheSkip('view.setStyle', c, key) return end
  styleCache[c] = key
  -- ★ 这里是全工程**唯一没有护栏的字号写入**（host.setFont 有 math.floor 兜底，这条没有）
  D.try('view.setStyle', c, size, function()
    if size then c.fontSize = size end
    if col then c.fontColor = Color.FromRGB(col[1], col[2], col[3]) end
  end)
end
local function setColor(c, col)
  if not c or not col then return end
  H.setColor(c, col[1], col[2], col[3], col[4] or 255)
end
local function recName(o)
  if o.makeup and o.makeup ~= '' then return o.makeup end
  local r = o.lines and o.lines[1] and o.lines[1].rec
  return r and r.name or '?'
end

-- 步骤文字限长：太长会**溢出卡片**（真机文本框不裁剪 → 直接盖到隔壁工位）
--   实测 28 号字下卡片内容区约放 16 个汉字（540px / 28px ≈ 19，留余量取 16）。
--   超长就加省略号；完整文案在逻辑层还有（小票/结算里能看全）。
local STEP_MAX = 16
local function clip(s, n)
  s = tostring(s or '')
  n = n or STEP_MAX
  local width = 0
  local i = 1
  while i <= #s do
    local b = s:byte(i)
    local step
    if b >= 240 then step = 4
    elseif b >= 224 then step = 3
    elseif b >= 192 then step = 2
    else step = 1 end
    width = width + (step > 1 and 1 or 0.55)
    if width > n then return s:sub(1, i - 1) .. '…' end
    i = i + step
  end
  return s
end

-- 横幅：显示临时提示（顾客到店/离开/打烊…）
function V.setBanner(v, msg)
  if not v or not v.hud or not v.hud.banner then return end
  if msg and msg ~= '' then
    local s = tostring(msg)
    if txtCache[v.hud.banner] ~= s then
      txtCache[v.hud.banner] = s
      pcall(function() v.hud.banner.text = s end)
    end
    H.show(v.hud.banner)
  else
    H.hide(v.hud.banner)
  end
end

-- ── 玩区显隐（菜单里不显示玩区；用户要求"菜单里不能有彩块和顾客区"）──
--   ★ 入口每帧按 scene 对齐（单一数据源）。曾经写成"切换时调一次"→ 被别处推翻，
--     又写成"每帧对比+自愈"→ 和显隐逻辑互相打架。最终：每帧幂等对齐，先设后不设。
-- 玩区可见性（工位/打包台/等候区/订单卡/结算背景板）—— **只管玩区**
--   ⚠️ 菜单专属内容（营业数据/产品手册/快捷键）不在这里管，见 V.setMenuVisible
-- 菜单/结算时才显示的"参考资料"面板（营业数据 · 产品手册 · 快捷键）
--   ★ 用户反馈："初始界面忘记把产品菜单以及其他的隐藏了"
--     进玩区时收起它们（玩区有工位/等候区/打包台，屏幕已经排满）
function V.setMenuVisible(v, on)
  if not v then return end
  -- ★ 必须**直设 active + visible**，不能走 H.show：
  --   H.show 的顺序是 `active=true` 再 `SetVisible(true)`，而实测
  --   **SetVisible(true) 紧跟 SetActive(true) 会把 visible 翻回 false** → 面板永远不显示。
  --   直设两个字段是稳的（和玩区的 toggle 同一套）。
  for _, bag in ipairs({ v.data, v.book, v.keys, v.menu }) do
    if bag and bag.controls then
      for _, c in ipairs(bag.controls) do
        if c then
          D.try('view.menuVisible.active', c, on, function() c:SetActive(on and true or false) end)
          D.try('view.menuVisible.visible', c, on, function() c:SetVisible(on and true or false) end)
        end
      end
    end
  end
end

function V.setBoardVisible(v, on)
  if not v or not v.stations then return 0 end
  local n = 0
  local function toggle(ctl)
    if not ctl then return end
    D.try('view.boardVisible.active', ctl, on, function() ctl:SetActive(on and true or false) end)
    D.try('view.boardVisible.visible', ctl, on, function() ctl:SetVisible(on and true or false) end)
    n = n + 1
  end
  local function each(list) for _, c in ipairs(list) do toggle(c) end end
  for _, st in ipairs(V.STATIONS) do
    local slot = v.stations[st.id]
    if slot then each(slot.controls) end
  end
  each(v.pack.controls)
  each(v.panel.controls)
  for i = 1, MAX_ORDERS do
    if v.orders[i] then each(v.orders[i].controls) end
  end
  return n
end

-- ═══════════════════════════════════════════════════════════════════
-- 初始化：建控件池（**顺序 = Z 序**：先建的在上）
-- ═══════════════════════════════════════════════════════════════════
function V.init(hostCfg)
  local v = { cfg = hostCfg, stations = {}, orders = {}, slips = {} }
  local W = hostCfg.spaceW or hostCfg.canvasW
  local H0 = hostCfg.spaceH or hostCfg.canvasH
  v.W, v.H = W, H0
  -- 设计坐标 → 屏幕坐标的缩放（真机高 900 → scale = 1.0）
  --   ★ 用 900 作基准（不是 720）：规范是按 1815×900 定的
  -- ★★ 按**实测画布**等比缩放整个版式（版式按 1815×900 设计）。
  --   之前写死 1815 → 画布宽度不同就整体偏右、打底铺不满、面板和工位重叠（用户两次反馈）。
  local s = SK.fitCanvas(W, H0)
  v.designScale = s
  v.scale = s
  v.W = W
  v.pad = hostCfg.root

  -- ═══ 0. 整屏黑色打底（规则 ①）═══
  --   最下层：**最先建**（先建的在下…… 不，先建的在上）
  --   ⚠️ 这里是唯一例外：打底必须**最后建**才对？—— 不对，见下：
  --   实测结论：paintList 里**索引大的在最上**（sibling-order 测试：Front 索引 2，在最上）。
  --   而"同级先出现的在上"是 Runtime scene 树的说法。两者相反，所以这里**按绘制实测**：
  --   打底放最先建 → 运行时它索引最小 → 按"索引小的在下"它就是最底 → 正确。
  do
    local bd = H.spawn(hostCfg, 'img', 'Backdrop')
    -- ★ 打底按**实测画布**铺，并留富余（原来用设计宽 → 21:9/16:9 宽屏上铺不满）
    H.setPos(bd, 0, 0); H.setSize(bd, W + 960, H0 + 960)
    -- ★ 用**不透明**（截图暴露：240 会透出左右边缘的游戏画面）
    H.setColor(bd, 3, 4, 7, 255)
    v.backdrop = bd
  end

  -- ═══ 2. 四张工位卡（2×2）═══
  local pos = {
    { AT.stationX,  AT.stationY },
    { AT.stationX2, AT.stationY },
    { AT.stationX,  AT.stationY2 },
    { AT.stationX2, AT.stationY2 },
  }
  for i, st in ipairs(V.STATIONS) do
    local px, py = pos[i][1], pos[i][2]
    local col = SK.accent(st.id)
    local lay = SK.stationCard(hostCfg, 'St_' .. st.id, px, py, col, false)
    -- 工位名：居中文本，x 要给它**框中心**（内容区中心略偏左，右边留给键位胶囊）
    local name = SK.textL(hostCfg, 'StN_' .. st.id, lay.nameX, lay.nameY, 200, 'title', C.onColor)
    local key  = SK.bg(hostCfg, 'StK_' .. st.id, lay.keyX, lay.keyY, 34, 28, { 0, 0, 0, 66 })
    local keyT = SK.textL(hostCfg, 'StKT_' .. st.id, lay.keyX - 6, lay.keyY, 34, 'small', C.onColor)
    local icon = SK.icon(hostCfg, 'StI_' .. st.id, lay.iconX, lay.iconY, st.icon, T.size.iconBig, { 255, 255, 255 })
    local step = SK.textL(hostCfg, 'StS_' .. st.id, lay.stepX, lay.stepY, lay.stepW, 'step', { 255, 255, 255 })
    local bar = SK.bar(hostCfg, 'StB_' .. st.id, lay.barX, lay.barY, lay.barW, { 255, 255, 255 })

    setText(name, st.name)
    setText(keyT, type(st.key) == 'function' and st.key() or st.key)
    setText(step, '等待小票')
    v.stations[st.id] = {
      col = col, lay = lay,
      controls = { lay.outline, lay.box, lay.hi, lay.panel, lay.divider, name, key, keyT, icon, step, bar.slot, bar.fill },
      box = lay.box, panel = lay.panel,
      name = name, key = key, keyT = keyT, icon = icon, step = step, bar = bar,
      barW = lay.barW,
    }

    -- ★ 实物化试水（2026-10-01）：火系区先挂一个**炮筒**实物件。
    --   归属/位置用户说"之后再说"，所以这里只做两件事：能显示、能跟着玩区显隐。
    if st.id == 'fire' then
      local okC, cone = pcall(P.cone, hostCfg, 'FireCone', lay.iconX, lay.iconY, { fitH = T.size.iconBig, maskColor = col })
      if okC and cone then
        local slot = v.stations[st.id]
        for _, c in ipairs({ cone.root, cone.mask, cone.tri, cone.grip, cone.mouth, cone.inner, cone.shine }) do
          slot.controls[#slot.controls + 1] = c
        end
        slot.cone = cone
        slot.coneScale = cone.scale
      end
    end
  end

  -- ═══ 3. 打包台 ═══
  do
    local col = C.pack
    local w, h = T.size.packW, T.size.packH
    local px, py = AT.packX, AT.packY
    local x0 = px - w / 2
    local y0 = py + h / 2
    local box = SK.bg(hostCfg, 'Pk_box', px, py, w, h, col)
    local iw = T.size.pad + T.size.iconMid + T.size.pad
    local dx = x0 + iw
    local dy = y0 - T.size.nameRowH
    local dw = w - iw
    local ph = h - T.size.nameRowH - T.size.radius
    local panel = SK.bg(hostCfg, 'Pk_panel', dx + dw / 2, dy - ph / 2, dw, ph, SK.chip(col))
    local divider = SK.bg(hostCfg, 'Pk_line', dx + dw / 2, dy + T.size.dividerH / 2, dw, T.size.dividerH, T.dividerCol)
    local icon = SK.icon(hostCfg, 'Pk_icon', x0 + T.size.pad + T.size.iconMid / 2, py, V.PACK.icon, T.size.iconMid, { 255, 255, 255 })
    local name = SK.textL(hostCfg, 'Pk_name', dx, y0 - T.size.nameRowH / 2, 120, 'head', C.onColor)
    local key  = SK.bg(hostCfg, 'Pk_keybg', dx + 130, y0 - T.size.nameRowH / 2, 56, 28, { 0, 0, 0, 66 })
    local keyT = SK.textL(hostCfg, 'Pk_key', dx + 108, y0 - T.size.nameRowH / 2, 56, 'small', C.onColor)
    local list = SK.textL(hostCfg, 'Pk_list', dx + T.size.pad, dy - 48, dw - T.size.pad * 2, 'step', { 255, 255, 255 })
    -- 交付提示（右下）
    local hint = SK.textL(hostCfg, 'Pk_hint', x0 + w - 220, y0 - h + 30, 200, 'small', C.dim)

    setText(name, V.PACK.name)
    setText(keyT, type(V.PACK.key) == 'function' and V.PACK.key() or V.PACK.key)
    setText(list, '暂时没有要交付的')
    setText(hint, '按空格全部交付')
    v.pack = {
      col = col, controls = { box, panel, divider, icon, name, key, keyT, list, hint },
      box = box, name = name, list = list, hint = hint,
    }
  end

  -- ═══ 4. 订单面板（贴右，整条到底）═══
  do
    local w = T.size.panelW
    local px = AT.panelL + w / 2
    local py = AT.panelY
    local h = T.size.panelH
    local box = SK.bg(hostCfg, 'OrderPanel', px, py, w, h, C.panelBg)
    local head = SK.textL(hostCfg, 'OrderHead', AT.panelL + T.gap.m, py + AT.panelHeadY, 260, 'head', C.gold)
    local empty = SK.textL(hostCfg, 'OrderEmpty', AT.panelL + T.gap.m, py - h / 2 + 40, w - 40, 'small', C.dim)
    setText(head, '等候区 / 在制')
    setText(empty, '（暂无顾客）')
    v.panel = { box = box, head = head, empty = empty, x = px, y = py, w = w, h = h,
                controls = { box, head, empty } }
  end

  -- ═══ 5. 订单卡（最多 5 张，整条铺满面板）═══
  for i = 1, MAX_ORDERS do
    local oy = AT.panelY + AT.orderTop - (i - 1) * AT.orderStep
    local w, h = T.size.orderW, T.size.orderH
    -- ★★ 坐标系口径（这里踩了大坑，看清再改）：
    --   `SK.bg` / `SK.textL` / `SK.bar` 的 x 都是**相对父控件中心**的坐标；
    --   而 AT.panelL 是"面板左边缘（相对中心）"。
    --   我上一版把 `ox = AT.panelL + 边距` 当"卡左"用，却又把它当"中心系"传给子元素 →
    --   **整张卡的内容右移了半个面板宽（176）**，真机上顾客名/标签/进度条全跑出面板（用户截图可见）。
    --   现在统一：ox = 卡片**左边缘**（中心系），子元素一律 ox + 偏移，底色类再 + w/2 换算成中心。
    local ox = AT.panelL + (T.size.panelW - w) / 2
    local y0 = oy + h / 2
    local box = SK.bg(hostCfg, 'Od_' .. i, ox + w / 2, oy, w, h, C.cardBg)
    -- 内容区提亮（和工位卡同一套规则：内容区比卡片浅半档）
    local cy = y0 - 60 - (h - 60 - 10) / 2
    local cpanel = SK.bg(hostCfg, 'OdP_' .. i, ox + w / 2, cy, w, h - 60 - 10, SK.chip(C.cardBg, 22))
    local divider = SK.bg(hostCfg, 'OdL_' .. i, ox + w / 2, y0 - 60 + T.size.dividerH / 2, w, T.size.dividerH, T.dividerCol)
    local edge = SK.bg(hostCfg, 'OdE_' .. i, ox + 3, oy, 4, h - 40, C.dim)
    -- ★ 框宽要"内收"，否则框本身会伸到卡外（文字是左对齐的，视觉无碍，但框出界会被 lint 报）
    local whoW = w - AT.orderInX * 2 - 118
    local who = SK.textL(hostCfg, 'OdW_' .. i, ox + AT.orderInX, y0 - 30, whoW, 'small', C.text)
    local tag = SK.bg(hostCfg, 'OdT_' .. i, ox + w - 48, y0 - 30, 64, 24, { 0, 0, 0, 56 })
    local tagT = SK.textL(hostCfg, 'OdTt_' .. i, ox + w - 60, y0 - 30, 56, 'tiny', C.dim)
    local whatW = w - AT.orderInX * 2
    local what = SK.textL(hostCfg, 'OdS_' .. i, ox + AT.orderInX, y0 - 84, whatW, 'small', C.text)
    local bar = SK.bar(hostCfg, 'OdB_' .. i, ox + AT.orderInX,
                       y0 - 56, whatW, C.good)  -- 耐心条：名称与要求之间
    local pct = SK.textL(hostCfg, 'OdPc_' .. i, ox + w - AT.orderInX - 64, y0 - 30, 56, 'tiny', C.good)
    setText(who, '顾客'); setText(tagT, ''); setText(what, ''); setText(pct, '')
    v.orders[i] = {
      controls = { box, cpanel, divider, edge, who, tag, tagT, what, bar.slot, bar.fill, pct },
      box = box, who = who, tagT = tagT, what = what, bar = bar, pct = pct,
      barW = w - AT.orderInX * 2, tagBg = tag,
    }
  end

  -- ═══ 5.5 小票行 —— **已删除**（用户 2026-09-27 决定）═══
  --   原来这里是一排可点的小票卡（"点我送 X 区"），用来手动把票搬到工位。
  --   删除理由（用户的判断，我认同）：
  --     · 它给玩家增加了一条**会失败的操作**：点票只挪票、不做工位，看起来"点了没反应"；
  --     · 而真正需要的"按键/点工位卡就能干活"已经由 G.act 的 opt.route 实现了
  --       （按键自动找活 + 推进，票不需要玩家搬）。
  --   现在**小票只当后台数据**：仍然一杯一票（名额/耐心/结单都依赖它），但不参与操作、不上屏。
  --   ⚠️ 因此 `V.sync` 里也不再有"小票行"的绘制；工位卡/HUD 是玩家唯一的操作反馈面。

  -- ═══ 6. 左列：营业数据（还原原版 9 项）═══
  do
    local w, h = T.size.dataW, T.size.dataH
    local px, py = AT.colLC, AT.dataY
    local box = SK.bg(hostCfg, 'DataBox', px, py, w, h, C.panelBg)
    local head = SK.textL(hostCfg, 'DataHead', AT.colLL + T.gap.m, py + h / 2 - 26, w - 30, 'head', C.gold)
    setText(head, '营业数据')
    -- 9 项做成 **2 列 × 5 行**网格（原版是宽屏横排；竖排 9 行在 900 高的画布里装不下）
    --   列宽 = 面板内宽的一半；每格"标签 + 数值"
    --   字段全部来自 state.lua / day.lua / config.lua（不自己造数）
    local rowDefs = {
      { k = 'money',    label = '营业额' },
      { k = 'rent',     label = '今日房租' },
      { k = 'served',   label = '已出餐' },
      { k = 'bad',      label = '翻车流失' },
      { k = 'combo',    label = '连击' },
      { k = 'auto',     label = '自动流转' },
      { k = 'kitchen',  label = '后厨容量' },
      { k = 'arrive',   label = '到店间隔' },
      { k = 'leftwait', label = '排队等跑的' },
    }
    local grid = {}
    local innerW = w - T.gap.m * 2
    local cellW = innerW / 2
    local rowH = 24
    for i, d in ipairs(rowDefs) do
      local col = (i - 1) % 2          -- 0=左列 1=右列
      local row = math.floor((i - 1) / 2)
      local gx = AT.colLL + T.gap.m + col * cellW
      local gy = py + h / 2 - 52 - row * rowH
      local lab = SK.textL(hostCfg, 'DataL' .. i, gx, gy, cellW * 0.60, 'tiny', C.dim)
      local val = SK.textL(hostCfg, 'DataV' .. i, gx + cellW * 0.58, gy, cellW * 0.42, 'tiny', C.text)
      setText(lab, d.label)
      setText(val, '—')
      grid[i] = { label = lab, val = val, def = d }
    end
    v.data = { box = box, head = head, rows = grid,
               controls = { box, head } }
    for _, r in ipairs(grid) do
      v.data.controls[#v.data.controls + 1] = r.label
      v.data.controls[#v.data.controls + 1] = r.val
    end
  end

  -- ═══ 7. 右列：产品手册（6 个配方）+ 快捷键 ═══
  do
    local w, h = T.size.bookW, T.size.bookH
    local px, py = AT.colRC, AT.bookY
    local box = SK.bg(hostCfg, 'BookBox', px, py, w, h, C.panelBg)
    local head = SK.textL(hostCfg, 'BookHead', AT.colRL + T.gap.m, py + h / 2 - 26, w - 30, 'head', C.gold)
    setText(head, '产品手册')
    local sub = SK.textL(hostCfg, 'BookSub', AT.colRL + T.gap.m, py + h / 2 - 52, w - 30, 'small', C.dim)
    setText(sub, '点一条起杯 · 键 1~8')
    -- 配方来自 recipes.lua（唯一来源）
    local RECIPES = require('recipes')
    local list = RECIPES.list or {}
    local rows = {}
    local rowH2 = 44
    for i = 1, math.min(6, #list) do
      local r = list[i]
      local ry = py + h / 2 - 92 - (i - 1) * rowH2
      local tag = SK.textL(hostCfg, 'BookT' .. i, AT.colRL + T.gap.m, ry, 40, 'small', C.gold)
      setText(tag, '[' .. tostring(r.tag or '?') .. ']')
      local nm = SK.textL(hostCfg, 'BookN' .. i, AT.colRL + T.gap.m + 44, ry, w - 140, 'body', C.text)
      setText(nm, tostring(r.name or '?'))
      local pr = SK.textL(hostCfg, 'BookP' .. i, AT.colRL + w - 76, ry, 60, 'small', C.dim)
      setText(pr, tostring(r.price or 0) .. ' 元')
      rows[i] = { tag = tag, name = nm, price = pr, rec = r }
    end
    v.book = { box = box, head = head, sub = sub, rows = rows, controls = { box, head, sub } }
    for _, r in ipairs(rows) do
      v.book.controls[#v.book.controls + 1] = r.tag
      v.book.controls[#v.book.controls + 1] = r.name
      v.book.controls[#v.book.controls + 1] = r.price
    end
  end

  -- 右列：快捷键说明（键位**从 input 读**，和实际绑定一致）
  do
    local w, h = T.size.keysW, T.size.keysH
    local px, py = AT.colRC, AT.keysY
    local box = SK.bg(hostCfg, 'KeysBox', px, py, w, h, C.panelBg)
    local head = SK.textL(hostCfg, 'KeysHead', AT.colRL + T.gap.m, py + h / 2 - 26, w - 30, 'head', C.gold)
    setText(head, '快捷键')
    local kk = IN and IN.primary or {}
    local function kn(a, d) local q = kk[a]; return (q == nil or q == '') and d or (q == 'SPACE' and '空格' or tostring(q)) end
    local lines = {
      string.format('%s 捣锤区 · %s 火系区 · %s 化学区 · %s 萃茶区', kn('shake','Y'), kn('fire','H'), kn('chem','K'), kn('brew','P')),
      string.format('%s 打包台出餐（备用键 %s 也可）', kn('pack','空格'), kn('pack2','Z')),
      -- ★★ 命名原则照抄原版（网页版 1720 行原话）：**取工位名的"动作字"**，不取屏幕位置、不取英文首字母
      --   我上一版写的是"取动作英文首字母（Shake/Fire/Chem/Brew）" —— 方向是反的，用户看得出。
      --   ⚠️ 平台没有 B/C 这两个键（官方枚举里只有奇匠按键 1-43 那批 + 通用键），
      --      所以物理键是 Y/H/K/P；编辑器里可以把它们改绑成 B/C，Lua 侧不用动。
      '命名：工位键取工位名的"动作字"（捣/火/化/泡），键位跟着活儿走',
      '（千星没有 B/C 键，用 Y/H/K 顶替；H/P 与原版相同）',
      string.format('%s 自动流转 · %s 自动出票 · %s 暂停（营业中）', kn('mode1','1'), kn('mode2','2'), kn('mode3','3')),
      '点小票 = 立刻送它去该去的工位',
    }
    local txts = {}
    for i, s in ipairs(lines) do
      local c = SK.textL(hostCfg, 'KeysL' .. i, AT.colRL + T.gap.m, py + h / 2 - 66 - (i - 1) * 34, w - 30, 'small', i == 1 and C.text or C.dim)
      setText(c, s)
      txts[i] = c
    end
    v.keys = { box = box, head = head, lines = txts, controls = { box, head } }
    for _, c in ipairs(txts) do v.keys.controls[#v.keys.controls + 1] = c end
  end

  -- ═══ 1. HUD 条 ═══
  v.hud = {}
  do
    local bar = SK.bg(hostCfg, 'HudBar', AT.hudX or 0, AT.hudY, T.size.hudW, T.size.hudH, C.hudBg)
    local lx = -(T.size.hudW) / 2      -- HUD 左边缘（HUD 居中，宽度已扣边距）
    local title = SK.textL(hostCfg, 'HudTitle', lx + AT.hudTitleX, AT.hudY, 150, 'head', C.gold)
    local clock = SK.textL(hostCfg, 'HudClock', lx + AT.hudClockX, AT.hudY, AT.hudClockW, 'head', C.text)
    -- 三项数据：图标 + 数字 + 说明（规则：图标化）
    --   ★ 坐标是**相对左区左边缘**的 → 必须写成 lx + (相对值)，别忘加 lx（我第一版忘了，
    --     结果三项数据全跑到画布外 1900+，是 layout-lint 抓出来的）
    local stats = { bar = bar, title = title, clock = clock, items = {} }
    local defs = {
      { key = 'served', icon = T.icon.ok,   col = C.good, label = '出餐' },
      { key = 'left',   icon = T.icon.warn, col = C.bad,  label = '流失' },
      { key = 'wip',    icon = T.icon.pack, col = C.text, label = '在制' },
    { key = 'combo',  icon = T.icon.brew, col = C.warn, label = '连击' },   -- 原版 HUD 第 4 项
    }
    for i, d in ipairs(defs) do
      local x = lx + AT.hudStatX + (i - 1) * AT.hudStatGap
      stats.items[i] = {
        icon = SK.icon(hostCfg, 'HudIc' .. i, x, AT.hudY, d.icon, T.size.iconS, d.col),
        val  = SK.textL(hostCfg, 'HudVal' .. i, x + 20, AT.hudY, 46, 'head', d.col),
        label = SK.textL(hostCfg, 'HudLab' .. i, x + 68, AT.hudY, 70, 'small', C.dim),
        def = d,
      }
    end
    -- 提示行：**右对齐到左区右边缘**（框中心 = 右边缘 - 框宽/2 - 边距）
    local tipW = AT.hudTipW
    stats.tip = SK.textL(hostCfg, 'HudTip', lx + T.size.hudW - tipW - AT.hudTipR, AT.hudY, tipW, 'small', C.dim)
    -- 横幅（临时提示：顾客到店/走了/打烊…）—— 独立控件，别借用标题
    --   （旧版把提示写进 HUD 标题，结果"标题长期显示游戏名"和"临时提示"互相覆盖）
    local bw = T.size.hudW - 96
    stats.banner = SK.textC(hostCfg, 'HudBanner', -(T.size.hudW) / 2 + 24 + bw / 2, AT.hudY - T.size.hudH / 2 - 22,
                           bw, 'body', C.gold)
    H.hide(stats.banner)
    v.hud = stats
  end

  -- ★★ 输入回执 / 按键反馈行：**不上屏，走日志**（2026-09-27 用户要求）。
  --   判据见 input.lua 的 `[KEYRECV]`（引擎把按键派给了哪个控件）与 `[DISPATCH]`（派发结果）。
  --   这些是为了区分"引擎没派发"和"客户端没画出来"，属于诊断，不该占玩家的屏幕。

  -- 菜单/结算的居中大字（复用，不另建 → 少踩"新建控件纯白"的坑）
  --   ★ 中间区域的文字已实测能显示（不像顶部 HUD 那样容易被裁/被盖）
  -- ★ 结算背景板：**不透明**整屏底，进结算时显示 → 盖住玩区（但盖不住更后建的结算大字）
  do
    local bag = H.spawn(hostCfg, 'img', 'SheetBag')
    H.setPos(bag, 0, 0); H.setSize(bag, W + 4, H0 + 4)
    H.setColor(bag, 4, 6, 11, 255)
    H.hide(bag)
    v.sheetBag = bag
  end

  v.big = {}
  do
    v.big.title = SK.textC(hostCfg, 'BigTitle', 0, 80, 900, 'display', C.gold)
    v.big.line1 = SK.textC(hostCfg, 'BigL1', 0, 10, 900, 'head', C.text)
    v.big.line2 = SK.textC(hostCfg, 'BigL2', 0, -40, 900, 'body', C.dim)
    v.big.line3 = SK.textC(hostCfg, 'BigL3', 0, -90, 900, 'small', C.dim)
    -- ★ 环保凭证两行（2026-10-01）：结算页专有。L5 是**推导链**——
    --   玩家若想"这 0.27 克哪来的"，照着这行能自己算一遍（见 recipes.eco 的注释）
    v.big.line4 = SK.textC(hostCfg, 'BigL4', 0, -140, 900, 'body', C.text)
    v.big.line5 = SK.textC(hostCfg, 'BigL5', 0, -186, 900, 'small', C.dim)
    v.big.controls = { v.big.title, v.big.line1, v.big.line2, v.big.line3, v.big.line4, v.big.line5 }

  -- ═══════════════════════════════════════════════════════════════════
  -- ★★ 初始界面（照原版 showStart 还原）
  --   原版面板：标题 + 一句话说明 + **3 张模式卡**（26px 大字"N 分钟" + 粗体名 + 灰说明，
  --   选中的卡粉色描边）+ **怎么玩**（7 条规则，虚线上边）+ **开门营业 →** 按钮 + tagline
  --   我第一版只做了 3 行大字 → 信息量和布局都差得远（用户指出）
  -- ═══════════════════════════════════════════════════════════════════
  v.menu = { controls = {}, cards = {}, ruleLines = {} }
  do
    local M = v.menu
    -- ★★ 菜单占用**整屏**（用户："菜单区域该有的区域没占满"）
    --   原版是 .veil（整屏半透明黑）+ 居中面板；千星没有 blur，用整屏不透明底衬等效。
    --   底部（等下）再放背景压暗，让菜单像"独立一屏"而不是"飘在中间的框"。
    local m0 = T.safe
    local panelW = math.min(W - m0 * 2, 1240)

    -- 整屏底衬（菜单背景）：不透明深色，盖住玩区
    M.veil = SK.bg(hostCfg, 'MnVeil', 0, 0, W + 8, H0 + 8, { 8, 10, 15, 255 })
    M.controls[#M.controls + 1] = M.veil
    -- 面板底衬：**整屏**（占满；内容块居中，宽度由 panelW 控制）
    M.panel = SK.bg(hostCfg, 'MnPanel', 0, 0, W + 8, H0 + 8, { 17, 22, 33, 255 })
    M.controls[#M.controls + 1] = M.panel

    local panelL = -panelW / 2   -- 内容块左边缘（居中）
    local pad = T.gap.xl
    local cx = 0
    local topY = H0 / 2 - m0 - pad            -- 内容顶端（中心系 y）
    -- 标题 + 说明
    M.title = SK.textL(hostCfg, 'MnTitle', panelL + pad, topY - 24, panelW - pad * 2, 'title', C.gold)
    M.controls[#M.controls + 1] = M.title
    M.sub = SK.textL(hostCfg, 'MnSub', panelL + pad, topY - 62, panelW - pad * 2, 'small', C.dim)
    M.controls[#M.controls + 1] = M.sub
    -- 3 张模式卡（铺满面板宽）
    local gapCard = T.gap.m
    local cw = (panelW - pad * 2 - gapCard * 2) / 3
    local chh = 104
    local cardCY = topY - 72 - chh / 2
    for i = 1, 3 do
      local cxx = panelL + pad + (cw + gapCard) * (i - 1) + cw / 2
      local card = SK.bg(hostCfg, 'MnCard' .. i, cxx, cardCY, cw, chh, { 21, 27, 40, 255 })
      local edge = SK.bg(hostCfg, 'MnCardE' .. i, cxx, cardCY, cw, chh, { 47, 58, 86, 255 })
      local big  = SK.textC(hostCfg, 'MnCardBig' .. i, cxx, cardCY + 26, cw - 16, 'title', C.text)
      local nm   = SK.textC(hostCfg, 'MnCardNm' .. i, cxx, cardCY - 10, cw - 16, 'small', C.text)
      local desc = SK.textC(hostCfg, 'MnCardD' .. i, cxx, cardCY - 34, cw - 16, 'tiny', C.dim)
      M.cards[i] = { card = card, edge = edge, big = big, name = nm, desc = desc,
                     controls = { card, edge, big, nm, desc } }
      for _, c in ipairs(M.cards[i].controls) do M.controls[#M.controls + 1] = c end
    end
    -- 怎么玩：标题 + 7 行（占满余下高度）
    local rulesTop = cardCY - chh / 2 - T.gap.xl
    M.rulesHead = SK.textL(hostCfg, 'MnRulesHead', panelL + pad, rulesTop - 10, panelW - pad * 2, 'body', C.text)
    M.controls[#M.controls + 1] = M.rulesHead
    local lineGap = 32
    for i = 1, 7 do
      local c = SK.textL(hostCfg, 'MnRule' .. i, panelL + pad, rulesTop - 44 - (i - 1) * lineGap, panelW - pad * 2, 'small', C.dim)
      M.ruleLines[i] = c
      M.controls[#M.controls + 1] = c
    end
    -- 底部：开门按钮 + tagline
    local btnY = -H0 / 2 + m0 + pad + 40    -- 底部一行（与标题/卡片同一内容列）
    local goW, goH = 150, 40
    local goCX = panelL + goW / 2   -- 与内容块左边缘对齐
    M.goLo = SK.bg(hostCfg, 'MnGoLo', goCX, btnY - 3, goW, goH, { 217, 59, 76, 255 })
    M.goBg = SK.bg(hostCfg, 'MnGoBg', goCX, btnY + 2, goW, goH - 6, { 255, 94, 108, 255 })
    M.goTx = SK.textC(hostCfg, 'MnGoTx', goCX, btnY, goW, 'head', { 255, 255, 255 })
    M.controls[#M.controls + 1] = M.goLo
    M.controls[#M.controls + 1] = M.goBg
    M.controls[#M.controls + 1] = M.goTx
    M.tag = SK.textL(hostCfg, 'MnTag', panelL + pad + goW + T.gap.l, btnY, panelW - pad * 2 - goW - T.gap.l, 'tiny', C.dim)
    M.controls[#M.controls + 1] = M.tag
    -- 命中矩形（菜单里点任意处都能开门，这里只保留给"将来要精确点击"用）
    M.goHit = { box = { anchoredPositionX = goCX, anchoredPositionY = btnY,
                        sizeDeltaX = goW, sizeDeltaY = goH } }

    -- 初始全隐藏（进菜单时再显示）
    for _, c in ipairs(M.controls) do H.hide(c) end
  end
  end

  H.say('view', '已建控件池：打底 + HUD + 4工位 + 打包台 + 面板 + %d 订单卡 + 菜单大字',
        tostring(MAX_ORDERS))
  return v
end

-- ═══════════════════════════════════════════════════════════════════
-- 每帧：把逻辑状态映射成控件属性
-- ═══════════════════════════════════════════════════════════════════
function V.sync(v, s)
  if not v or not s then return end
  local S = v.stations

  -- HUD：时钟 + 三项数据
  local left = (s.phase == 'closing') and s.closingLeft or s.dayLeft
  setText(v.hud.clock, string.format('第 %d/%d 天   %02d:%02d',
    s.day, s.mode.days, math.floor(left / 60), math.floor(left % 60)))
  setStyle(v.hud.clock, T.font.head, C.text)
  local vals = {
    tostring(s.served or 0), tostring(s.left or 0),
    string.format('%d/%d', STATE.wipCount(s), CFG.kitchen.maxWip),
    'x' .. tostring(s.combo or 0),          -- 连击（原版 HUD 第 4 项）
  }
  -- ★★ 每个工位"真正排在它这里的票数"（**不是全店未开工总数**）
  --   踩坑：原来卡上显示的是"全店未开工的杯数"，跟这个工位毫无关系 →
  --     捣锤区显示「等待小票（5 杯排队）」，而那 5 杯根本不经过捣锤区
  --     → 玩家以为有活，按了没反应，判定"按键坏了"（用户报的就是这个）。
  --   现在只统计"下一步就在这个工位"的票。
  local queued = {}
  for _, sl in ipairs(s.slips or {}) do
    local nx = STATE.nextStep(sl.cup)
    if nx and nx.st and not sl.ready then
      queued[nx.st] = (queued[nx.st] or 0) + 1
    end
  end
  local wipN = 0
  for _, n in pairs(queued) do wipN = wipN + n end
  for i, it in ipairs(v.hud.items) do
    setText(it.val, vals[i] or '0')
    setText(it.label, it.def.label)
    -- 连击没起来时压暗，起来了才发亮（一眼看出"连上了没有"）
    if it.def.key == 'combo' then
      setStyle(it.val, T.font.head, (s.combo or 0) > 1 and C.warn or C.dim)
    end
  end
  -- ★ 提示行里的键位**动态拼**（读实际绑定），不再写死
  --   ⚠️ 真正的赋值放到工位循环**之后**（要用 busy 状态算"哪个工位有活"），见下面
  local ks = IN and IN.primary or {}
  local function kk(a, d) local x = ks[a]; return (x == nil or x == '') and d or (x == 'SPACE' and '空格' or tostring(x)) end

  -- 工位卡
  for _, st in ipairs(V.STATIONS) do
    local slot = S[st.id]
    if slot then
      -- ★ 判据统一走 V.stationState（与小票行/HUD 同一套，绝不再自相矛盾）
      local stState, mine, nxUsed = V.stationState(s, st.id)
      if stState == 'work' then
        local nx = nxUsed or STATE.nextStep(mine.cup)
        local rec = mine.cup.rec
        local tag = (rec and rec.tag) and ('[' .. rec.tag .. '] ') or ''
        local prog = ''
        -- ★ 进度必须写出来：
        --   · 连按类 → "连按 2/5"（按一下数字就变）
        --   · 按住类 → "按住 0.3/0.9"（**按住时数字在涨**，玩家才知道要一直按着）
        --   原来按住类只写"按住"两个字 → 按一下没反应，看起来像按键坏了
        if nx.kind == 'mash' then
          prog = string.format('   连按 %d/%d', nx.done or 0, nx.taps or 1)
        elseif nx.kind == 'hold' then
          local full = CFG.hold and CFG.hold.sec or 0.9
          -- ★★ "按住类"必须对**按下这一下**就有可见回应（2026-09-27 用户口径）：
          --   按住类的进度是每帧累积的，按一下（33ms）数字几乎不动 →
          --   用户在真机上看到的就是"工位卡上明明有任务，我按了键却没有任何变化"。
          --   现在：只要"按住中"，卡上就多一句"按住中（别松手）"；
          --   如果连按下的记录都没有，再补一句"按一下开始"告诉他要按哪个键。
          local pressed = IN and IN.down and IN.down[st.id]
          local touched = pressed or (IN and IN.holdTouched and IN.holdTouched[st.id])
          local tail = touched and '   按住中（别松手）'
                            or string.format('   按住 %s 开始', kk(st.id, st.key))
          prog = string.format('  ⇩按住不放 %.1f/%.1f 秒%s', nx.done or 0, full, tail)
        end
        setText(slot.step, clip(tag .. nx.t) .. prog)
        -- ★ 进度条：mash(连按) 和 hold(按住) **都要显示进度**。
        --   原来只算 mash → 按住时进度条一直不动，用户以为"按住没用"（真实反馈）。
        local frac = K.stepProgress(s, st.id)
        SK.barSet(slot.bar, frac, { 255, 255, 255 })        -- ★★ 这个工位**有活** → 卡片用原色 + 键位胶囊高亮
        --   用户反馈"按了没反应"：现场日志证实按键每次都被收到了，
        --   真正的原因是**这个工位当时没有能做的小票**，而画面没把"有活/没活"说清楚。
        --   现在：没活的工位压暗（一眼看出"按它没用"），有活的亮起来。
        H.setColor(slot.box, slot.col[1], slot.col[2], slot.col[3], 255)
        H.setColor(slot.panel, SK.chip(slot.col, 40)[1], SK.chip(slot.col, 40)[2], SK.chip(slot.col, 40)[3], 255)
        H.setColor(slot.key, 255, 255, 255, 90)
        H.setColor(slot.icon, 255, 255, 255, 255)     -- 有活：图标全亮
        slot.busy = true
      else
        -- ★★ 没活 / 等名额 要把话说死（用户真实困惑："我按 30 次才有反应"）：
        --   玩家看不出"现在是按不了"还是"按键坏了" → 只能狂按碰运气。
        --   ★ 三态必须分清（stationState）：'waiting'（有活但没名额）时
        --     **不能**写"按 X 无效"—— 活就在这儿，只是要等名额腾出来；
        --     写成"无活"就是自相矛盾（小票行会同时说"→ 点我送 本工位"）。
        local q = queued[st.id] or 0
        local kname = tostring((st.key and type(st.key) == 'function' and st.key()) or st.key or '?')
        if stState == 'waiting' then
          setText(slot.step, '有活 · 等名额腾出来（后厨满了）')
          H.setColor(slot.key, 255, 255, 255, 70)
        elseif q > 0 then
          -- 有票排队但没轮到这个工位（池子里在排）→ 也说清楚
          setText(slot.step, string.format('排队中 %d 张 · 还没轮到', q))
        else
          setText(slot.step, string.format('本工位无活（按 %s 无效）', kname))
        end
        -- 进度条画一条很暗的满条，视觉上表明"这里现在不能做"
        SK.barSet(slot.bar, 0, { 255, 255, 255 })
        -- ★ 没活 → 压暗；等名额 → 半亮（活在这儿，只是排不上）
        local d = SK.darken(slot.col, stState == 'waiting' and 0.62 or 0.42)
        H.setColor(slot.box, d[1], d[2], d[3], 255)
        H.setColor(slot.panel, SK.chip(d, 18)[1], SK.chip(d, 18)[2], SK.chip(d, 18)[3], 255)
        if stState ~= 'waiting' then H.setColor(slot.key, 0, 0, 0, 30) end
        H.setColor(slot.icon, 255, 255, 255, stState == 'waiting' and 140 or 90)
        slot.busy = false
      end
    end
  end

  -- ★★ HUD 提示行：**明确告诉你哪个工位有活**
  --   用户报"按了没反应"，现场日志证明按键每次都被收到，
  --   真正原因是那个工位当时没活 → 现在直接把"有活"的工位列出来，按它一定有用。
  do
    local busy, waiting = {}, {}
    for _, st in ipairs(V.STATIONS) do
      local slot = S[st.id]
      if slot then
        local ss = V.stationState(s, st.id)
        if ss == 'work' then busy[#busy + 1] = kk(st.id, st.key) .. ' ' .. st.name:sub(1, 2)
        elseif ss == 'waiting' then waiting[#waiting + 1] = st.name:sub(1, 2) end
      end
    end
    local tipTxt
    if s.phase == 'closing' then
      tipTxt = '收尾中（做完手上的就收摊）'
    elseif #busy > 0 then
      tipTxt = '现在能按：' .. table.concat(busy, '  ')
    elseif #waiting > 0 then
      tipTxt = '有活但没名额：' .. table.concat(waiting, ' ') .. '（做完一杯就腾出来）'
    else
      tipTxt = string.format('暂无可做的活 · 键位 %s/%s/%s/%s',
        kk('shake','Y'), kk('fire','H'), kk('chem','K'), kk('brew','P'))
    end
    setText(v.hud.tip, tipTxt)
    -- ★ 存一份"本帧原文"：入口的调试追加要用它当基准，
    --   否则读 v.hud.tip.text 再追加会**每帧自我累加、无限膨胀**（踩过）
    v.hudTips = tipTxt
  end

  -- （输入回执**不上屏**：2026-09-27 用户要求放到日志里 → 见 input.lua 的 [KEYRECV]。）

  -- 打包台
  do
    local n, names = 0, {}
    for _, sl in ipairs(s.slips) do
      if sl.ready then
        n = n + 1
        if #names < 3 then names[#names + 1] = (sl.cup.rec and sl.cup.rec.name) or '?' end
      end
    end
    if n > 0 then
      -- ★ 有杯等出餐时，**把要按的键写在打包台上**（真机日志证明玩家不知道该按什么：
      --   23 次按键里空格一次没按过，一直在按没用的键）
      local ph = string.format('可交付 %d 杯   %s%s   ← 按 %s 出餐',
        n, table.concat(names, ' · '), n > 3 and ' …' or '',
        kk('pack', '空格'))
      setText(v.pack.list, ph)
      H.setColor(v.pack.hint, C.onColor[1], C.onColor[2], C.onColor[3], 255)
    else
      setText(v.pack.list, '暂时没有要交付的')
      H.setColor(v.pack.hint, C.dim[1], C.dim[2], C.dim[3], 255)
    end
  end

  -- 订单卡
  local oi = 0
  for _, o in ipairs(s.orders) do
    oi = oi + 1
    local card = v.orders[oi]
    if not card then break end
    for _, c in ipairs(card.controls) do H.show(c) end
    local frac = math.max(0, math.min(1, o.pat / (o.patMax > 0 and o.patMax or 1)))
    local acc = o.inProgress and C.shake or C.dim
    if frac < 0.28 then acc = C.bad elseif frac < 0.6 then acc = C.warn end
    H.setColor(card.tagBg, acc[1], acc[2], acc[3], 56)
    setText(card.tagT, o.inProgress and '在制' or ('等候 #' .. tostring(o.queueNo)))
    setStyle(card.tagT, T.font.small, acc)
    setText(card.who, o.name)
    setText(card.what, string.format('%s %s    已做 %d/%d', o.ice or '', o.sugar or '', o.made or 0, o.need))
    SK.barSet(card.bar, frac, acc)
    setText(card.pct, string.format('%d%%', math.floor(frac * 100)))
    setStyle(card.pct, T.font.small, acc)
  end
  for i = oi + 1, MAX_ORDERS do
    for _, c in ipairs(v.orders[i].controls) do H.hide(c) end
  end
  setText(v.panel.head, oi == 0 and '等候区   暂时没人' or ('等候区 / 在制   ' .. tostring(oi) .. ' 位'))
  if oi == 0 then H.show(v.panel.empty) else H.hide(v.panel.empty) end

  -- ═══ 小票行：**不画了**（2026-09-27 用户决定：小票只当后台数据、不参与操作）═══
  --   原来这里给每张票画一个卡（谁/下一步/点我送哪），并支持点它搬票。
  --   问题：点票只挪票、不推进工位，玩家会以为"点了没反应"；而且它和工位卡各有一套
  --   "有没有活"的判据，真机上出现过互相矛盾的显示（已修，但那条路本身也该收掉）。
  --   现在信息全在**工位卡 + HUD 提示行**上表达，玩家只需要操作工位。
  -- ★★ 左列"营业数据"9 项（还原原版的信息量）
  --   字段全部来自 state.lua / day.lua / config.lua，不自己造数
  if v.data then
    local D = require('day')
    local wip = 0
    for _, sl in ipairs(s.slips or {}) do
      if not sl.ready then wip = wip + 1 end
    end
    local interval = 0
    pcall(function() interval = D.arriveInterval(s) end)
    local money = (s.money or 0)
    local rent = (s.today and s.today.rent) or CFG.rent.perDay
    local vals = {
      string.format('%d 元', money),
      string.format('%d 元%s', (s.rentPaid or 0), ((s.rentDebt or 0) > 0) and ('  欠' .. s.rentDebt) or ''),
      string.format('%d 杯', s.served or 0),
      string.format('%d / %d', s.mistakes or 0, s.left or 0),
      string.format('x%d  (最高 x%d)', s.combo or 0, s.maxCombo or 0),
      CFG.auto and CFG.auto.on and '开' or '关',
      string.format('%d / %d 单', wip, CFG.kitchen.maxWip),
      string.format('%.1f 秒', interval),
      string.format('%d 位', s.leftWaiting or 0),
    }
    for i, r in ipairs(v.data.rows) do
      setText(r.val, vals[i] or '—')
      -- 颜色：营业额金色、翻车流失红色、连击奶油色
      local col = C.text
      if i == 1 then col = C.gold
      elseif i == 4 then col = ((s.mistakes or 0) + (s.left or 0)) > 0 and C.bad or C.dim
      elseif i == 5 then col = (s.combo or 0) > 1 and C.warn or C.dim
      elseif i == 6 then col = (CFG.auto and CFG.auto.on) and C.good or C.dim
      elseif i == 9 then col = (s.leftWaiting or 0) > 0 and C.bad or C.dim end
      setStyle(r.val, T.font.small, col)
    end
  end
end

-- ═══════════════════════════════════════════════════════════════════
-- 菜单（居中大字；玩区由入口隐藏）
-- ═══════════════════════════════════════════════════════════════════
function V.drawMenu(v, sel)
  if not v or not v.menu then return end
  local M = v.menu
  local CFGM = require('config').modes
  -- 模式表（顺序 = 原版 Object.entries(CFG.modes)：按总时长从短到长）
  --   ★★ 2026-09-27 还原度修正：三个模式**都开放**。
  --      原版（网页版 391-395）quick/fast/slow 全是单人局，days = 1/5/5、总时长 300/600/1200 秒。
  --      移植版曾把 fast/slow 标成"施工中（多人相关）"锁掉 —— 那是我自己加的闸，
  --      代码里没有任何依据，直接砍掉了原版的**主玩法（5 天日循环）**。
  local MODES = {
    { key = 'quick', ready = true },
    { key = 'fast',  ready = true },
    { key = 'slow',  ready = true },
  }
  local selKey = (MODES[sel] and MODES[sel].key) or 'quick'
  local selM = CFGM[selKey]

  setText(M.title, '雪皇的后厨 · 荒诞饮品模拟器')
  setStyle(M.title, T.font.title, C.gold)
  setText(M.sub, '名字离谱，操作真实。把左边的小票拖到工位，一步一步做出来，送到打包台。')

  for i = 1, 3 do
    local card = M.cards[i]
    local mk = MODES[i]
    local m = mk and CFGM[mk.key]
    if not card or not m then
      for _, c in ipairs(card and card.controls or {}) do H.hide(c) end
    else
      local on = (i == sel)
      local secs = m.total or ((m.days or 1) * (m.perDay or 0))
      setText(card.big, string.format('%d 分钟', math.floor(secs / 60)))
      setStyle(card.big, T.font.title, C.text)
      setText(card.name, m.label)
      setStyle(card.name, T.font.small, C.text)
      setText(card.desc, string.format('%s%s', m.desc or '',
        (m.days or 1) > 1 and string.format('（每天 %d 分钟）', math.floor((m.perDay or 0) / 60)) or ''))
      -- 选中卡：粉色描边（原版 .mode.sel{border-color:#ff5e6c}）
      H.setColor(card.edge, on and 255 or 47, on and 94 or 58, on and 108 or 86, 255)
      H.setColor(card.card, on and 30 or 21, on and 36 or 27, on and 52 or 40, 255)
    end
  end

  setText(M.rulesHead, '怎么玩')
  setStyle(M.rulesHead, T.font.small, C.text)
  -- 原版 7 条（键位替换成我们的实际绑定）
  local ks = IN and IN.primary or {}
  local function kn(a, d) local q = ks[a]; return (q == nil or q == '') and d or (q == 'SPACE' and '空格' or tostring(q)) end
  local rules = {
    '接单：左边自动进客；后厨同时只能有 3 个未完成任务，多的在等候区排队（排队也吃耐心）',
    '流转：小票会自动走到下一手；想抢速度就**点小票**立刻送过去',
    string.format('做工位：%s 捣锤 · %s 火系 · %s 化学 · %s 萃茶（按住类要按住、连按类要连按）',
      kn('shake','Y'), kn('fire','H'), kn('chem','K'), kn('brew','P')),
    string.format('出餐：小票全绿后自动进打包台，按 %s 或 %s 出餐，越快评分越高',
      kn('pack','空格'), kn('pack2','Z')),
    '纪律：做错工位 = 翻车扣钱；客人耐心条空了就走人',
    string.format('时间：整套经营锁死在 %d 分钟里，忙的时候时间稍慢、闲下来稍快',
      math.floor(((selM and (selM.total or ((selM.days or 1) * (selM.perDay or 0)))) or 300) / 60)),
    string.format('开关（营业中）：%s 自动流转 · %s 自动出票 · %s 暂停',
      kn('mode1','1'), kn('mode2','2'), kn('mode3','3')),
  }
  for i, line in ipairs(M.ruleLines) do
    setText(line, '· ' .. (rules[i] or ''))
    setStyle(line, T.font.tiny, i == 7 and C.warn or C.dim)
  end

  setText(M.goTx, '开门营业 →')
  setStyle(M.goTx, T.font.body, { 255, 255, 255 })
  local okGo = MODES[sel] ~= nil
  H.setColor(M.goBg, okGo and 255 or 90, okGo and 94 or 100, okGo and 108 or 120, 255)
  if M.goLo then H.setColor(M.goLo, okGo and 217 or 74, okGo and 59 or 82, okGo and 76 or 100, 255) end
  setText(M.tag, '「如果你在生活中善于观察，一定能体会到这种感觉。」')
  -- HUD 在菜单里当"品牌条"：只留副标题 + 提示
  setText(v.hud.title, '荒诞饮品模拟器'); setStyle(v.hud.title, T.font.small, C.dim)
  setText(v.hud.clock, (MODES[sel] and MODES[sel].ready) and '点「开门营业」开始' or '施工中')
  setStyle(v.hud.clock, T.font.head, (MODES[sel] and MODES[sel].ready) and C.good or C.bad)
  for _, it in ipairs(v.hud.items) do setText(it.val, ''); setText(it.label, '') end
  -- 三行大字在菜单里不用（原版的信息都在面板里）
  setText(v.big.title, ''); setText(v.big.line1, '')
  setText(v.big.line2, ''); setText(v.big.line3, '')
  setText(v.big.line4, ''); setText(v.big.line5, '')
  -- ★ 最后**直接 SetVisible(true)**（H.show 对这批无效，且 SetVisible 紧跟 SetActive 会翻回 false）
  for _, c in ipairs(M.controls) do
    D.try('view.menuBig.active', c, true, function() c:SetActive(true) end)
    D.try('view.menuBig.visible', c, true, function() c:SetVisible(true) end)
  end
end

-- ═══════════════════════════════════════════════════════════════════
-- 结算 / 总分
-- ═══════════════════════════════════════════════════════════════════
function V.drawResult(v, s)
  if not v or not s then return end
  for _, c in ipairs(v.big.controls) do D.try('view.big.visible', c, true, function() c:SetVisible(true) end) end
  -- 环保凭证（★ 两个结算页面都用它）
  --   ★ 2026-10-01 用户定：**只保留"固化下来的减碳"，不搞碳排放计算**。
  --   所以这里只有两句话：固化了几毫克 + 一句一本正经的感谢。
  --   大反差（空气里本来就没多少 CO₂）留给玩家自己想 —— 他自己笑出来的比写出来好笑。
  -- ★ 2026-10-01 用户定：**不做币种转化**，提前算好、直接输出结果（毫克 / 津元）
  --   所以这里没有"卖出 0.0000000243 元"那行，也没有汇率说明 —— 就是两个成品数。
  local function ecoLines(eco)
    local fixed, zwd = (eco and eco.fixed) or 0, (eco and eco.zwd) or 0
    if fixed <= 0 then return '', '' end
    local l4 = string.format('本单固化 CO₂ %.2f 毫克', fixed * 1000)
    local l5 = string.format('= %.2f 亿津巴布韦元 · 感谢您为环保事业的贡献', zwd / 1e8)
    return l4, l5
  end
  local function sumEco(stats)
    local e = { fixed = 0, zwd = 0 }
    for _, d in ipairs(stats or {}) do
      local x = d.eco or {}
      e.fixed = e.fixed + (x.fixed or 0)
      e.zwd = e.zwd + (x.zwd or 0)
    end
    return e
  end
  local function put(title, tCol, tSize, l1, l2, l3, e4, e5)
    setText(v.big.title, title); setStyle(v.big.title, tSize, tCol)
    setText(v.big.line1, l1 or ''); setStyle(v.big.line1, T.font.head, C.text)
    setText(v.big.line2, l2 or ''); setStyle(v.big.line2, T.font.body, C.dim)
    setText(v.big.line3, l3 or ''); setStyle(v.big.line3, T.font.small, C.dim)
    setText(v.big.line4, e4 or ''); setStyle(v.big.line4, T.font.body, C.text)
    setText(v.big.line5, e5 or ''); setStyle(v.big.line5, T.font.small, C.gold)
  end
  if s.ended and s.result then
    local r = s.result
    put(string.format('收摊！评级 %s', tostring(r.rank)), C.gold, T.font.display,
      string.format('总分 %d', r.total or 0),
      string.format('出餐 %d · 流失 %d · 翻车 %d', s.served or 0, s.left or 0, s.mistakes or 0),
      '按空格回到菜单，再来一局',
      ecoLines(sumEco(s.dayStats)))
    return
  end
  if s.settling then
    local last = s.dayStats and s.dayStats[#s.dayStats]
    -- ★ 字段名必须与 day.lua 的记录一致：dayStats 存的是 { day, served, money, left, mistakes, rent, paid }
    --   原来读 `last.revenue`（不存在）→ 结算页营业额**恒显示 0**（审计挖出来的真值 bug）。
    put(string.format('第 %d 天结算完了', s.day), C.gold, T.font.title,
      last and string.format('出餐 %d 杯 · 营业额 %d', last.served or 0, last.money or 0) or '',
      last and string.format('流失 %d · 翻车 %d', last.left or 0, last.mistakes or 0) or '',
      string.format('房钱 %s · 手上还剩 %d 元      按空格继续',
        (last and last.paid) or '已付', s.money or 0),
      ecoLines(last and last.eco))
  end
end

-- ══════════════════════════════════════════════════════════════════════════
-- V.workHere(s, stationId) —— **"这个工位现在能不能干活"的唯一判据**
--
-- ★★ 为什么必须抽出来（2026-09-27 真机+本地同时复现的显示 bug）：
--   原来各处各用一套判据：
--     · 工位卡：`nextStep(cup).st == 工位`          ← 对
--     · 小票卡：`sl.st == nx.st`（票当前停在哪）    ← 错（sl.st 会**留在旧工位**）
--   于是同一帧出现自相矛盾的两句话：
--     小票卡：「在本工位（按 P 动手）」
--     萃茶区卡：「本工位无活（按 P 无效）」
--   玩家照着按 → 什么都没发生 → 就是用户说的"客户端上看不到状态更新"。
--   现在两边都问这一个函数，**不可能再互相矛盾**。
--
-- 返回：票（能干活的那张）或 nil
-- ══════════════════════════════════════════════════════════════════════════
-- ══════════════════════════════════════════════════════════════════════════
-- V.stationState(s, stationId) —— 工位状态机（**画面与逻辑的唯一共同口径**）
--
-- ★★ 为什么必须显式建模（2026-09-27 定位到的显示 bug）：
--   原来是"各处各写一套 if"，于是同一帧出现互相矛盾的两句话：
--     · 工位卡：`nextStep(cup).st == 工位`      → 票在别的工位就说"无活"
--     · 小票卡：`sl.st == nx.st`（票停在哪）    → 票停在旧工位也说"在本工位，按 X 动手"
--   玩家照着按 → 什么都没发生 → 就是"客户端上看不到状态更新"。
--   现在所有显示都问这一个函数，返回三态之一：
--
--   'nw'      无活：这个工位现在没有"该在这儿做"的票
--   'waiting' 有活但**没名额**：票已经挂在这，后厨满 3 个在制，等一个名额腾出来
--             （这种**不能**说"按 X 无效" —— 按了会被 routeSlip 挡回来，玩家又白按一次）
--   'work'    有活可做：按这个工位的键**一定**能推进
--
-- game 参数用于名额判定；不传时退化为"按 nextStep 判定"（测试里方便）。
-- ══════════════════════════════════════════════════════════════════════════
function V.stationState(s, stationId, game)
  if not s or not stationId then return 'nw', nil, nil end
  for _, sl in ipairs(s.slips or {}) do
    if stationId == 'pack' then
      if sl.ready then return 'work', sl, nil end
    else
      local nx = STATE.nextStep(sl.cup)
      if (not sl.ready) and nx ~= nil and nx.st == stationId then
        if nx.noSlot == true or sl.cup.startedAt ~= nil or sl.cup.slotReady == true then
          return 'work', sl, nx
        end
        return 'waiting', sl, nx          -- 有活，但还没拿到名额
      end
    end
  end
  return 'nw', nil, nil
end

-- 兼容入口：只要"能干活的那张票"（等价 stationState == 'work'）
function V.workHere(s, stationId)
  local st, sl = V.stationState(s, stationId)
  if st == 'work' then return sl end
  return nil
end

-- V.stateLine(s) —— **一行 ASCII 状态行**（"画面 vs 逻辑"对齐用的唯一判据）
--
-- 为什么必须有（2026-09-27 的教训）：我做了好几个诊断开关（keyLog/autoplay/stationDebug），
--   但它们都走 `H.param(name, 默认值)`，而 `script:GetParam` 返回的是**编辑器里定义的那个值**：
--   编辑器里没定义 → 拿到默认值；编辑器里定义成 0 → **0 覆盖掉我的默认值**。
--   于是"我打开诊断开关"这件事在真机上根本没法保证。
--   ⇒ 换成**默认就输出**的状态行：不依赖任何脚本变量，进游戏就有一行事实可读。
--
-- 输出示例（纯 ASCII，真机不乱码）：
--   [STATE] t=12 day1/5 orders=2 slips=3 ready=1
--      work=[shake:#1 hold:0.4/0.9 chem:#2 mash:2/5 brew:- fire:-]
--      press=[shake=Y fire=H chem=K brew=P pack=SPACE,Z]
-- ══════════════════════════════════════════════════════════════════════════
function V.stateLine(s)
  if not s then return '[STATE] no-game' end
  local n, readyN = 0, 0
  for _, sl in ipairs(s.slips or {}) do n = n + 1; if sl.ready then readyN = readyN + 1 end end
  local parts = {}
  for _, st in ipairs(V.STATIONS) do
    local mine, nx = nil, nil
    for _, sl in ipairs(s.slips or {}) do
      local q = STATE.nextStep(sl.cup)
      if q and q.st == st.id then mine = sl; nx = q; break end
    end
    if mine and nx then
      local prog = ''
      if nx.kind == 'mash' then prog = string.format(' mash:%d/%d', nx.done or 0, nx.taps or 1)
      elseif nx.kind == 'hold' then prog = string.format(' hold:%.1f/%.1f', nx.done or 0, (CFG.hold and CFG.hold.sec) or 0.9)
      else prog = ' tap' end
      parts[#parts + 1] = string.format('%s:#%s%s', st.id, tostring(mine.id), prog)
    else
      parts[#parts + 1] = st.id .. ':-'
    end
  end
  local keys = {}
  local ks = IN and IN.primary or {}
  for _, a in ipairs({ 'shake', 'fire', 'chem', 'brew' }) do
    keys[#keys + 1] = a .. '=' .. tostring(ks[a] or '?')
  end
  keys[#keys + 1] = 'pack=SPACE'
  return string.format('[STATE] t=%.0f day%d/%d orders=%d slips=%d ready=%d work=[%s] press=[%s]',
    s.t or 0, s.day or 1, (s.mode and s.mode.days) or 0, #(s.orders or {}), n, readyN,
    table.concat(parts, ' '), table.concat(keys, ' '))
end

-- 收起菜单/结算大字（进玩区时调）
-- ★★ 动作反馈大字（V.showFeed / V.hideFeed）已随还原度重做删除 —— 原版没有这种东西。
function V.hideBig(v)
  if not v or not v.big then return end
  for _, c in ipairs(v.big.controls) do H.hide(c) end
end

-- ★★ 结算页/总分页的"独占画面"开关
--   用户反馈："收摊！出现了但**没盖住后面**"（工位卡还看得见、糊在一起）。
--   做法：进结算 → 藏玩区 + 显示"结算背景板"（SheetBag：一块**后建**的不透明整屏底，
--        因为 Z 序是"后建的在上"，它会盖住工位/打包台/订单面板，但不会盖住结算大字
--        —— 大字是在它之后建的）。回玩区 → 玩区恢复 + 藏掉背景板。
--   幂等：只在状态**变化**时动控件。
function V.showResultSheet(v, on)
  if not v then return end
  if v._sheet == on then return end
  v._sheet = on
  if on then
    V.setBoardVisible(v, false)
    if v.sheetBag then H.show(v.sheetBag) end
  else
    if v.sheetBag then H.hide(v.sheetBag) end
    V.setBoardVisible(v, true)
  end
end

return V
