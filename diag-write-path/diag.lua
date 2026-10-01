-- diag.lua —— 「真机上画面不更新」的写入链路诊断（诊断构建专用，平时不进包）
--
-- 一次真机部署要把三个假设切开：
--   A. 某次控件写入在**真机上报错**、被 pcall 吞掉，而 view 的缓存已经记成新值
--      ⇒ 之后每帧都认为"值没变"，画面永远停住（作者指出的头号嫌疑）
--   B. 缓存逻辑本身有问题（写入根本没成功却记成已写）
--   C. 启动阶段就抛错（bootErr）⇒ OnUpdate 每帧提前 return，键回调照旧（日志正常、画面全死）
--
-- 脚本变量（编辑器里定义才生效，没定义用默认值）：
--   diag=0        关掉诊断（默认开）
--   forceWrite=1  每帧无视缓存强制写一遍（模拟器作者给的排查技巧）
--
-- 输出全部 ASCII，便于在乱码日志里搜：
--   [WERR] tag=view.setStyle ctrl=StS_brew val=28 err=integer expected        ← 单次写入失败
--   [WERR-CACHE] tag=view.setText ctrl=StS_brew skipped=1 lastErr=...        ← 缓存把"上次写失败"当成了已显示
--   [WERR-SUM] kinds=2 hits=17 | view.setStyle@StS_brew x9 ; ...             ← 每 30 帧一行汇总
--   [BOOT] bootErr=<值>  或  [BOOT] ok
--   [SYNC] afterAct err=...                                                  ← afterAct 里被吞掉的错误
--
-- ⚠️ 本模块只做"观测"，不改任何玩法逻辑；线上一旦确认病因，请连同写入点的改动一起回退。

local D = {}

D.on = true
D.forceWrite = false
D.kinds = {}      -- key -> { tag, ctrl, val, err, n }
D.hits = 0
D.order = {}      -- 去重键的出现顺序
D.failed = {}     -- 控件 -> 最近一次失败的 err（成功则清除）★ 缓存投毒判据
D._lastSum = 0
D._booted = false

local function emit(s)
  if print then pcall(print, s) end
end

local function nameOf(c)
  if c == nil then return '-' end
  local ok, n = pcall(function() return c.name end)
  if ok and n ~= nil and tostring(n) ~= '' then return tostring(n) end
  return '<unnamed>'
end

local function valOf(v)
  if v == nil then return '-' end
  if type(v) == 'string' then
    if #v > 24 then return string.sub(v, 1, 24) .. '..' end
    return v
  end
  return tostring(v)
end

function D.setup(on, forceWrite)
  D.on = (on ~= false)
  D.forceWrite = (forceWrite == true)
  emit(string.format('[DIAG] on=%s forceWrite=%s', tostring(D.on), tostring(D.forceWrite)))
end

-- 记一次失败（同 tag+控件 只打第一行，其余计数，避免刷屏）
function D.note(tag, c, val, err)
  local ctrl = nameOf(c)
  local key = tag .. '|' .. ctrl
  local e = D.kinds[key]
  if e then
    e.n = e.n + 1
  else
    e = { tag = tag, ctrl = ctrl, val = valOf(val), err = tostring(err), n = 1 }
    D.kinds[key] = e
    D.order[#D.order + 1] = key
    emit(string.format('[WERR] tag=%s ctrl=%s val=%s err=%s', tag, ctrl, e.val, e.err))
  end
  D.hits = D.hits + 1
  D.failed[c] = e.err
end

-- ★ 写入点统一入口：**检查 pcall 的返回值**（原来没人看，真机报错完全不留痕）
function D.try(tag, c, val, fn)
  local ok, err = pcall(fn)
  if not ok then
    if D.on then D.note(tag, c, val, err) else D.failed[c] = tostring(err) end
    return false, err
  end
  D.failed[c] = nil          -- 这一次成功了 → 该控件不再处于"投毒"状态
  return true
end

-- 缓存命中但该控件上次写失败过 ⇒ 画面就是被这条卡住的（A 假设的直接证据）
function D.cacheSkip(tag, c, val)
  if not D.on then return end
  if D.failed[c] then
    local ctrl = nameOf(c)
    emit(string.format('[WERR-CACHE] tag=%s ctrl=%s skipped=1 val=%s lastErr=%s',
      tag, ctrl, valOf(val), tostring(D.failed[c])))
    D.hits = D.hits + 1
  end
end

function D.boot(errText)
  D._booted = true
  if errText == nil then emit('[BOOT] ok') else emit('[BOOT] bootErr=' .. tostring(errText)) end
end

function D.afterAct(errText)
  if errText ~= nil then emit('[SYNC] afterAct err=' .. tostring(errText)) end
end

-- 每 30 帧一行汇总（没有错误就不打）
function D.summary(frame)
  if not D.on then return end
  if D.hits == 0 then return end
  local f = frame or 0
  if (f - D._lastSum) < 30 then return end
  D._lastSum = f
  local top = {}
  for i = 1, math.min(#D.order, 4) do
    local e = D.kinds[D.order[i]]
    top[#top + 1] = string.format('%s@%s x%d', e.tag, e.ctrl, e.n)
  end
  emit(string.format('[WERR-SUM] kinds=%d hits=%d | %s', #D.order, D.hits, table.concat(top, ' ; ')))
end

return D
