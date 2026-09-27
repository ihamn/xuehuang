-- @entry
-- xuehuang.lua —— 雪皇的后厨 · 千星客户端脚本入口（正式版）
--
-- 这一层只做四件事：
--   ① 生命周期接线（OnInit / OnStart / OnUpdate）
--   ② 状态机：菜单 → 营业 → 当日结算 → 总分 → 重开
--   ③ 输入路由（按键 + 光标点击 → 逻辑层动作 / 界面操作）
--   ④ 把逻辑层的事件变成提示文案
-- ★ 它**不含任何玩法规则**：规则全在 kitchen/order/day 里，改规则不要改这个文件。
--
-- 平台契约（踩过的坑，别改回去）：
--   · 建控件必须在 OnStart 及之后（InstantiateClientUIControl 在 OnInit 返回 nil）
--   · 必须 script:EnableUpdate(true)，否则收不到 OnUpdate
--   · game 的全局函数用点号调用；新建控件默认"纯白 + 可见"→ 建完立刻设色或隐藏
--   · 光标点击要先 showCursor=true（host.lua 已设），且需要一个"光标检测区域"控件

local H = require('host')
local G = require('game')
local V = require('view')
local IN = require('input')
local CFG = require('config')

local BUILD = 'xuehuang-r3'   -- 纯 ASCII，方便在日志里搜（r3 = 出餐双键 + 按键探针 + 名额硬上界）

local built, bootErr = false, nil
local _tickErrShown = false
local v, hostCfg = nil, nil
local banner, bannerT, _bannerActive = nil, 0, false
-- ★ showCounts **默认关**：HUD 上不该出现调试尾巴（要看就在脚本变量里设 showCounts=1）
local autoplay, heartbeat, showCounts = false, false, false
-- ★ 有菜单（原版 showStart 就是选模式界面）：scene = 'menu' | 'play'
local menuMode = 2          -- 菜单上选中的模式（1..3）；★ 默认 2 = 原版默认的「标准」fast
local scene = 'menu'
local paused = false        -- 暂停（原版 Esc；平台无 Esc 语义键 → 营业中用 3 切换）

local function say(...) H.say('雪皇', ...) end

local function tip(msg, sec)
  banner, bannerT = tostring(msg), (sec or 2.0)
  _bannerActive = true
  if v then V.setBanner(v, banner) end
end

-- ── 逻辑事件 → 提示 ──
local function wireEvents()
  G.on('arrive', function(e) tip(string.format('%s 要 %s %s %s', e.o.name, e.o.makeup, e.o.ice, e.o.sugar), 2.2) end)
  G.on('leave',  function(e) tip(string.format('%s 等不及走了', e.o.name), 2.2) end)
  G.on('lastcall', function() tip('最后接单：之后不再放人进来', 3) end)
  G.on('closing',  function() tip('打烊：不再接待新顾客，手上的做完就收摊', 3) end)
  G.on('graceout', function() tip('清场时间到：动过手的算交付，没开工的记流失', 3) end)
  G.on('dayend',   function(e) tip(string.format('第 %d 天结算', e.day), 3) end)
end

-- ── 状态机 ──
-- ★ 菜单 = 原版 showStart 的选模式界面（用户指出我漏了它）。
--   ⚠️ 用户要求"删掉按空格开始的逻辑"指的**不是菜单**，而是别的地方；
--      原版确实是"选完模式 → 开门营业 → 进游戏"，所以菜单保留。
local function enterMenu()
  scene = 'menu'
  pcall(function() require('input').clearInput() end)
  if v then
    V.setBoardVisible(v, false)
    V.setMenuVisible(v, true)
    V.setBanner(v, nil)
  end
end

