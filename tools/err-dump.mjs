import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const SIM = 'D:/miliastra-beyond-simulator';
const { createRuntime } = await import(pathToFileURL(path.join(SIM, 'client/lua-runtime/src/index.js')).href);
const rt = createRuntime({ canvasWidth: 1880.733, canvasHeight: 900 });
const root = rt.addRoot({ name: 'Canvas', kind: 'container' });
root.SetActive(true);
for (const [i, k] of [[1, 'image'], [2, 'textbox'], [3, 'cursor'], [4, 'container']]) rt.registerTemplate(i, { kind: k });
rt.mountScript({ path: 'main', source: fs.readFileSync('dist/xuehuang.lua', 'utf8'), control: root, params: {} });
for (let f = 0; f < 5; f++) rt.step(1 / 30);
for (const l of (rt.logs || [])) {
  const t = (l.text || '').replace(/^\[info\]\s*/, '');
  if (/BUILD|error|err|nil|雪皇|view|host/i.test(t)) console.log('  ' + t.slice(0, 220));
  if (l.error) console.log('  ERR ' + String(l.error).slice(0, 400));
}
// 直接看 mountScript 抛出的错误（如果没被 pcall 吞掉）
console.log('  --- 已 mounted，试 step ---');
try { for (let f = 0; f < 3; f++) rt.step(1 / 30); } catch (e) { console.log('  STEP ERR: ' + e.message); }
