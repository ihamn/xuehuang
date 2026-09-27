// ui-diff.mjs —— "屏幕上到底有没有变"的硬量法
//
// 用户的判定（2026-09-27）：日志里连按进度 0/4→1/4→… 在变，**但游戏画面上纹丝不动**。
//   ⇒ 逻辑在动、屏幕不动。这类问题必须直接量**运行时控件树**，不能再用日志推。
//
// 做法：每按一次键，把**所有可见控件的文字**抓一份快照，逐字段 diff。
//   变了的字段 / 没变的字段都列出来，并标出哪些控件属于工位卡。

import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const BUNDLE = path.resolve(ROOT, 'dist/xuehuang.lua');
const SIM = 'D:/miliastra-beyond-simulator';
const { createRuntime } = await import(pathToFileURL(path.join(SIM, 'client/lua-runtime/src/index.js')).href);

const rt = createRuntime({ canvasWidth: 1280, canvasHeight: 720 });
const root = rt.addRoot({ name: 'Canvas', kind: 'container' });
root.SetActive(true);
for (const [i, k] of [[1, 'image'], [2, 'textbox'], [3, 'cursor'], [4, 'container']]) rt.registerTemplate(i, { kind: k });
const lines = () => (rt.logs || []).map(x => String(x.text || ''));
rt.mountScript({
  path: 'main',
  source: fs.readFileSync(BUNDLE, 'utf8'),
  control: root,
  params: { autoplay: 1, keyLog: 1, stateEvery: 1 },
});

const DT = 1 / 30;
function snapshot() {
  const out = {};
  (function walk(c, depth) {
    const n = String(c.name || '');
    if (n) out[n] = {
      text: c.text === undefined ? null : String(c.text),
      active: c.active, visible: c.visible,
      color: c.imageColor === undefined ? null : c.imageColor,
      w: c.sizeDeltaX, h: c.sizeDeltaY, x: c.anchoredPositionX, y: c.anchoredPositionY,
    };
    for (const k of (c.children || [])) walk(k, depth + 1);
  })(root, 0);
  return out;
}
function diff(a, b) {
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  const out = [];
  for (const k of keys) {
    const x = a[k], y = b[k];
    if (!x || !y) { out.push(k + ': 控件存在性变化'); continue; }
    if (x.text !== y.text) out.push(`${k}.text: "${x.text}" → "${y.text}"`);
    if (x.active !== y.active) out.push(`${k}.active: ${x.active} → ${y.active}`);
    if (x.visible !== y.visible) out.push(`${k}.visible: ${x.visible} → ${y.visible}`);
    if (x.color !== y.color) out.push(`${k}.imageColor: ${x.color} → ${y.color}`);
    if (x.w !== y.w || x.h !== y.h) out.push(`${k}.size: ${x.w}x${x.h} → ${y.w}x${y.h}`);
  }
  return out;
}

const KEY = { shake: 'KeyboardCraftspersonKey13Down', fire: 'KeyboardCraftspersonKey15Down',
              chem: 'KeyboardCraftspersonKey20Down', brew: 'KeyboardCraftspersonKey18Down' };

// 等到某个工位有活（tap/mash 都行 —— 这两种逻辑上每按必变）
const workRe = /work=\[([^\]]*)\]/;
let sid = null;
for (let f = 0; f < 30 * 60 && !sid; f++) {
  rt.step(DT);
  const st = lines().filter(x => x.indexOf('[STATE]') >= 0).pop();
  if (!st) continue;
  const m = workRe.exec(st);
  if (!m) continue;
  for (const piece of m[1].split(' ')) {
    if (!piece.includes(':-')) { sid = piece.split(':')[0]; break; }
  }
}
if (!sid) { console.log('没等到"工位有活"，无法量'); process.exit(1); }
const st0 = lines().filter(x => x.indexOf('[STATE]') >= 0).pop().trim();
console.log(`— 按键后"控件树"有没有变 — 工位=${sid}`);
console.log(`  逻辑状态：${st0}`);

const nameList = ['StS_' + sid, 'StB_' + sid, 'St_' + sid + '_box', 'St_' + sid + '_panel'];
const stsText = ['StS_shake', 'StS_fire', 'StS_chem', 'StS_brew'];

const before = snapshot();
console.log(`\n  按键前（相关控件）：`);
for (const n of nameList.concat(stsText)) if (before[n]) console.log(`    ${n.padEnd(18)} text="${before[n].text}" color=${before[n].color}`);

// ★ 按一次键（不 step）—— 与真机"按一下"等价
rt.injectKey(KEY[sid]);
const after = snapshot();
const d = diff(before, after);
console.log(`\n  按键**后立刻**（不 step 帧）控件树变化：${d.length} 处`);
for (const x of d.slice(0, 14)) console.log(`    ${x}`);
if (!d.length) console.log('    （控件树一处都没变）');

// 再 step 一帧，看是不是"下一帧才变"
rt.step(DT);
const after2 = snapshot();
const d2 = diff(after, after2);
console.log(`\n  再走 1 帧后控件树变化：${d2.length} 处`);
for (const x of d2.slice(0, 14)) console.log(`    ${x}`);
if (!d2.length) console.log('    （控件树一处都没变）');

console.log(`\n  逻辑侧最新 STATE：${(lines().filter(x => x.indexOf('[STATE]') >= 0).pop() || '').trim()}`);
console.log(`  画面侧 StS_${sid} = "${after2['StS_' + sid] && after2['StS_' + sid].text}"`);
rt.destroy();
