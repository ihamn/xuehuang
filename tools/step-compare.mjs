// 半档幅度对比条：卡片色 vs 内容区色（+20 / +30 / +40 / +55 四档）
import fs from 'node:fs';
import path from 'node:path';
import { createCanvas, GlobalFonts } from '@napi-rs/canvas';

const ROOT = path.resolve(import.meta.dirname, '..');
const W = 1200, H = 460;
let FAMILY = 'sans-serif';
for (const f of ['C:/Windows/Fonts/msyh.ttc', 'C:/Windows/Fonts/simhei.ttf']) {
  if (fs.existsSync(f)) { try { GlobalFonts.registerFromPath(f, 'UICN'); FAMILY = 'UICN'; break; } catch { /* next */ } }
}
const canvas = createCanvas(W, H);
const g = canvas.getContext('2d');
g.textBaseline = 'middle';
const rgb = a => 'rgb(' + a.join(',') + ')';
const lift = (a, d) => a.map(v => Math.min(255, v + d));
function text(s, x, y, size, col, align) {
  g.font = size + 'px ' + FAMILY; g.fillStyle = col; g.textAlign = align || 'left'; g.fillText(s, x, y);
}

const colors = { shake: [58, 122, 220], fire: [232, 126, 52], chem: [158, 106, 224], brew: [52, 176, 128], pack: [40, 192, 176] };
const deltas = [20, 30, 40, 55];

g.fillStyle = 'rgb(4,5,8)'; g.fillRect(0, 0, W, H);
text('内容区底衬幅度对比（上排=卡片原色，下排=内容区）', 32, 30, 18, 'rgb(238,243,252)');

let x = 32;
const bw = 210, bh = 90;
for (const d of deltas) {
  text('+' + d, x + bw / 2, 66, 16, 'rgb(255,214,130)', 'center');
  let y = 90;
  for (const [, c] of Object.entries(colors)) {
    g.fillStyle = rgb(c); g.fillRect(x, y, bw, bh);
    g.fillStyle = rgb(lift(c, d)); g.fillRect(x, y + bh, bw, bh);
    y += bh * 2 + 8;
  }
  x += bw + 20;
}
text('哪一档的"内容区比卡片浅"看着刚好？（差别太小时真机上根本看不出来）', 32, H - 28, 15, 'rgb(176,190,216)');

fs.writeFileSync(path.join(ROOT, 'preview/step-compare.png'), await canvas.encode('png'));
console.log('已生成：preview/step-compare.png');
