// view-snap2.mjs —— 本地"画面预览"：逻辑层用测试台跑（已验证可靠），控件树从 JS 读
//
//   node tools/view-snap2.mjs --seconds=30 --out=preview/view.png
//
// 为什么不用 script:Invoke 那套：模拟器给每段代码独立 _ENV、invoke 返回值也不稳，
// 我在那上面花了不少时间。逻辑层本身有可靠的跑法（logic/kitchen/game 三个测试都在用），
// 所以这里就一条路：**合成脚本 → 挂载 → 每帧 step（脚本自己 autoplay）→ 读控件树 → 画图**。
// autoplay 由脚本变量控制，走的是脚本内部路径，不依赖任何外部注入。
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const argOf = (n, d) => { const h = process.argv.find(a => a.startsWith('--' + n + '=')); return h ? h.slice(n.length + 3) : d; };
const W = Number(argOf('w', 1280)), H = Number(argOf('h', 720));
const SECONDS = Number(argOf('seconds', 30));
const OUT = path.resolve(ROOT, argOf('out', 'preview/view.png'));
const BUNDLE = path.resolve(ROOT, argOf('bundle', 'dist/xuehuang.lua'));
import { SIM_ROOT as SIM } from './sim-root.mjs';   // 模拟器位置：一处解析（云电脑/本机通用）
const ENTRY = path.join(SIM, 'client/lua-runtime/src/index.js');
if (!fs.existsSync(ENTRY) || !fs.existsSync(BUNDLE)) { console.log('跳过：缺模拟器或产物'); process.exit(0); }

const { createRuntime, walkControls, unpackRgba } = await import(pathToFileURL(ENTRY).href);
const rt = createRuntime({ canvasWidth: W, canvasHeight: H });
const root = rt.addRoot({ name: 'Canvas', kind: 'container' })
root.SetActive(true)   // ★ 必须激活：未激活时 scriptCanRun=false，OnUpdate 不会跑;
for (const [i, k] of [[1, 'image'], [2, 'textbox'], [3, 'cursor'], [4, 'container']]) rt.registerTemplate(i, { kind: k });
rt.mountScript({ path: 'main', source: fs.readFileSync(BUNDLE, 'utf8'), control: root, params: { autoplay: 1 } });

const DT = 1 / 30;
for (let f = 0; f < Math.round(SECONDS / DT); f++) rt.step(DT);

// ── 收集可见控件（含绝对位置）──
const flat = [];
for (const r of (rt.roots || [])) walkControls(r, c => flat.push(c));
const drawn = [];
(function collect(c, ox, oy) {
  const cx = ox + (c.anchoredPositionX || 0), cy = oy + (c.anchoredPositionY || 0);
  if (c !== root && c.active !== false && c.visible !== false) drawn.push({ c, cx, cy });
  for (const k of (c.children || [])) collect(k, cx, cy);
})(root, 0, 0);

// ── 画 ──
const buf = Buffer.alloc(W * H * 3, 0);
for (let i = 0; i < W * H; i++) { buf[i * 3] = 22; buf[i * 3 + 1] = 26; buf[i * 3 + 2] = 36; }
const px = (x, y, r, g, b, a = 1) => {
  x = Math.round(x); y = Math.round(y);
  if (x < 0 || y < 0 || x >= W || y >= H) return;
  const i = (y * W + x) * 3;
  buf[i] = buf[i] * (1 - a) + r * a; buf[i + 1] = buf[i + 1] * (1 - a) + g * a; buf[i + 2] = buf[i + 2] * (1 - a) + b * a;
};
const rect = (x, y, w, h, r, g, b, a = 1) => { for (let yy = y; yy < y + h; yy++) for (let xx = x; xx < x + w; xx++) px(xx, yy, r, g, b, a); };
for (const it of drawn) {
  const { c, cx, cy } = it;
  const w = Math.max(1, Math.round(c.sizeDeltaX || 0)), h = Math.max(1, Math.round(c.sizeDeltaY || 0));
  const left = Math.round(W / 2 + cx - w / 2), top = Math.round(H / 2 - cy - h / 2);
  const t = String(c.typeofName || '');
  if (t.includes('Image')) {
    let r = 200, g = 200, b = 200, a = 1;
    try {
      const u = unpackRgba(c.imageColor ?? 0xffffffff);
      r = u[0]; g = u[1]; b = u[2];
      // ★ imageColor 是 RGBA，alpha 必须参与混合。不混合的话，半透明面板会被画成
      //   "接近背景的实心色"，预览图里就看不见 —— 我因此以为面板位置错了，白查一轮。
      a = (u[3] ?? 255) / 255;
    } catch {}
    if (a > 0.02) rect(left, top, w, h, r, g, b, a);   // px() 里已做 alpha 混合
  } else if (t.includes('TextBox') && c.text) {
    const lines = String(c.text).split('\n');
    lines.forEach((ln, i) => {
      const tw = Math.min(w, Math.max(6, ln.length * 8));
      rect(left + 2, top + i * 18, tw, 12, 235, 240, 255, .85);
    });
  }
}
const raw = Buffer.alloc((W * 3 + 1) * H);
for (let y = 0; y < H; y++) { raw[y * (W * 3 + 1)] = 0; buf.copy(raw, y * (W * 3 + 1) + 1, y * W * 3, (y + 1) * W * 3); }
const crc32 = b => { let c, t = []; for (let n = 0; n < 256; n++) { c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c; } let r = 0xffffffff; for (const x of b) r = t[(r ^ x) & 0xff] ^ (r >>> 8); return (r ^ 0xffffffff) >>> 0; };
const chunk = (type, data) => { const l = Buffer.alloc(4); l.writeUInt32BE(data.length); const body = Buffer.concat([Buffer.from(type, 'ascii'), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc32(body)); return Buffer.concat([l, body, c]); };
const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 2;
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));

console.log(`${SECONDS}s → ${path.relative(process.cwd(), OUT)}　可见控件 ${drawn.length} / 总 ${flat.length}`);
const shows = drawn.filter(d => String(d.c.typeofName || '').includes('Image')).length;
console.log(`  其中图片 ${shows}`);
const texts = drawn.filter(d => d.c.text).map(d => String(d.c.text).replace(/\n/g, ' / '));
for (const t of texts.slice(0, 12)) console.log('  · ' + t);
rt.destroy();
