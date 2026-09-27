-- game.lua —— 主循环与生命周期（这一层是逻辑层的主循环；真机入口是 hello.lua）
--
-- 三条真机契约（都在注释里写死，避免以后有人"顺手优化"回去）：
--   ① 建控件必须在 OnStart 及之后：`game.InstantiateClientUIControl` 在 **OnInit 返回 nil**
--      （网页版前身踩过：在 OnInit 建控件 → 全 nil → 连报错提示都建不出来 → 白屏且无提示）
--   ② 不调 `script:EnableUpdate(true)` 就**永远收不到 OnUpdate**（逐帧是命脉）
--   ③ `game` 的全局函数用**点号**调用（`game.GetUICanvasSize()`），冒号会多传隐式实参

local CFG = require('config')
local R = require('recipes')
local S = require('state')
local O = require('order')
local K = require('kitchen')
local D = require('day')

local G = {}

-- 不依赖控件的日志通道（诊断必须走 print，否则"控件建不出来"时什么都看不到）
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
local function say(...)
  local ok, line = pcall(fmt, ...)
  if not ok then line = tostring((...)) end
  if print then pcall(print, '[雪皇] ' .. line) end
end
G.say = say
G.fmt = fmt

G.BUILD = 'xuehuang-core 2026-09-26 c1'

-- 回调表：表现层 subscribe（这样逻辑层不认识 UI，反过来 UI 只收事件）
G.listeners = {}
function G.on(evt, fn) G.listeners[evt] = G.listeners[evt] or {}; table.insert(G.listeners[evt], fn) end
function G.emit(evt, payload)
  local l = G.listeners[evt]
  if not l then return end
  for _, fn in ipairs(l) do
    local ok, e = pcall(fn, payload)
    if not ok then say('监听 %s 出错：%s', evt, tostring(e)) end
  end
end

-- 开一局
function G.newGame(modeName)
  G.s = S.new(modeName or CFG.defaultMode)
  say('开新局：%s（%d 天 × %d 秒 = %d 秒，人数密度 ×%s）',
      G.s.mode.label, G.s.mode.days, G.s.mode.perDay, G.s.mode.total, tostring(G.s.mode.arriveScale))
  return G.s
end

-- 推进一步（表现层每帧调它；测试也能直接推）
--   dtReal：真实经过秒数
function G.tick(dtReal)
  local s = G.s
  if not s or s.ended then return end
  local ev = D.tick(s, dtReal)
  if ev then
    for _, e in ipairs(ev) do
      if e.kind == 'arrive' then
        say('%s 要 %s %s %s', e.o.name, e.o.makeup, e.o.ice, e.o.sugar)
      elseif e.kind == 'leave' then
        say('%s 走了（耐心耗尽）', e.o.name)
      elseif e.kind == 'lastcall' then
        say('最后接单：之后不再放人进来，手上的做完就收摊')
      elseif e.kind == 'closing' then
        say('打烊：不再接待新顾客')
      elseif e.kind == 'graceout' then
        say('清场宽限期到：已经动过手的单算交付，没开工的记流失')
      end
      G.emit(e.kind, e)
    end
  end
end

