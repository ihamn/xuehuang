// key-flush.mjs —— 按键是否**当场**把画面刷了（不需要等下一帧 OnUpdate）
//
//   node tools/key-flush.mjs
//
// 用户的原始描述（2026-09-27，这是本工具的由来）：
//   「某个工作区出现了任务，**按按键**哪怕日志正常，客户端那**依旧不会显示这个任务有任何变化**；
//     而**拿鼠标去点那个任务**，就会正常加进度完成任务。」
//
// 两条路都调 G.act（逻辑一样），差别只能在"谁在之后把画面刷了"：
//   · 鼠标：click 分支跑在 OnUpdate 的 pump 里 → 紧接着当帧 V.sync → 画面立刻变
//   · 键盘：回调是引擎直接调进来的，跑在 OnUpdate **之外**（帧与帧之间）→ 自己不刷画面
//
// 本工具就测这一件事：**注入一次按键（不 step 帧）**，看工位卡文字有没有变。
//   修好之前：不变（要等下一次 OnUpdate）
//   修好之后：当场变

import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const BUNDLE = path.resolve(ROOT, 'dist/xuehuang.lua');
const SIM = 'D:/miliastra-beyond-simulator';
const { createRuntime } = await import(pathToFileURL(path.join(SIM, 'client/lua-runtime/src/index.js')).href);

const W = 1280, H = 720;
const rt = createRuntime({ canvasWidth: W, canvasHeight: H });
const root = rt.addRoot({ name: 'Canvas', kind: 'container' });
root.SetActive(true);
for (const [i, k] of [[1, 'image'], [2, 'textbox'], [3, 'cursor'], [4, 'container']]) rt.registerTemplate(i, { kind: k });
function logLines() { return (rt.logs || []).map(x => String(x.text || '')); }
rt.mountScript({
  path: 'main',
  source: fs.readFileSync(BUNDLE, 'utf8'),
  control: root,
  params: { autoplay: 1, keyLog: 1, stateEvery: 1 },   // autoplay 负责开门；之后我们手动按键
});

const DT = 1 / 30;
function findCtrl(name) {
  let out = null;
  (function walk(c) {
    if (out) return;
    if (String(c.name || '') === name) { out = c; return; }
    for (const k of (c.children || [])) walk(k);
  })(root);
  return out;
}
const textOf = (n) => { const c = findCtrl(n); return c ? String(c.text === undefined ? '' : c.text) : ''; };

let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('  OK  ' + m); } else { fail++; console.log('  X   ' + m); } };

// ── 跑到"某个工位确实有活"的那一刻（读 [STATE] 的 work=[…]）──
const workRe = /work=\[([^\]]*)\]/;
function workStation() {
  const lines = logLines().filter(x => x.indexOf('[STATE]') >= 0);
  if (!lines.length) return null;
  const m = workRe.exec(lines[lines.length - 1]);
  if (!m) return null;
  for (const piece of m[1].split(' ')) {
    if (!piece.includes(':-')) return piece.split(':')[0];
  }
  return null;
}
const KEYOF = { shake: 'KeyboardCraftspersonKey13Down', fire: 'KeyboardCraftspersonKey15Down',
                chem: 'KeyboardCraftspersonKey20Down', brew: 'KeyboardCraftspersonKey18Down' };

let sid = null;
for (let f = 0; f < 30 * 40 && !sid; f++) {
  rt.step(DT);
  sid = workStation();
}
console.log('— 按键"当场刷画面"判定 —');
if (!sid) {
  console.log('  X   40 秒内没等到"某个工位有活"的时刻，无法判定');
  process.exit(1);
}
console.log(`  等到有活的工位：${sid}（卡上文字 "${textOf('StS_' + sid)}"）`);

// ── 关键：注入一次按键，**不 step 帧**，看画面有没有变 ──
// ★★ 2026-09-27 第三次修正（用户口径）：**期望值反了**。
//   原来要求"按键当帧控件树就变"——那意味着在**键回调（帧外/输入上下文）**里写控件属性，
//   真机上正是这样才"逻辑变了、屏幕不重绘"（用户：「日志正常，客户端那依旧不会显示变化」；
//   而鼠标点击跑在帧内，所以正常）。
//   现在键盘回调只登记，处理与刷画面都在**下一个 OnUpdate 帧内**完成 ⇒ 期望：
//     · 不 step 帧：控件树**不该**变（帧外不该写属性）
//     · step 1 帧后：控件树**必须**变（帧内处理 + 帧内绘制）
const before = textOf('StS_' + sid);
const beforeTip = textOf('HudTip');
rt.injectKey(KEYOF[sid]);
const afterNoStep = textOf('StS_' + sid);
rt.step(DT);                      // 走一帧：这才是引擎正常重绘的时机
const afterOneFrame = textOf('StS_' + sid);
const afterTip = textOf('HudTip');

console.log(`  按键前 StS_${sid} = "${before}"`);
console.log(`  按键后（不 step） = "${afterNoStep}"`);
console.log(`  再走 1 帧        = "${afterOneFrame}"`);
console.log(`  HudTip: "${beforeTip}" → "${afterTip}"`);

ok(afterNoStep === before,
  '键回调（帧外）**不**直接写控件属性 —— 避免真机"帧外写属性不重绘"的那个坑');
ok(afterOneFrame !== before,
  '走一帧后控件树就变了 → 键盘路径与鼠标点击在引擎看来同类（都在帧内改属性并重绘）');
const dispatchLog = logLines().filter(x => x.indexOf('[DISPATCH]') >= 0).slice(-1)[0] || '';
console.log(`  最后一次派发日志：${dispatchLog.trim() || '（没有）'}`);

console.log(`\n结果：passed ${pass} / failed ${fail}`);
rt.destroy();
process.exit(fail ? 1 : 0);
