// crop-icons.mjs —— 把素材库截图里的图标网格**放大裁出来**，逐号看清是什么
//   node tools/crop-icons.mjs
// 输出：preview/icons-*.png（每个图标一格 + 编号标签）
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const mod = await import(pathToFileURL(path.join(ROOT, 'node_modules/@napi-rs/canvas/index.js')).href)
  .catch(() => import('@napi-rs/canvas'));
const { createCanvas, loadImage, GlobalFonts } = mod.default || mod;

const SRC = path.join(ROOT, 'screenshots',
  process.argv[2] || '06-编辑器-素材库-玩法图标单色.png');
// 网格参数：从截图里量的（图标格 58px、四列步进 58、行步进 58）
const G = { x0: 318, y0: 598, step: 58, cols: 22, rows: 5, pad: 10 };
const arg = (n, d) => { const h = process.argv.find(a => a.startsWith('--' + n + '=')); return h ? h.slice(n.length + 3) : d; };
const colStart = Number(arg('colStart', 0)); const colEnd = Number(arg('colEnd', G.cols));
const label0 = Number(arg('label0', 0));

const img = await loadImage(SRC);
const cell = 96;
const pageW = (colEnd - colStart) * cell + 20, pageH = G.rows * (cell + 22) + 20;
const cv = createCanvas(pageW, pageH);
const g = cv.getContext('2d');
g.fillStyle = '#0a0c12'; g.fillRect(0, 0, pageW, pageH);
for (const f of ['C:/Windows/Fonts/msyh.ttc', 'C:/Windows/Fonts/simhei.ttf']) {
  if (fs.existsSync(f)) { try { GlobalFonts.registerFromPath(f, 'CN'); break; } catch {} }
}
for (let r = 0; r < G.rows; r++) {
  for (let c = colStart; c < colEnd; c++) {
    const sx = G.x0 + c * G.step, sy = G.y0 + r * G.step;
    const dx = (c - colStart) * cell + 10, dy = r * (cell + 22) + 10;
    g.drawImage(img, sx, sy, G.step, G.step, dx, dy, cell, cell);
    g.fillStyle = '#8fa3c8'; g.font = '15px CN, sans-serif'; g.textAlign = 'center';
    g.fillText(String(label0 + r * G.cols + c), dx + cell / 2, dy + cell + 17);
  }
}
const out = path.join(ROOT, 'preview', 'icons-' + path.basename(SRC, '.png') + '.png');
fs.writeFileSync(out, cv.toBuffer('image/png'));
console.log(`已出图 ${path.relative(ROOT, out)}  ${pageW}x${pageH}  （列 ${colStart}..${colEnd - 1}，行 0..${G.rows - 1}）`);