-- 玩家动作：在某工位按一下
--   返回 { ok=bool, why=string, done=bool }
--
--   opt.route（默认 false）：**票不在这个工位时，先把票送过来**再动手。
--     ★ 为什么需要（真机日志：9085 条 [LOGIC] 里 8984 条 ok=false）：
--       玩家的操作顺序是"按下工位键"，而票经常还在别的工位/还没挂工位。
--       没有这一项时，按键 99% 什么都发生不了 → 玩家判定"快捷键坏了"。
--       等价于原版"点小票立刻送过去"（网页版 forwardSlip）——**不改变任何规则**，
--       只是把玩家原本要点两次的操作做成一次。翻车判定（票该去别的工位）仍然保留。
--     ⚠️ 有 opt.route 也**不会**抢别的工位的活：只会把"下一步就是这个工位"的票送过来，
--        该去别的工位的票照样拒绝（否则 shake 键能把 chem 的活抢走，规则就错了）。
function G.act(stationId, kind, slipId, opt)
  local s = G.s
  if not s or s.ended then return { ok = false, why = '还没开门' } end
  opt = opt or {}
  -- 找出这个工位上"能动的那张票"（优先指定 id，否则队列里第一张能做的）
  local function workable(sl)
    local nx = S.nextStep(sl.cup)
    if stationId == 'pack' then return sl.ready or (nx and nx.st == 'pack') end
    return (not sl.ready) and nx ~= nil and nx.st == stationId
  end
  local sl
  if slipId then
    for _, x in ipairs(s.slips) do if x.id == slipId and workable(x) then sl = x end end
  end
  if not sl then for _, x in ipairs(s.slips) do if workable(x) then sl = x; break end end end
  -- ★ 票不在这个工位 → 把"下一步就是这个工位"的票先送过来（还原原版"点小票立刻送过去"）
  --   挑票顺序：**按耐心从低到高**（快没耐心的先做），同耐心按票号。
  --   只挑"下一步 == 本工位"的；没名额的票会被 routeSlip 挡下（名额规则不变）。
  if not sl and opt.route then
    local cands = {}
    for _, x in ipairs(s.slips or {}) do
      local nx2 = S.nextStep(x.cup)
      local want = (stationId == 'pack') and x.ready or ((not x.ready) and nx2 ~= nil and nx2.st == stationId)
      if want and x.st ~= stationId then cands[#cands + 1] = x end
    end
    table.sort(cands, function(a, b)
      local pa = (a.o and a.o.pat) or 1e9
      local pb = (b.o and b.o.pat) or 1e9
      if pa == pb then return a.id < b.id end
      return pa < pb
    end)
    for _, x in ipairs(cands) do
      if K.forwardSlip(s, x, true) and workable(x) then sl = x; break end
    end
  end
  if not sl then
    -- ★ REJECT 探针（纯 ASCII，真机可 grep）：把"为什么这个工位没活"一次说清 ——
    --   列出每张票的 (票号, ready?, 下一步工位)。用来区分：
    --     ① 根本没有票（杯子还没拿到在制名额）  ② 票的下一步不是这个工位  ③ 票已 ready 等打包
    --   ⚠️ 上一版这个探针插在别处、源文件里那句有空格差异 → 没进去（白查一轮）
    if print then
      local parts = {}
      for _, x in ipairs(s.slips or {}) do
        local nx2 = S.nextStep(x.cup)
        parts[#parts + 1] = string.format('#%s:%s:%s', tostring(x.id),
          x.ready and 'ready' or 'open', nx2 and tostring(nx2.st) or 'nil')
      end
      pcall(print, string.format('[REJECT] want=%s slips=%d [%s] orders=%d served=%d',
        tostring(stationId), #(s.slips or {}), table.concat(parts, ' '), #(s.orders or {}), s.served or 0))
    end
    return { ok = false, why = '这个工位暂时没有能做的小票' }
  end

  local nx = S.nextStep(sl.cup)
  if stationId == 'pack' and sl.ready then
    local okk, why = K.deliverCup(s, sl)
    return { ok = okk, why = why }
  end
  if not nx then return { ok = false, why = '这杯已经做完了，送打包台' } end
  if nx.st ~= stationId then
    K.doWrong(s, sl.cup, stationId)
    return { ok = false, why = string.format('翻车！%s 做不了「%s」', stationId, nx.t) }
  end
  if kind == 'release' then nx.holdOn = false; return { ok = true } end
  local r = K.pressStep(s, sl)
  return { ok = true, done = r.done, step = r.step }
end

-- 玩家动作：点手册起杯（关掉自动出票后才有用）
function G.startCup(recId)
  local rec = R.byId(recId)
  if not rec then return { ok = false, why = '没有这个产品' } end
  local okk, why = K.startCup(G.s, rec)
  return { ok = okk, why = why }
end

-- 表现层在结算页按"继续"时调
function G.nextDay()
  if not G.s then return end
  if G.s.ended then return end
  D.nextDay(G.s)
  G.emit('daystart', { day = G.s.day })
end

return G
