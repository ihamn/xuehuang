-- @entry
-- hello.lua —— 雪皇的后厨 · 最小验证脚本（千星奇域客户端 Lua）
--
-- 它的唯一使命：证明「脚本映射 -> 挂到客户端控件 -> 试玩」这条管线是通的。
-- ★ 只依赖官方 API，不依赖雪皇的任何业务代码。所以它能把问题一刀切开：
--     · hello 能跑   -> 管线没问题，剩下的都是业务代码的事
--     · hello 也不跑 -> 是"文件没进去 / 映射没建 / 没挂到控件"这类管线问题
--
-- ★★ 三条真机契约（来自 miliastra-beyond-simulator 的 observed-contract，真机踩出来的）：
--   1. game.InstantiateClientUIControl 在 **OnInit 阶段返回 nil**，必须放在 OnStart 及之后。
--      原来把建控件放在 OnInit -> 全部 nil -> 连"报错提示"都是控件、也建不出来 -> 屏幕全白且无提示。
--   2. 官方 API 是 script:EnableUpdate(enabled)；**不打开就永远收不到 OnUpdate**。
--   3. game 的全局函数按当前 API 用**点号**调用（game.GetUICanvasSize()），
--      用冒号会产生隐式 game 实参、真机报 bad argument count。
--
-- 期望现象：屏幕上出现标题 + 一行状态字 + 5 个工位方块（这是个"版式占位图"，不是游戏）。
--
-- 脚本变量（编辑器里填，不填就自动认）：
--   autoPrefabs=1 自动认模板（默认开）；imgPrefab / textPrefab / cursorPrefab 手动兜底
--   artImage=<资产号> 指定图片素材（不填就在画布里借一张配好图的控件）
--
-- ★ 需要建几个客户端控件模板？**两个就够、最多三个**（图片 / 文本框 / 光标检测区）。
--   别去找"容器模板"——官方《客户端控件和客户端脚本》写得很清楚：
--     挂载点是**客户端控件容器**（这是服务端控件：界面布局 → 添加界面控件 → 客户端控件容器），
--     脚本直接挂在它身上（日志里的 mounted=ClientUIContainerControl:1 就是它），
--     我们的子控件挂在 script.object 这棵树上。**所以不需要第四个模板**（我上一条说错了）。
--   ⚠ 官方另一条：**客户端控件容器必须处于"激活且可见"**，容器里的控件和脚本才生效
--     （对应日志里「客户端控件根控件数 = N」，是 0 就是容器在运行时没生效）。
--
-- ── 真机实测到的 ID 一览（本项目 UID 190800866 / 关卡 1073741826，2026-09-26）──
--   ★ 这些数字**只作为人肉核对的参考**：脚本靠双空间扫描自动认模板（不写死常量），
--     所以换关卡/换账号都不用改代码。写在这里是为了下次看日志时知道那串数字是什么。
--   关卡目录 ID .......... 1073741826   （Beyond_Local_Save_Level 下的目录名 = 存档 1073741826.gil）
--   图片控件模板索引 ..... 1073741855   （自动认出来的 img；形如 1073741xxx，别和素材号混）
--   文本框控件模板索引 ... 1073741856
--   光标检测区模板索引 ... 1073741857
--   容器模板索引 ......... nil          （不需要：挂载点就是客户端控件容器本身）
--   图片控件运行时 ID ....   2          （日志里的 ClientUIImageControl:2 那种 ":N"）
--   文本框运行时 ID ......   3
--   光标区运行时 ID ......   4
--   ⚠ 素材号（资产号，形如 100001）= 编辑器里那张图的编号，脚本靠它在运行时 SetImage；
--     它和上面的"模板索引"是**两套不同的数字**（zuma 也在这上面栽过）。

local W, H = 1280, 720           -- 基线：手机 16:9（官方给的 2D 布局基准）
local built, err = false, nil
local t = 0
local parts = {}                 -- 池：运行期只改属性，不新建/销毁

