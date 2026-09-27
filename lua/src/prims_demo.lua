-- prims_demo.lua —— 把 6 个基础形状铺开显示（附编号文字），先把"图元长什么样"验清楚
--
--   node tools/lua-test.mjs --entry=prims_demo --out=dist/prims_demo.lua
--   node tools/sim-run.mjs dist/prims_demo.lua --frames=3 --json=dist/prims.json
--   node tools/props-render.mjs dist/prims.json preview/design/prims.png
--
-- 为什么要这一页：我在设计"锥体/杯身"时，一上来就假设"三角形尖朝上"，
--   然后为了掰成尖朝下又加了旋转和遮挡块 —— 全是建立在一个**没验证过的假设**上。
--   正确的顺序是：先把 6 个基础形状按真实素材号铺出来看清朝向，再拿它们拼东西。
--   （同理：真机上还要再确认一次，因为模拟器的图元是我自己渲染的。）

local H = require('host')

local root = nil

-- 形状清单：素材号 + 名字（按官方素材库分类）
local SHAPES = {
  { art = 100001, name = '100001 方块' },
  { art = 100002, name = '100002 圆' },
  { art = 100003, name = '100003 三角' },
  { art = 100004, name = '100004 四角星' },
  { art = 100005, name = '100005 五角星' },
  { art = 100006, name = '100006 圆环' },
}

-- ★ 标签用**图元画色条**而不是文本框：模拟器里模板文本框自带白底、
--   且 `t.text` / `fontColor` 在沙箱里不生效（画出来是一排白条，看不到字）。
--   这里改成"每个字符一根色条"—— 只为在图上能认出是哪一档，不做可读文字。
local GLYPH = {
  ['0'] = '111101101101111', ['1'] = '010010010010010', ['2'] = '111001111100111',
  ['3'] = '111001111001111', ['4'] = '101101111001001', ['5'] = '111100111001111',
  ['6'] = '111100111101111', ['7'] = '111001001001001', ['8'] = '111101111101111',
  ['9'] = '111101111001111', [' '] = '000000000000000',
  ['方'] = '111101101101111', ['圆'] = '111101111101111', ['三'] = '111001010010010',
  ['角'] = '111101111101101', ['四'] = '111100100100111', ['星'] = '010110010110010',
  ['五'] = '111100111001111', ['环'] = '111101101101111', ['转'] = '001111001111001',
  ['°'] = '110110000000000',
}
local function textBars(cfgParent, str, x, y, px)
  px = px or 3
  local total = #str * 4 * px
  local bx = x - total / 2
  for i = 1, #str do
    local ch = str:sub(i, i)
    local g = GLYPH[ch] or GLYPH['0']
    for row = 1, 5 do
      for col = 1, 3 do
        if g:sub((row - 1) * 3 + col, (row - 1) * 3 + col) == '1' then
          local b = H.spawn(cfgParent, 'img', 'g' .. i .. '_' .. row .. col)
          H.setSize(b, px, px)
          H.setPos(b, bx + (i - 1) * 4 * px + (col - 1) * px, y + (3 - row) * px)
          H.setColor(b, 170, 195, 235, 255)
        end
      end
    end
  end
end

function OnInit() script:EnableUpdate(true) end

function OnStart()
  root = script.object

  local W = 1280
  local x0 = -W / 2 + 120      -- 第一个的横坐标（画布中心为 0）
  local y0 = 120
  local stepX = 175
  local cfgTxt = { root = root, img = 1, text = 2 }

  for i, s in ipairs(SHAPES) do
    local cfg = { root = root, img = 1, text = 2, art = s.art }
    local c = H.spawn(cfg, 'img', 'P' .. s.art)
    H.setSize(c, 110, 110)
    H.setPos(c, x0 + (i - 1) * stepX, y0)
    H.setColor(c, 224, 190, 130, 255)             -- 统一颜色，只看形状

    textBars(cfgTxt, s.art .. '', x0 + (i - 1) * stepX, y0 - 76, 3)
    print(string.format('[PRIMS] 建 %s  尺寸110x110', s.name))
  end

  -- 对照：三角转 180°（看旋转怎么作用）
  local c = H.spawn({ root = root, img = 1, text = 2, art = 100003 }, 'img', 'Ptri180')
  H.setSize(c, 110, 110)
  H.setPos(c, x0, y0 - 250)
  H.setColor(c, 224, 190, 130, 255)
  pcall(function() c.localRotationZ = 180 end)
  textBars(cfgTxt, '100003', x0, y0 - 322, 3)
  local label = H.spawn(cfgTxt, 'img', 'Ptri180Tag')
  H.setSize(label, 60, 8); H.setPos(label, x0, y0 - 345)
  H.setColor(label, 255, 150, 120, 255)           -- 红条 = "转过 180°"
  print('[PRIMS] 另建：三角旋转 180° 对照')
end

function OnUpdate(dt) end
function OnDestroy() end
