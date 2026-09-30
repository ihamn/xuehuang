-- glyph_probe.lua —— 「用文字当像素画」可行性探针（2026-10-01）
--
-- 为什么要它：用 █ ■ ● 这类文字把一个 16×27 的像素场压成**几个文本框**，
--   能把 433 个控件的火焰压成个位数控件（按颜色分层：每种颜色一个文本框）。
--   但这条路卡在三个**只能真机验**的问题上 —— 这个探针一次回答它们。
--
-- 三问：
--   ① 字库有没有这些字形（缺字会画豆腐块 / 问号）
--   ② U+3000（表意空格）与全角方块**是否等宽**（决定"按颜色分层"能否对齐）
--   ③ 多行方块的行高**是否等于字号**（不等于就露横缝，拼不出实心块）
--
-- 怎么看（截图即可）：
--   每块**红底** = "期望方块覆盖的范围"，上面的方块应**正好铺满**它：
--     · 长度对不上   → 字宽 ≠ 字号 ⇒ ②不成立
--     · 上下有横缝   → 行高 > 字号 ⇒ ③不成立
--     · 方框 / 问号  → 该字形不在字库 ⇒ ①不成立
--
-- 用法：node tools/lua-test.mjs --entry=glyph_probe --out=dist/glyph_probe.lua
local H = require('host')

local root, cfg
local built = false

local SAMPLES = '█ ■ ● ▲ ◆ ▓ ▒ ░ ▄ ▀'      -- 待测字形（合成时会转成 Lua 十进制转义）
local BLOCK   = '█'                          -- U+2588 全块：像素画主力
local IDSP    = '\227\128\128'               -- U+3000 表意空格（显式转义，避免看不见）
local SP      = ' '                          -- 普通空格（做对照）

-- 建一个"左对齐 + 顶对齐 + 关自适应字号"的文本框（格子要对齐，这三条缺一不可）
local function txt(name, x, y, w, h, s, size, col)
  local c = H.spawn(cfg, 'text', name)
  H.setPos(c, x, y)
  H.setSize(c, w, h)
  c.adaptiveFontSize = false
  c.fontSize = size
  pcall(function() c.horizontalAlignment = Enum.TextHorizontalAlignment.Left end)
  pcall(function() c.verticalAlignment = Enum.TextVerticalAlignment.Top end)
  if col then H.setColor(c, col[1], col[2], col[3], 255) end
  c.text = s
  return c
end

-- 红底尺子：用基础方块素材铺出"期望的像素范围"（宽 = 列数 × 字号，高 = 行数 × 字号）
local function ruler(name, x, y, w, h)
  local c = H.spawn(cfg, 'img', name)
  H.setPos(c, x, y)
  H.setSize(c, w, h)
  H.setColor(c, 190, 60, 60, 255)
  return c
end

local WORLD = { 255, 255, 255 }
local NOTE  = { 190, 190, 190 }

local function field(name, x, y, cols, rows, size, ch)
  local s = {}
  for i = 1, rows do s[i] = string.rep(ch or BLOCK, cols) end
  ruler(name .. '_r', x, y, cols * size, rows * size)
  return txt(name, x, y, cols * size + 40, rows * size + 20, table.concat(s, '\n'), size, WORLD)
end

function OnInit()
  script:EnableUpdate(true)
end

function OnStart()
  if built then return end
  built = true
  local ok, err = pcall(function()
    root = script.object
    root:SetActive(true)
    cfg = H.setup(root)

    txt('T0', 0, 390, 1600, 40, 'GLYPH PROBE  -  blocks must cover the red bars exactly', 26, WORLD)

    -- ① 字形存在性
    txt('A0', 0, 330, 1600, 44, SAMPLES, 28, WORLD)
    txt('A0c', 0, 302, 1600, 22, 'A: glyphs above - tofu / question mark = missing glyph', 14, NOTE)

    -- ②-a 等宽：16 个全块 @16 → 红尺宽 16*16 = 256
    ruler('B0_r', 0, 240, 256, 18)
    txt('B0', 0, 240, 400, 26, string.rep(BLOCK, 16), 16, WORLD)
    txt('B0c', 0, 214, 1000, 22, 'B0: 16 blocks vs red 256px (=16*16)', 13, NOTE)

    -- ②-b 间隔混排：块 + U+3000，等宽则每块都落在红尺上
    ruler('B1_r', 0, 172, 256, 18)
    txt('B1', 0, 172, 400, 26, string.rep(BLOCK .. IDSP, 8), 16, WORLD)
    txt('B1c', 0, 146, 1000, 22, 'B1: block+U+3000 x8 - must still cover the red bar', 13, NOTE)

    -- ②-c 普通空格对照（预期会漂移，用来确认"必须用 U+3000"）
    txt('B2', 0, 106, 400, 26, string.rep(BLOCK .. SP, 8), 16, WORLD)
    txt('B2c', 0, 80, 1000, 22, 'B2: block+normal space - drift expected', 13, NOTE)

    -- ③ 行高：8 行 × 16 全块 @16 → 红尺 256×128，铺满=无缝
    field('C0', 0, -30, 16, 8, 16)
    txt('C0c', 0, -110, 1000, 22, 'C0: 8 rows x 16 blocks vs red 256x128 - seams?', 13, NOTE)

    -- ④ 换字号 24 再测一次 → 红尺 384×72
    field('D0', 0, -170, 16, 3, 24)
    txt('D0c', 0, -222, 1000, 22, 'D0: 3 rows x 16 blocks @24 vs red 384x72', 13, NOTE)

    H.say('glyph', 'BUILD=glyph-probe-1 控件=%s 字号档=16/24', tostring(#(root.children or {})))
  end)
  if not ok then H.say('glyph', 'BUILD-FAILED %s', tostring(err)) end
end

function OnUpdate(dt) end
