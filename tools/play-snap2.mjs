// play-snap.mjs —— 真跑一遍并出图（菜单态 / 玩区）
//   node tools/play-snap.mjs --mode=menu|play --out=preview/x.png [--sec=6]
//
// 与 view-snap2 的区别：这个会**真的按空格开局**，所以能看到玩区（含真实文字）。
// Z 序：实测 **先出现的在最下层**（Backdrop 最先建=最底），所以**正序画**。
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { createCanvas, GlobalFonts } from '@napi-rs/canvas';

const ROOT = path.resolve(import.meta.dirname, '..');
const argOf = (n, d) => { const h = process.argv.find(a => a.startsWith('--' + n + '=')); return h ? h.slice(n.length + 3) : d; };
const MODE = argOf('mode', 'menu');
const SEC = Number(argOf('sec', 6));
const W = Number(argOf('w', 1815)), H = Number(argOf('h', 900));
const OUT = path.resolve(ROOT, argOf('out', 'preview/play.png'));
const SIM = 'D:/miliastra-beyond-simulator';

const { createRuntime, unpackRgba } = await import(pathToFileURL(path.join(SIM, 'client/lua-runtime/src/index.js')).href);
const rt = createRuntime({ canvasWidth: W, canvasHeight: H });
const root = rt.addRoot({ name: 'Canvas', kind: 'container' });
root.SetActive(true);
for (const [i, k] of [[1, 'image'], [2, 'textbox'], [3, 'cursor'], [4, 'container']]) rt.registerTemplate(i, { kind: k });
rt.mountScript({ path: 'main', source: fs.readFileSync(path.join(ROOT, 'dist/xuehuang.lua'), 'utf8'), control: root, params: {} });

for (let f = 0; f < Math.round(SEC * 30); f++) {
  if (MODE === 'play' && f === 20) rt.injectKey('KeyboardJumpKeyDown');
  rt.step(1 / 30);
}

let FAMILY = 'sans-serif';
for (const f of ['C:/Windows/Fonts/msyh.ttc', 'C:/Windows/Fonts/simhei.ttf']) {
  if (fs.existsSync(f)) { try { GlobalFonts.registerFromPath(f, 'UICN'); FAMILY = 'UICN'; break; } catch { /* next */ } }
}
const canvas = createCanvas(W, H);
const g = canvas.getContext('2d');
g.textAlign = 'center'; g.textBaseline = 'middle';

// 收集（深度优先，保持同级顺序）
const flat = [];
(function walk(c, ox, oy) {
  const x = ox + (c.anchoredPositionX || 0), y = oy + (c.anchoredPositionY || 0);
  if (c !== root) flat.push({ c, x, y });
  for (const k of (c.children || [])) walk(k, x, y);
})(root, 0, 0);

g.fillStyle = 'rgb(4,5,8)'; g.fillRect(0, 0, W, H);
let shown = 0;
// ★ 正序画：**先出现的在最下层**（Backdrop 是第一个 → 先画）→ 后面的盖在上面
for (let i = 0; i < flat.length; i++) {
  const { c, x, y } = flat[i];
  if (c.active === false || c.visible === false) continue;
  const w = Math.round(c.sizeDeltaX || 0), h = Math.round(c.sizeDeltaY || 0);
  if (w <= 0 || h <= 0) continue;
  const t = String(c.typeofName || '');
  const left = W / 2 + x - w / 2, top = H / 2 - y - h / 2;
  shown++;
  if (t.includes('Image')) {
    let col = '#ffffff';
    try { const u = unpackRgba(c.imageColor ?? 0); col = 'rgba(' + u[0] + ',' + u[1] + ',' + u[2] + ',' + ((u[3] ?? 255) / 255) + ')'; } catch { /* ignore */ }
    g.fillStyle = col; g.fillRect(left, top, w, h);
  } else if (t.includes('TextBox')) {
    const s = String(c.text || '');
    if (!s) continue;
    let col = '#ffffff';
    try { const u = unpackRgba(c.fontColor ?? 0); col = 'rgb(' + u[0] + ',' + u[1] + ',' + u[2] + ')'; } catch { /* ignore */ }
    g.font = (c.fontSize || 20) + 'px ' + FAMILY;
    g.fillStyle = col;
    g.fillText(s, left + w / 2, top + h / 2);
  }
}
console.log('mode=' + MODE + '  ' + SEC + 's  可见 ' + shown + ' / 总 ' + flat.length);
for (const l of (rt.logs || [])) if (/BUILD-FAILED|出错/.test(l.text)) console.log('  LOG ' + l.text);
fs.writeFileSync(OUT, await canvas.encode('png'));
console.log('已生成：' + path.relative(ROOT, OUT));
