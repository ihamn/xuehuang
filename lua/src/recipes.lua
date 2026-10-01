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

-- ★★ 每一步的 `vis`（视觉增量）—— "玩家按了一下，杯子里发生什么"（2026-10-01）
--   设计稿：docs/杯子内容-操作到视觉映射.md
--   字段含义（view.lua 只按这些字段画，不做判断）：
--     fill   数字   该步**做完后**的液面（0..1，绝对量）。mash 步会在 taps 次按动里**均分**涨上去
--     color  颜色   'drinkId'（查 props 的 P.drink）或 {r,g,b} 显式值；液体颜色向它靠拢
--     add    配料   'lemon' | 'ice' | 'peach' | 'apple'（mash 步做完才出现）
--     state  状态   'bubble' | 'dryice' | 'foam' | 'steam'（做完才点亮）
--     mix    混合   'milky'（往白里混）| 'uniform'（摇匀归一）
--     rim    杯口   'caramel'（炙烤焦糖）
--     lid    布尔   盖盖子（封杯）
--     pulse  动效   'shake' | 'ripple' | 'splash' | 'shuffle'（每次按动都放一次）
--     press  手法   ★★ 连按步（mash）**必须写**，它决定玩家用哪个动作/道具：
--                     'hammer' 柠檬锤（**只用来捣碎果肉、压缩出干冰** —— 用户 2026-10-01 定）
--                     'pump'   按压/注入（例如"加满空杯"）
--                     'shake'  摇晃（例如"摇匀至颜色均一"）
--                   ⇒ view 按 press 决定放什么动作，别拿锤子去干加水的活
--     tool   器具   该步作用于**器具**、杯子不动（例如咖啡机前三步）——
--                  这类步必须显式写出来，否则就是"按了没反应"
local list = {
  {
    id = 'dryice', name = '干冰干柠檬水', tag = '冰', price = 30, diff = 2, source = '官方',
    -- ★ 唯一真的"固化"了 CO₂ 的产品：0.5 L × 0.04% ÷ 22.4 × 44 = 0.00039 g（0.39 毫克）
    --   （结算页那条环保凭证就是拿它和"玩家自己排的 0.27 克"对照的）
    co2FixedG = 0.00039,
    heavy = true,   -- 重活：十几下连按
    -- ★★ 2026-10-01 用户指出并改定的顺序：**先压缩，后加水**。两条理由：
    --   ① 物理：要压的是**空气**。杯里先灌到七分满，活塞下去顶的是不可压缩的液体
    --      （液面只会被挤上去、溢出来），气体反而是从缝里跑掉的那个 —— 压不动。
    --      空杯压空气才成立（锤头也才够得着杯底）。
    --   ② 演出：真干冰的招牌效果是**遇水剧烈冒雾**。先做出干冰、再加水，
    --      第 5 步那一下就把白雾"点着"了 —— 收尾有一个大画面。
    --   （工位是热键切的 Y/H/K/P，不是走位 ⇒ 换顺序不多花代价。）
    steps = {
      { st = 'shake', t = '双手握住杯子，稳住（别让气跑掉）', kind = 'hold', vis = { pulse = 'shake' } },
      { st = 'shake', t = '快速压缩内部空气至 25000 千帕', kind = 'mash', taps = 6, press = 'hammer',
        vis = { pulse = 'ripple', onDone = { state = 'bubble' } } },
      -- quip：这一步的"完成为什么说得通"——用户 2026-10-01 圈定这句（共 12.3 宽，
      --   在 view.lua 的 STEP_MAX=16 以内；超过会溢出工位卡盖住隔壁，所以长度由测试把关）
      { st = 'shake', t = '继续压缩，直至出现固态干冰', kind = 'mash', taps = 6, press = 'hammer',
        vis = { pulse = 'ripple', onDone = { state = 'dryice' }, quip = '0.04% 也是本店的客人。' } },
      { st = 'brew',  t = '放入干柠檬片', kind = 'tap', vis = { add = 'lemon' } },
      { st = 'brew',  t = '加水至七分满（干冰遇水，冒雾）', kind = 'tap',
        vis = { fill = 0.70, color = 'lemon', state = 'fogburst', pulse = 'flash' } },
      { st = 'pack',  t = '封杯出餐', kind = 'tap', vis = { lid = true } },
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
      { st = 'fire', t = '掏出枪筒', kind = 'tap', vis = { tool = 'torch' } },
      { st = 'fire', t = '用喷火枪烤香，烤完直接递给客人（甜筒不用打包）', kind = 'hold',
        vis = { tool = 'torch', pulse = 'flash' } },
    },
  },
  {
    id = 'bromine', name = '空杯满杯千溴水', tag = '溴', price = 44, diff = 3, source = '官方',
    steps = {
      { st = 'chem',  t = '用量筒取 10ml 溴水原液', kind = 'hold', vis = { fill = 0.15, color = 'brom' } },
      { st = 'chem',  t = '加满空杯至满杯', kind = 'mash', taps = 5, press = 'pump', vis = { fill = 1.00, color = 'brom' } },
      { st = 'shake', t = '摇匀至颜色均一', kind = 'mash', taps = 4, press = 'shake',
        vis = { pulse = 'shuffle', mix = 'uniform', onDone = { state = 'foam' } } },
      { st = 'pack',  t = '封杯出餐', kind = 'tap', vis = { lid = true } },
    },
  },
  {
    id = 'instcoffee', name = '现萃速溶咖啡', tag = '咖', price = 24, diff = 1, source = '官方',
    -- ★ 全 tap：这是"新手第一杯"，刻意不做连按/按住；前三步拆包也不占名额
    steps = {
      { st = 'brew', t = '取速溶咖啡粉', kind = 'tap', noSlot = true, vis = { tool = 'coffee' } },
      { st = 'brew', t = '放入咖啡机粉碗', kind = 'tap', noSlot = true, vis = { tool = 'coffee' } },
      { st = 'brew', t = '按下萃取键', kind = 'tap', noSlot = true, vis = { tool = 'coffee' } },
      -- tap 步的 state 直接写字段（onDone 只给 mash 步用）
      { st = 'brew', t = '注入热水', kind = 'tap', vis = { fill = 1.00, color = 'coffee', state = 'steam' } },
      { st = 'pack', t = '封杯出餐', kind = 'tap', vis = { lid = true } },
    },
  },
  {
    id = 'newton', name = '牛顿苹果奶绿', tag = '苹', price = 34, diff = 2, source = '官方',
    steps = {
      { st = 'shake', t = '把苹果砸进杯子里（重力加速度请自行脑补）', kind = 'mash', taps = 4, press = 'hammer',
        vis = { pulse = 'splash', onDone = { add = 'apple' } } },
      { st = 'brew',  t = '注入绿茶汤', kind = 'tap', vis = { fill = 0.55, color = { 122, 168, 92 } } },
      { st = 'chem',  t = '加入奶精', kind = 'tap', vis = { mix = 'milky' } },
      { st = 'brew',  t = '注入牛奶', kind = 'hold', vis = { fill = 1.00, color = 'milk' } },
      { st = 'pack',  t = '封杯出餐', kind = 'tap', vis = { lid = true } },
    },
  },
  {
    id = 'peach', name = '蟠桃四季春', tag = '桃', price = 36, diff = 2, source = '官方',
    steps = {
      { st = 'brew',  t = '注入四季春茶汤', kind = 'hold', vis = { fill = 0.70, color = { 168, 172, 96 } } },
      { st = 'fire',  t = '炙烤杯口（烤出焦糖香）', kind = 'hold', vis = { rim = 'caramel', pulse = 'flash' } },
      { st = 'shake', t = '加入蟠桃果肉并摇匀', kind = 'mash', taps = 5, press = 'hammer',
        vis = { pulse = 'shuffle', color = 'peach', onDone = { add = 'peach' } } },
      { st = 'pack',  t = '封杯出餐', kind = 'tap', vis = { lid = true } },
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

-- ══════════════════════════════════════════════════════════════════════
-- 环保贡献凭证（2026-10-01）
--
-- ★ 用户定：**只保留"固化下来的减碳"，不搞"碳排放计算"**。
--   原话意思是：太讲现实不太好，让玩家自己去体会。
--   所以这里**没有**"玩家做功→代谢→排碳"那套（曾经算到 0.36 克，还配了碳价卖钱），
--   也**没有**碳价 —— 只剩一个诚实的小数字：
--
--   干冰那款把杯里空气的 CO₂ 固化了下来：
--     0.5 L × 0.04% ÷ 22.4 L/mol × 44 g/mol = 0.00039 g = **0.39 毫克**
--
--   结算页就写这一句（"固化 CO₂ 0.39 毫克" + "感谢您为环保事业的贡献"），
--   剩下的大反差（空气里本来就没多少 CO₂）玩家自己会想明白 —— 那声笑是他自己笑出来的。
-- ══════════════════════════════════════════════════════════════════════

-- ── 卖碳的钱，**提前折算成津元**，运行时不换算（2026-10-01 用户定）──
--   用户要求：不要在最后做币种转化，**提前算好，直接用 mg / 津元 输出结果**。
--   于是这里只留一个成品常数：**津元/毫克**。它是下面三个真数一次算完的：
--     碳价  62.36 元/吨（2025 全国碳市场 CEA 成交均价）
--     汇率  7.2 元/美元
--     津元  1 美元 = Z$35,000,000,000,000,000（3.5×10^16，2015 津元退市价）
--     1 毫克 = 1e-9 吨 → ×62.36 元/吨 → ÷7.2 → ×3.5e16 = **3.0314e8 津元/毫克**
--   旁证：同期说法"175,000,000,000,000,000 旧币换 5 美元"（÷5 = 3.5e16 ✓）
--   ⇒ 一杯固化 0.39 毫克 × 3.0314e8 = **1.18 亿津元**（而它实际值 0.0000000243 元）
recipes.ECO = {
  zwdPerMg = 3.0314e8,       -- 津元/毫克（已含碳价与汇率，**成品常数**）
}

-- 返回 { fixed, zwd }：本单固化了多克 CO₂、以及它卖得的**津元**（直接给结果，不换算）
function recipes.eco(r)
  if not r then return { fixed = 0, zwd = 0 } end
  local fixed = r.co2FixedG or 0                       -- 克
  return { fixed = fixed, zwd = fixed * 1000 * recipes.ECO.zwdPerMg }   -- 克→毫克→津元
end

return recipes