-- ★★ 三个模式**全部可玩**（2026-09-27 还原度修正）。
--   原版（网页版 391-395 行）quick/fast/slow 都是单人局，days=1/5/5、总时长 300/600/1200 秒，
--   移植版却把 fast/slow 标成"施工中（多人相关）"锁掉了 —— 那是我自己加的闸，
--   代码里没有任何依据，而且直接砍掉了原版的**主玩法（5 天日循环）**。
--   现在恢复：三个模式都能进，菜单上不再有"施工中"。
local DEFAULT_MODE = 'fast'       -- 与 menuMode 的默认值一致
local MODE_ORDER = { 'quick', 'fast', 'slow' }

-- 工位动作 → 中文名（提示文案用；键位映射的唯一真相仍在 input.lua 的 IN.BIND）
local STATION_ACT = { shake = '捣锤', fire = '火系', chem = '化学', brew = '萃茶', pack = '打包' }

local function startGame()
  local m = IN.MODES[menuMode] or DEFAULT_MODE
  G.newGame(m)
  scene = 'play'
  paused = false
  pcall(function() require('input').clearInput() end)
  if v then
    local n = V.setBoardVisible(v, true)
    V.setMenuVisible(v, false)    -- 玩区排满了，收起菜单资料面板
    V.hideBig(v)                  -- 收起大字
    say('开局：模式=%s，显示玩区 %d 个控件', m, n)
  end
  tip('开张！按 Y/H/K/P 做工位，空格打包', 3.5)
end

-- 菜单/结算页的按键消费；返回 true = 已消费
--   · 菜单：1/2/3 选模式（三个都能玩），确认键 / 点屏幕 = 开门营业
--   · 结算中（一天的账）→ 确认键 = 进入下一天
--   · 整局结束（总分页）→ 确认键 = 回菜单再选一局
local function uiAct(act)
  if scene == 'menu' then
    -- 1/2/3 选模式（与原版 showStart 的模式卡片一一对应）
    local mi = ({ mode1 = 1, mode2 = 2, mode3 = 3 })[act]
    if mi then
      menuMode = mi
      local mk = IN.MODES[mi]
      V.drawMenu(v, menuMode)
      tip(string.format('已选：%s —— 点「开门营业」开始', tostring(mk)), 2.5)
      return true
    end
    -- ★ 开局方式（用户要求）：菜单里**空格不触发开门**；点屏幕 = 原版「开门营业」按钮
    --   键盘后备 = 确认键（Backspace；43 个奇匠按键里没有回车）
    if act == 'confirm' or act == 'click' then startGame(); return true end
    return false
  end
  if G.s and (G.s.settling or G.s.ended) and (act == 'confirm' or act == 'pack') then
    if G.s.ended then
      say('整局结束 → 回菜单')
      enterMenu()
    else
      G.nextDay()
    end
    return true
  end
  return false
end

