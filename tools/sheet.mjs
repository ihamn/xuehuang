// sheet.mjs —— 把 preview/design 里的主要出图拼成一张"图集"
//
//   node tools/sheet.mjs [输出名]
//
// 为什么要有它：设计稿一多，一张张发很费事。拼成一张，标题写在格子上，一眼看全。
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const mod = await import(pathToFileURL(path.join(ROOT, 'node_modules/@napi-rs/canvas/index.js')).href)
  .catch(() => import('@napi-rs/canvas'));
const { createCanvas, loadImage, GlobalFonts } = mod.default || mod;

const DIR = path.join(ROOT, 'preview', 'design');
const SIMDIR = path.join(ROOT, 'preview', 'sim');
// 输出到 preview/ 根：这张是**总览**，既不是设计稿也不是模拟器图
const outName = process.argv[2] || '图集.png';
const outDir = path.join(ROOT, 'preview');

// 每格：源图 + 标题（按顺序拼）。dir 省略 = preview/design
const SHEET = [
  { f: '形状-杯子.png',            t: '① 杯子 · 侧壁 8.75° 陡锥 + 平液面 + 五色饮料' },
  { f: '形状-炮筒.png',            t: '② 炮筒 · 三档同一形状 × 静止/喷火' },
  { f: '火-尺寸15x25与12x20.png',  t: '③ 火 · DOOM 算法（16×27 格 / 432 方块）' },
  { f: 'prims.png', dir: 'sim',    t: '④ 基础形状图鉴（模拟器实建）· 100001~100006' },
  { f: 'props-sim.png', dir: 'sim',t: '⑤ 模拟器实建 · 杯子 + 炮筒 + 火（真实控件树）' },
  { f: '界面-工位状态.png',         t: '⑥ 工位状态图鉴（无活 / 有活 / 等名额）' },
];

const CELL_W = 760;          // 每格内容宽
const PAD = 14, TITLE_H = 30, GAP = 16;
const cols = 2;

const imgs = [];
for (const s of SHEET) {
  const p = path.join(s.dir === 'sim' ? SIMDIR : DIR, s.f);
  if (!fs.existsSync(p)) { console.log(`  跳过（没有）：${s.f}`); continue; }
  const im = await loadImage(p);
  const scale = CELL_W / im.width;
  imgs.push({ im, t: s.t, w: CELL_W, h: Math.round(im.height * scale) });
}

const rows = Math.ceil(imgs.length / cols);
const cellH = Math.max(...imgs.map(i => i.h));
const W = PAD + cols * (CELL_W + PAD);
const H = PAD + rows * (TITLE_H + cellH + GAP) + PAD;
const cv = createCanvas(W, H);
const g = cv.getContext('2d');
g.fillStyle = '#07090f'; g.fillRect(0, 0, W, H);
for (const f of ['C:/Windows/Fonts/msyh.ttc', 'C:/Windows/Fonts/simhei.ttf']) {
  if (fs.existsSync(f)) { try { GlobalFonts.registerFromPath(f, 'CN'); break; } catch {} }
}

imgs.forEach((it, i) => {
  const c = i % cols, r = Math.floor(i / cols);
  const x = PAD + c * (CELL_W + PAD);
  const y = PAD + r * (TITLE_H + cellH + GAP);
  g.fillStyle = '#FFD682'; g.font = 'bold 17px CN, sans-serif';
  g.fillText(it.t, x + 2, y + 20);
  g.drawImage(it.im, x, y + TITLE_H, it.w, it.h);
  g.strokeStyle = '#22304c'; g.lineWidth = 1;
  g.strokeRect(x + 0.5, y + TITLE_H + 0.5, it.w - 1, it.h - 1);
});

const out = path.join(outDir, outName);
fs.writeFileSync(out, cv.toBuffer('image/png'));
console.log(`图集：preview/${outName}  ${W}×${H}  ${imgs.length} 格`);
