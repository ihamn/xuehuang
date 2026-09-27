// hold-repro.mjs —— 精确复现"按住类步骤按键无反应"
//
// 真机证据（2026-09-27 20:04 日志）：
//   [BRANCH] chem kind=mash oneTap=true done=0.000 → 1.000 → … → 4.000   ← 连按类正常
//   [BRANCH] chem kind=hold oneTap=true done=0.000                        ← 按住类按了不变
//   hold:0.0/0.9 ×55 次采样，一次没涨
//
// 本工具只问一个问题：**对着一个 hold 步骤按一次键，这一步会不会收口？**
//   若本地会收口、真机不会 ⇒ 差异在环境（配置取值/分支），继续找；
//   若本地也不收口 ⇒ 我本地就能抓到根因。

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

const HOLD_ACT = { shake: 'KeyboardCraftspersonKey13Down', fire: 'KeyboardCraftspersonKey15Down',
                   chem: 'KeyboardCraftspersonKey20Down', brew: 'KeyboardCraftspersonKey18Down' };

// 跑到"某个工位正好卡在 hold 步骤"的时刻
const holdRe = /work=\[([^\]]*)\]/;
let act = null, sid = null, guard = 0;
for (let f = 0; f < 30 * 60 && !act; f++) {
  rt.step(DT);
  const st = lines().filter(x => x.indexOf('[STATE]') >= 0).pop();
  if (!st) continue;
  const m = holdRe.exec(st);
  if (!m) continue;
  for (const piece of m[1].split(' ')) {
    if (piece.indexOf('hold:') >= 0) { sid = piece.split(':')[0]; act = sid; break; }
  }
}

console.log('— 按住类步骤：按一次键会不会收口 —');
if (!act) { console.log('  X   60 秒内没等到"工位卡在 hold 步骤"的时刻，无法复现'); process.exit(1); }
const before = textOf('StS_' + sid);
console.log(`  等到：${sid}  hold 步骤，卡上文字 "${before}"`);
guard = 0;

// 按一次（不 step 帧）
rt.injectKey(HOLD_ACT[sid]);
const afterOne = textOf('StS_' + sid);
const br = lines().filter(x => x.indexOf('[BRANCH]') >= 0).pop() || '（无 BRANCH）';
console.log(`  按一次后卡面："${afterOne}"`);
console.log(`  运行时分支：${br.trim()}`);

// 再按几次（每次都 step 一帧模拟真实节奏）
for (let i = 0; i < 5; i++) { rt.step(DT); rt.injectKey(HOLD_ACT[sid]); rt.step(DT); }
const afterMany = textOf('StS_' + sid);
console.log(`  再按 5 次后卡面："${afterMany}"`);

const holds = lines().filter(x => x.indexOf('hold:') >= 0);
const progressed = holds.some(x => !x.includes('hold:0.0/0.9'));
ok(afterOne !== before || afterMany !== before,
  '按住类按下去后画面/状态有变化（真机上这里是"纹丝不动"）');
ok(progressed || !afterMany.includes('hold'),
  '按住类步骤最终收口（真机上 hold:0.0/0.9 卡死）');

console.log(`\n结果：passed ${pass} / failed ${fail}`);
rt.destroy();
process.exit(fail ? 1 : 0);