local function boot()
  if built then return end
  built = true
  local ok, err = pcall(function()
    local root = H.root()
    if not root then error('找不到挂载控件：脚本要挂在**客户端控件容器**上') end
    pcall(function() root:SetActive(true) end)
    hostCfg = H.setup(root)
    v = V.init(hostCfg)
    autoplay   = tonumber(tostring(H.param('autoplay', 0))) ~= 0
    heartbeat  = tonumber(tostring(H.param('heartbeat', 0))) ~= 0
    showCounts = tonumber(tostring(H.param('showCounts', 0))) ~= 0
    if autoplay then say('autoplay=1：机器人替玩家打（本地出图用）') end
    wireEvents()
    IN.attach(hostCfg, tip)
    -- ★★ 键盘路径改成"帧内处理"（2026-09-27 用户口径，第三次修正）：
    --   用户原话：「某个工作区出现了 xxx 任务，点按键，**哪怕日志正常，客户端那依旧不会显示
    --   这个任务有任何变化**；而鼠标去点那个任务，就会正常加进度完成任务。」
    --   鼠标点击跑在引擎 UI/帧上下文里 → 引擎当场重绘；键盘回调跑在帧外的输入上下文里 →
    --   在那里写控件属性，真机上不重绘（逻辑变了、屏幕不动）。
    --   ⇒ forceQueue = true：键回调只登记，真正的处理 + 刷画面都在**下一个 OnUpdate 帧内**，
    --     让键盘路径与鼠标路径在引擎看来完全同类。
    --   （本地要临时验证"回调直呼"旧行为，把这里改成 false 即可。）
    IN.forceQueue = true
    -- ★ 按键探针默认开：按一下键就会在日志里留下 [KDOWN X] 一行（keyLog=0 可关）。
    --   注意：H.param 拿到的是**编辑器里定义的值**，编辑器没定义才用默认值 ——
    --   所以诊断不能依赖"我在编辑器里设了开关"，见下面每秒状态行的注释。
    IN.logKey(tonumber(tostring(H.param('keyLog', 1))) ~= 0)
    -- ★ 光标检测区域铺满画布（默认 0×0 → 点不中；见 input.lua 的 ensureAreaSize）
    do
      local area = IN.findArea(hostCfg.root)
      if area then
        -- ★ 兼容：旧版有 IN.ensureAreaSize，重写后它并入了 attach；
        --   这里用 pcall + 直调 SetSizeDelta，**绝不能再让 boot 抛错**
        --   （boot 抛错 → bootErr 设置 → 之后每帧 return → 全游戏卡死，这是真机"点一次也没反应"的根因）
        local okA = pcall(function() area:SetSizeDelta(hostCfg.spaceW or 1920, hostCfg.spaceH or 1080) end)
        say('光标检测区域已铺满 %sx%s -> %s', tostring(hostCfg.spaceW), tostring(hostCfg.spaceH), okA and 'ok' or '失败')
      else
        say('警告：控件树里没有"光标检测区域"，鼠标点击不可用（菜单将只能靠键盘）')
      end
    end
    -- ★ 先停在菜单（原版 showStart）——点「开门营业」或按确认键才开局
    scene = 'menu'
    V.setBoardVisible(v, false)
    V.setMenuVisible(v, true)
    V.drawMenu(v, menuMode)
    say('已就绪 BUILD=%s —— 菜单（按 1/2/3 选模式 → 点屏幕开门营业）', BUILD)
    tip(string.format('BUILD=%s  菜单：按 1/2/3 选模式 → 开门营业', BUILD), 6)
  end)
  if not ok then
    bootErr = tostring(err)
    say('BUILD-FAILED %s', bootErr)
    pcall(function() if v then V.setBanner(v, 'BOOT-ERR ' .. bootErr) end end)
  end
end

function OnInit()
  say('OnInit（只登记，不建控件）')
  if script and script.EnableUpdate then
    local ok, e = pcall(function() script:EnableUpdate(true) end)
    say('EnableUpdate(true) -> %s', ok and 'ok' or tostring(e))
  end
end

function OnStart() boot() end

