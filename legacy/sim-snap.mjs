// sim-snap.mjs —— 把脚本跑出来的控件树，离线渲染成一张 PNG（用来"看"版式）
//
// 为什么需要它：真机上"有没有显示、摆得对不对"只能靠人肉截图报给我，一轮几分钟。
// 而控件树里的位置/尺寸/颜色/文字都是真数据 —— 直接把它们画成图，版式问题本地就能看出来。
// ★ 它不是真机渲染：字体、九宫格拉伸、遮罩这些一律不准，只用来判断"位置/尺寸/层级/配色"对不对。
//
// 用法：
//   node tools/sim-snap.mjs lua/src/hello.lua --out=out/layout.png
//   node tools/sim-snap.mjs lua/src/hello.lua --w=1280 --h=720
//
// 依赖：模拟器（同 sim-run.mjs）+ Python(bundled) 或 node 侧 zlib 手写 PNG。
//   这里用最朴素的办法：把矩形画进一个 RGB 缓冲，然后用 zlib 手写 PNG，不引第三方包。

import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const argOf = (n, d) => {
  const hit = process.argv.find(a => a.startsWith('--' + n + '='));
  return hit ? hit.slice(n.length + 3) : d;
};
const scriptArg = process.argv.slice(2).find(a => !a.startsWith('--'));
const SCRIPT = path.resolve(ROOT, scriptArg || 'lua/src/hello.lua');
const W = Number(argOf('w', 1280)), H = Number(argOf('h', 720));
const OUT = path.resolve(ROOT, argOf('out', 'out/layout.png'));
const FRAMES = Number(argOf('frames', 30));

const ENTRY = ['D:/miliastra-beyond-simulator/client/lua-runtime/src/index.js']
  .find(p => fs.existsSync(p));
if (!ENTRY) { console.log('跳过：没找到模拟器'); process.exit(0); }

const { createRuntime, walkControls, unpackRgba } = await import(pathToFileURL(ENTRY).href);
const rt = createRuntime({ canvasWidth: W, canvasHeight: H });
const root = rt.addRoot({ name: 'Canvas', kind: 'container' })
root.SetActive(true)   // ★ 必须激活：未激活时 scriptCanRun=false，OnUpdate 不会跑;
rt.registerTemplate(1, { kind: 'image', name: 'Img' });
rt.registerTemplate(2, { kind: 'textbox', name: 'Text' });
rt.registerTemplate(3, { kind: 'cursor', name: 'CursorArea' });
rt.registerTemplate(4, { kind: 'container', name: 'Panel' });
rt.mountScript({ path: 'main', source: fs.readFileSync(SCRIPT, 'utf8'), control: root, params: { imgPrefab: 1, textPrefab: 2 } });
for (let f = 0; f < FRAMES; f++) rt.step(1 / 30);

// ── 收集控件（带绝对位置）：子控件的 anchoredPosition 相对父中心 ──
const items = [];
(function walk(c, ox, oy) {
  const cx = ox + (c.anchoredPositionX || 0);
  const cy = oy + (c.anchoredPositionY || 0);
  if (c.active !== false && c.visible !== false && c !== root) {
    items.push({ c, cx, cy });
  }
  for (const k of (c.children || [])) walk(k, cx, cy);
})(root, 0, 0);

// ── 画布：左上角为原点、y 向下（和板坐标一致，方便肉眼对位）──
const buf = Buffer.alloc(W * H * 3);
for (let i = 0; i < W * H; i++) { buf[i*3] = 24; buf[i*3+1] = 28; buf[i*3+2] = 38; }   // 深蓝底
const px = (x, y, r, g, b, a) => {
  if (x < 0 || y < 0 || x >= W || y >= H) return;
  const i = (y * W + x) * 3;
  const A = a == null ? 1 : a;
  buf[i]   = Math.round(buf[i]   * (1 - A) + r * A);
  buf[i+1] = Math.round(buf[i+1] * (1 - A) + g * A);
  buf[i+2] = Math.round(buf[i+2] * (1 - A) + b * A);
};
const rect = (x, y, w, h, r, g, b, a) => {
  for (let yy = Math.max(0, y); yy < Math.min(H, y + h); yy++)
    for (let xx = Math.max(0, x); xx < Math.min(W, x + w); xx++) px(xx, yy, r, g, b, a);
};

for (const it of items) {
  const { c, cx, cy } = it;
  const w = Math.max(1, Math.round(c.sizeDeltaX || 0)), h = Math.max(1, Math.round(c.sizeDeltaY || 0));
  // 板坐标：左下角原点、y 向上 → 左上角原点、y 向下
  const left = Math.round(W / 2 + cx - w / 2);
  const top  = Math.round(H / 2 - cy - h / 2);
  if (String(c.typeofName || '').includes('Image')) {
    let r = 200, g = 200, b = 200, a = 1;
    try { const [rr, gg, bb, aa] = unpackRgba(c.imageColor ?? 0xffffffff); r = rr; g = gg; b = bb; a = (aa ?? 255) / 255; } catch {}
    rect(left, top, w, h, r, g, b, a);
    // 边框（方便数有几个方块）
    for (let x = left; x < left + w; x++) { px(x, top, 255, 255, 255, .5); px(x, top + h - 1, 255, 255, 255, .5); }
    for (let y = top; y < top + h; y++) { px(left, y, 255, 255, 255, .5); px(left + w - 1, y, 255, 255, 255, .5); }
  } else if (String(c.typeofName || '').includes('TextBox') && c.text) {
    // 文字不渲染字体，只画一条"文字占位条"，长度按字数估
    const tw = Math.min(w, Math.max(8, String(c.text).length * 9));
    rect(left + Math.round((w - tw) / 2), top + Math.round(h / 2) - 1, tw, 3, 255, 255, 255, .85);
  }
}

// ── 手写 PNG（RGB，无第三方依赖）──
const raw = Buffer.alloc((W * 3 + 1) * H);
for (let y = 0; y < H; y++) {
  raw[y * (W * 3 + 1)] = 0;
  buf.copy(raw, y * (W * 3 + 1) + 1, y * W * 3, (y + 1) * W * 3);
}
const chunk = (type, data) => {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body) >>> 0);
  return Buffer.concat([len, body, crc]);
};
function crc32(b) { let c, t = []; for (let n = 0; n < 256; n++) { c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c; } let r = 0xffffffff; for (const x of b) r = t[(r ^ x) & 0xff] ^ (r >>> 8); return r ^ 0xffffffff; }
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0)),
]);
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, png);

console.log(`控件 ${items.length} 个 → ${path.relative(process.cwd(), OUT)}（${W}x${H}）`);
for (const it of items.slice(0, 20)) {
  const { c, cx, cy } = it;
  console.log(`  ${String(c.typeofName).replace('ClientUI','').replace('Control','').padEnd(16)} `
    + `pos=(${Math.round(cx)},${Math.round(cy)}) size=${Math.round(c.sizeDeltaX||0)}x${Math.round(c.sizeDeltaY||0)} `
    + (c.text ? `text="${c.text}"` : ''));
}
rt.destroy();
