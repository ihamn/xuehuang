import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { SIM_ROOT as SIM } from './sim-root.mjs';   // 模拟器位置：一处解析（云电脑/本机通用）
const W = 1880.733, H = 900;
const { createRuntime } = await import(pathToFileURL(path.join(SIM, 'client/lua-runtime/src/index.js')).href);
const rt = createRuntime({ canvasWidth: W, canvasHeight: H });
const canvas = rt.addRoot({ name: 'Canvas', kind: 'container' });
canvas.SetActive(true);
for (const [i, k] of [[1, 'image'], [2, 'textbox'], [3, 'cursor'], [4, 'container']]) rt.registerTemplate(i, { kind: k });
rt.mountScript({ path: 'main', source: fs.readFileSync('dist/xuehuang.lua', 'utf8'), control: canvas, params: {} });
for (let f = 0; f < 8; f++) rt.step(1 / 30);
const find = (c, n) => { if (!c) return null; if (c.name === n) return c; for (const k of (c.children || [])) { const r = find(k, n); if (r) return r; } return null; };
const findA = c => { if (!c) return null; if (String(c.typeofName || '').includes('CursorEvent')) return c; for (const k of (c.children || [])) { const r = findA(k); if (r) return r; } return null; };
rt.injectCursor(findA(canvas), 'CursorClick', { x: 200, y: 200 });
for (let f = 0; f < 15; f++) rt.step(1 / 30);
const T = id => String((find(canvas, 'StS_' + id) || {}).text || '');
const IDLE = t => /无活|排队中/.test(t);
const KEY = { shake: 'KeyboardCraftspersonKey13', fire: 'KeyboardCraftspersonKey15', chem: 'KeyboardCraftspersonKey20', brew: 'KeyboardCraftspersonKey18' };
function tap(base) { rt.injectKey(base + 'Down'); for (let f = 0; f < 2; f++) rt.step(1 / 30); rt.injectKey(base + 'Up'); for (let f = 0; f < 3; f++) rt.step(1 / 30); }

let measured = 0;
for (let sec = 0; sec < 200 && measured < 3; sec++) {
  let did = false;
  for (const id of ['brew', 'chem', 'fire', 'shake']) {
    const t = T(id);
    if (IDLE(t)) continue;
    did = true;
    if (t.includes('按住')) {
      // 这就是我们要量的：点按几次才完成
      const before = t;
      let n = 0;
      while (T(id) === before && n < 40) { tap(KEY[id]); n++; }
      console.log(`  ★ hold 步骤 "${before.slice(0, 26)}" → 点按 ${n} 次后变化: "${T(id).slice(0, 26)}"`);
      measured++;
    } else if (t.includes('连按')) {
      for (let i = 0; i < 8; i++) tap(KEY[id]);
    } else {
      tap(KEY[id]);
    }
  }
  if (!did) for (let f = 0; f < 30; f++) rt.step(1 / 30);
}
if (!measured) console.log('  200 秒内没遇到 hold 步骤');
