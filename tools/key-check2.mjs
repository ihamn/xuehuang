import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const SIM = 'D:/miliastra-beyond-simulator';
const W = 1880.733, H = 900;
const { createRuntime } = await import(pathToFileURL(path.join(SIM, 'client/lua-runtime/src/index.js')).href);
const rt = createRuntime({ canvasWidth: W, canvasHeight: H });
const root = rt.addRoot({ name: 'Canvas', kind: 'container' });
root.SetActive(true);
for (const [i, k] of [[1, 'image'], [2, 'textbox'], [3, 'cursor'], [4, 'container']]) rt.registerTemplate(i, { kind: k });
// autoplay=1 让机器人造出小票（但机器人也会自己做工位；这里只用来造活）
rt.mountScript({ path: 'main', source: fs.readFileSync('dist/xuehuang.lua', 'utf8'), control: root, params: { autoplay: 0 } });
for (let f = 0; f < 8; f++) rt.step(1 / 30);
const find = (c, n) => { if (c.name === n) return c; for (const k of (c.children || [])) { const r = find(k, n); if (r) return r; } return null; };
const stepOf = (id) => String((find(root, 'StS_' + id) || {}).text || '');
// 进游戏
rt.injectKey('KeyboardCraftspersonKey42Down'); rt.step(1 / 30); rt.injectKey('KeyboardCraftspersonKey42Up');
for (let f = 0; f < 8; f++) rt.step(1 / 30);
console.log('  进游戏: ' + find(root, 'St_shake_box').visible);
// 等顾客来（时间推进 120s = 3600 帧太多；用 600 帧=20s）
for (let f = 0; f < 900; f++) rt.step(1 / 30);
console.log('  20s 后各工位步骤: ' + ['shake', 'fire', 'chem', 'brew'].map(i => i + '="' + stepOf(i).slice(0, 10) + '"').join('  '));
// 有活的话，按对应键试
const KEYS = { shake: ['KeyboardCraftspersonKey13Down', 'Y'], fire: ['KeyboardCraftspersonKey15Down', 'H'], chem: ['KeyboardCraftspersonKey20Down', 'K'], brew: ['KeyboardCraftspersonKey18Down', 'P'] };
for (const [id, [key, label]] of Object.entries(KEYS)) {
  const before = stepOf(id);
  for (let i = 0; i < 12; i++) { rt.injectKey(key); for (let f = 0; f < 3; f++) rt.step(1 / 30); rt.injectKey(key.replace('Down', 'Up')); for (let f = 0; f < 4; f++) rt.step(1 / 30); }
  const after = stepOf(id);
  const active = !before.includes('等待小票');
  console.log(`  ${label}(${id}) ${active ? '[有活]' : '[没活]'}  "${before.slice(0, 14)}" → "${after.slice(0, 14)}"  ${before !== after ? '✓' : '·'}`);
}
