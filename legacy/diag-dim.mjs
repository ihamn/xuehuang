// diag-dim.mjs —— 诊断"方块显示/隐藏"这类问题
//   node tools/diag-dim.mjs
//
// ★ 关键认知（我在这上面折腾过）：模拟器/真机给脚本的 `_ENV` 是**隔离**的，
//   从外面另跑一段 Lua **看不到**脚本里的全局函数（`__diag`/`__state` 都是 nil）。
//   所以诊断结果要**由脚本自己写进控件文字**（HUD 标题），外面读控件文字即可。
//   脚本里的 `__diag()` 就是干这个的。
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const SIM = 'D:/miliastra-beyond-simulator';
const BUNDLE = path.join(ROOT, 'out', 'xuehuang.lua');
const { createRuntime } = await import(pathToFileURL(path.join(SIM, 'client/lua-runtime/src/index.js')).href);

const rt = createRuntime({ canvasWidth: 1600, canvasHeight: 900 });
const root = rt.addRoot({ name: 'C', kind: 'container' });
root.SetActive(true);
for (const [i, k] of [[1, 'image'], [2, 'textbox'], [3, 'cursor'], [4, 'container']]) rt.registerTemplate(i, { kind: k });
rt.mountScript({ path: 'main', source: fs.readFileSync(BUNDLE, 'utf8'), control: root, params: {} });

const findByName = (c, n) => { if (c.name === n) return c; for (const k of (c.children || [])) { const r = findByName(k, n); if (r) return r; } return null; };
const findArea = c => { if (String(c.typeofName || '').includes('CursorEvent')) return c; for (const k of (c.children || [])) { const r = findArea(k); if (r) return r; } return null; };
const hud = () => String((findByName(root, 'HudTitle') || {}).text || '');
const invoke = name => {
  const sc = (root.scripts || [])[0];
  if (!sc || typeof sc.invoke !== 'function') return '(无 invoke)';
  try { const r = sc.invoke(name, []); return r == null ? '(nil)' : String(r); } catch (e) { return 'ERR ' + e.message; }
};
const imgs = () => { const a = []; (function w(c) { const t = String(c.typeofName || ''); if (c.active !== false && c.visible !== false && t.includes('Image') && c.name) a.push(c.name); (c.children || []).forEach(w); })(root); return a; };

console.log('=== 1) 菜单态 ===');
for (let f = 0; f < 5; f++) rt.step(1 / 30);
console.log('  invoke(__diag) = ' + invoke('__diag'));
console.log('  HUD: ' + hud());
console.log('  可见图片: ' + imgs().join(', '));

console.log('=== 2) 按空格开局后 ===');
rt.injectKey('KeyboardJumpKeyDown');
for (let f = 0; f < 6; f++) rt.step(1 / 30);
invoke('__diag');
console.log('  HUD: ' + hud());
console.log('  可见图片: ' + imgs().join(', '));

console.log('=== 2.5) 自测 hide/show ===');
console.log('  ' + invoke('__selftest'));
console.log('  HUD: ' + hud());
console.log('=== 3) 点击捣锤区 ===');
const area = findArea(root);
const box = findByName(root, 'St_shake');
if (area && box) {
  rt.injectCursor(area, 'CursorClick', { x: 800 + (box.anchoredPositionX || 0), y: 450 + (box.anchoredPositionY || 0) });
  for (let f = 0; f < 3; f++) rt.step(1 / 30);
  invoke('__diag');
  console.log('  HUD: ' + hud());
} else console.log('  没有光标区域或工位方块');

const errs = (rt.logs || []).filter(l => l.level === 'error');
console.log('  error: ' + errs.length + (errs[0] ? ' | ' + errs[0].text : ''));
console.log('=== 全部日志 ===');
for (const l of (rt.logs || [])) console.log('  [' + l.level + '] ' + l.text);
rt.destroy();