local _heart = 0
function OnUpdate(dt)
  _heart = _heart + 1
  if heartbeat and _heart % 60 == 0 then
    say('心跳 %d 帧 · 场景=%s · t=%s', _heart, tostring(scene),
        G.s and string.format('%.1f', G.s.t) or 'nil')
  end
  if not built then boot() end
  if bootErr then return end
  local dt2 = dt or 0.033

  -- ① 逻辑推进（结算页/总分时冻结；暂停时不推进）
  if scene == 'play' and not paused and G.s and not G.s.settling and not G.s.ended then
    local ok, err = pcall(function() G.tick(dt2) end)
    if not ok then
      -- ★★ 逻辑出错**不再永久卡死**（旧版设置 bootErr → 之后每帧直接 return →
      --   玩家看到的就是"按键/点击全都没反应"）。现在：记日志 + 报一次横幅，但**继续跑**。
      say('tick 出错（已忽略，继续运行）：%s', tostring(err))
      if v and not _tickErrShown then
        _tickErrShown = true
        pcall(function() V.setBanner(v, '逻辑错误：' .. tostring(err)) end)
      end
    end
  end

  -- ② 自动演示（只在脚本变量 autoplay=1 时）
  --   ★ autoplay 也要**自己开门**：默认停在菜单（等玩家点"开门营业"），
  --     而本地出图/回归没有鼠标 → 不放行的话截图永远停在菜单上（我踩过这个坑）。
  if autoplay then
    pcall(function()
      if scene == 'menu' then startGame() end
    end)
  end
  if autoplay and scene == 'play' then
    pcall(function()
      if G.s and G.s.settling then G.nextDay()
      elseif G.s and not G.s.ended then __bot() end
    end)
  end

  -- ③ 输入：界面层优先，剩下的给玩法
  IN.frameDt = dt2
  IN.pump({
    tip = tip,
    -- ★★ 动作处理完**立刻刷画面**（键盘路径的命门）
    --   用户的原始描述：「某个工作区出现了任务，按按键哪怕日志正常，客户端那依旧不会显示
    --   这个任务有任何变化；而拿鼠标去点那个任务，就会正常加进度完成任务。」
    --   两条路都调 G.act（逻辑一样），差别在**谁在之后把画面刷了**：
    --     · 鼠标：click 分支跑在 OnUpdate 的 pump 里 → 紧接着当帧 V.sync 就跑 → 画面立刻变
    --     · 键盘：回调是**引擎直接调进来**的，跑在 OnUpdate 之外（帧与帧之间）→ 自己不刷画面
    --   所以键盘路径必须"自己把画面刷了"，不能只等下一帧。
    --   ⚠️ 只读 s 刷画面，不推进逻辑 → 不会"一次按键走两步"。
    afterAct = function()
      if not v then return end
      pcall(V.sync, v, G.s)
      -- 玩区/菜单显隐也按当前场景对齐（与 OnUpdate 里同一套，幂等）
      V.setBoardVisible(v, scene == 'play')
      V.setMenuVisible(v, scene ~= 'play')
    end,
    act = function(act, kind)
      -- ★ 出餐有两个键（空格 + Z）：语义归一成 pack，后面只认一个名字。
      --   为什么需要备用键：真机日志里玩家 23 次按键中**空格一次都没按过**，
      --   而空格在千星是"跳跃/滑翔"事件，可能收不到（详见 input.lua 的 BIND 注释）。
      if act == 'pack2' then act = 'pack' end
      -- ★★ 鼠标点击：**必须在这里拦**（在玩法命中测试之前）
      if act == 'click' then
        -- ★ 顺序（关键）：**菜单/结算页先处理点击**，再轮到玩区的命中测试。
        --   踩坑记录：原来 click 分支无条件 return（提前退出），而"菜单点任意处开门"
        --   的逻辑在 uiAct 里 → 菜单永远收不到点击 → 卡在菜单进不去游戏。
        if uiAct('click') then return nil end
        if not v then IN.clearClick(); return nil end
        local I2 = require('input')
        local ck = I2.clicked
        local hitId = nil
        for _, st in ipairs(V.STATIONS) do
          local slot = v.stations[st.id]
          if slot and IN.hit(v, slot.box, 10) then hitId = st.id break end
        end
        if not hitId and IN.hit(v, v.pack.box, 10) then hitId = 'pack' end
        if ck then
          say('鼠标点击 (%d,%d) → 命中 %s', math.floor(ck.x), math.floor(ck.y), tostring(hitId or '空处'))
        end
        I2.clearClick()
        -- ★★ 点工位卡 = 按那个工位键（原版 doStationAction(btn,'press')）
        --   G.act 带 opt.route：票不在这个工位时**自动把"下一步就是这个工位"的票送过来**
        --   再动手 —— 所以点工位卡和按工位键**行为完全一致**，一定会有回应。
        if hitId then return G.act(hitId, 'press', nil, { route = true }) end
        -- ★ 小票卡的点选交互**已删除**（用户 2026-09-27 决定：小票只当后台数据，不参与操作）。
        --   原来这里有"点小票 = 送它去该去的工位"，它带来一个额外失败模式：
        --   玩家看到票上的字、以为点它就等于做工位，于是反复点、画面却只挪票不推进。
        --   现在所有操作都只在**工位卡**上发生（点它 / 按对应键），一张票都不需要搬。
        return nil
      end
      -- ★★ 界面层优先（菜单选模式 / 开门 / 结算继续）
      if uiAct(act) then return nil end
      -- ★ 营业中的开关：1/2/3 = 自动流转 / 自动出票 / 暂停（原版 A/S/Esc）
      if act == 'mode1' then
        if kind ~= 'release' then
          CFG.auto.on = not CFG.auto.on
          tip(CFG.auto.on and '自动流转：开（小票自己走）' or '自动流转：关（要你亲手点小票送）', 2.2)
        end
        return nil
      end
      if act == 'mode2' then
        if kind ~= 'release' then
          CFG.autoTicket.on = not CFG.autoTicket.on
          tip(CFG.autoTicket.on and '自动出票：开' or '自动出票：关（要手动起杯）', 2.2)
        end
        return nil
      end
      if act == 'mode3' then
        if kind ~= 'release' then
          paused = not paused
          tip(paused and '已暂停（再按 3 继续）' or '继续营业', 2.2)
        end
        return nil
      end
      if act == 'confirm' then return nil end

      -- ★★ 四个工位键 + 空格：走玩法层，**带自动送票**（opt.route）。
      --   这就是"按下去永远有回应"的那一环：票不在工位 → 先把票送过来，再动手。
      --   结果一律有可见反馈（成功/翻车/没活），不再有静默失败。
      if kind ~= 'release' and STATION_ACT[act] then
        local nm = STATION_ACT[act]
        -- ★★ 支路取证（2026-09-27）：把"这次按键实际命中的步骤种类 + oneTap 开关的值"打出来。
        --   为什么必须打：源码里 oneTap 明明是 true、部署链路的 sha 也对，
        --   但真机 480 次采样 hold 仍是 0.0 ⇒ 必须确定运行时到底看的哪个值、走的哪个分支。
        do
          local S3 = require('state')
          local nx = nil
          for _, sl in ipairs(G.s and G.s.slips or {}) do
            local q = S3.nextStep(sl.cup)
            if q and q.st == act then nx = q break end
          end
          if print then
            pcall(print, string.format('[BRANCH] %s kind=%s oneTap=%s done=%.3f sec=%s',
              tostring(act), nx and tostring(nx.kind) or 'none',
              tostring(CFG.hold and CFG.hold.oneTap), nx and (nx.done or 0) or -1,
              tostring(CFG.hold and CFG.hold.sec)))
          end
        end
        local r = G.act(act, kind, nil, { route = true })
        if r and r.ok then
          local step = r.step
          say('%s → %s（%s）', nm, tostring(r.after or 0),
              step and tostring(step.t) or '')
          if step and step.kind == 'mash' then
            tip(string.format('%s：连按 %d/%d', nm, math.floor(r.after or 0), step.taps or 1), 1.6)
          elseif step and step.kind == 'hold' then
            tip(string.format('%s：按住不放 %.1f/%.1f 秒', nm, r.after or 0,
                (CFG.hold and CFG.hold.sec) or 0.9), 1.8)
          elseif r.done then
            tip(string.format('OK %s：这一步完成', nm), 1.8)
          else
            tip(string.format('OK %s 推进中', nm), 1.4)
          end
        else
          say('%s 没活：%s', nm, tostring(r and r.why))
          tip(string.format('× %s：%s', nm, tostring(r and r.why or '现在做不了')), 2.4)
        end
        return r
      end
      if kind == 'release' and STATION_ACT[act] then
        return G.act(act, kind)          -- 松手：按住类停下（原版 doStationAction(btn,'release')）
      end
      return nil
    end,
  })

  -- ④ 画面
  local okSync, errSync = pcall(V.sync, v, G.s)
  if not okSync then say('V.sync 出错：%s', tostring(errSync)) end
  -- ★ 玩区显隐：**每帧按 scene 对齐**（幂等，先设后不设）。
  --   为什么不用"切换时调一次"：实测那次调用会被后续逻辑推翻（14 个控件设成显示、
  --   下一帧又变回隐藏），查不出是谁干的。每帧对齐是"单一数据源"，不会再打架。
  if v then
    V.setBoardVisible(v, scene == 'play')
    -- ★ 菜单资料面板（营业数据/产品手册/快捷键）：**只有菜单态显示**
    --   （用户反馈"初始界面忘记把产品菜单以及其他的隐藏了"）
    V.setMenuVisible(v, scene ~= 'play')
  end

  -- ★ 常显诊断尾巴：**默认关**（HUD 上不该出现调试字样）
  --   ⚠️ 曾经写成 H.setText(c, c.text .. '…') 每帧追加 → 那行几秒涨到几千字，
  --      表现就是"文字乱掉/看不见"。这是本节最经典的坑。
  --   ★ 拼的时候必须用**本帧 view 写的原文**（V.sync 存在 v.hudTips 里），
  --     不能读 `v.hud.tip.text` 再追加 —— 那会每帧自追加、无限膨胀。
  if v and v.hud and v.hud.tip then
    local extra = ''
    if showCounts then extra = extra .. '   |   ' .. __counts() end
    if extra ~= '' then
      local base = v.hudTips or ''
      H.setText(v.hud.tip, tostring(base) .. extra)
    end
  end
  -- ★★ 结算/总分页：**只在"s.settling 或 s.ended"且"确实在玩"时才画**。
  --   ① 我一度误读截图，以为"开局就显示收摊" —— 用户澄清：**那是最后才出现的**，位置对。
  --   ② 真正的问题是：**结算页没盖住后面的玩区**（工位卡还看得见，糊在一起）。
  --      → 结算时必须【藏玩区 + 把打底提到最上】，让结算页独占画面。
  --      用 V.showResultSheet 统一处理（幂等：只在状态变化时动控件，不每帧翻）。
  if scene == 'menu' then
    local okM, errM = pcall(V.drawMenu, v, menuMode)
    if not okM then say('V.drawMenu 出错：%s', tostring(errM)) end
  end
  local showResult = (scene == 'play') and G.s and (G.s.settling or G.s.ended)
  if showResult then
    if v then V.showResultSheet(v, true) end
    local okR, errR = pcall(V.drawResult, v, G.s)
    if not okR then say('V.drawResult 出错：%s', tostring(errR)) end
  elseif scene == 'play' and v then
    V.showResultSheet(v, false)   -- 回到玩区：玩区恢复、打底回到底层
    V.hideBig(v)
  end

  -- ★★ 状态行：进游戏后**默认每秒打一行**（纯 ASCII），把"画面显示"和"逻辑状态"钉在同一行上。
  --   为什么不再用脚本变量开关：`H.param` 取的是**编辑器里定义的值**，编辑器里定义成 0
  --   就会把默认值覆盖掉 → "我打开了诊断开关"在真机上无法保证（这是我踩过的坑）。
  --   一行只有 ~120 字节，100 秒也才 100 行，值得常驻。
  if scene == 'play' and G.s then
    _tick = (_tick or 0) + 1
    -- stateEvery=1 → 每帧都打（本地"逐帧对齐"测试用）；默认每 30 帧（≈1 秒）
    local every = (tonumber(tostring(H.param('stateEvery', 0))) ~= 0) and 1 or 30
    if _tick % every == 0 then
      local okL, line = pcall(V.stateLine, G.s)
      if okL and line then
        -- ★ 走 IN.stateLog：**不受 keyLog 开关影响**（踩过：keyLog=0 顺手关掉了状态行）
        if IN.stateLog then IN.stateLog(line) elseif print then pcall(print, line) end
      else
        say('stateLine 出错：%s', tostring(line))
      end
    end
  end

  -- ⑤ 提示计时（放在最后）：横幅到点就收
  if bannerT > 0 then
    bannerT = bannerT - dt2
    if bannerT <= 0 then
      _bannerActive = false
      if v then V.setBanner(v, nil) end
    end
  end
