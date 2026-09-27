-- props_demo.lua —— 让 props.lua 的三个视觉件在模拟器里真建出来，并出图看形状
--
--   node tools/lua-test.mjs --entry=props_demo --out=dist/props_demo.lua
--   node tools/sim-run.mjs dist/props_demo.lua --frames=40 --json=dist/props.json
--
-- 目的（对应"静态视觉件"这一步）：
--   ① 形状拼不拼得出来（基础形状 + 叠块 + 旋转）
--   ② 控件预算够不够（火焰 432 格是最大头）
--   ③ 液面是不是**水平的**（杯子的关键修正点）
--
-- ★ 两个坑（踩过，别再犯）：
--   1. 入口被 lua-test.mjs **铺平**成最外层代码 → 生命周期必须是**全局函数**，结尾不能 `return {...}`
--   2. `local P = ...`（模块里的 vararg）铺平后 `...` 是 nil → 必须 `require('props')`
local P = require('props')

local root = nil
local cup, cone, fire = nil, nil, nil
local frames = 0

function OnInit()
  script:EnableUpdate(true)
end

function OnStart()
  root = script.object
  if root then
    pcall(function() root:SetSizeDelta(1280, 720) end)
    pcall(function() root:SetActive(true) end)
    pcall(function() root:SetVisible(true) end)
  end

  local cfg = { root = root, img = 1, text = 2 }

  -- 三件排开（画布 1280×720，原点在中心）
  cup  = P.cup(cfg, 'Cup', -420, 60, P.drink.brom)       -- 溴水（黄褐）
  cone = P.cone(cfg, 'Cone',  0, 110, { lit = true })    -- 炮筒（点火状态）
  fire = P.fire(cfg, 'Fire',  420, -20)                  -- 火：16×27 = 432 格

  -- 液面演示：同一个杯子摆四份不同进度，验证"液面是平的"
  local demo = { 0.0, 0.25, 0.62, 1.0 }
  for i = 1, #demo do
    local c = P.cup(cfg, 'CupFill' .. i, -600 + (i - 1) * 96, -230, P.drink.water)
    c.setFill(demo[i])
  end
  cup.setFill(0.62)

  print(string.format('[PROPS] 已建：杯 1 + 液面演示 4 + 炮筒 1 + 火 %d 格',
    fire.blockCount))
  print(string.format('[PROPS] 几何：斜面 %.2f° → 杯口 %d（上宽）/ 杯底 %.1f（下窄）',
    P.spec.cup.slopeDeg, P.spec.cup.wTop, P.cupBottomWidth()))
end

function OnUpdate(dt)
  frames = frames + 1
  if fire then
    -- 火：30fps 节流（火不需要 60fps；真机同理，别每帧都算 432 格）
    if frames % 2 == 0 then
      fire.step()
      fire.draw()
    end
  end
  if frames % 30 == 0 then
    print(string.format('[PROPS] 帧 %d 火已跑 %d 步', frames, math.floor(frames / 2)))
  end
end

function OnDestroy() end
-- ★ 不能 return {...}：铺平后生命周期就靠上面的全局函数，return 反而会遮蔽它们

