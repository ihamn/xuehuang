// probe-slips.mjs —— 查"小票行"控件到底建没建、在哪、可见性如何
//   node tools/probe-slips.mjs --seconds=4.2
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const argOf = (n, d) => { const h = process.argv.find(a => a.startsWith('--' + n + '=')); return h ? h.slice(n.length + 3) : d; };
const W = Number(argOf('w', 1280)), H = Number(argOf('h', 720));
const SECONDS = Number(argOf('seconds', 4.2));
const BUNDLE = path.resolve(ROOT, argOf('bundle', 'dist/xuehuang.lua'));
import { SIM_ROOT as SIM } from './sim-root.mjs';   // 模拟器位置：一处解析（云电脑/本机通用）
const { createRuntime, walkControls } = await import(pathToFileURL(path.join(SIM, 'client/lua-runtime/src/index.js')).href);
const rt = createRuntime({ canvasWidth: W, canvasHeight: H });
const root = rt.addRoot({ name: 'Canvas', kind: 'container' });
root.SetActive(true);
for (const [i, k] of [[1, 'image'], [2, 'textbox'], [3, 'cursor'], [4, 'container']]) rt.registerTemplate(i, { kind: k });
rt.mountScript({ path: 'main', source: fs.readFileSync(BUNDLE, 'utf8'), control: root, params: { autoplay: 1 } });
const DT = 1 / 30;
for (let f = 0; f < Math.round(SECONDS / DT); f++) rt.step(DT);

const flat = [];
for (const r of (rt.roots || [])) walkControls(r, c => flat.push(c));
const rows = [];
(function collect(c, ox, oy) {
  const cx = ox + (c.anchoredPositionX || 0), cy = oy + (c.anchoredPositionY || 0);
  rows.push({ name: c.name, t: String(c.typeofName || ''), a: c.active, v: c.visible, cx, cy, w: c.sizeDeltaX, h: c.sizeDeltaY, text: c.text });
  for (const k of (c.children || [])) collect(k, cx, cy);
})(root, 0, 0);

const slips = rows.filter(r => /^Sl/.test(String(r.name || '')));
console.log(`小票行控件：${slips.length} 个`);
for (const s of slips.slice(0, 24)) {
  console.log(`  ${String(s.name).padEnd(6)} ${s.t.includes('Image') ? 'img' : 'txt'} active=${s.a} visible=${s.v} pos=(${s.cx.toFixed(0)},${s.cy.toFixed(0)}) size=${(s.w || 0).toFixed(0)}x${(s.h || 0).toFixed(0)} text="${String(s.text || '').slice(0, 26)}"`);
}
const offscreen = rows.filter(r => Math.abs(r.cy) > H / 2 + 40 || Math.abs(r.cx) > W / 2 + 40);
console.log(`\n中心系下 y 超出画布（|cy| > ${H / 2 + 40}）的控件：${offscreen.length} 个`);
for (const o of offscreen.slice(0, 12)) console.log(`  ${String(o.name).padEnd(8)} cy=${o.cy.toFixed(0)} cx=${o.cx.toFixed(0)}`);
const who = rows.filter(r => /KeysBox|BookHead|SlW1|Sl1$/.test(String(r.name || '')));
console.log('\n抽样：');
for (const o of who) console.log(`  ${String(o.name).padEnd(8)} active=${o.a} visible=${o.v} pos=(${o.cx.toFixed(0)},${o.cy.toFixed(0)}) size=${(o.w || 0).toFixed(0)}x${(o.h || 0).toFixed(0)}`);
rt.destroy();
