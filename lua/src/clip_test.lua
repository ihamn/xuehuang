-- clip_test.lua —— 实测两件事（决定"用三角形裁出梯形"这条路走不走得通）
--
--   node tools/lua-test.mjs --entry=clip_test --out=dist/clip_test.lua
--   node tools/sim-run.mjs dist/clip_test.lua --frames=2 --json=dist/clip.json
--   node tools/props-render.mjs dist/clip.json preview/design/clip-test.png
--
-- 问题①：父控件的子控件**超出父矩形**时，是被引擎裁掉、还是照常画出来？
--    · 若"照常画出来" → 没法用"把三角尖放到父控件外"来裁 → 得用**遮挡**
--    · 若"被裁掉"     → 一个三角形 + 一个裁剪框就能做出梯形（最省控件）
-- 问题②：`Enum.ImageType.Basic`（基础）和 `Stretch`（拉伸）哪个能把三角拉成细长？
--    做梯形需要又宽又扁 / 又窄又高的三角，得知道哪个 imageType 才不糊。

local H = require('host')

local root = nil
local frames = 0

function OnInit() script:EnableUpdate(true) end

function OnStart()
  root = script.object
  local cfg = { root = root, img = 1, text = 2 }

  ---------------------------------------------------------------
  -- 实验 A：子控件超出父矩形，会不会被裁？
  --   父：200×200 的方块（放在 x=-400）
  --   子：600×600 的方块（比父大 3 倍）
  --   ★ 实测结论：**不裁**。读回尺寸仍是 600×600，图上也是超出父框照常画。
  --     ⇒ "把三角尖摆到父框外让它被裁掉"这条路**不成立**，只能用遮挡。
  ---------------------------------------------------------------
  local pA = H.spawn(cfg, 'img', 'A_parent')
  H.setPos(pA, -400, 100); H.setSize(pA, 200, 200)
  H.setColor(pA, 60, 90, 140, 255)

  local cA = H.spawn(cfg, 'img', 'A_child', pA)
  H.setPos(cA, 0, 0); H.setSize(cA, 600, 600)
  H.setColor(cA, 230, 120, 60, 200)

  local w, h = -1, -1
  pcall(function() w = cA.sizeDeltaX; h = cA.sizeDeltaY end)
  print(string.format('[CLIP] A 子控件读回尺寸 = %s x %s（我给的是 600x600 → 引擎没替我裁）', tostring(w), tostring(h)))

  -- ★ 图形控件要出"三角形"，必须走 cfg.art（H.spawn 内部用 SetImage(StaticReference, cfg.art)）。
  --   我上一版在脚本里直接调 tri:SetImage(...)，沙箱里不生效 → 画出来全是方块。踩过。
  local art = cfg.art or 100003
  local cfgArt = { root = root, img = 1, text = 2, art = art }

  ---------------------------------------------------------------
  -- 实验 B：遮挡法 —— 三角 + 一块盖住尖头的方块
  --   注意：遮挡块用的是**画布底色**。所以只有在"背景是纯色"的地方才成立；
  --   叠在别的东西（比如液体上）就不成立（会把底下的东西一起盖掉）。
  ---------------------------------------------------------------
  local tri = H.spawn(cfgArt, 'img', 'B_triangle')
  H.setSize(tri, 100, 140); H.setPos(tri, -80, 30)
  H.setColor(tri, 224, 190, 130, 255)
  local mask = H.spawn(cfg, 'img', 'B_mask')
  H.setSize(mask, 140, 92); H.setPos(mask, -80, -74)      -- 盖住下段 → 留下梯形
  H.setColor(mask, 10, 14, 24, 255)

  ---------------------------------------------------------------
  -- 实验 C：对照 —— 同样尺寸的方块（模拟"叠条法"的一层）
  ---------------------------------------------------------------
  local sq = H.spawn(cfg, 'img', 'C_square')
  H.setSize(sq, 100, 48); H.setPos(sq, 180, 30)
  H.setColor(sq, 224, 190, 130, 255)

  ---------------------------------------------------------------
  -- 实验 D：两个三角形拼一个"上下都收"的形状（漏斗/甜筒相反向）
  ---------------------------------------------------------------
  local t1 = H.spawn(cfgArt, 'img', 'D_tri1')
  H.setSize(t1, 100, 70); H.setPos(t1, 460, 60)          -- 尖朝下的三角
  H.setColor(t1, 224, 190, 130, 255)
  local t2 = H.spawn(cfgArt, 'img', 'D_tri2')
  H.setSize(t2, 100, 70); H.setPos(t2, 460, -10)         -- 再一个（看朝向）
  H.setColor(t2, 200, 170, 120, 255)
  pcall(function() t2.localRotationZ = 180 end)          -- 转 180° → 尖朝上？

  print('[CLIP] 已建：A 裁剪试验 / B 三角+遮挡 / C 方块对照 / D 三角形旋转测试（art=' .. tostring(art) .. '）')
end

function OnUpdate(dt)
  frames = frames + 1
  if frames == 2 then
    print('[CLIP] 第 2 帧：控件总数（含画布）' )
  end
end

function OnDestroy() end
