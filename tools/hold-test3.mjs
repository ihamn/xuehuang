// 确定性按住测试：先反复按火系区键，直到当前步变成"按住"类，再验证进度条会不会涨
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const SIM = 'D:/miliastra-beyond-simulator';
const { createRuntime } = await import(pathToFileURL(path.join(SIM, 'client/lua-runtime/src/index.js')).href);
const rt = createRuntime({ canvasWidth: 1815, canvasHeight: 900 });
const root = rt.addRoot({ name: 'Canvas', kind: 'container' });
root.SetActive(true);
for (const [i, k] of [[1, 'image'], [2, 'textbox'], [3, 'cursor'], [4, 'container']]) rt.registerTemplate(i, { kind: k });
rt.mountScript({ path: 'main', source: fs.readFileSync('dist/xuehuang.lua', 'utf8'), control: root, params: {} });
for (let f = 0; f < 5; f++) rt.step(1 / 30);
rt.injectKey('KeyboardJumpKeyDown');
for (let f = 0; f < 200; f++) rt.step(1 / 30);

const find = (c, n) => { if (c.name === n) return c; for (const k of (c.children || [])) { const r = find(k, n); if (r) return r; } return null; };
const stepOf = (id) => String((find(root, 'StS_' + id) || {}).text || '');
const fillW = (id) => Math.round((find(root, 'StB_' + id + '_f') || { sizeDeltaX: 0 }).sizeDeltaX);
const K = 'KeyboardCraftspersonKey15Down', U = 'KeyboardCraftspersonKey15Up';

// 反复短按火系区，直到出现"按住"步骤
let found = false;
for (let i = 0; i < 60 && !found; i++) {
  rt.injectKey(K); for (let f = 0; f < 3; f++) rt.step(1 / 30); rt.injectKey(U);
  for (let f = 0; f < 6; f++) rt.step(1 / 30);
  if (stepOf('fire').includes('按住')) found = true;
}
console.log('  找到按住步骤: ' + found + '  "' + stepOf('fire') + '"');
if (!found) process.exit(0);

// ① 按住 0.4s → 进度条应该有部分填充（小于满），步骤不该完成
rt.injectKey(K);
for (let f = 0; f < 12; f++) rt.step(1 / 30);
const w1 = fillW('fire');
console.log('  按住 0.4s: 进度条宽=' + w1 + '  (应 >1)   步骤="' + stepOf('fire').slice(0, 14) + '"');
// ② 继续按住到 1.2s → 完成、进入下一步
for (let f = 0; f < 24; f++) rt.step(1 / 30);
console.log('  按住共 1.2s: 步骤="' + stepOf('fire').slice(0, 16) + '"  (应已推进)');
rt.injectKey(U);
for (let f = 0; f < 5; f++) rt.step(1 / 30);
console.log('  松手后: 步骤="' + stepOf('fire').slice(0, 16) + '"');
