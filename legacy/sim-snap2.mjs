// sim-snap2.mjs —— 带标注的离线渲染（给"人眼看版式"用）
//   node tools/sim-snap2.mjs lua/src/hello.lua --w=1815 --h=900 --out=out/layout-annotated.png
//
// 和 sim-snap.mjs 的区别：这个会把每个控件的**名字**画上去，并画两条坐标轴参考线，
// 方便人直接对着真机截图指出"哪个控件在哪、哪个没出现"。
// ★ 不是真机渲染：字体/九宫格/遮罩一律不准，只判"位置·尺寸·数量·配色"。

import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const argOf = (n, d) => { const h = process.argv.find(a => a.startsWith('--' + n + '=')); return h ? h.slice(n.length + 3) : d; };
const SCRIPT = path.resolve(ROOT, process.argv.slice(2).find(a => !a.startsWith('--')) || 'lua/src/hello.lua');
const W = Number(argOf('w', 1815)), H = Number(argOf('h', 900));
const OUT = path.resolve(ROOT, argOf('out', 'out/layout-annotated.png'));

const ENTRY = 'D:/miliastra-beyond-simulator/client/lua-runtime/src/index.js';
if (!fs.existsSync(ENTRY)) { console.log('skip: no simulator'); process.exit(0); }
const { createRuntime, walkControls, unpackRgba } = await import(pathToFileURL(ENTRY).href);

const rt = createRuntime({ canvasWidth: W, canvasHeight: H });
const root = rt.addRoot({ name: 'Canvas', kind: 'container' });
rt.registerTemplate(1, { kind: 'image' });
rt.registerTemplate(2, { kind: 'textbox' });
rt.registerTemplate(3, { kind: 'cursor' });
rt.registerTemplate(4, { kind: 'container' });
rt.mountScript({ path: 'm', source: fs.readFileSync(SCRIPT, 'utf8'), control: root, params: { imgPrefab: 1, textPrefab: 2 } });
for (let f = 0; f < 30; f++) rt.step(1 / 30);

const items = [];
(function walk(c, ox, oy) {
  const cx = ox + (c.anchoredPositionX || 0), cy = oy + (c.anchoredPositionY || 0);
  if (c !== root && c.active !== false && c.visible !== false) items.push({ c, cx, cy });
  for (const k of (c.children || [])) walk(k, cx, cy);
})(root, 0, 0);

const buf = Buffer.alloc(W * H * 3, 0);
for (let i = 0; i < W * H; i++) { buf[i * 3] = 18; buf[i * 3 + 1] = 22; buf[i * 3 + 2] = 32; }
const px = (x, y, r, g, b, a = 1) => {
  x = Math.round(x); y = Math.round(y);
  if (x < 0 || y < 0 || x >= W || y >= H) return;
  const i = (y * W + x) * 3;
  buf[i] = buf[i] * (1 - a) + r * a; buf[i + 1] = buf[i + 1] * (1 - a) + g * a; buf[i + 2] = buf[i + 2] * (1 - a) + b * a;
};
const rect = (x, y, w, h, r, g, b, a = 1) => { for (let yy = y; yy < y + h; yy++) for (let xx = x; xx < x + w; xx++) px(xx, yy, r, g, b, a); };
const outline = (x, y, w, h, r, g, b, a = 1) => { for (let xx = x; xx < x + w; xx++) { px(xx, y, r, g, b, a); px(xx, y + h - 1, r, g, b, a); } for (let yy = y; yy < y + h; yy++) { px(x, yy, r, g, b, a); px(x + w - 1, yy, r, g, b, a); } };

