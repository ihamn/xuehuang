-- day.lua —— 时间推进 / 到店 / 打烊清场 / 每日结算
--
-- 这里有三条**用真机日志和玩家反馈换来的**规则：
--   ① 到店间隔逐日收紧，且收尾会**越来越稀**（到点直接不放人）—— "快结束时人来的几率减小"
--   ② 打烊后进入清场：**耐心冻结**，让玩家把手上的做完
--      （反例：网页版打烊后耐心还在掉 → 客人走到一半没了 → 玩家觉得"打烊后什么都干不了"）
--   ③ 结算**幂等**：一天只结一次账
--      （反例：网页版每帧重复结算 → 房租被反复扣、欠租几秒滚成几千）

local CFG = require('config')
local R = require('recipes')
local S = require('state')
local O = require('order')
local K = require('kitchen')

local D = {}

local function pickWeighted(tbl, u) return R.pickWeighted(tbl, u) end

-- 时间流速：积压 → 慢，空闲 → 快；均值 ≈ 1（总时长仍锁在 days × perDay）
local function updateFlow(s, dtReal)
  local backlog = 0
  for _, sl in ipairs(s.slips) do if not sl.ready then backlog = backlog + 1 end end
  s.backlog = backlog
  local busy = (#s.orders > 0) or (backlog > 0)
  if busy then s.idle = 0 else s.idle = s.idle + dtReal end
  local F = CFG.flow
  local target = F.base + math.min(backlog, F.backlogMax) * F.backlogGain
  if s.idle > F.idleAfter then target = target + F.idleBonus end
  if (not busy) and #s.orders == 0 then target = math.min(target, 1.0) end
  s.flow = s.flow + (target - s.flow) * math.min(1, dtReal * 1.5)
  s.flow = math.max(F.min, math.min(F.max, s.flow))
  return s.flow
end

-- 到店：算"现在多久来一个"（含收尾减速），不动状态（方便测试）
function D.arriveInterval(s)
  local A = CFG.arrive
  local scale = A.dayScale ^ (s.day - 1)
  local base = A.min + math.random() * (A.max - A.min)
  base = base * scale * (s.mode.arriveScale or 1)
  local jit = 1 + (math.random() * 2 - 1) * A.jitter
  return math.max(1.5, base * jit)
end

-- 收尾减速倍率：当天剩余进入最后 rampFrom 比例后，间隔被逐渐拉长（最多 ×rampTo）
function D.slowFactor(s)
  local CL = CFG.closing
  local frac = S.dayFrac(s)
  if frac >= CL.rampFrom then return 1 end
  local r = math.min(1, (CL.rampFrom - frac) / CL.rampFrom)
  return 1 + (CL.rampTo - 1) * r * r          -- 二次曲线：越到后面掉得越快
end

-- 推进一步。返回本帧发生的事件列表（供表现层弹提示）
function D.tick(s, dtReal)
  local ev = {}
  if s.ended or s.phase == 'done' then return ev end
  if s.settling then return ev end            -- 正在结算：整段打烊逻辑冻结

  local dt = dtReal * updateFlow(s, dtReal)
  s.t = s.t + dtReal
  s.totalLeft = math.max(0, s.totalLeft - dt)
  s.dayLeft = math.max(0, s.dayLeft - dt)

  -- ── 到店 ──
  if s.phase == 'closing' or s.dayLeft <= 0 then
    -- 打烊了：不再放人
  else
    local slow = D.slowFactor(s)
    s.nextArrive = s.nextArrive - dt / slow
    if s.nextArrive <= 0 and #s.orders < CFG.kitchen.maxWaiting + 4 then
      local o = O.spawn(s)
      s.nextArrive = D.arriveInterval(s)
      ev[#ev + 1] = { kind = 'arrive', o = o }
    end
    if slow > 1.6 and s.lastCallDay ~= s.day then
      s.lastCallDay = s.day
      ev[#ev + 1] = { kind = 'lastcall' }
    end
  end

  -- ── 名额池 + 耐心 ──
  -- ★ ARRIVE 探针（ASCII）：到店计时器与订单数（排查"跑了很久没客人"）
  do
    _arr = (_arr or 0) + 1
    if print and _arr % 60 == 0 then
      pcall(print, string.format('[ARRIVE] t=%.1f dayLeft=%.1f next=%.2f orders=%d slips=%d slow=%.2f phase=%s',
        s.t, s.dayLeft, s.nextArrive, #s.orders, #s.slips, D.slowFactor(s), tostring(s.phase)))
    end
  end

  K.refreshSlots(s)
  local P = CFG.patience
  local closingNow = (s.phase == 'closing')
  for i = #s.orders, 1, -1 do
    local o = s.orders[i]
    if o.status ~= 'done' and not closingNow then   -- ★ 清场期间耐心冻结
      local drain = (not o.inProgress) and P.waitDrain or (o.status == 'ready' and P.readyDrain or 1)
      o.pat = o.pat - dt * drain
      if o.pat <= 0 then
        O.leave(s, o, not o.inProgress)
        ev[#ev + 1] = { kind = 'leave', o = o }
      end
    end
  end

  K.tickHolds(s, dt)
  K.sweepZombieSlips(s)
  K.autoForward(s, dtReal, true)

  -- ── 打烊流程 ──
  if s.phase ~= 'closing' and s.dayLeft <= 0 then
    s.phase = 'closing'
    s.closingLeft = CFG.closing.graceSec
    ev[#ev + 1] = { kind = 'closing' }
  end
  if s.phase == 'closing' then
    local pending = {}
    for _, o in ipairs(s.orders) do
      local allDone = true
      for _, c in ipairs(o.cups) do if not c.made then allDone = false end end
      if not allDone then pending[#pending + 1] = o end
    end
    s.closingLeft = s.closingLeft - dtReal
    if (#pending == 0 or s.closingLeft <= 0) and not s.settling then
      s.settling = true
      if #pending > 0 then
        -- ★ 宽限期到了：**已经动过手的单直接算你完成**（别让玩家做掉的白费），
        --   只有"压根没开工"的才算流失 —— 惩罚的是"没动手"，不是"手慢"。
        for _, o in ipairs(pending) do
          if o.inProgress or (o.made or 0) > 0 then
            for _, c in ipairs(o.cups) do
              if not c.done then
                c.done = true
                for _, st in ipairs(c.steps) do st.ok = true end
              end
            end
            O.finish(s, o, s.t)
          else
            s.left = s.left + 1; s.today.left = s.today.left + 1
            for i = #s.orders, 1, -1 do if s.orders[i] == o then table.remove(s.orders, i) end end
          end
        end
        s.slips = {}
        ev[#ev + 1] = { kind = 'graceout' }
      end
      D.settle(s)
      ev[#ev + 1] = { kind = 'dayend', day = s.day }
      return ev
    end
  end

  s.today.flow = s.flow
  return ev
end

-- 结算（幂等：一天只结一次）
function D.settle(s)
  if s.settledDay == s.day then return false end
  s.settledDay = s.day
  local rent = CFG.rent.perDay
  s.rentPaid = s.rentPaid + rent
  local paid = s.money >= rent
  if paid then
    s.money = s.money - rent
  else
    s.rentDebt = s.rentDebt + (rent - s.money)
    s.money = 0
  end
  local rec = { day = s.day, served = s.today.served, money = s.today.money,
                left = s.today.left, mistakes = s.today.mistakes,
                rent = rent, paid = paid, debt = s.rentDebt,
                eco = s.today.eco }   -- ★ 当日环保凭证（结算页显示；收摊时按天累加）
  s.dayStats[#s.dayStats + 1] = rec
  s.log[#s.log + 1] = string.format('第 %d 天：出餐 %d 杯 / 营业额 %d / 流失 %d / 翻车 %d → 房租 %d %s',
    rec.day, rec.served, rec.money, rec.left, rec.mistakes, rent, paid and '已付' or ('欠缴(累计 ' .. s.rentDebt .. ')'))
  if s.day >= s.mode.days then
    D.endGame(s)
    return true
  end
  s.settling = true          -- 等表现层"继续"→ nextDay
  return true
end

-- 下一天
function D.nextDay(s)
  s.settling = false
  s.phase = 'open'
  s.day = s.day + 1
  s.dayLeft = s.mode.perDay
  s.today = { served = 0, money = 0, left = 0, mistakes = 0,
              eco = { fixed = 0, zwd = 0 } }   -- ★ 每天归零，否则凭证会一路累加
  s.nextArrive = CFG.arrive.first
  return s.day
end

-- 收工：算总分与评级
function D.endGame(s)
  s.ended = true
  s.phase = 'done'
  for _, o in ipairs(s.orders) do s.left = s.left + 1; s.today.left = s.today.left + 1 end
  s.orders = {}; s.slips = {}
  local acc = (s.served + s.left) > 0 and (s.served / (s.served + s.left)) or 0
  local flowScore = math.floor(acc * 100 * CFG.score.flowWeight)
  local debt = s.rentDebt
  local total = math.max(0, s.score + flowScore + s.money - debt)
  local rank = 'D'
  for _, r in ipairs(CFG.ranks) do
    if total >= r.min then rank = r.r; break end
  end
  -- 欠租降档：每 debtPerRank 元降一档
  local steps = math.min(4, math.floor(debt / math.max(1, CFG.rent.debtPerRank)))
  local ORDER = { 'S', 'A', 'B', 'C', 'D' }
  if steps > 0 then
    local idx = 1
    for i, x in ipairs(ORDER) do if x == rank then idx = i end end
    rank = ORDER[math.min(#ORDER, idx + steps)]
  end
  s.result = { rank = rank, total = total, score = s.score, flowScore = flowScore,
               money = s.money, debt = debt, downgraded = steps, acc = acc }
  return s.result
end

return D
