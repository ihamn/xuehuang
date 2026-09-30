import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { SIM_ROOT as SIM } from './sim-root.mjs';   // 模拟器位置：一处解析（云电脑/本机通用）
const { createRuntime } = await import(pathToFileURL(path.join(SIM, 'client/lua-runtime/src/index.js')).href);
const rt = createRuntime({ canvasWidth: 1880.733, canvasHeight: 900 });
const root = rt.addRoot({ name: 'Canvas', kind: 'container' });
root.SetActive(true);
for (const [i, k] of [[1, 'image'], [2, 'textbox'], [3, 'cursor'], [4, 'container']]) rt.registerTemplate(i, { kind: k });
rt.mountScript({ path: 'main', source: fs.readFileSync('dist/xuehuang.lua', 'utf8'), control: root, params: {} });
for (let f = 0; f < 6; f++) rt.step(1 / 30);
const find = (c, n) => { if (c.name === n) return c; for (const k of (c.children || [])) { const r = find(k, n); if (r) return r; } return null; };
const vis = (n) => { const c = find(root, n); if (!c) return '不存在'; const a = c.active, s = c.visible; return `active=${a} visible=${s}`; };
console.log('  ── 菜单时各面板可见性 ──');
for (const n of ['OrderPanel', 'DataBox', 'BookBox', 'KeysBox', 'St_shake_box', 'Pk_box', 'HudBar', 'BigTitle']) {
  console.log('    ' + n.padEnd(14) + vis(n));
}
console.log('  ── 按 1 + 空格 能不能开局 ──');
rt.injectKey('KeyboardCraftspersonKey1Down'); rt.step(1 / 30);
rt.injectKey('KeyboardCraftspersonKey1Up'); for (let f = 0; f < 3; f++) rt.step(1 / 30);
rt.injectKey('KeyboardJumpKeyDown'); for (let f = 0; f < 6; f++) rt.step(1 / 30);
rt.injectKey('KeyboardJumpKeyUp'); for (let f = 0; f < 20; f++) rt.step(1 / 30);
for (const l of (rt.logs || [])) {
  const t = (l.text || '').replace(/^\[info\]\s*/, '');
  if (/开局|拒绝开局|mode=/.test(t)) console.log('    ' + t.slice(0, 120));
}
console.log('    玩区可见性: St_shake_box ' + vis('St_shake_box') + '  BookBox ' + vis('BookBox'));
