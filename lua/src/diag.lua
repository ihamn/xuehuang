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

-- ★★ 这条 emit 自己**不许静默失败**（2026-10-01 本地实测踩到）：
--   诊断的全部价值 = "失败留痕"，而它自己的 `pcall(print, s)` 第一版就是把失败吞掉的 ——
--   本地跑出来 [WERR-SUM] 里数到了 view.setText@HudTip，可那一行 [WERR] 本体**根本没出现**。
--   ⇒ 打印失败就退化成"只留 ASCII"再打一次：宁可信息少，绝不让一条 [WERR] 消失。
local function emit(s)
  if not print then return end
  local ok = pcall(print, s)
  if ok then return end
  local ascii = string.gsub(s, '[\128-\255]', '?')
  pcall(print, ascii)
  pcall(print, '[WERR-EMIT] raw-print failed; ascii-only above')
end

local function nameOf(c)
  if c == nil then return '-' end
  local ok, n = pcall(function() return c.name end)
  if ok and n ~= nil and tostring(n) ~= '' then return tostring(n) end
  return '<unnamed>'
end

-- 截断**必须落在 UTF-8 字符边界上**：日志通道按 UTF-8 解字符串，切出半个汉字 = 非法字节。
local function cut(s, n)
  if #s <= n then return s end
  local i = n
  while i > 0 do
    local b = string.byte(s, i + 1)
    if not (b and b >= 128 and b < 192) then break end   -- 128~191 = 多字节的后续字节
    i = i - 1
  end
  return string.sub(s, 1, i) .. '..'
end

local function valOf(v)
  if v == nil then return '-' end
  if type(v) == 'string' then return cut(v, 24) end
  return tostring(v)
end

-- ★ 本诊断构建的标签（ASCII）：用来在关卡存档/日志里一眼认出"跑的是诊断版"，
--   和 BUILD=xuehuang-r3 区分开（旧 r3 产物没有这一行）。改这行不影响任何行为。
local DIAG_TAG = 'xuehuang-diag-w1'

function D.setup(on, forceWrite)
  D.on = (on ~= false)
  D.forceWrite = (forceWrite == true)
  emit(string.format('[DIAG] tag=%s on=%s forceWrite=%s', DIAG_TAG, tostring(D.on), tostring(D.forceWrite)))
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
