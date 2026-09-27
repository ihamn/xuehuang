// 图标定稿确认图：四个工位 + 打包台，用真实素材号
import fs from 'node:fs';
import path from 'node:path';
import { createCanvas, GlobalFonts } from '@napi-rs/canvas';

const ROOT = path.resolve(import.meta.dirname, '..');
const W = 1500, H = 560;
let FAMILY = 'sans-serif';
for (const f of ['C:/Windows/Fonts/msyh.ttc', 'C:/Windows/Fonts/simhei.ttf']) {
  if (fs.existsSync(f)) { try { GlobalFonts.registerFromPath(f, 'UICN'); FAMILY = 'UICN'; break; } catch { /* next */ } }
}
const canvas = createCanvas(W, H);
const g = canvas.getContext('2d');
g.textBaseline = 'middle';
const text = (s, x, y, size, col, align) => { g.font = size + 'px ' + FAMILY; g.fillStyle = col; g.textAlign = align || 'left'; g.fillText(s, x, y); };
function rr(x, y, w, h, r, fill) {
  g.beginPath(); const k = Math.min(r, w / 2, h / 2);
  g.moveTo(x + k, y); g.arcTo(x + w, y, x + w, y + h, k); g.arcTo(x + w, y + h, x, y + h, k);
  g.arcTo(x, y + h, x, y, k); g.arcTo(x, y, x + w, y, k); g.closePath();
  g.fillStyle = fill; g.fill();
}
// 按素材号画近似形状（真机是素材图）
function art(id, cx, cy, s) {
  const h = s / 2;
  g.save(); g.lineWidth = Math.max(2, s / 12); g.lineCap = 'round';
  const white = 'rgba(255,255,255,.95)';
  g.strokeStyle = white; g.fillStyle = white;
  if (id === 102002) {           // 火元素
    g.beginPath(); g.moveTo(cx, cy - h); g.quadraticCurveTo(cx + h, cy, cx + h * .35, cy + h * .6);
    g.quadraticCurveTo(cx, cy + h, cx - h * .35, cy + h * .6); g.quadraticCurveTo(cx - h, cy, cx, cy - h); g.fill();
    g.fillStyle = 'rgb(232,126,52)'; g.beginPath(); g.ellipse(cx, cy + h * .25, h * .3, h * .42, 0, 0, 7); g.fill();
  } else if (id === 102004) {    // 冰元素
    for (let i = 0; i < 6; i++) {
      const a = i * Math.PI / 3;
      g.beginPath(); g.moveTo(cx, cy); g.lineTo(cx + Math.cos(a) * h, cy + Math.sin(a) * h); g.stroke();
      g.beginPath(); g.moveTo(cx + Math.cos(a) * h * .55, cy + Math.sin(a) * h * .55);
      g.lineTo(cx + Math.cos(a + .5) * h * .8, cy + Math.sin(a + .5) * h * .8); g.stroke();
    }
  } else if (id === 102015) {    // 护盾 + 雷
    g.beginPath(); g.moveTo(cx, cy - h); g.lineTo(cx + h * .8, cy - h * .55); g.lineTo(cx + h * .8, cy + h * .15);
    g.quadraticCurveTo(cx + h * .7, cy + h * .85, cx, cy + h); g.quadraticCurveTo(cx - h * .7, cy + h * .85, cx - h * .8, cy + h * .15);
    g.lineTo(cx - h * .8, cy - h * .55); g.closePath(); g.fill();
    g.fillStyle = 'rgb(158,106,224)';
    g.beginPath(); g.moveTo(cx - h * .05, cy - h * .5); g.lineTo(cx + h * .38, cy - h * .02);
    g.lineTo(cx + h * .05, cy - h * .02); g.lineTo(cx + h * .3, cy + h * .5); g.lineTo(cx - h * .35, cy - h * .05);
    g.lineTo(cx - h * .02, cy - h * .05); g.closePath(); g.fill();
  } else if (id === 102041) {    // 壶/罐
    g.beginPath(); g.ellipse(cx, cy + h * .15, h * .55, h * .62, 0, 0, 7); g.fill();
    g.fillRect(cx - h * .18, cy - h * .95, h * .36, h * .4);
    g.beginPath(); g.moveTo(cx + h * .5, cy); g.quadraticCurveTo(cx + h * 1.05, cy + h * .2, cx + h * .5, cy + h * .5); g.stroke();
  } else if (id === 102028) {    // 装箱
    g.fillRect(cx - h * .8, cy - h * .5, h * 1.6, h * 1.2);
    g.strokeStyle = 'rgb(40,192,176)'; g.beginPath(); g.moveTo(cx - h * .8, cy - h * .1); g.lineTo(cx + h * .8, cy - h * .1); g.stroke();
  }
  g.restore();
}
g.fillStyle = 'rgb(4,5,8)'; g.fillRect(0, 0, W, H);
text('图标定稿（4 工位 + 打包台）· 形状为近似示意，真机是素材图', 32, 30, 20, 'rgb(238,243,252)');

const sts = [
  { name: '捣锤区', key: '1', col: [58, 122, 220], id: 102004, why: '冰元素（做干冰）' },
  { name: '火系区', key: 'H', col: [232, 126, 52], id: 102002, why: '火元素（喷火枪）' },
  { name: '化学区', key: 'K', col: [158, 106, 224], id: 102015, why: '护盾+雷（素材库没烧瓶）' },
  { name: '萃茶区', key: 'P', col: [52, 176, 128], id: 102041, why: '壶/罐（泡茶）' },
  { name: '打包台', key: '空格', col: [40, 192, 176], id: 102028, why: '装箱（封杯出餐）' },
];
const CW = 280, CH = 170;
sts.forEach((st, i) => {
  const x = 32 + i * (CW + 14), y = 70;
  const c = 'rgb(' + st.col.join(',') + ')';
  rr(x, y, CW, CH, 12, c);
  rr(x + CW * .38, y + 44, CW * .62, CH - 56, 0, 'rgb(' + st.col.map(v => Math.min(255, v + 40)).join(',') + ')');
  g.fillStyle = 'rgba(255,255,255,.20)'; g.fillRect(x + CW * .38, y + 44, CW * .62, 2);
  text(st.name, x + CW * .40, y + 24, 22, 'rgb(255,255,255)');
  rr(x + CW - 46, y + 10, 34, 24, 6, 'rgba(0,0,0,.26)');
  text(st.key, x + CW - 29, y + 23, 13, 'rgb(255,255,255)', 'center');
  art(st.id, x + 44, y + CH / 2, 64);
  text('素材号 ' + st.id, x + 12, y + CH + 26, 15, 'rgb(255,214,130)');
  text(st.why, x + 12, y + CH + 48, 14, 'rgb(176,190,216)');
});
text('素材号已写进 lua/src/skin.lua 的 icon 表；换图标只改那一处', 32, H - 40, 14, 'rgb(176,190,216)');
fs.writeFileSync(path.join(ROOT, 'preview/icon-final.png'), await canvas.encode('png'));
console.log('已生成：preview/icon-final.png');
