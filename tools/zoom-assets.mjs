// zoom-assets.mjs —— 从素材库截图里裁一块放大，用来看清某个素材号长什么样
//
//   node tools/zoom-assets.mjs <源png> <x> <y> <w> <h> [放大倍数] [输出名]
//
// 用途：我在正文里引用素材号（比如"基础形状 100003 是三角形"）之前，先把它放大确认。
// 素材库截图里有编号网格，但**行位置每张图不一样**，所以要能指定区域裁。
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const mod = await import(pathToFileURL(path.join(ROOT, 'node_modules/@napi-rs/canvas/index.js')).href)
  .catch(() => import('@napi-rs/canvas'));
const { createCanvas, loadImage, GlobalFonts } = mod.default || mod;

const [src, xs, ys, ws, hs, zs, outName] = process.argv.slice(2);
const x = Number(xs), y = Number(ys), w = Number(ws), h = Number(hs), z = Number(zs || 4);
const srcPath = path.isAbsolute(src) ? src : path.join(ROOT, src);
const img = await loadImage(srcPath);

const cv = createCanvas(w * z, h * z);
const g = cv.getContext('2d');
g.fillStyle = '#0a0c12'; g.fillRect(0, 0, cv.width, cv.height);
g.imageSmoothingEnabled = false;                 // 放大看像素，不要平滑
g.drawImage(img, x, y, w, h, 0, 0, w * z, h * z);
for (const f of ['C:/Windows/Fonts/msyh.ttc', 'C:/Windows/Fonts/simhei.ttf']) {
  if (fs.existsSync(f)) { try { GlobalFonts.registerFromPath(f, 'CN'); break; } catch {} }
}
g.fillStyle = '#FFD682'; g.font = '16px CN, sans-serif';
g.fillText(`${path.basename(srcPath)}  裁 (${x},${y}) ${w}×${h}  放大 ${z}×`, 10, 20);

const out = path.join(ROOT, 'preview/design', outName || '_zoom.png');
fs.writeFileSync(out, cv.toBuffer('image/png'));
console.log(`已裁：preview/design/${path.basename(out)}  ${cv.width}×${cv.height}`);
