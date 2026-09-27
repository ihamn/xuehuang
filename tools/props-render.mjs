// props-render.mjs —— 把 sim-run.mjs 导出的**扁平控件表**画成 PNG
//
//   node tools/props-render.mjs dist/props.json preview/design/props-sim.png
//
// 为什么要自己写（而不是用 D:/zuma 的 sim-render.mjs）：
//   那个工具读的是**嵌套树**（root/children），而我们的导出是**扁平数组**
//   （controls: [{kind,name,x,y,w,h,color,visible,rot}]）→ 它一张图里"可见图片控件 0 个"。
//   与其改它，不如让渲染器对准我们自己的格式（而且我们还需要 rot，用来画杯子的斜条）。
//
// 坐标系：千星原点在**画布中心**、Y 向上；PNG 原点在左上、Y 向下 → 画的时候要翻 Y。
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const mod = await import(pathToFileURL(path.join(ROOT, 'node_modules/@napi-rs/canvas/index.js')).href)
  .catch(() => import('@napi-rs/canvas'));
const { createCanvas, GlobalFonts } = mod.default || mod;

const inFile = process.argv[2] || 'dist/props.json';
const outFile = process.argv[3] || 'preview/design/props-sim.png';
const data = JSON.parse(fs.readFileSync(path.resolve(ROOT, inFile), 'utf8'));

const W = data.canvas?.w || 1280, H = data.canvas?.h || 720;
const cv = createCanvas(W, H);
const g = cv.getContext('2d');
g.fillStyle = '#0a0e18'; g.fillRect(0, 0, W, H);

for (const f of ['C:/Windows/Fonts/msyh.ttc', 'C:/Windows/Fonts/simhei.ttf']) {
  if (fs.existsSync(f)) { try { GlobalFonts.registerFromPath(f, 'CN'); break; } catch {} }
}

// 0xAARRGGBB（千星的 ColorValue 是打包整数）
function unpack(v) {
  if (v == null) return { r: 255, g: 255, b: 255, a: 255 };
  const n = v >>> 0;
  return { a: (n >>> 24) & 255, r: (n >>> 16) & 255, g: (n >>> 8) & 255, b: n & 255 };
}

let drawn = 0, skipped = 0;
// ── ★ 按 imageId 画对应的**基础形状** ──
//   运行时的 ImageControl 是有 imageId 的（scene.js 的默认字段 + SetImage 写它），
//   所以模拟器**能**验证"三角形到底什么样"。之前画成方块只是我的渲染器没看这个字段。
//   基础形状：100001 方块 · 100002 圆 · 100003 三角 · 100004 四角星 · 100005 五角星 · 100006 圆环
function drawShape(g, art, cx, cy, w, h, rot) {
  g.save();
  g.translate(cx, cy);
  if (rot) g.rotate(-rot * Math.PI / 180);
  const hw = w / 2, hh = h / 2;
  g.beginPath();
  switch (art) {
    case 100002:                                  // 圆
      g.ellipse(0, 0, hw, hh, 0, 0, Math.PI * 2); break;
    case 100003:                                  // 三角（顶点在**上**，底边在下）
      g.moveTo(0, -hh); g.lineTo(hw, hh); g.lineTo(-hw, hh); g.closePath(); break;
    case 100004: {                                // 四角星
      const k = 0.34;
      g.moveTo(0, -hh); g.lineTo(hw * k, -hh * k); g.lineTo(hw, 0); g.lineTo(hw * k, hh * k);
      g.lineTo(0, hh); g.lineTo(-hw * k, hh * k); g.lineTo(-hw, 0); g.lineTo(-hw * k, -hh * k);
      g.closePath(); break;
    }
    case 100005: {                                // 五角星
      for (let i = 0; i < 10; i++) {
        const a = -Math.PI / 2 + i * Math.PI / 5;
        const r = (i % 2 === 0) ? 1 : 0.42;
        const px = Math.cos(a) * hw * r, py = Math.sin(a) * hh * r;
        i === 0 ? g.moveTo(px, py) : g.lineTo(px, py);
      }
      g.closePath(); break;
    }
    case 100006: {                                // 圆环（外圆 - 内圆，反向填充）
      const t = Math.min(hw, hh) * 0.28;
      g.ellipse(0, 0, hw, hh, 0, 0, Math.PI * 2);
      g.ellipse(0, 0, Math.max(0.5, hw - t), Math.max(0.5, hh - t), 0, 0, Math.PI * 2, true);
      break;
    }
    default:                                      // 100001 / 其他 → 方块（矩形）
      g.rect(-hw, -hh, w, h); break;
  }
  g.fill();
  g.restore();
}

for (const c of (data.controls || [])) {
  if (c.visible === false || c.active === false) { skipped++; continue; }
  const col = unpack(c.color);
  if (col.a === 0 || c.w === 0 || c.h === 0) { skipped++; continue; }
  // 千星：中心原点、Y 向上 → PNG：左上原点、Y 向下
  const cx = W / 2 + (c.x || 0);
  const cy = H / 2 - (c.y || 0);
  const w = Math.abs(c.w || 0), h = Math.abs(c.h || 0);
  g.save();
  g.globalAlpha = col.a / 255;
  g.fillStyle = `rgb(${col.r},${col.g},${col.b})`;
  drawShape(g, c.art, cx, cy, w, h, c.rot);
  g.restore();
  drawn++;
}
// 标题条（便于辨认是哪份导出）
g.fillStyle = 'rgba(8,12,20,.85)'; g.fillRect(0, 0, W, 26);
g.fillStyle = '#8fa3c8'; g.font = '14px CN, sans-serif';
g.fillText(`${data.script || inFile}  ·  画 ${drawn} 个控件（跳过 ${skipped}）  ·  共 ${(data.controls || []).length}`, 12, 18);

fs.mkdirSync(path.dirname(path.resolve(ROOT, outFile)), { recursive: true });
fs.writeFileSync(path.resolve(ROOT, outFile), cv.toBuffer('image/png'));
console.log(`出图：${outFile}  画了 ${drawn} 个 / 跳过 ${skipped} 个 / 共 ${(data.controls || []).length}`);
