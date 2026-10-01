-- state.lua —— 运行时状态（唯一的一份，谁都不许另开变量存游戏数据）
--
-- 为什么要单独一个模块：网页版吃过亏 —— "谁在制、谁排队"这类状态散在几个函数里各存一份，
-- 改了 A 忘了 B，表现就是"莫名其妙的重复小票/名额不释放"。
-- 千星版从第一天起：**所有游戏状态都挂在这一个表上**。

local CFG = require('config')

local S = {}

-- 一局的状态。newGame 时创建，之后所有模块都读写它。
function S.new(modeName)
  local m = CFG.mode(modeName)
  return {
    mode = m,
    -- 时间
    t = 0,                 -- 真实经过（秒）
    day = 1,
    dayLeft = m.perDay,
    totalLeft = m.total,
    flow = 1,
    idle = 0,
    phase = 'open',        -- open 营业中 | closing 打烊清场（耐心冻结）| done 收工
    lastCallDay = 0,       -- "最后接单"提示只在当天弹一次
    closingLeft = 0,
    settling = false,      -- 正在出当日结算页（防止每帧重复结算）
    settledDay = 0,        -- 已结算过哪一天（幂等闸）
    -- 内容
    orders = {},           -- 订单数组
    slips = {},            -- 小票数组（一杯一张）
    oid = 0,               -- 订单自增 id
    sid = 0,               -- 小票自增 id
    nextArrive = CFG.arrive.first,
    -- 账
    money = 0, rentPaid = 0, rentDebt = 0,
    served = 0, mistakes = 0, left = 0, leftWaiting = 0,
    score = 0, combo = 0, maxCombo = 0,
    today = { served = 0, money = 0, left = 0, mistakes = 0,
              eco = { fixed = 0, zwd = 0 } },   -- ★ 环保凭证的当日累加（固化量 + 已折好的津元；每天归零）
    dayStats = {},
    log = {},
    ended = false,
    autoMoves = 0,
  }
end

-- 今天还剩多少比例（打烊减速用）
function S.dayFrac(s)
  if s.mode.perDay <= 0 then return 1 end
  return math.max(0, math.min(1, s.dayLeft / s.mode.perDay))
end

-- 当前这一杯的"下一步"（每一步 ok=true 之后自动往后走；全做完返回 nil）
function S.nextStep(cup)
  for i = 1, #cup.steps do
    if not cup.steps[i].ok then return cup.steps[i], i end
  end
  return nil
end

-- 这一杯算不算"占着后厨名额"
--   ★ 口径（与原版一致，是 K.refreshSlots 的算法）：开工了（startedAt ~= nil）且没做完
--   ⚠️ noSlot（纯手感步骤，例：速溶咖啡前三步）**不占名额** —— 这是原版的设计意图：
--      一杯三步的咖啡不该和一杯十几下连按的干冰抢同一个名额。
--      但它**不能变成"绕过名额闸门"的通行证**：那条路我踩过 ——
--      beginWork 里 `if not freeStep then 检查名额 end` 让连续按兑茶键开出无限杯，
--      端到端测试实测在制峰值 7（上限 3）。现在用 S.wipGateCount 单独管闸门（见下）。
function S.cupWip(cup)
  if cup.made or cup.startedAt == nil then return false end
  local _, idx = S.nextStep(cup)
  local upto = idx or #cup.steps
  for k = 1, upto do
    if not cup.steps[k].noSlot then return true end
  end
  return false
end

-- ★★ 闸门口径：**在飞的杯** = 已开工（`startedAt ~= nil`）**或**已发到资格（`slotReady`，等着动手）。
--   为什么必须与 cupWip 分开：cupWip 允许 noSlot 的杯不占名额，
--   如果闸门也用它，就没有任何东西限制"同时开多少杯纯手感步骤的活" → 无上界。
--   为什么连 `slotReady` 也要算：refreshSlots 会**预发**资格给排队中的杯，
--   如果闸门不认这份预发，就会出现"3 个在制 + 3 个预发"→ 第 4 杯照样开工（实测过）。
--   有了它，`S.wipCount ≤ maxWip` 成了**真的不变量**（端到端测试盯着）。
function S.wipGateCount(s)
  local n = 0
  for _, o in ipairs(s.orders) do
    for _, c in ipairs(o.cups) do
      if not c.made and (c.startedAt ~= nil or c.slotReady) then n = n + 1 end
    end
  end
  return n
end

-- 现在有几个"未完成任务"在制
function S.wipCount(s)
  local n = 0
  for _, o in ipairs(s.orders) do
    for _, c in ipairs(o.cups) do if S.cupWip(c) then n = n + 1 end end
  end
  return n
end

return S
