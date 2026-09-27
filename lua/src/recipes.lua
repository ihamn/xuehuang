-- recipes.lua —— 产品表（配方 + 手法 + 出餐方式）
--
-- 每一步写三件事：
--   st   工位（shake 捣 / fire 火 / chem 化 / brew 泡 / pack 打包）
--   t    这一步的文案（会显示在按钮和手册上，写清"做什么"，别写"点这里"）
--   kind 手法：tap 一下 ／ mash 连按 N 下 ／ hold 按住
-- 缺省 kind 由 taps 推断：
--   有 taps（且 >1）→ mash；否则 tap。
-- ★ 手法要**混着来**：全是连按会很累，全是一下又没手感。
--
-- 特殊标记：
--   serveNow = 做完即出（不进打包台，最后一步收口时直接交给客人）
--   noSlot   = 这一步**不占后厨名额**（纯手感步骤，例如速溶咖啡的拆包）
--             意义：一杯 3 步的咖啡不该和一杯十几下连按的干冰抢同一个名额
--   heavy    = 重活（混点时不把两个重活放同一单）

local recipes = {}

-- ── 工位 id（逻辑层只认这四个 + pack）──
recipes.STATIONS = { 'shake', 'fire', 'chem', 'brew', 'pack' }

local list = {
  {
    id = 'dryice', name = '干冰干柠檬水', tag = '冰', price = 30, diff = 2, source = '官方',
    heavy = true,   -- 重活：十几下连按
    steps = {
      { st = 'brew',  t = '放入干柠檬片', kind = 'tap' },
      { st = 'brew',  t = '加水至七分满', kind = 'tap' },
      { st = 'shake', t = '双手握住杯子', kind = 'hold' },
      { st = 'shake', t = '快速压缩内部空气至 25000 千帕', kind = 'mash', taps = 6 },
      { st = 'shake', t = '继续压缩，直至出现固态干冰', kind = 'mash', taps = 6 },
      { st = 'pack',  t = '封杯出餐', kind = 'tap' },
    },
  },
  {
    -- ★ 恶搞产品：neta 现实里的「黑芝麻冰麒麟」（黑→白、冰→火、雪糕→辣甜筒）
    --   定位：快消品 —— 工序只有"掏枪筒 + 喷火"两件事，喷完直接递给客人，不进打包台
    --   它本质是**一支甜筒**，不是杯装饮料，所以没有封杯这回事
    --   ★ 第一步文案按用户要求改过：原来是「从枪筒里掏出甜筒」→ 现在直接「掏出枪筒」
    id = 'qilin', name = '白芝麻火麒麟', tag = '甜', price = 32, diff = 1, source = '官方',
    serveNow = true,
    steps = {
      { st = 'fire', t = '掏出枪筒', kind = 'tap' },
      { st = 'fire', t = '用喷火枪烤香，烤完直接递给客人（甜筒不用打包）', kind = 'hold' },
    },
  },
  {
    id = 'bromine', name = '空杯满杯千溴水', tag = '溴', price = 44, diff = 3, source = '官方',
    steps = {
      { st = 'chem',  t = '用量筒取 10ml 溴水原液', kind = 'hold' },
      { st = 'chem',  t = '加满空杯至满杯', kind = 'mash', taps = 5 },
      { st = 'shake', t = '摇匀至颜色均一', kind = 'mash', taps = 4 },
      { st = 'pack',  t = '封杯出餐', kind = 'tap' },
    },
  },
  {
    id = 'instcoffee', name = '现萃速溶咖啡', tag = '咖', price = 24, diff = 1, source = '官方',
    -- ★ 全 tap：这是"新手第一杯"，刻意不做连按/按住；前三步拆包也不占名额
    steps = {
      { st = 'brew', t = '取速溶咖啡粉', kind = 'tap', noSlot = true },
      { st = 'brew', t = '放入咖啡机粉碗', kind = 'tap', noSlot = true },
      { st = 'brew', t = '按下萃取键', kind = 'tap', noSlot = true },
      { st = 'brew', t = '注入热水', kind = 'tap' },
      { st = 'pack', t = '封杯出餐', kind = 'tap' },
    },
  },
  {
    id = 'newton', name = '牛顿苹果奶绿', tag = '苹', price = 34, diff = 2, source = '官方',
    steps = {
      { st = 'shake', t = '把苹果砸进杯子里（重力加速度请自行脑补）', kind = 'mash', taps = 4 },
      { st = 'brew',  t = '注入绿茶汤', kind = 'tap' },
      { st = 'chem',  t = '加入奶精', kind = 'tap' },
      { st = 'brew',  t = '注入牛奶', kind = 'hold' },
      { st = 'pack',  t = '封杯出餐', kind = 'tap' },
    },
  },
  {
    id = 'peach', name = '蟠桃四季春', tag = '桃', price = 36, diff = 2, source = '官方',
    steps = {
      { st = 'brew',  t = '注入四季春茶汤', kind = 'hold' },
      { st = 'fire',  t = '炙烤杯口（烤出焦糖香）', kind = 'hold' },
      { st = 'shake', t = '加入蟠桃果肉并摇匀', kind = 'mash', taps = 5 },
      { st = 'pack',  t = '封杯出餐', kind = 'tap' },
    },
  },
}

-- ── 规范化：给每一步补上 kind / taps / noSlot，并算出这杯的"工序量" ──
--   工序量 = 每步的成本之和（连按按次数算），用于：耐心回补量、评分里"重活"的判定
local TAPS = require('config').taps
for _, r in ipairs(list) do
  local load = 0
  for i, s in ipairs(r.steps) do
    if not s.kind then s.kind = (s.taps and s.taps > 1) and 'mash' or 'tap' end
    if s.kind == 'mash' and not s.taps then
      -- 没写 taps 的连按：按配方难度取档（4/5/6 下）
      s.taps = TAPS[math.min(#TAPS, math.max(1, r.diff))]
    end
    if s.kind ~= 'mash' then s.taps = nil end
    s.noSlot = s.noSlot == true
    load = load + (s.kind == 'mash' and (s.taps or 1) or 1)
  end
  r.load = load
  -- 出餐方式：serveNow 的品最后一步自己就是交付点
  r.needsPack = not r.serveNow and r.steps[#r.steps].st == 'pack'
end

recipes.list = list

-- 按 id 取配方
function recipes.byId(id)
  for _, r in ipairs(list) do if r.id == id then return r end end
  return nil
end

-- 线性插值取加权随机项（加权查表：比概率累加快、也比它好读）
--   util 传 [0,1) 的随机数进来，方便测试复现
function recipes.pickWeighted(tbl, util)
  local total = 0
  for _, e in ipairs(tbl) do total = total + (e.p or 0) end
  local x = (util or 0) * total
  local acc = 0
  for _, e in ipairs(tbl) do
    acc = acc + (e.p or 0)
    if x < acc then return e end
  end
  return tbl[#tbl]
end

return recipes
