-- ═══════════════════════════════════════════════════════════════════════════
-- input.lua —— 输入层（**重写版 v2** 2026-09-27）
--
-- 血泪教训（真机日志实测，别改回去）：
--   ① **鼠标一直正常、按键一直不生效** ⇒ 两者用**不同的注册机制**：
--        鼠标 → 挂在「光标检测区域」控件上的 AddCursorEventListener
--        按键 → AddKeyEventListener（挂在哪很关键）
--      ⇒ 现在**两个控件都挂**（光标检测区域 + 容器根节点），日志里能看到各自绑了几条。
--   ② 键回调**直接派发**，不走队列：真机上出现过 [key] 有 123 条而 [act] 是 0 的情况
--      （回调与 OnUpdate 不共享队列表）。
--   ③ 一个动作一个键，**没有候选/去重/推断**（旧版多键候选导致同键双绑、主键错位）。
--   ④ 判据一律用 **ASCII 日志**（真机中文会乱码）：[key] / [act] / [REJECT] / [LOGIC]。
-- ═══════════════════════════════════════════════════════════════════════════

local H = require('host')
local IN = {}

-- ── 物理键 → 千星"奇匠按键 N"编号（取自官方注解的"默认物理键"）────────────
IN.K = {
  ['1'] = 1,  ['2'] = 2,  ['3'] = 3,  ['4'] = 4,  ['5'] = 5,
  ['6'] = 6,  ['7'] = 7,  ['8'] = 8,  ['9'] = 9,  ['0'] = 10,
  ['U'] = 11, ['Z'] = 12, ['Y'] = 13, ['G'] = 14, ['H'] = 15, ['I'] = 16,
  ['O'] = 17, ['P'] = 18, ['J'] = 19, ['K'] = 20, ['L'] = 21, ['V'] = 22,
  ['F5'] = 23, ['F6'] = 24, ['F7'] = 25, ['F8'] = 26, ['F9'] = 27, ['F10'] = 28,
  [','] = 33, ['.'] = 34, ['/'] = 35,
  ['SPACE'] = 'JUMP',      -- 空格（跳跃键，不是奇匠按键）
}

-- ★★ 出餐（打包）必须有**两个**可用输入，理由见 BIND 表里 pack/pack2 的注释：
--   空格在千星里是"跳跃/滑翔"（KeyboardJumpKeyDown），可能被世界系统先吃掉；
--   Z 是奇匠按键12（默认物理键 Z），一定收得到。
IN.PACK_KEYS = { 'SPACE', 'Z' }

-- ── 绑定表（唯一真相：一个动作一个键）────────────────────────────────────
--   原版（网页版 1718~1726 行）的命名原则：**取工位名的动作字**，不取屏幕位置 ——
--      捣 / 火 / 化 / 泡 各一个键，键位跟着活儿走。
--   ⚠️ 平台约束（官方注解 Enum.KeyEventType，lua/types/mihoyo_client_ui_api.d.lua:331-495）：
--      千星**没有 B / C / R 这三个键**（奇匠按键只有 1-10、U Z Y G H I O P J K L V、F5-F10、
--      标点、42=Backspace、43=CapsLock；另有通用键 Space/F/E/Q/R/T/X/Tab/WASD/Ctrl）。
--      所以物理键无法与网页版逐个相同；这里保住**语义**（四个工位各一键、与原版一一对应）：
--        捣锤=Y（原版 B）· 火系=H（原版 H，相同）· 化学=K（原版 C）· 萃茶=P（原版 P，相同）
--      编辑器里可以把这几个奇匠按键的物理键改成 B/C，Lua 侧不用动。
--   ⚠️ 开关：原版是 Esc 暂停 / A 自动流转 / S 自动出小票，平台没有这三个语义键，
--      按用户拍板：**营业中** 1 / 2 / 3 = 自动流转 / 自动出票 / 暂停。
--      菜单态同一个 1/2/3 是"选模式"（见 xuehuang.lua 的 uiAct）——
--      和原版"1~8 只在关掉自动出票后才有用"是同一类"按键随场景换语义"。
IN.BIND = {
  { act = 'shake',   key = 'Y',         label = '捣锤' },
  { act = 'fire',    key = 'H',         label = '火系' },
  { act = 'chem',    key = 'K',         label = '化学' },
  { act = 'brew',    key = 'P',         label = '萃茶' },
  { act = 'pack',    key = 'SPACE',     label = '打包' },
  -- ★★ 出餐备用键（2026-09-27 真机日志逼出来的）：那次运行玩家按了 23 次键，
  --   **空格一次都没按过**，而咖啡早已做完只等出餐 → 看起来就是"卡住了"。
  --   空格在千星是"跳跃/滑翔"（KeyboardJumpKeyDown），可能被世界系统先吃掉，
  --   所以出餐**不能只挂在空格上**：再绑一个奇匠按键 Z（按键12）。
  --   语义与 pack 完全一致（入口把 pack2 归一成 pack）。
  { act = 'pack2',   key = 'Z',         label = '打包（备用键）' },
  { act = 'mode1',   key = '1',         label = '菜单1 / 自动流转' },
  { act = 'mode2',   key = '2',         label = '菜单2 / 自动出票' },
  { act = 'mode3',   key = '3',         label = '菜单3 / 暂停' },
  { act = 'confirm', key = 'BACKSPACE', label = '确认' },
}

