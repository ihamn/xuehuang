// state-diff.mjs —— 逐帧对比"玩家按下键之后，客户端画面上该变的文字变了没有"
//
//   node tools/state-diff.mjs --seconds=8
//
// 为什么需要：真机日志已经证明**逻辑在动**（[act] → [雪皇] 萃茶 → 0（取速溶咖啡粉）），
//   但用户看到的是"客户端画面没有状态更新"。这两件事必须能分开测：
//   · 逻辑层：用 lua/test/*.lua 测（已有）
//   · 表现层：**这个工具** —— 它读运行时控件树里的**真实文本**，看画面会不会跟着变。
//
// 输出：每个"状态变化帧"打印一次工位卡 + 小票卡 + 打包台的文字。

import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const argOf = (n, d) => { const h = process.argv.find(a => a.startsWith('--' + n + '=')); return h ? h.slice(n.length + 3) : d; };
const W = Number(argOf('w', 1280)), H = Number(argOf('h', 720));
const SECONDS = Number(argOf('seconds', 10));
const BUNDLE = path.resolve(ROOT, argOf('bundle', 'dist/xuehuang.lua'));
const SIM = 'D:/miliastra-beyond-simulator';
const { createRuntime, walkControls } = await import(pathToFileURL(path.join(SIM, 'client/lua-runtime/src/index.js')).href);

const rt = createRuntime({ canvasWidth: W, canvasHeight: H });
const root = rt.addRoot({ name: 'Canvas', kind: 'container' });
root.SetActive(true);
for (const [i, k] of [[1, 'image'], [2, 'textbox'], [3, 'cursor'], [4, 'container']]) rt.registerTemplate(i, { kind: k });
// ★ 不开 autoplay：我们要看"没人在打"时画面的样子，再自己按键
rt.mountScript({ path: 'main', source: fs.readFileSync(BUNDLE, 'utf8'), control: root, params: { keyLog: 0 } });

function texts() {
  const out = {};
  (function collect(c) {
    const n = String(c.name || '');
    if (!/^img|^txt|^cursor|^container/.test(n) && c.text !== undefined) {
      const t = String(c.text || '');
      if (t) out[n] = t;
    }
    if (c.text !== undefined && c.text !== '' && /^Sl|^St|^Od|^Hud|^Pack|^Data/.test(n)) out[n] = String(c.text);
    for (const k of (c.children || [])) collect(k);
  })(root);
  return out;
}
function keyPress(name) { rt.injectKey(name); }
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// 1) 先跑 4 秒让客人进店、票出来
const DT = 1 / 30;
for (let f = 0; f < Math.round(4 / DT); f++) rt.step(DT);
openGame();
console.log('— 开门后（等 3 秒让客人进店）—');
for (let f = 0; f < 90; f++) rt.step(DT);
// ★ 开门：三种都试一遍（模拟器的注入方式与真机不同，先确认哪条能通）
function openGame() {
  // ① 点击：走"光标检测区域"控件的 CursorClick（真机点屏幕 = 这条）
  let area = null;
  (function find(c) {
    if (!area && String(c.name || '') === '光标检测区域') area = c;
    for (const k of (c.children || [])) find(k);
  })(root);
  if (area) { try { area.SimulateCursorClick(); console.log('（已调用 光标检测区域:SimulateCursorClick）'); } catch (e) { console.log('SimulateCursorClick 失败: ' + e.message); } }
  // ② 确认键：Backspace（奇匠按键42）
  rt.injectKey('KeyboardCraftspersonKey42Down');
  // ③ 兜底：直接按 1/2/3 里没用的… 不用了，前两条应该够
}
for (let f = 0; f < 30; f++) rt.step(DT);

let prev = texts();
console.log('\n【画面文字快照 #0（还没按键）】');
for (const [k, v] of Object.entries(prev)) console.log(`  ${k.padEnd(14)} ${v}`);

// 2) 按 P（萃茶）20 次，每次之后对比画面文字有没有变
console.log('\n— 连按 20 次 P（萃茶），每次看画面文字是否变化 —');
let changes = 0;
for (let i = 1; i <= 20; i++) {
  keyPress('KeyboardCraftspersonKey18Down');
  for (let f = 0; f < 4; f++) rt.step(DT);
  const now = texts();
  const diff = [];
  for (const k of new Set([...Object.keys(prev), ...Object.keys(now)])) {
    if (prev[k] !== now[k]) diff.push(`${k}: "${prev[k] || ''}" → "${now[k] || ''}"`);
  }
  if (diff.length) {
    changes++;
    console.log(`\n  按第 ${i} 次 → 变化 ${diff.length} 处`);
    for (const d of diff.slice(0, 8)) console.log(`     ${d}`);
  } else {
    console.log(`  按第 ${i} 次 → 画面文字**没有任何变化**`);
  }
  prev = now;
}

console.log(`\n结论：20 次按键里，画面文字变化了 ${changes} 次。`);
if (changes === 0) console.log('  ⇒ 表现层没跟着状态变（这就是用户说的"客户端上没有状态更新"）。');
else console.log('  ⇒ 表现层会跟着状态变。');
rt.destroy();
