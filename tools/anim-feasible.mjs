// anim-feasible.mjs —— 验证"每帧改控件属性"能不能变成画面上的运动
//
// 为什么要先验证：动画 = 每帧改 pos/scale/rotation。
//   如果这个平台上"脚本改属性 → 画面不动"（前面键盘那条线就是卡在这儿），
//   那所有演出方案都是空中楼阁，必须先换路子（Tween / 引擎动画）。
//
// 做法：直接写一份最小脚本，让一个图片控件每帧右移，读运行时控件树的真实坐标看它有没有动。

import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const SIM = 'D:/miliastra-beyond-simulator';
const { createRuntime } = await import(pathToFileURL(path.join(SIM, 'client/lua-runtime/src/index.js')).href);

const SRC = `
local root = script.object
local frames = 0
local img = nil
local tweenImg = nil

function OnInit() script:EnableUpdate(true) end
function OnStart()
  img = game.InstantiateClientUIControl(1, root)
  img.name = 'AnimImg'
  img:SetActive(true) img:SetVisible(true)
  img.sizeDeltaX = 60 img.sizeDeltaY = 60
  img.anchoredPositionX = -200 img.anchoredPositionY = 0

  -- 对照组：用官方 Tween 让它同时往右更远
  tweenImg = game.InstantiateClientUIControl(1, root)
  tweenImg.name = 'TweenImg'
  tweenImg:SetActive(true) tweenImg:SetVisible(true)
  tweenImg.sizeDeltaX = 60 tweenImg.sizeDeltaY = 60
  tweenImg.anchoredPositionX = -200 tweenImg.anchoredPositionY = 120
  pcall(function()
    game.Tween(tweenImg, { anchoredPositionX = 200 }, 1.0):SetEase(Enum.EaseType.Linear):Play()
  end)
end
function OnUpdate(dt)
  frames = frames + 1
  if img then
    -- ★ 每帧手改属性（这是所有演出的基本手段）
    img.anchoredPositionX = -200 + frames * 4
    pcall(function() img.localRotationZ = (frames * 3) % 360 end)
  end
end
return { OnInit = OnInit, OnStart = OnStart, OnUpdate = OnUpdate }
`;

const rt = createRuntime({ canvasWidth: 1280, canvasHeight: 720 });
const root = rt.addRoot({ name: 'Canvas', kind: 'container' });
root.SetActive(true);
for (const [i, k] of [[1, 'image'], [2, 'textbox'], [3, 'cursor'], [4, 'container']]) rt.registerTemplate(i, { kind: k });
rt.mountScript({ path: 'main', source: SRC, control: root, params: {} });

function read(name) {
  let out = null;
  (function walk(c) {
    if (out) return;
    if (String(c.name || '') === name) { out = c; return; }
    for (const k of (c.children || [])) walk(k);
  })(root);
  return out;
}
const DT = 1 / 30;
const samples = [];
for (let f = 0; f < 45; f++) {
  rt.step(DT);
  if (f % 10 === 0) {
    const a = read('AnimImg'), b = read('TweenImg');
    samples.push({
      f,
      animX: a && a.anchoredPositionX, animRot: a && a.localRotationZ,
      tweenX: b && b.anchoredPositionX,
    });
  }
}
console.log('— 每帧改属性 vs 官方 Tween：画面坐标有没有动 —');
for (const s of samples) {
  console.log(`  帧 ${String(s.f).padStart(2)}  AnimImg.x=${String(Math.round(s.animX)).padStart(5)}  rot=${String(s.animRot).padStart(3)}  TweenImg.x=${String(Math.round(s.tweenX)).padStart(5)}`);
}
const first = samples[0], last = samples[samples.length - 1];
const animMoved = Math.abs(last.animX - first.animX) > 5;
const tweenMoved = Math.abs(last.tweenX - first.tweenX) > 5;
console.log('');
console.log(`  每帧手改属性：${animMoved ? '✓ 坐标真的在动' : '✗ 坐标没动'}`);
console.log(`  官方 Tween  ：${tweenMoved ? '✓ 坐标真的在动' : '✗ 坐标没动（或 Tween 不可用）'}`);
console.log(`\n结论：${animMoved || tweenMoved ? '至少一条路可行 → 演出可以做' : '两条路都不动 → 必须换实现方式'}`);
rt.destroy();