-- ── 状态 ────────────────────────────────────────────────────────────────
IN.primary = {}
IN.bound = {}
IN.down = {}
IN.holdTouched = {}     -- "这个工位键按下过"（按住类的可见回应用）
IN.stats = {}
IN.clicked = nil
IN.MODES = { 'quick', 'fast', 'slow' }
IN.frameDt = 0.033
IN.keys = IN.down

-- ── 内部：取/存全局（回调与主体可能不共享 _ENV）──────────────────────────
local function G() return _G or _ENV end
local function getAct() local g = G(); return g and g.__IN_ACT end

-- ── 派发辅助：有回调就直呼，没有就排队（pump 下一帧消费）──────────────
local function dispatch(act, kind)
  local g = G()
  local fn = g and g.__IN_ACT
  if kind == 'press' then
    IN.down[act] = true
    -- ★ "按过这一下"的记录：按住类步骤的进度是每帧累积的，按一下数字几乎不动 →
    --   表现层需要这个标记才能对"按下"给可见回应（否则真机上就是"按了没反应"）。
    IN.holdTouched[act] = true
  elseif kind == 'release' then
    IN.down[act] = nil
  end
  IN.stats[act] = (IN.stats[act] or 0) + 1
  -- ★★ 主动刷新画面（2026-09-27 用户口径修正后的关键改动）
  --   用户的原始描述：「某个工作区出现了任务，**按按键**哪怕日志正常，**客户端那依旧不会显示
  --   这个任务有任何变化**；而**拿鼠标去点那个任务**，就会正常加进度完成任务。」
  --   ⇒ 两条路都调 G.act（逻辑一样），差别只在"谁在之后把画面刷了"：
  --     · 鼠标点击：入口的 click 分支跑在 OnUpdate 的 pump 里 → 紧接着当帧的 V.sync 就跑 → 画面立刻变
  --     · 键盘：回调是**引擎直接调进来的**，跑在 OnUpdate **之外**（帧与帧之间）→ 自身不刷画面，
  --       只能等下一帧 OnUpdate 的 V.sync。真机上这一帧的落差 + 工位卡文字只在"值变了"时才写
  --       ⇒ 表现就是"按了没反应，鼠标点了才有反应"。
  --   修法：由入口传入 IN.afterAct —— 每次派发**处理完之后立刻刷一次画面**。
  --   ⚠️ 只刷画面（view 是只读 s 的），不推进逻辑 → 不会造成"一次按键走两步"。
  if print and IN.keyLog ~= false then
    pcall(print, string.format('[DISPATCH] %s %s -> %s', tostring(act), tostring(kind),
      fn and '直呼回调' or '入队（等下一帧 pump）'))
  end
  if fn and not IN.forceQueue then
    local ok, err = pcall(fn, act, kind)
    if not ok and print then pcall(print, '[act] 派发出错: ' .. tostring(err)) end
    -- ★ 动作处理完 → 立刻刷画面（键盘路径的关键：不能只等下一帧 OnUpdate）
    if IN.afterAct then pcall(IN.afterAct, act, kind) end
  else
    -- ★★ 队列路径（2026-09-27 用户口径修正）：把整个动作**推迟到帧内**处理。
    --   为什么（用户三次纠正后我才能复述准确）：
    --     鼠标点击是在引擎的 UI/帧上下文里回调的 → 引擎当场重绘，玩家立刻看到进度；
    --     键盘回调是引擎从外部调进来的，跑在**帧外/输入上下文**里 → 在那里写控件属性，
    --     真机上"逻辑变了、屏幕纹丝不动"（日志里连按 0/4→1/4 在走，屏幕上没反应）。
    --   ⇒ 现在强制走队列：键回调只登记，真正的处理和刷画面都在**下一个 OnUpdate 帧内**完成，
    --     于是键盘路径与鼠标路径在引擎看来**完全同类**（都是在帧内改属性）。
    --   ⚠️ IN.forceQueue 由入口在 attach 时打开；关掉即回到"回调直呼"（本地测试/旧行为）。
    IN.queue[#IN.queue + 1] = { act = act, kind = kind }
  end
end

IN.queue = {}

function IN.clearInput()
  for k in pairs(IN.queue) do IN.queue[k] = nil end
  for k in pairs(IN.down) do IN.down[k] = nil end
  for k in pairs(IN.holdTouched) do IN.holdTouched[k] = nil end
  IN.clicked = nil
end

-- ── 枚举名 ──────────────────────────────────────────────────────────────
local function enumOf(keyName)
  local n = IN.K[keyName]
  if n == 'JUMP' then return 'KeyboardJumpKeyDown' end
  if type(n) == 'number' then return 'KeyboardCraftspersonKey' .. n .. 'Down' end
  return nil
end

-- ── 找光标检测区域 ──────────────────────────────────────────────────────
local function findCursorArea(c, depth)
  if not c or depth > 4 then return nil end
  if H.kindOf(c):find('Cursor', 1, true) then return c end
  local ok, kids = pcall(function() return c:GetChildren() end)
  if ok and type(kids) == 'table' then
    for i = 1, #kids do
      local r = findCursorArea(kids[i], depth + 1)
      if r then return r end
    end
  end
  return nil
end
IN.findArea = function(root) return findCursorArea(root, 0) end

-- ══════════════════════════════════════════════════════════════════════════
-- attach：绑定按键（双挂）+ 光标
-- ══════════════════════════════════════════════════════════════════════════
function IN.attach(cfg, tip)
  local root = cfg and cfg.root
  if not root then H.say('input', '没有挂载控件，输入不可用'); return 0 end

  local override = {
    shake = H.param('keyShake', ''), fire = H.param('keyFire', ''),
    chem = H.param('keyChem', ''), brew = H.param('keyBrew', ''),
    pack = H.param('keyPack', ''),
  }

  -- 绑定目标：**光标检测区域 + 容器根节点都挂**（真机上鼠标那条路是好的，键也挂同一控件上试）
  local area = findCursorArea(root, 0)
  local targets = {}
  if area then targets[#targets + 1] = { name = 'area', c = area } end
  targets[#targets + 1] = { name = 'root', c = root }
  IN.targets = targets

  -- ★★ 真机钥匙探针（ASCII，2026-09-27 r2）：唯一能一刀切开的判据
  --   背景：移植侧一直只打印"绑定成功"（[bind]），**从没在按键回调里打过日志**，
  --   所以"按键到底有没有进来"从来没有真机证据（本地模拟器与真机可能不同）。
  --   判据：
  --     ① 日志出现 [KTARGET] → 监听挂在哪些控件上一目了然（以及容器 active/visible）
  --     ② 按一下键，日志里出现**恰好一行** [KDOWN X] → 事件路径通，锅在动作分发
  --     ③ 按一下键，[KDOWN] 连成一片（每帧一行）→ 真机**按住就每帧回调**，
  --        必须用"边沿触发"（只在 false→true 的那一帧派发），否则等于一直按着
  --     ④ 一行都没有 → 事件根本没进来 → 查容器 active/visible、脚本是否真导入
  IN.keyCount = { area = 0, root = 0 }
  function IN.logKey(on)
    IN.keyLog = (on ~= false)
  end
  local function kl(fmt, ...)
    if IN.keyLog == false then return end
    if print then pcall(print, string.format(fmt, ...)) end
  end
  IN.kl = kl
  -- ★★ 状态行专用日志：**不受 keyLog 开关影响**。
  --   踩坑：我把每秒状态行挂在 IN.kl 上，而 kl 被 keyLog=0 关掉了 →
  --   "关掉按键日志"顺手把状态行也关了，诊断当场失效（而且毫无提示）。
  --   诊断输出的开关必须**各管各的**。
  function IN.stateLog(line)
    if print then pcall(print, tostring(line)) end
  end
  do
    local w, h = '?', '?'
    pcall(function() w, h = cfg.spaceW or '?', cfg.spaceH or '?' end)
    local a, v2, nm = '?', '?', '?'
    pcall(function()
      a = tostring(root.active); v2 = tostring(root.visible); nm = tostring(root.name)
    end)
    kl('[KTARGET] root=%s active=%s visible=%s 监听挂点=%d 光标区=%s canvas=%sx%s',
      nm, a, v2, #targets, area and '有' or '无', tostring(w), tostring(h))
    for _, tg in ipairs(targets) do
      local ta, tv, tn = '?', '?', '?'
      pcall(function() ta = tostring(tg.c.active); tv = tostring(tg.c.visible); tn = tostring(tg.c.name) end)
      kl('[KTARGET]   %s name=%s active=%s visible=%s', tg.name, tn, ta, tv)
    end
  end

  local function bindOne(act, keyName)
    local evName = enumOf(keyName)
    if not evName then
      H.say('input', '  键 %s 不认识（动作 %s 跳过）', tostring(keyName), tostring(act))
      return false
    end
    local okE, ev = pcall(function() return Enum.KeyEventType[evName] end)
    if not okE or ev == nil then
      H.say('input', '  事件 %s 不存在（动作 %s 跳过）', tostring(evName), tostring(act))
      return false
    end
    local upName = string.gsub(evName, 'KeyDown$', 'KeyUp')
    local okU, evU = pcall(function() return Enum.KeyEventType[upName] end)
    if not okU then evU = nil end

    local bound = 0
    for _, tg in ipairs(targets) do
      local okD = pcall(function()
        tg.c:AddKeyEventListener(ev, function()
          IN.keyCount[tg.name] = (IN.keyCount[tg.name] or 0) + 1
          -- ★★ 回执（改成放**日志**，2026-09-27 用户要求）：
          --   真机排查的关键证据是"引擎到底把这次按键派给了**哪个控件**上的监听器"。
          --   日志只能证明脚本收到了，证明不了派给了谁；把这行补上就能一刀切开。
          --   格式固定好搜：搜 "[KEYRECV]" 就能捞出全部按键回执。
          IN.lastTarget = tostring(tg.name) .. '#' .. tostring(tg.c.name or '')
          if print then
            pcall(print, string.format('[KEYRECV] %s <- %s @%s (第 %d 次)',
              tostring(act), tostring(keyName), IN.lastTarget, IN.keyCount[tg.name]))
          end
          dispatch(act, 'press')
          return true
        end)
      end)
      if okD then bound = bound + 1 end
      if evU ~= nil then
        pcall(function()
          tg.c:AddKeyEventListener(evU, function()
            kl('[KUP %s] %s <- %s', tostring(tg.name), tostring(act), tostring(keyName))
            dispatch(act, 'release')
            return true
          end)
        end)
      end
    end
    if print then pcall(print, string.format('[bind] %s=%s 挂到 %d 个控件', tostring(act), tostring(keyName), bound)) end
    if bound > 0 then
      IN.bound[#IN.bound + 1] = act .. '=' .. keyName
      return true
    end
    return false
  end

  local used, n = {}, 0
  for _, b in ipairs(IN.BIND) do
    local keyName = b.key
    local ov = override[b.act]
    if ov and ov ~= '' then keyName = string.upper(tostring(ov)) end
    if used[keyName] then
      H.say('input', '  键 %s 在绑定表里重复（动作 %s）→ 跳过', tostring(keyName), tostring(b.act))
    else
      used[keyName] = true
      if bindOne(b.act, keyName) then
        IN.primary[b.act] = keyName
        n = n + 1
      end
    end
  end

  H.say('input', '已绑定 %d 个键（目标 %d 个控件）：%s', n, #targets, table.concat(IN.bound, ' '))
  local show = {}
  for _, b in ipairs(IN.BIND) do
    if IN.primary[b.act] then show[#show + 1] = b.act .. '=' .. IN.primary[b.act] end
  end
  H.say('input', '键位：%s', table.concat(show, ' '))

  -- ── 光标点击 ──
  if area then
    pcall(function() area:SetSizeDelta(cfg.spaceW or 1920, cfg.spaceH or 1080) end)
    local okL = pcall(function()
      area:AddCursorEventListener(Enum.CursorEventType.CursorClick, function()
        local okp, gx, gy = pcall(game.GetCursorUIPos)
        if okp and type(gx) == 'number' and type(gy) == 'number' then
          IN.clicked = { x = gx, y = gy }
          if print then pcall(print, string.format('[key] click %.0f %.0f', gx, gy)) end
          dispatch('click', 'press')
        end
      end)
    end)
    H.say('input', '光标区已铺满 %sx%s 监听=%s', tostring(cfg.spaceW), tostring(cfg.spaceH), okL and 'ok' or '失败')
  else
    H.say('input', '控件树里没有"光标检测区域" → 鼠标点击不可用')
  end
  return n
end

-- ══════════════════════════════════════════════════════════════════════════
-- pump：每帧调用。把 act 回调发布到全局（键回调直呼它）+ 消费排队事件
-- ══════════════════════════════════════════════════════════════════════════
function IN.pump(handlers)
  local g = G()
  if g then g.__IN_ACT = handlers and handlers.act or nil end
  -- ★ 入口注册"动作后立刻刷画面"的回调（键盘路径的关键，见 dispatch 的注释）
  IN.afterAct = handlers and handlers.afterAct or nil
  -- ★★ 强制帧内处理（默认开）：键回调只登记，真正的处理放到帧内 —— 见 dispatch 的说明。
  --   这是"键盘改了逻辑但客户端不重绘"的修法：让键盘路径与鼠标点击在引擎看来同类。
  if handlers and handlers.forceQueue ~= nil then IN.forceQueue = handlers.forceQueue end
  IN.frame = (IN.frame or 0) + 1

  -- 消费排队事件（回调已经在派发时这里通常是空的；留给"早于 pump 到达"的事件）
  if #IN.queue > 0 then
    local q = {}
    for i = 1, #IN.queue do q[i] = IN.queue[i] end
    for i = #IN.queue, 1, -1 do IN.queue[i] = nil end
    for i = 1, #q do
      local e = q[i]
      if handlers and handlers.act then
        pcall(handlers.act, e.act, e.kind)
        -- 排队事件走完也让入口刷一次画面（与键盘直呼路径保持一致）
        if handlers.afterAct then pcall(handlers.afterAct, e.act, e.kind) end
      end
    end
  end

  -- ★★ **不再每帧补发**（2026-09-27 真机教训）：
  --   旧版对"按着的工位键"每帧重发一次 press。而真机上 KeyUp 可能送不到
  --   → IN.down[act] 永不清除 → **每帧都重按** → 日志刷屏、表现错乱、玩家看到"没变化"。
  --   现在所有步骤都是"一次输入即完成"，无需补发。
  --   （保留 IN.down 只是给"是否按着"的查询用，不驱动任何派发。）
end

-- ══════════════════════════════════════════════════════════════════════════
-- 命中测试（鼠标点工位卡）
-- ★★ y 轴口径（2026-10-01 修正，别再翻回去）：
--   官方光标 API（GetCursorUIPos）与控件 anchoredPosition 是**同一套口径**：
--   画布左下角为原点、y 向上为正（见 奇域实战经验-交接手册.md 的「光标坐标」一条）。
--   ⇒ 两者之间只需**平移到画布中心**，不要再翻符号。
--   ⚠️ 这里原写的是「实测 y 向下为正 ⇒ 用 H/2 - y 翻转」，那一版把 y 镜像了：
--     上面一排（y≈+224）两张卡的点会落到打包台（y≈-204）上，打包台的点又落到上面一排；
--     中间一排 y=0 的两张镜像后不变 ⇒ 一直"看着能用"，只有上面一排和打包台是坏的。
--     （2026-10-01 用户真机报的正是「捣锤/火系点不动、还正好跑到打包台」）
-- ══════════════════════════════════════════════════════════════════════════
function IN.hit(v, ctrl, pad)
  if not IN.clicked or not ctrl or not v then return false end
  pad = pad or 0
  local cx = IN.clicked.x - (v.W or 0) / 2
  local cy = IN.clicked.y - (v.H or 0) / 2
  local ok, x, y, w, h = pcall(function()
    return ctrl.anchoredPositionX, ctrl.anchoredPositionY, ctrl.sizeDeltaX, ctrl.sizeDeltaY
  end)
  if not ok or type(x) ~= 'number' then return false end
  return cx >= x - w / 2 - pad and cx <= x + w / 2 + pad
     and cy >= y - h / 2 - pad and cy <= y + h / 2 + pad
end

function IN.clearClick() IN.clicked = nil end

return IN
