-- order.lua —— 点单（混点生成 + 耐心）
--
-- 三条从网页版搬来的硬规则（每条都是玩家反馈换来的）：
--   ① 一单可以同款多杯，也可以多种不同（"顾客可以点同一种点多杯，也可以点多种不同的"）
--   ② **不把两个重活放同一单**（干冰 + 另一个重活 = 二十多下连按，那是惩罚不是玩法）
--   ③ 耐心按**这一单点了几杯**给（杯数越多越愿意等），并且**每做完一杯回补一点**
--      —— 因为"全做完一起交"会让客人等更久，进度本身就是补偿

local CFG = require('config')
local R = require('recipes')
local S = require('state')

local O = {}

-- 抽签用的随机源：**可以注入**（测试要可复现，所以不直接调 math.random）
--   默认用 math.random；测试里换成确定性序列
local rng = function() return math.random() end
function O.setRng(fn) rng = fn end

local function pickWeighted(tbl)
  return R.pickWeighted(tbl, rng())
end
local function pickUniform(list)
  return list[math.min(#list, math.floor(rng() * #list) + 1)]
end

-- 生成"这一单要哪几杯什么"：返回 lines = { { rec = 配方, n = 杯数 }, ... }
--   cupN 总杯数；重活不与重活同单
function O.drinkPlan(cupN)
  local pool = R.list
  if cupN <= 1 then
    return { { rec = pickUniform(pool), n = cupN } }
  end
  -- 混不混：2 杯一半概率，3 杯以上多半会混
  local mixed = rng() < (cupN == 2 and CFG.mix.mixedChance2 or CFG.mix.mixedChance3)
  if not mixed then
    return { { rec = pickUniform(pool), n = cupN } }
  end
  local kinds = 2
  if cupN >= 3 and rng() < 0.5 then kinds = 3 end
  kinds = math.min(kinds, cupN, #pool)

  local lines, left = {}, cupN
  for i = 1, kinds do
    local rest = kinds - i
    -- 候选：没用过的配方
    local cand = {}
    for _, r in ipairs(pool) do
      local used = false
      for _, l in ipairs(lines) do if l.rec.id == r.id then used = true end end
      if not used then cand[#cand + 1] = r end
    end
    -- ① 第一项优先选**非重活**（避免"重活 + 重活"）
    if i == 1 then
      local light = {}
      for _, r in ipairs(cand) do if not r.heavy then light[#light + 1] = r end end
      if #light > 0 then cand = light end
    end
    -- ② 后面几项也尽量避开重活（只要还有非重活可选）
    if i > 1 then
      local light = {}
      for _, r in ipairs(cand) do if not r.heavy then light[#light + 1] = r end end
      if #light > 0 then cand = light end
    end
    if #cand == 0 then cand = pool end
    local rec = pickUniform(cand)
    -- 给后面几项至少各留 1 杯
    local maxN = left - rest
    local n
    if i == kinds then n = left
    else n = math.max(1, math.min(maxN, 1 + math.floor(rng() * math.max(1, maxN)))) end
    lines[#lines + 1] = { rec = rec, n = n }
    left = left - n
  end
  -- 兜底：万一算法把杯数算漏了，全补到最后一项（宁可名字难看，也不能少杯）
  local sum = 0
  for _, l in ipairs(lines) do sum = sum + l.n end
  if sum < cupN then lines[#lines].n = lines[#lines].n + (cupN - sum) end
  return lines
end

-- 生成一张订单
function O.spawn(s)
  local cupN = pickWeighted(CFG.cups).n
  local lines = O.drinkPlan(cupN)
  local ice = pickWeighted(CFG.ice).v
  local sugar = pickWeighted(CFG.sugar).v
  local P = CFG.patience
  -- 耐心：按杯数给 + 个体差异
  local pat = math.max(P.min, P.base + cupN * P.perCup) * (1 + (rng() * 2 - 1) * P.jitter)
  s.oid = s.oid + 1
  local o = {
    id = s.oid, name = O.pickName(), rec = lines[1].rec, lines = lines,
    ice = ice, sugar = sugar,
    cups = {}, need = cupN, pat = pat, patMax = pat,
    made = 0, delivered = 0, status = 'wait',
    inProgress = false, priority = false, queueNo = 0,
    patBonus = 0, born = s.t,
  }
  local i = 0
  for _, line in ipairs(lines) do
    for _ = 1, line.n do
      i = i + 1
      local steps = {}
      for _, st in ipairs(line.rec.steps) do
        steps[#steps + 1] = { st = st.st, t = st.t, kind = st.kind, taps = st.taps,
                              noSlot = st.noSlot, ok = false, done = 0 }
      end
      o.cups[#o.cups + 1] = { made = false,
        i = i, rec = line.rec, steps = steps, done = false, served = false,
        err = false, startedAt = nil, finishedAt = nil, slotReady = false,
      }
    end
  end
  local names = {}
  for _, line in ipairs(lines) do names[#names + 1] = line.n .. '×' .. line.rec.name end
  o.makeup = table.concat(names, ' + ')
  s.orders[#s.orders + 1] = o
  return o
end

O.NAMES = { '隔壁老王', '雪皇本尊', '柠檬精', '干冰爱好者', '不喝冰的阿姨', '物理系学弟',
            '牛顿本人', '后厨实习生', '挑剔的美食家', '加班到凌晨的人', '一杯就倒', '四杯打包' }
function O.pickName() return pickUniform(O.NAMES) end

-- 做完一杯：记账 + **给客人续一点耐心**（续的量与这杯的工序量挂钩）
--
-- ★★ 杯子有三个状态，别混（我第一版把 done 既当"做完"又当"放上托盘"，结果整局交不掉单）：
--     cup.steps 全 ok  = 这一步做完了
--     cup.made   = true = **这杯真的做完了**（可以放托盘 / 直接交付）
--     cup.done   = true = **这杯已经交给客人了**（结单计数用这个）
--   `o.made` 统计的是 "做完" 的杯数；`O.finish` 只在**全部交付**时调用。
function O.onCupMade(s, o, cup, served)
  o.made = 0
  for _, c in ipairs(o.cups) do if c.made then o.made = o.made + 1 end end
  if not served and o.status ~= 'done' then
    o.status = (o.made < o.need) and 'ready' or 'done'
  end
  local P = CFG.patience
  local load = 0
  for _, st in ipairs(cup.steps) do
    load = load + ((st.kind == 'mash') and (st.taps or 1) or 1)
  end
  local bonus = P.doneBonus + math.min(P.doneBonusMax, load * P.perStep)
  o.pat = math.min(o.patMax, o.pat + bonus)
  o.patBonus = o.patBonus + bonus
  return bonus
end

-- 整单交付的判定：**每一杯都交付了**才算整单完成（不是"做完了"）
function O.allDelivered(o)
  for _, c in ipairs(o.cups) do if not c.done then return false end end
  return true
end

-- 客人走了（耐心清零）：记流失并把它移除
function O.leave(s, o, wasWaiting)
  o.status = 'lost'
  s.left = s.left + 1
  s.today.left = s.today.left + 1
  if wasWaiting then s.leftWaiting = s.leftWaiting + 1 end
  s.combo = 0
  s.money = math.max(0, s.money - CFG.money.leavePenalty)
  s.score = math.max(0, s.score - CFG.score.leave)
  for i = #s.orders, 1, -1 do if s.orders[i] == o then table.remove(s.orders, i) end end
  -- 它的票也一起撤掉（否则会留下"没有主人的票"）
  for i = #s.slips, 1, -1 do if s.slips[i].o == o then table.remove(s.slips, i) end end
  return o
end

-- 整单交付结算：一次连击、一次评分
function O.finish(s, o, now)
  o.delivered = o.need
  o.status = 'done'
  local perfect = true
  local slowest = 0
  for _, c in ipairs(o.cups) do
    if c.err then perfect = false end
    local used = (c.finishedAt or now) - (c.startedAt or 0)
    if used > slowest then slowest = used end
  end
  local fast = slowest < 25
  if perfect then s.combo = s.combo + 1; s.maxCombo = math.max(s.maxCombo, s.combo)
  else s.combo = 0 end
  local tip = math.min(CFG.money.comboMax, s.combo * CFG.money.comboStep)
  local earn, sc = 0, 0
  for _, c in ipairs(o.cups) do
    earn = earn + CFG.money.perCup + math.floor(c.rec.price * 0.2)
      + (perfect and 4 or 0) + (fast and CFG.money.rushBonus or 0) + tip
    sc = sc + CFG.score.perCup + (perfect and 20 or 0)
      + (fast and CFG.score.rushBonus or 0) + s.combo * 2
  end
  if not perfect then earn = math.floor(earn * 0.5); sc = math.floor(sc * 0.7) end
  s.money = s.money + earn
  s.score = s.score + sc
  s.today.money = s.today.money + earn
  -- 已"做完即出"的杯已经单独记过 served，不重复计
  local already = 0
  for _, c in ipairs(o.cups) do if c.served then already = already + 1 end end
  local addCups = o.need - already
  s.served = s.served + addCups
  s.today.served = s.today.served + addCups
  -- ★ 环保凭证：每出一杯，把这杯**固化**的 CO₂ 与它**已折好的津元**累加进当日
  --   （不做排碳计算、也不在结算时换算 —— 见 recipes.ECO 的成品常数）
  for _, c in ipairs(o.cups) do
    local e = R.eco(c.rec)
    local te = s.today.eco
    if te then te.fixed = te.fixed + e.fixed; te.zwd = te.zwd + e.zwd end
  end
  for i = #s.orders, 1, -1 do if s.orders[i] == o then table.remove(s.orders, i) end end
  return { earn = earn, score = sc, perfect = perfect, fast = fast, tip = tip, cups = addCups }
end

return O