-- 不依赖控件的日志通道：print 是官方日志 API
-- ★★ 别用 pcall(string.format, ...) 这条路 —— 真机实测它会失败（2026-09-26 日志里打出的是
--    字面量 "BUILD=%s canvas=%dx%d"，而那一行正是我用来判断"跑的是哪一版"的唯一手段）。
--    而且 string.format 对浮点用 %d 会**抛错**（真机画布 1814.86x900.0，
--    "number has no integer representation"）；放在 OnUpdate 里就是每帧抛一次、日志被刷爆。
--    所以手写一个极简格式化：认 %s / %d / %f / %.Nf / %% 一律 tostring，失败也绝不影响主流程。
local function fmt(f, ...)
  if type(f) ~= 'string' then return tostring(f) end
  local args, ai, out = { ... }, 1, {}
  local i = 1
  while true do
    -- ★ 支持宽度/精度修饰符：`%-16s` `%.1f` `%5d` 都要认（不认的话会把参数号吃掉，
    --   打出 `DIAG 来源=%-16s SetImage=StaticReference` 这种错位输出 —— 我自己踩过）
    local s, e = string.find(f, '%%[-+ #0]*%d*%.?%d*[sdf]', i)
    if not s then out[#out + 1] = string.sub(f, i); break end
    out[#out + 1] = string.sub(f, i, s - 1)
    local v = args[ai]; ai = ai + 1
    out[#out + 1] = (v == nil) and '(nil)' or tostring(v)
    i = e + 1
  end
  return table.concat(out)
end
local function say(...)
  local ok, line = pcall(fmt, ...)
  if not ok then line = tostring((...)) end
  if print then pcall(print, '[hello] ' .. line) end
end

local function param(name, d)
  local v = script and script:GetParam(name)
  if v == nil then return d end
  return v
end

-- ★ 版本标语：**ASCII**，用来判断"游戏里跑的是哪一版"。
--   交接手册 §二.3：日志里的中文是乱码，所以判据必须用 ASCII。
local BUILD = 'xuehuang-hello 2026-09-26 b7'

-- ★★ 模板索引的扫描空间（zuma 用真机日志换来的教训，别再想岔一次）：
--   真机的**控件模板索引是大数字**，和关卡目录同一个 ID 空间（形如 1073741846 ~ 1073742xxx），
--   不是 1/2/3/4。zuma 第一版只扫 1~32，于是"用户明明存为模板了"也全是 nil。
--   正确做法：**两个空间都扫** —— 小范围 1~32 + 大范围 2^30+1 ~ 2^30+192；
--   小范围要扫完（容器模板常排在最后），大范围只要必需的都认出来就早退。
local BASE = 1073741824                    -- 2^30
local SMALL_MAX, BIG_MAX = 32, 192

-- 从 typeof(控件) 猜它是哪一类（官方 typeof 返回运行时类型名，用来识别宿主对象）
local function kindOf(c)
  if not typeof then return nil end
  local ok, t = pcall(typeof, c)
  if not ok or not t then return nil end
  t = tostring(t)
  if string.find(t, 'Image') then return 'img' end
  if string.find(t, 'TextBox') then return 'text' end
  if string.find(t, 'Cursor') then return 'cursor' end
  if string.find(t, 'Container') then return 'panel' end
  return nil
end

-- 试着用某个索引建一个控件；建出来就按类型归类并**立刻销毁**（探针不占控件预算）
local function tryPrefab(i, found, parent)
  local ok, c = pcall(game.InstantiateClientUIControl, i, parent)
  if not ok or not c then return nil end
  local k = kindOf(c)
  if DestroyClientUIControl then pcall(DestroyClientUIControl, c) end
  if k and not found[k] then found[k] = i end
  return k
end

-- 扫两个索引空间，返回 { img=?, text=?, cursor=?, panel=? }
-- ★ 大范围放到 2^30+1023：模板索引是编辑器分配的，可能排得比 192 还远（早退条件保证不会白扫太多）
local function detectPrefabs(parent)
  local found = {}
  for i = 1, SMALL_MAX do tryPrefab(i, found, parent) end
  if not (found.img and found.text) then
    for i = BASE + 1, BASE + 1023 do
      tryPrefab(i, found, parent)
      if found.img and found.text and found.cursor then break end
    end
  end
  return found
end

-- ★ 现场取证：把"到底有什么"打出来，而不是靠猜。
--   真机第一次接管线时最费时间的不是写代码，是**不知道画布里有什么**。
--   这里全用官方 API：GetClientUIRoots / PrintClientUITree / GetChildren / GetParent / FindChild / typeof。
-- ★★ 关键判据（2026-09-26 真机日志）：`根控件数 = 0` 且官方树也说 `Roots: 0`
--    —— 按官方定义 GetClientUIRoots() = "实际显示的客户端控件容器画布中的默认容器节点"，
--    0 就是"容器在运行时不生效"。但脚本却能挂上容器（mounted=…:1），所以**还要看从挂载控件走一圈**：
--    往上走得到父节点 = 容器其实在树里，只是没被算作"显示的根"。
local function ctlInfo(c)
  local t = '?'
  if typeof then local ok, v = pcall(typeof, c); if ok and v then t = tostring(v) end end
  return tostring(c) .. ' (' .. t .. ')'
end

-- 沿父链往上走，走几步看它是"真根"还是"挂在某处"
local function dumpAncestors(root)
  local cur, depth = root, 0
  while cur and depth < 6 do
    local p = nil
    local ok, v = pcall(function() return cur:GetParent() end)
    if ok then p = v end
    if not p then say('  父链第 %s 层 = %s  ← 到顶了（没有父节点）', tostring(depth), ctlInfo(cur)); break end
    cur = p; depth = depth + 1
    say('  父链第 %s 层 = %s', tostring(depth), ctlInfo(cur))
  end
end

-- 递归打印 [挂载控件] 以下的自有控件树（这就是"画布里到底摆了什么"）
local function dumpChildren(c, depth, prefix)
  if depth > 4 then return end
  local ok, kids = pcall(function() return c:GetChildren() end)
  if not ok or not kids then say('%s(取子控件失败)', prefix); return end
  say('%s子控件 %s 个', prefix, tostring(#kids))
  for i, k in ipairs(kids) do
    local nm = nil
    local ok2, v = pcall(function() return k.name end)
    if ok2 then nm = v end
    say('%s  [%s] %s name=%s', prefix, tostring(i), ctlInfo(k), tostring(nm))
    dumpChildren(k, depth + 1, prefix .. '    ')
  end
end

local function dumpScene(root)
  local roots = game.GetClientUIRoots()
  local n = roots and #roots or 0
  say('DIAG 根控件数(GetClientUIRoots) = %s', tostring(n))
  if n == 0 then
    say('DIAG → 0 = 按官方定义"实际显示的容器画布中的默认容器节点"不存在（容器在运行时不生效）')
  end
  for i = 1, math.min(n, 6) do say('DIAG   root[%s] = %s', tostring(i), ctlInfo(roots[i])) end

  local ok, err2 = pcall(game.PrintClientUITree)
  say('DIAG PrintClientUITree -> %s', ok and 'ok（官方树已写进日志，找 [UITree] 那几行）' or tostring(err2))

  if root then
    say('DIAG 挂载控件 = %s', ctlInfo(root))
    say('DIAG --- 从挂载控件往上走 ---')
    dumpAncestors(root)
    say('DIAG --- 从挂载控件往下走 ---')
    dumpChildren(root, 0, 'DIAG')
  end

  -- 官方：FindClientUIRoot 按**名称**查找 UI 根控件；再试 FindChild（路径查找子控件）
  for _, nm in ipairs({ 'T_Img', 'T_Text', 'T_Cursor', 'T_Panel', 'Img', 'Text', 'Cursor', 'Panel' }) do
    local ok3, c = pcall(game.FindClientUIRoot, nm)
    if ok3 and c then say('DIAG FindClientUIRoot(%s) -> %s', nm, ctlInfo(c)) end
    if root then
      local ok4, c2 = pcall(function() return root:FindChild(nm) end)
      if ok4 and c2 then say('DIAG FindChild(%s) -> %s', nm, ctlInfo(c2)) end
    end
  end

  -- ★★ 把每个子控件的 imageId / imageType 报出来。这是"图片为什么是? "的唯一判据：
  --   imageId=0（或 nil）= **编辑器里那张控件没有配图**；imageId>0 = 配了，脚本能借来用。
  --   不报这两个值，就只能靠猜（我这一轮就白猜了一轮）。
  local function dumpImgInfo(c, depth, prefix)
    if depth > 3 then return end
    local ok, kids = pcall(function() return c:GetChildren() end)
    if not ok or type(kids) ~= 'table' then return end
    for i = 1, #kids do
      local k = kids[i]
      local t = (typeof and typeof(k)) or '?'
      if tostring(t):find('Image', 1, true) then
        local id, it = nil, nil
        pcall(function() id = k.imageId end)
        pcall(function() it = k.imageType end)
        say('DIAG 图片控件 name=%s imageId=%s imageType=%s  （id=0/nil 就是编辑器里没配图）',
            tostring(k.name), tostring(id), tostring(it))
      end
      dumpImgInfo(k, depth + 1, prefix)
    end
  end
  if root then dumpImgInfo(root, 0, 'DIAG') end
end

-- ★★ 图片素材号（资产号）—— 这是"图片控件画什么"的那串数字，和模板索引是两套东西。
--   优先级：脚本变量 artImage > 下面这张表里的默认值 > 在画布里借一张配好图的控件。
--   注意：这张表是**本项目的资产**（用户 2026-09-26 从编辑器里点出来报给我的编号）。
--   换关卡/换账号要重填 —— 所以脚本仍然保留"在画布里借"的路径，一个数字都不填也能跑。
local ART = {
  -- ★ 底衬用**基本方形**（用户实测：纯几何图形，拉长不变形；圆角方形拉长会糊）。
  --   2026-09-26 真机已验证：SetImage + 素材号这条路完全正常
  --   （把底衬临时换成"返回箭头"后，5 个方块立刻变成 5 个箭头 ⇒ 引擎确实按号画图）。
  box      = 100001,   -- 基本方形（底衬通用：工位底板 / 打包台 / 进度条 / 卡片底）
  square   = 100001,   -- 同上（别名，读起来清楚）
  roundbox = 100182,   -- 圆角方形（**只用于接近正方形的场合**，比如按钮；拉长会糊）
  mark     = 100122,   -- ⚠️ 标识（翻车/警告提示）
  back     = 100109,   -- 返回箭头（箭头形状，已在真机上验证能画出来）
  info     = 100115,   -- 详情 i 图标（以后做说明按钮用）
}
local DEFAULT_ART = ART.box          -- 没指定就用基本方形（可拉伸、不糊）

-- ★★ 图片素材号：动态创建的图片控件**不会继承模板/画布上那张图**（zuma 真机实测）。
--   不调 SetImage 的话每个图片控件都画成"?"。所以：
--     ① 优先用脚本变量 artImage=<资产号>；
--     ② 否则用 ART 表里的默认（圆角方形 100182）；
--     ③ 再否则**在画布里借**一张已经配好图的控件的 id；
--     ④ 都没有才报出来（不猜一个随机号 —— 猜错了只会画成"?"，徒增困惑）。
--   ⚠ 两个数字别搞混：**图片控件模板索引**（1073741855 这种）≠ **素材 id**（资产号，100182 这种）。
local function adoptImageId(root)
  local found, seen = {}, {}
  local function walk(ctrl, depth)
    if not ctrl or depth > 4 or seen[ctrl] then return end
    seen[ctrl] = true
    local ok, kids = pcall(function() return ctrl:GetChildren() end)
    if not ok or type(kids) ~= 'table' then return end
    for i = 1, #kids do
      local ch = kids[i]
      local id = ch and ch.imageId
      local t = typeof and typeof(ch) or nil
      -- ★ 只认正整数：0 = 没配图（真机/假宿主都这么给），捡了 0 等于没设 → 全画成"?"
      if type(id) == 'number' and id > 0 and type(t) == 'string' and string.find(t, 'Image', 1, true) then
        found[#found + 1] = { id = id, name = tostring(ch.name), t = t }
      end
      walk(ch, depth + 1)
    end
  end
  walk(root, 1)
  local up = root
  for _ = 1, 3 do
    if not up then break end
    local ok, p = pcall(function() return up:GetParent() end)
    up = ok and p or nil
    walk(up, 1)
  end
  local okr, roots = pcall(game.GetClientUIRoots)
  if okr and type(roots) == 'table' then for i = 1, #roots do walk(roots[i], 1) end end
  return found
end

local IMG_ID = nil                     -- 解析出来的素材号
local IMG_SRC = nil                    -- Enum.ImageSource.StaticReference（取不到就明说，别等 SetImage 抛了才发现）
-- ★★ 枚举自省：真机上 `Enum.ImageSource.StaticReference` **可能取不到值**（2026-09-26 真机实测：
--    取不到 → setImg 里提前 return → SetImage 一次都没调 → 屏幕上的图永远是"?"，
--    而日志里只有一行中文提示，很容易被忽略）。
--    所以这里把枚举**名字**全打出来，并把 ImageSource 的每个成员也列出来，一眼就能看出该用哪个。
local function enumNames(tbl)
  local out = {}
  if type(tbl) ~= 'table' then return out end
  for k, v in pairs(tbl) do out[#out + 1] = tostring(k) end
  table.sort(out)
  return out
end
local function resolveImgSource()
  local ok, v = pcall(function() return Enum.ImageSource.StaticReference end)
  if ok and v ~= nil then return v end
  -- 打印真相：Enum 有哪些字段、ImageSource 有哪些成员
  say('DIAG Enum 字段：%s', table.concat(enumNames(Enum), ' '))
  say('DIAG Enum.ImageSource 成员：%s', table.concat(enumNames(Enum and Enum.ImageSource), ' '))
  for _, nm in ipairs({ 'StaticReference', 'Static', 'Reference', 'Asset', 'Image', 'Basic', 'Prefab', 'Local' }) do
    local ok2, v2 = pcall(function() return Enum.ImageSource[nm] end)
    if ok2 and v2 ~= nil then say('注意：Enum.ImageSource.StaticReference 取不到，改用 .%s', nm); return v2 end
  end
  return nil
end
local IMG_VERIFY_DONE = false
local IMG_TYPE_LOGGED = false
local function setImg(c)
  if not c or not IMG_ID then return end
  -- ★★ 只对**图片控件**调 SetImage。`mk()` 是图片/文本框共用的，无条件调会让文本框也去
  --   SetImage —— 文本框没这个方法，报错是 "attempt to call a nil value (method 'SetImage')"，
  --   看着像"模拟器/真机不支持 SetImage"，其实是**传错了控件**（我就在这上面白查了一轮）。
  if typeof then
    local ok0, t = pcall(typeof, c)
    if ok0 and t and not tostring(t):find('Image', 1, true) then return end
  end
  if IMG_SRC == nil then
    say('SetImage 跳过：Enum.ImageSource.StaticReference 取不到值（Enum.ImageSource=%s）',
        tostring(Enum and Enum.ImageSource))
    return
  end
  local ok, e = pcall(function() c:SetImage(IMG_SRC, IMG_ID) end)
  if not ok then say('SetImage 失败（素材 %s）：%s', tostring(IMG_ID), tostring(e)) end

  -- ★★ 关键：把 imageType 设成**拉伸**，否则图片按原始尺寸画、不铺满控件
  --   （用户反馈"图标都太小，没有渲染出来的里面那么大"，就是这个）。
  --   官方 API：imageType 是 ImageType，**读写**（Enum.ImageType.Basic 基础 / .Stretch 拉伸），
  --   而 imageSource/imageId 是只读 —— 所以"铺不铺满"只能靠这个字段。
  local before = nil
  pcall(function() before = c.imageType end)
  local setOk = false
  if Enum and Enum.ImageType and Enum.ImageType.Stretch then
    local ok3 = pcall(function() c.imageType = Enum.ImageType.Stretch end)
    setOk = ok3
    if not ok3 then
      -- 有的环境枚举是逐项取值的，再试一次用字符串/原始值
      pcall(function() c.imageType = Enum.ImageType['Stretch'] end)
    end
  end
  if not IMG_TYPE_LOGGED then
    IMG_TYPE_LOGGED = true
    local after = nil
    pcall(function() after = c.imageType end)
    say('图片类型：原来=%s 设为拉伸=%s 现在=%s（Basic 就是"按原图尺寸画"，所以会显得小）',
        tostring(before), setOk and 'ok' or '失败', tostring(after))
  end

  -- ★★ 设完**读回来**自证。屏幕上那张图是"?"时，只有两条路：
  --     ① SetImage 没写进去（读回来的 imageId 还是 0）→ 素材号/枚举的问题
  --     ② 写进去了但真机画不出来（读回来 == 我们要的号）→ 是素材本身（图不存在/不是 Basic/要九宫格）
  --   imageId / imageSource 是**只读**字段（官方 API），所以能安全地当校验用。
  if not IMG_VERIFY_DONE then
    IMG_VERIFY_DONE = true
    local id, src2, it = nil, nil, nil
    pcall(function() id = c.imageId end)
    pcall(function() src2 = c.imageSource end)
    pcall(function() it = c.imageType end)
    say('SetImage 回读自证：要求素材=%s，控件里现在是 imageId=%s / imageSource=%s / imageType=%s',
        tostring(IMG_ID), tostring(id), tostring(src2), tostring(it))
    if tostring(id) ~= tostring(IMG_ID) then
      say('   → 说明**没有写进去**：多半是素材号不对（项目里没有这个资产），或 Enum.ImageSource 取错了')
    else
      say('   → 写进去了。若屏幕仍是"?"，那就是素材本身画不出来（换一张图，或它会走九宫格/遮罩）')
    end
  end
end

local function mk(prefab, name, x, y, w, h, color, noArt)
  local c = game.InstantiateClientUIControl(prefab, script.object)
  if not c then
    error('控件创建失败（prefab=' .. tostring(prefab) .. '）：这个索引没有客户端控件模板。'
      .. '看日志里 PROBE 那行：它列出了真正能用的索引（真机索引是大数字，形如 1073741xxx）。')
  end
  c:SetActive(true)
  c:SetAnchoredPosition(x, y)
  c:SetSizeDelta(w, h)
  if not noArt then setImg(c) end                              -- ★ 每张图都要自己 SetImage（见上面注释）
  if color then c.imageColor = color end
  if name then c.name = name end
  return c
end

local function build()
  local cw, ch = game.GetUICanvasSize()
  say('BUILD=%s canvas=%dx%d', BUILD, cw, ch)
  W, H = cw, ch

  local root = script.object
  if not root then
    local rs = game.GetClientUIRoots()
    root = rs and rs[1]
  end
  if not root then error('找不到挂载控件：脚本要挂在**客户端控件**上（不能挂主屏）') end
  say('mounted=%s', tostring(root))
  root:SetActive(true)

  -- ★★ 自动认模板：不用人去编辑器里点开控件抄那 4 个大数字（抄错不报错、只表现为"建不出来"）。
  --   流程：双空间扫描 → 用 typeof 归类 → 探针立刻销毁。
  --   填了脚本变量的**以变量为准**（autoPrefabs=0 可关掉自动认，回退到 1/2/3/4）。
  local auto = tonumber(param('autoPrefabs', 1)) ~= 0
  local found = auto and detectPrefabs(root) or {}
  local imgP  = param('imgPrefab',  found.img)
  local txtP  = param('textPrefab', found.text)
  local curP  = param('cursorPrefab', found.cursor)
  local panP  = param('panelPrefab', found.panel)
  say('自动认模板：img=%s text=%s cursor=%s panel=%s  ← 这是**控件模板索引**（1073741xxx 那串）',
      tostring(found.img), tostring(found.text), tostring(found.cursor), tostring(found.panel))
  say('用这套索引：img=%s text=%s cursor=%s panel=%s',
      tostring(imgP), tostring(txtP), tostring(curP), tostring(panP))
  dumpScene(root)                      -- ★ 现场取证：根控件数 / 控件树 / 按名字查找

  -- ★ 素材号（图片控件画什么图）：脚本变量 artImage > ART 表默认（圆角方形）
  IMG_ID = tonumber(tostring(param('artImage', '')))
  local src = '脚本变量 artImage'
  if not IMG_ID then
    IMG_ID, src = DEFAULT_ART, '内置 ART 表（基本方形 ' .. tostring(DEFAULT_ART) .. '，可拉伸不糊）'
  end
  if IMG_ID then
    IMG_SRC = resolveImgSource()
    say('本次用素材号 = %s   来源：%s', tostring(IMG_ID), src)
  end
  -- 先把"画布里配好图的控件"列出来（必须在建任何测试控件**之前**做，否则会捡到自己刚设的号）
  local cand = adoptImageId(root)
  if #cand > 0 then
    for i = 1, math.min(#cand, 6) do
      say('画布里配好图的控件：name=%s type=%s 素材号=%s', cand[i].name, cand[i].t, tostring(cand[i].id))
    end
  else
    say('画布里没有配好图的控件（imageId>0 的一个都没有）—— 用的是默认/变量里的素材号')
  end
  if not IMG_ID then
    say('警告：一个素材号都没有 —— 图片控件会画成"?"。'
      .. '在画布/容器里给图片控件选一张图，或在脚本变量填 artImage=<资产号>。')
  end

  -- ★★ 把容器里"原有的、**没配图**的图片控件"**隐藏掉**（用户 2026-09-26 的点子）。
  --   背景：屏幕底层一直有个"?"，我的方块其实画得好好的（把底衬换成返回箭头后 5 个方块立刻变形
  --   ⇒ SetImage 完全正常）。那个"?"就是**容器里原有的 ClientUIImageControl(imageId=0)**：
  --   引擎对"没配图的图片控件"就画一个"?"。
  --   它不是我建的（我不能删），但**能关掉** —— `SetActive(false)` 之后控件不可见、也不再画"?"。
  --   （不能只 `SetVisible(false)`：active 状态才决定"参不参与渲染"，两个都设更稳。）
  --   注意：**已经配好图的**控件不动（那可能是你在编辑器里刻意摆的）。
  local hidden = 0
  local function hideBlank(c, depth)
    if not c or depth > 3 then return end
    local ok, kids = pcall(function() return c:GetChildren() end)
    if not ok or type(kids) ~= 'table' then return end
    for i = 1, #kids do
      local k = kids[i]
      local t = (typeof and typeof(k)) or ''
      if tostring(t):find('Image', 1, true) then
        local id = nil
        pcall(function() id = k.imageId end)
        local nm = nil
        pcall(function() nm = k.name end)
        if id == nil or id == 0 then
          pcall(function() k:SetVisible(false) end)
          local ok2 = pcall(function() k:SetActive(false) end)
          if ok2 then hidden = hidden + 1 end
          say('  隐藏空白图片控件 name=%s（imageId=%s）→ %s',
              tostring(nm), tostring(id), ok2 and 'ok' or '失败')
        end
      end
      hideBlank(k, depth + 1)
    end
  end
  hideBlank(root, 0)
  if hidden == 0 then say('  容器里没有"没配图的图片控件"（那个"?"若还在，就不是它）') end

  if not txtP or not imgP then
    error('没认出必需的控件模板（img/text）。真机索引是**大数字**（形如 1073741846），'
      .. '和关卡目录同一个 ID 空间。请确认：界面控件组管理 → 界面控件组库 → **客户端控件模板** → '
      .. '添加客户端控件 → **存为模板**。建**图片 + 文本框**两个就够（光标检测区做输入时再加；'
      .. '**不需要容器模板**）。也可以在脚本变量里填 imgPrefab/textPrefab 兜底。')
  end

  -- 标题
  local title = mk(txtP, 'Title', 0, H / 2 - 60, math.min(W - 80, 900), 56)
  title.fontSize = 34
  title.text = '雪皇的后厨 · 荒诞饮品模拟器'

  -- 状态行（会每帧更新）
  local info = mk(txtP, 'Info', 0, H / 2 - 110, math.min(W - 80, 900), 34)
  info.fontSize = 18
  info.text = '正在摆放工位…'
  parts.info = info

  -- 5 个工位方块：1280×720 基线下的版式占位（上面 4 个 2×2，下面打包台横条）
  local SW, SH = 300, 110
  local xs = { -SW / 2 - 12, SW / 2 + 12 }
  local ys = { 60, -70 }
  local names = { '捣锤区 B', '火系区 H', '化学区 C', '萃茶区 P' }
  local colors = { '#7ee0ff', '#ff9a4d', '#c9a7ff', '#8ee08a' }
  for i = 1, 4 do
    local col = (i - 1) % 2 + 1
    local row = math.floor((i - 1) / 2) + 1
    local box = mk(imgP, 'Station' .. i, xs[col], ys[row], SW, SH, Color.FromRGB(30, 38, 54))
    local lab = mk(txtP, 'StationLabel' .. i, xs[col], ys[row] + 26, SW - 20, 30)
    lab.fontSize = 20
    lab.text = names[i]
    parts[#parts + 1] = box
    parts[#parts + 1] = lab
  end
  local pack = mk(imgP, 'Pack', 0, -190, SW * 2 + 24, 84, Color.FromRGB(40, 34, 22))
  local packLab = mk(txtP, 'PackLabel', 0, -190, SW * 2, 30)
  packLab.fontSize = 20
  packLab.text = '打包台  ␣'
  parts[#parts + 1] = pack
  parts[#parts + 1] = packLab

  say('控件已建：%d 个（含标题/状态行）', #parts + 2)
  -- ★ 逐个报位置/尺寸：屏幕上少了谁、歪在哪，靠这行对账。
  --   （"中央只有一个?" 这种描述没法靠猜——把每个控件的 pos/size 打出来就能对上号）
  --   ★★ 同时读回 imageId：屏幕上那些"?"到底是不是**我自己的底衬**，
  --   就看那 5 个方块控件的 imageId 是不是都等于我给的那个号（是的）→ 号无效的话"?"就是我的。
  for i = 1, #parts do
    local c = parts[i]
    local px, py, w, h = nil, nil, nil, nil
    pcall(function() px, py = c:GetAnchoredPosition() end)
    pcall(function() w, h = c:GetSizeDelta() end)
    local iid, ityp = nil, nil
    pcall(function() iid = c.imageId end)
    pcall(function() ityp = c.imageType end)
    say('  控件[%s] name=%s pos=(%s,%s) size=(%s,%s) imageId=%s imageType=%s',
        tostring(i), tostring(c.name), tostring(px), tostring(py), tostring(w), tostring(h),
        tostring(iid), tostring(ityp))
  end
  parts.built = true
end

local function tryBuild()
  if built then return end
  built = true
  local ok, e = pcall(build)
  if not ok then
    err = tostring(e)
    say('BUILD-FAILED %s', err)
    -- 出错时尽量把它写进那行状态字（如果控件已经建出来了）
    if parts.info then parts.info.text = '!! ' .. err end
  end
end

function OnInit()
  -- ★ 契约 1：这里**什么都不建**（Instantiate 在 OnInit 返回 nil）
  say('OnInit（只登记，不建控件）')
  -- ★ 契约 2：不打开就收不到 OnUpdate
  if script and script.EnableUpdate then
    local ok, e = pcall(function() script:EnableUpdate(true) end)
    say('EnableUpdate(true) -> %s', ok and 'ok' or tostring(e))
  else
    say('警告：没有 script.EnableUpdate，逐帧回调可能不会触发')
  end
end

function OnStart()
  say('OnStart —— 开始建控件')
  tryBuild()
end

function OnUpdate(dt)
  if not built then tryBuild() end          -- 兜底：万一某些版本不调 OnStart
  t = t + dt
  -- （素材号轮换实验已删除 —— 死代码也一并清掉，见 build 里的说明）
  if parts.info and not err then
    -- ★★ 这里**必须**用我们自己的 fmt，不能用 string.format：
    --   真机画布尺寸是浮点（1814.86 x 900.0），`string.format('%dx%d', …)` 在 Lua 5.3 会抛
    --   "number has no integer representation"，而且是在 OnUpdate 里 —— **每帧抛一次**，
    --   日志被刷爆、状态行永远停在"正在摆放工位…"（2026-09-26 真机实测）。
    --   fmt 只认 %s/%d 并一律 tostring，所以浮点也安全。
    parts.info.text = fmt('跑起来了 · %.1fs · 画布 %sx%s · 控件 %s 个', t, W, H, #parts + 2)
  end
end

function OnLevelUpdate(dt) end
function OnDestroy() end

return { OnInit = OnInit, OnStart = OnStart, OnUpdate = OnUpdate, OnLevelUpdate = OnLevelUpdate, OnDestroy = OnDestroy }