// 5x7 点阵字，够画控件名和坐标（不引字体）
const FONT = {
  A: ['01110','10001','10001','11111','10001','10001','10001'], B: ['11110','10001','11110','10001','10001','10001','11110'],
  C: ['01110','10001','10000','10000','10000','10001','01110'], D: ['11110','10001','10001','10001','10001','10001','11110'],
  E: ['11111','10000','11110','10000','10000','10000','11111'], G: ['01110','10001','10000','10111','10001','10001','01111'],
  I: ['11111','00100','00100','00100','00100','00100','11111'], K: ['10001','10010','11100','10010','10001','10001','10001'],
  L: ['10000','10000','10000','10000','10000','10000','11111'], M: ['10001','11011','10101','10001','10001','10001','10001'],
  N: ['10001','11001','10101','10011','10001','10001','10001'], O: ['01110','10001','10001','10001','10001','10001','01110'],
  P: ['11110','10001','10001','11110','10000','10000','10000'], R: ['11110','10001','10001','11110','10100','10010','10001'],
  S: ['01111','10000','01110','00001','00001','10001','01110'], T: ['11111','00100','00100','00100','00100','00100','00100'],
  U: ['10001','10001','10001','10001','10001','10001','01110'], X: ['10001','01010','00100','00100','00100','01010','10001'],
  '0': ['01110','10001','10011','10101','11001','10001','01110'], '1': ['00100','01100','00100','00100','00100','00100','01110'],
  '2': ['01110','10001','00001','00110','01000','10000','11111'], '3': ['11110','00001','01110','00001','00001','10001','01110'],
  '4': ['00010','00110','01010','10010','11111','00010','00010'], '5': ['11111','10000','11110','00001','00001','10001','01110'],
  '6': ['00110','01000','10000','11110','10001','10001','01110'], '7': ['11111','00001','00010','00100','01000','01000','01000'],
  '8': ['01110','10001','01110','10001','10001','10001','01110'], '9': ['01110','10001','10001','01111','00001','00010','01100'],
  '-': ['00000','00000','00000','11111','00000','00000','00000'], '(': ['00010','00100','01000','01000','01000','00100','00010'],
  ')': ['01000','00100','00010','00010','00010','00100','01000'], '?': ['01110','10001','00001','00110','00100','00000','00100'],
  ':': ['00000','00100','00000','00000','00100','00000','00000'], ' ': ['00000','00000','00000','00000','00000','00000','00000'],
};
function text(s, x, y, r, g, b, scale = 1) {
  s = String(s).toUpperCase();
  let cx = x;
  for (const ch of s) {
    const g7 = FONT[ch] || FONT['?'];
    for (let row = 0; row < 7; row++) for (let col = 0; col < 5; col++)
      if (g7[row][col] === '1') rect(cx + col * scale, y + row * scale, scale, scale, r, g, b, .95);
    cx += 6 * scale;
  }
}

// 参考线：屏幕中心十字（板坐标系的原点）
outline(0, 0, W, H, 40, 46, 60, 1);
for (let x = 0; x < W; x++) px(x, Math.round(H / 2), 70, 78, 100, .55);
for (let y = 0; y < H; y++) px(Math.round(W / 2), y, 70, 78, 100, .55);

for (const { c, cx, cy } of items) {
  const w = Math.max(1, Math.round(c.sizeDeltaX || 0)), h = Math.max(1, Math.round(c.sizeDeltaY || 0));
  const left = Math.round(W / 2 + cx - w / 2), top = Math.round(H / 2 - cy - h / 2);
  const isImg = String(c.typeofName || '').includes('Image');
  const isTxt = String(c.typeofName || '').includes('TextBox');
  if (isImg) {
    let r = 210, g = 210, b = 210, a = 1;
    try { const [rr, gg, bb, aa] = unpackRgba(c.imageColor ?? 0xffffffff); r = rr; g = gg; b = bb; a = (aa ?? 255) / 255; } catch {}
    rect(left, top, w, h, r, g, b, a);
    outline(left, top, w, h, 255, 255, 255, .6);
    text(c.name || 'IMG', left + 6, top + 6, 255, 255, 255, 1);
    text(`${cx},${cy}`, left + 6, top + 18, 180, 220, 255, 1);
  } else if (isTxt && c.text) {
    outline(left, top, w, h, 120, 150, 200, .5);
    text(String(c.text).slice(0, 14), left + 4, top + Math.round(h / 2) - 3, 255, 255, 255, 1);
  }
}

const raw = Buffer.alloc((W * 3 + 1) * H);
for (let y = 0; y < H; y++) { raw[y * (W * 3 + 1)] = 0; buf.copy(raw, y * (W * 3 + 1) + 1, y * W * 3, (y + 1) * W * 3); }
const crc32 = b => { let c, t = []; for (let n = 0; n < 256; n++) { c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c; } let r = 0xffffffff; for (const x of b) r = t[(r ^ x) & 0xff] ^ (r >>> 8); return (r ^ 0xffffffff) >>> 0; };
const chunk = (type, data) => { const l = Buffer.alloc(4); l.writeUInt32BE(data.length); const body = Buffer.concat([Buffer.from(type, 'ascii'), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc32(body)); return Buffer.concat([l, body, c]); };
const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 2;
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
console.log(`控件 ${items.length} 个 → ${path.relative(process.cwd(), OUT)} (${W}x${H})`);
rt.destroy();