end

function OnLevelUpdate(dt) end
function OnDestroy() end

-- ── 外部调用入口（script:Invoke）＋ 自检 ──
function __state()
  local s = G.s
  if not s then return 'no-game' end
  return H.fmt('scene=%s t=%.1f day=%d/%d phase=%s orders=%d slips=%d served=%d money=%d ended=%s',
    tostring(scene), s.t, s.day, s.mode.days, s.phase, #s.orders, #s.slips, s.served, s.money, tostring(s.ended))
end
function __act(stationId, kind)
  local r = G.act(tostring(stationId), tostring(kind or 'press'))
  return (r and r.ok) and 'ok' or ('no: ' .. tostring(r and r.why))
end
function __bot()
  local K = require('kitchen'); local S = require('state')
  local s = G.s
  if not s or s.ended then return 'done' end
  if s.settling then G.nextDay(); return 'nextday' end
  for _, sl in ipairs(s.slips) do
    if sl.ready then K.deliverCup(s, sl); return 'pack' end
    local nx = S.nextStep(sl.cup)
    if nx then
      if sl.st ~= nx.st then K.routeSlip(s, sl, nx.st) end
      if nx.kind == 'hold' then nx.holdOn = true; K.tickHolds(s, 0.05) else K.pressStep(s, sl) end
      return 'work'
    end
  end
  for _, o in ipairs(s.orders) do for _, c in ipairs(o.cups) do
    if not c.made and K.slipFor(s, c) == nil and c.slotReady then G.startCup(c.rec.id); return 'start' end
  end end
  return 'idle'
end
function __counts()
  local imgOn, imgAll, txtOn, txtAll = 0, 0, 0, 0
  local function walk(c, depth)
    if not c or depth > 3 then return end
    local t = H.kindOf(c)
    local on = false
    pcall(function() on = (c.active ~= false) and (c.visible ~= false) end)
    if t:find('Image', 1, true) then imgAll = imgAll + 1; if on then imgOn = imgOn + 1 end end
    if t:find('TextBox', 1, true) then txtAll = txtAll + 1; if on then txtOn = txtOn + 1 end end
    local ok, kids = pcall(function() return c:GetChildren() end)
    if ok and type(kids) == 'table' then for i = 1, #kids do walk(kids[i], depth + 1) end end
  end
  if hostCfg and hostCfg.root then walk(hostCfg.root, 0) end
  return string.format('IMG %d/%d  TXT %d/%d', imgOn, imgAll, txtOn, txtAll)
end
-- 自检：把每个方块的 active/visible 报出来（排查"方块没显示"这类问题）
function __diag()
  local out = {}
  local function st(c, tag)
    if not c then out[#out + 1] = tag .. '=nil'; return end
    local a, vis = '?', '?'
    pcall(function() a = tostring(c.active) end)
    pcall(function() vis = tostring(c.visible) end)
    out[#out + 1] = string.format('%s(%s,%s)', tag, a, vis)
  end
  if v then
    for _, sid in ipairs({ 'shake', 'fire', 'chem', 'brew' }) do
      local slot = v.stations[sid]
      if slot then
        st(slot.lay.box, 'box_' .. sid)
        st(slot.lay.panel, 'pnl_' .. sid)
      end
    end
    st(v.pack.box, 'pack')
    st(v.hud.bar, 'hud')
    st(v.backdrop, 'bg')
  end
  local txt = 'DBG scene=' .. tostring(scene) .. ' ' .. table.concat(out, ' ')
  if v then V.setBanner(v, txt) end
  return txt
end
function __menu(m)
  if m then menuMode = math.max(1, math.min(3, tonumber(m) or 1)) end
  if scene == 'menu' and v then V.drawMenu(v, menuMode) end
  return 'mode=' .. tostring(IN.MODES[menuMode]) .. ' scene=' .. tostring(scene)
end

return { OnInit = OnInit, OnStart = OnStart, OnUpdate = OnUpdate,
         OnLevelUpdate = OnLevelUpdate, OnDestroy = OnDestroy,
         __state = __state, __act = __act, __bot = __bot, __counts = __counts, __menu = __menu, __diag = __diag }
