-- cup_tri_demo.lua —— 用「三角形 + 遮挡」做杯子（对照"叠条法"）
--
--   node tools/lua-test.mjs --entry=cup_tri_demo --out=dist/cup_tri_demo.lua
--   node tools/sim-run.mjs dist/cup_tri_demo.lua --frames=3 --json=dist/cup_tri.json
--   node tools/props-render.mjs dist/cup_tri.json preview/design/cup-tri.png
--
-- ★ 为什么要试这条（用户的想法）：把倒三角的**尖头盖住**，剩下的就是梯形 → 杯身只要 2 个控件。
--   实测前提（tools/sim-run 里验过）：
--     · 千星**不裁**子控件 → 不能靠"把尖头放到框外裁掉"，只能用**遮挡**
--     · 遮挡块是拿**背景色**盖的 → 只在纯色背景上成立（所以杯子里的液体仍然要用叠条法）
--
-- 三角朝向（按渲染器实测）：三角形图元**顶点在上、底边在下**。
--   杯子需要"宽上窄下"→ 把三角**转 180°**（尖朝下），再盖住下半段的尖头。

local H = require('host')
local P = require('props')

local root = nil

function OnInit() script:EnableUpdate(true) end

function OnStart()
  root = script.object
  local cfg = { root = root, img = 1, text = 2, art = 100003 }   -- art：三角形

  -- 反推杯身需要的三角几何
  --   杯：口径 100（顶）、底径 69.2（底）、高 100，侧壁离垂直 8.75°
  --   三角转 180° 后：顶边宽 W、尖在下；把尖头（高度 H_tip）盖住 →
  --   露出高度 h 处的宽度 = W × (h / H_tri)
  --   要 h=100 时宽 69.2、h=0 时宽 100... 直接用相似三角形解：
  --     设三角总高 Htri、顶宽 Wtop；盖住 t 高度后露出 (Htri - t)
  --     露出段：上宽 Wtop，下宽 Wtop × (Htri - t) / Htri
  --   取 Wtop = 108（略宽于口径，视觉上更像杯口外沿）、要下宽 69.2
  --     → (Htri - t)/Htri = 69.2/108 = 0.641 → t = 0.359 × Htri
  --   取 Htri = 280 → t = 100.5，露出高 = 179.5 ≈ 我们要的 100 → 再按比例缩放
  local Wtop, wantBottom = 108, P.cupBottomWidth()
  local ratio = wantBottom / Wtop                      -- 0.641
  -- 让"露出段高度 = 杯高 hh"、且露出段下宽 = ratio×Wtop：
  --   Htri - t = hh  →  下宽/上宽 = hh / Htri = ratio  →  Htri = hh / ratio
  local hh = P.spec.cup.h
  local Htri = hh / ratio
  local triH = Htri
  local Wtri = Wtop

  ---------------------------------------------------------------
  -- ① 方案 T（三角+遮挡）：杯身
  --   三角转 180°（尖朝下），中心放在"露出段中点 + 尖头一半"的位置
  ---------------------------------------------------------------
  local cupX, cupY = -300, 40
  local tipH = Htri - hh                               -- 被盖住的尖头高度
  local tri = H.spawn(cfg, 'img', 'T_triBody')
  H.setSize(tri, Wtri, triH)
  -- 三角中心 y：让它"尖"落在 露出段下沿 - tipH/2
  --   根坐标：露出段从 cupY-? 起算。这里直接把露出段下沿对齐到 y = cupY - hh/2
  local yExposedBottom = cupY - hh / 2
  H.setPos(tri, cupX, yExposedBottom + tipH / 2 + hh / 2 - (triH / 2 - Htri / 2))
  pcall(function() tri.localRotationZ = 180 end)
  H.setColor(tri, 224, 240, 255, 110)                  -- 玻璃

  -- 遮挡块：盖住尖头（用深色 = 画布底色近似）
  local mask = H.spawn(cfg, 'img', 'T_mask')
  H.setSize(mask, Wtri + 40, tipH + 40)
  H.setPos(mask, cupX, yExposedBottom - (tipH + 40) / 2 + 1)
  H.setColor(mask, 10, 14, 24, 255)

  ---------------------------------------------------------------
  -- ② 方案 B（叠条法）：对照，摆在右边
  ---------------------------------------------------------------
  local cup = P.cup(cfg, 'B_cup', 260, 40, P.drink.brom, { maskColor = P.spec.MASK_CANVAS })
  cup.setFill(0.6)

  ---------------------------------------------------------------
  -- ③ 文字标注
  ---------------------------------------------------------------
  local function label(txt, x, y)
    local t = H.spawn(cfg, 'text', 'L' .. txt:sub(1, 6))
    pcall(function()
      t.text = txt
      t.fontSize = 22
      t.fontColor = Color.FromRGBA(200, 220, 255, 255)
    end)
    H.setPos(t, x, y)
    H.setSize(t, 460, 30)
  end
  label('三角+遮挡（用户思路）', -300, 150)
  label('叠条法（32 条）', 260, 150)

  print(string.format('[CUP-TRI] 三角几何：总高 %.0f 顶宽 %.0f 盖住尖头 %.0f 露出 %.0f（下宽应约 %.1f）',
    Htri, Wtri, tipH, hh, Wtri * (hh / Htri)))
  print('[CUP-TRI] 三角+遮挡 = 2 个控件；叠条法 = 32+16+5 个控件')
end

function OnUpdate(dt) end
function OnDestroy() end
