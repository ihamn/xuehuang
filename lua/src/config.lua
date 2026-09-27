-- config.lua —— 雪皇的后厨 · 所有数值的唯一来源
--
-- 为什么单独一个文件：网页版那 2900 行里最痛的经验是"同一个数散在三处"，
-- 改了一处另一处没改，表现就是"改了没反应"。所以千星版从第一天起：
--   **任何会被调的数字都只写在这里**，别的文件一律 require 这份。
--
-- 平台约束（真机实测，别踩）：
--   · 整数是 32 位（不要写需要 64 位整数的运算）
--   · 画布 1815x900 是 PC；2D 布局基线是手机 16:9（1280x720），表现层按它构图再等比缩放
--   · require 按路径 '子目录/文件名'（无 .lua 后缀）

local CFG = {}

-- ── 玩法模式：每个模式自带"几天 / 每天多久"，总时长 = days x perDay ──
--   arriveScale = 本盘的"人数密度"（1 = 基准）；短盘时间少，所以把人数也降下来
--   quick = 5 分钟一口气一天（没有日结打断）
CFG.modes = {
  quick = { days = 1, perDay = 300,  arriveScale = 1.45, label = '5 分钟局',  desc = '一口气经营 5 分钟' },
  fast  = { days = 5, perDay = 120,  arriveScale = 1.00, label = '10 分钟局', desc = '每天 2 分钟' },
  slow  = { days = 5, perDay = 240,  arriveScale = 1.00, label = '20 分钟局', desc = '每天 4 分钟' },
}
-- ★ 默认模式必须是**可玩**的：quick（fast/slow 需要多人，施工中）
--   ⚠️ 上一版这里还是 'fast'（施工中）→ 别的路径若用它开局会直接失败
CFG.defaultMode = 'quick'

-- ── 后厨容量：同时**未完成的任务（杯）** ≤ maxWip；等候区最多 maxWaiting 位 ──
--   ★ 关键规则：同一张单的几杯**一起进池**（按单填池），不能"第一杯开工就把同单第二杯挤出去"
CFG.kitchen = { maxWip = 3, maxWaiting = 10 }

-- ── 到店：每次间隔在 [min,max] 内随机 → 到店时间天然动态；dayScale 逐日收紧 ──
--   closing.rampFrom：当天剩余进入最后这个比例后，到店间隔被逐渐拉长（最多 xrampTo）
--   closing.graceSec：打烊后的"清场"宽限期硬上限（这段时间耐心**冻结**）
CFG.arrive = { first = 2.5, min = 8, max = 14, dayScale = 0.95, jitter = 0.2 }
CFG.closing = { rampFrom = 0.35, rampTo = 4, graceSec = 45 }

-- ── 点单 ──
--   cups：杯数的加权分布（加权查表就够，不需要复杂随机）
--   ice/sugar：同上
CFG.cups  = { { n = 1, p = 0.50 }, { n = 2, p = 0.25 }, { n = 3, p = 0.125 }, { n = 4, p = 0.125 } }
CFG.ice   = { { v = '正常', p = 0.75 }, { v = '去冰', p = 0.125 }, { v = '常温', p = 0.125 } }
CFG.sugar = { { v = '正常糖', p = 0.75 }, { v = '七分糖', p = 0.125 }, { v = '五分糖', p = 0.125 } }

-- ── 混点：一单可以同款多杯，也可以多种不同 ──
--   mixedChance2/3：2 杯 / 3 杯以上时"混点"的概率
--   twoHeavyBan：不允许把两个"重活"放同一单（干冰 + 重活 = 二十多下连按，那是惩罚不是玩法）
CFG.mix = { mixedChance2 = 0.50, mixedChance3 = 0.65 }

-- ── 耐心：按"这一单点了几杯"动态给（杯数越多，客人愿意等越久）──
--   waitDrain：排队的掉得慢一档；readyDrain：做完了只是没交的掉得更慢
--   doneBonus/perStep/doneBonusMax：**每做完一杯给客人续一点耐心**（进度本身就是补偿）
CFG.patience = {
  base = 38, perCup = 12, min = 26, jitter = 0.15,
  doneBonus = 3, perStep = 0.4, doneBonusMax = 8,
  waitDrain = 0.6, readyDrain = 0.35,
}

-- ── 时间流速：积压 → 慢，空闲 → 快；均值 ≈ 1，所以总时长仍锁在 days x perDay ──
CFG.flow = { base = 0.85, backlogGain = 0.05, backlogMax = 6, idleBonus = 0.4, idleAfter = 8, min = 0.5, max = 1.6 }

-- ── 钱与评分 ──
CFG.money = { perCup = 26, rushBonus = 12, strikePenalty = 18, leavePenalty = 30, comboStep = 2, comboMax = 30 }
CFG.score = { perCup = 100, rushBonus = 40, mistake = 60, leave = 80, flowWeight = 0.8 }
-- 房租：每天固定 100；欠款从最终结算里扣，并按每 debtPerRank 元降一档评级
CFG.rent  = { perDay = 100, debtPerRank = 100 }
-- 评级档位（分数从高到低）
CFG.ranks = { { min = 34000, r = 'S' }, { min = 24000, r = 'A' }, { min = 15000, r = 'B' }, { min = 8000, r = 'C' }, { min = 0, r = 'D' } }

-- ── 手法（tap/mash/hold）──
-- ★★ 2026-09-27 真机证据修正（这次有日志，不是猜）：
--   19:15 那次真机运行里，玩家按 P 共 13 次，**[STATE] 一直是 hold:0.0/0.9，48 次采样全是 0.0**，
--   而且整份日志里**一条 [KUP]（按键抬起）都没有**。
--   结论：在这个平台上，**"按住"这种输入不可用** ——
--     · 真机不送 KeyUp（可能被千星的跳跃/滑翔占用，也可能键事件只给按下）
--     · 于是 `holdOn` 永远清不掉、进度也攒不起来，按住类步骤**永远做不完**
--     · 玩家看到的就是"工位卡上有任务，按键盘它从不变；鼠标点却能完成"（鼠标点的是 tap 类）
--   所以：**按住类改成一次输入即完成**（oneTap）。
--   代价：丢掉原版"按住 0.9 秒"的手感；收益：这个平台**能玩**。
--   原版的按住累积逻辑保留在 kitchen.pressStep 里（oneTap=false 即可切回）。
--   连按类（mash）不受影响：每次输入 +1 本来就成立。
CFG.hold = { sec = 0.9, tapBoost = 0, oneTap = true }
CFG.taps = { 4, 5, 6 }            -- 连按类每步的档位（按配方难度取）

-- ── 自动（可关）──
--   auto.on：小票自动流转（某一步长时间没人管，自动送去该去的工位）
--   autoTicket.on：客人一进后厨，这单每杯立刻出票（不用手动起杯）
CFG.auto = { on = true, after = 5 }
CFG.autoTicket = { on = true, maxPerOrder = 8 }

-- ── 界面（表现层用；逻辑层不读，但放这里省得两处对不上）──
CFG.ui = {
  designW = 1280, designH = 720,      -- 2D 布局基线（手机 16:9），PC 上等比放大
  stallWarn = 3.0,                    -- 小票在某工位停留超过这么久就闪
}

-- 取某个模式的完整配置（含总时长）
function CFG.mode(name)
  local m = CFG.modes[name] or CFG.modes[CFG.defaultMode]
  return {
    key = name or CFG.defaultMode,
    days = m.days, perDay = m.perDay,
    total = m.days * m.perDay,
    arriveScale = m.arriveScale,
    label = m.label, desc = m.desc,
  }
end

return CFG
