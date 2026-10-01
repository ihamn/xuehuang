-- cup_vis_test.lua —— 逐步视觉增量（vis）的数据体检
--   node tools/lua-test.mjs lua/test/cup_vis_test.lua
--
-- 为什么单测这个：vis 是**数据**，写错了不会有语法错误、也不会有运行时报错 ——
--   它只会表现为"玩家按了，杯子里什么都没发生"（或缺一整杯）。这正是最难查的那类错。
--   所以这里把"数据该满足的形状"钉死。

local R = require('recipes')
local P = require('props')

local pass, fail = 0, 0
local function ok(c, m)
  if c then pass = pass + 1; print('  OK  ' .. m) else fail = fail + 1; print('  X   ' .. m) end
end

local CUP_STATES = { bubble = true, dryice = true, foam = true, steam = true, fogburst = true }
local CUP_ADD    = { lemon = true, ice = true, peach = true, apple = true }
local CUP_PULSE  = { shake = true, ripple = true, splash = true, shuffle = true, flash = true }
local CUP_MIX    = { milky = true, uniform = true }

local all = R.list   -- ★ 是**表**不是函数（recipes.list = list）
print(string.format('== 共 %d 个产品 ==', #all))

local missingVis, badColor, onDoneNonMash, badFill, noLid, toolOnCup, fillJump = 0, 0, 0, 0, 0, 0, 0

for _, p in ipairs(all) do
  local steps = p.steps
  local isCup = not p.serveNow
  local prevFill = 0
  local maxFill, lastVis = 0, nil
  local name = p.name

  for i, st in ipairs(steps) do
    local v = st.vis
    if not v then
      missingVis = missingVis + 1
      print(string.format('  X   [%s] 第 %d 步没有 vis（= 玩家按了没反应）：%s', name, i, tostring(st.t)))
    else
      lastVis = v
      -- 颜色必须是"存在的饮料 id"或 {r,g,b}
      if v.color then
        if type(v.color) == 'string' then
          if not P.drink[v.color] then badColor = badColor + 1
            print(string.format('  X   [%s] 第 %d 步 color="%s" 在 P.drink 里不存在', name, i, v.color)) end
        elseif type(v.color) == 'table' then
          local c = v.color
          if not (c[1] and c[2] and c[3] and c[1] >= 0 and c[1] <= 255 and c[2] >= 0 and c[2] <= 255 and c[3] >= 0 and c[3] <= 255) then
            badColor = badColor + 1
            print(string.format('  X   [%s] 第 %d 步 color 不是合法的 {r,g,b}(0..255)', name, i))
          end
        else
          badColor = badColor + 1
          print(string.format('  X   [%s] 第 %d 步 color 类型不对（%s）', name, i, type(v.color)))
        end
      end
      -- ★ onDone 只能出现在 mash 步：tap/hold 步的"完成"就是那一下，
      --   写 onDone 会让人以为有延迟，实际上语义重复（而且容易和 kind 改动脱节）
      if v.onDone and st.kind ~= 'mash' then
        onDoneNonMash = onDoneNonMash + 1
        print(string.format('  X   [%s] 第 %d 步是 %s 步却用了 onDone（应当直接写字段）', name, i, st.kind))
      end
      -- 枚举值检查
      local d = v.onDone or v
      if d.state and not CUP_STATES[d.state] then ok(false, '[' .. name .. '] state 非法：' .. tostring(d.state)) end
      if d.add and not CUP_ADD[d.add] then ok(false, '[' .. name .. '] add 非法：' .. tostring(d.add)) end
      if v.pulse and not CUP_PULSE[v.pulse] then ok(false, '[' .. name .. '] pulse 非法：' .. tostring(v.pulse)) end
      if v.mix and not CUP_MIX[v.mix] then ok(false, '[' .. name .. '] mix 非法：' .. tostring(v.mix)) end

      -- 液面：0..1、不许倒退、mash 步要能均分
      if v.fill then
        if v.fill < 0 or v.fill > 1 then badFill = badFill + 1
          print(string.format('  X   [%s] 第 %d 步 fill=%.2f 越界', name, i, v.fill)) end
        if v.fill < prevFill - 0.001 then fillJump = fillJump + 1
          print(string.format('  X   [%s] 第 %d 步 fill 倒退（%.2f → %.2f）', name, i, prevFill, v.fill)) end
        if st.kind == 'mash' and (st.taps or 1) < 2 then
          print(string.format('  X   [%s] 第 %d 步 mash 步要涨液面却没有 taps', name, i))
        end
        prevFill = v.fill
        if v.fill > maxFill then maxFill = v.fill end
      end
      -- 器具步：杯子产品不该出现 tool（那是非杯装/器具步）
      if v.tool and isCup and v.fill == nil and v.add == nil and v.state == nil then
        -- 允许（咖啡前三步作用于器具），但要能一眼看出来
      end
      if v.tool and isCup then toolOnCup = toolOnCup + 1 end
    end
  end

  if isCup then
    -- 杯装产品：最后一步必须封杯；整杯的液面要有意义（不是空的）
    if not (lastVis and lastVis.lid) then noLid = noLid + 1
      print(string.format('  X   [%s] 最后一步没有 lid=true（封杯出餐没盖盖子）', name)) end
    if maxFill < 0.55 then
      print(string.format('  X   [%s] 整杯最高液面只有 %.2f（杯子几乎是空的）', name, maxFill))
      badFill = badFill + 1
    end
    print(string.format('  OK  [%s] %d 步 · 液面峰值 %.2f · 配料/状态已标注', name, #steps, maxFill))
  else
    -- 非杯装（serveNow，例如甜筒）：不该出现任何液体字段
    local anyFill = false
    for _, st in ipairs(steps) do
      local v = st.vis or {}
      local d = v.onDone or v
      if v.fill or d.add or v.lid then anyFill = true end
    end
    ok(not anyFill, string.format('[%s] 非杯装产品（serveNow）不该有液体/配料/盖子字段', name))
  end
end

print('== 连按步的"手法"（press）==')
-- ★★ 用户 2026-10-01 定的口径：**柠檬锤只干两件事** —— 捣碎果肉、压缩出干冰。
--   所以这里把"哪一步该用锤子"钉死；多标一步（拿锤子去加水/摇匀）或漏标都要红。
local PRESS_OK = { hammer = true, pump = true, shake = true }
local expectedHammer = {            -- 产品 id → 第几步（1 基）
  dryice = { [2] = true, [3] = true },   -- ★ 压缩挪到最前面后，锤子步变成第 2、3 步
  newton = { [1] = true },
  peach  = { [3] = true },
}
local hammerSet, pressMissing, pressBad, hammerWrong = {}, 0, 0, 0
for _, p in ipairs(all) do
  for i, st in ipairs(p.steps) do
    if st.kind == 'mash' then
      local pr = st.press
      if not pr then
        pressMissing = pressMissing + 1
        print(string.format('  X   [%s] 第 %d 步是连按步却没写 press（玩家不知道该用哪个动作）', p.name, i))
      elseif not PRESS_OK[pr] then
        pressBad = pressBad + 1
        print(string.format('  X   [%s] 第 %d 步 press="%s" 不是合法手法', p.name, i, tostring(pr)))
      elseif pr == 'hammer' then
        hammerSet[p.id .. '#' .. i] = true
        local want = expectedHammer[p.id] and expectedHammer[p.id][i]
        if not want then
          hammerWrong = hammerWrong + 1
          print(string.format('  X   [%s] 第 %d 步标了 hammer，但柠檬锤**只该用于捣碎果肉/压缩出干冰**：%s', p.name, i, tostring(st.t)))
        end
      end
    elseif st.press then
      pressBad = pressBad + 1
      print(string.format('  X   [%s] 第 %d 步不是连按步却有 press', p.name, i))
    end
  end
end
-- 反向：该用锤子的步一个都不能漏
for pid, idxs in pairs(expectedHammer) do
  for i in pairs(idxs) do
    if not hammerSet[pid .. '#' .. i] then
      hammerWrong = hammerWrong + 1
      print(string.format('  X   [%s] 第 %d 步应当用柠檬锤（捣果肉/压缩），却没标 press=hammer', pid, i))
    end
  end
end
ok(pressMissing == 0, string.format('每个连按步都写了 press（缺 %d 处）', pressMissing))
ok(pressBad == 0, string.format('press 取值都合法（hammer/pump/shake，错 %d 处）', pressBad))
ok(hammerWrong == 0, string.format('柠檬锤只标在"捣碎果肉/压缩出干冰"这 4 步上（错 %d 处）', hammerWrong))
print(string.format('  · 柠檬锤用在：%s', (function()
  local ks = {} for k in pairs(hammerSet) do ks[#ks + 1] = k end table.sort(ks) return table.concat(ks, ' ')
end)()))

print('== 汇总 ==')
ok(missingVis == 0, string.format('每一步都有 vis（缺 %d 处）—— "按了没反应"就是这么来的', missingVis))
ok(badColor == 0, string.format('颜色字段都合法（坏 %d 处）', badColor))
ok(onDoneNonMash == 0, string.format('onDone 只用在 mash 步（错用 %d 处）', onDoneNonMash))
ok(badFill == 0, string.format('液面字段都合法（坏 %d 处）', badFill))
ok(fillJump == 0, string.format('液面从不倒退（倒退 %d 处）', fillJump))
ok(noLid == 0, string.format('每个杯装产品最后都封杯（缺 %d 处）', noLid))
print(string.format('== 器具步（杯子不动、反馈落在器具上）共 %d 步 —— 这些必须另有提示，否则就是"按了没反应" ==', toolOnCup))

print(string.format('== 汇总 ==  passed %d / failed %d', pass, fail))
if fail == 0 then print('✓ 视觉增量数据体检通过') end
