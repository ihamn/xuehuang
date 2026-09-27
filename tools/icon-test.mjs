// icon-test.mjs —— 用真实素材号出四工位图标测试图
//   node tools/icon-test.mjs
//
// 目的：把"候选素材号"画进工位卡里，一眼看出哪个合适。
//   真机上图标是 SetImage(StaticReference, 素材号) 来的；
//   这里用几何形状近似（我画不出千星素材），所以**只验证"语义/位置/大小"，不验证真实外观**。
import fs from 'node:fs';
import path from 'node:path';
import { createCanvas, GlobalFonts } from '@napi-rs/canvas';

const ROOT = path.resolve(import.meta.dirname, '..');
const W = 1500, H = 620;
let FAMILY = 'sans-serif';
for (const f of ['C:/Windows/Fonts/msyh.ttc', 'C:/Windows/Fonts/simhei.ttf']) {
  if (fs.existsSync(f)) { try { GlobalFonts.registerFromPath(f, 'UICN'); FAMILY = 'UICN'; break; } catch { /* next */ } }
}
const canvas = createCanvas(W, H);
const g = canvas.getContext('2d');
g.textBaseline = 'middle';
function text(s, x, y, size, col, align) { g.font = size + 'px ' + FAMILY; g.fillStyle = col; g.textAlign = align || 'left'; g.fillText(s, x, y); }
function rr(x, y, w, h, r, fill) {
  g.beginPath(); const k = Math.min(r, w / 2, h / 2);
  g.moveTo(x + k, y); g.arcTo(x + w, y, x + w, y + h, k); g.arcTo(x + w, y + h, x, y + h, k);
  g.arcTo(x, y + h, x, y, k); g.arcTo(x, y, x + w, y, k); g.closePath();
  g.fillStyle = fill; g.fill();
}
// 按"编号"画一个近似形状（真机是素材图）
function art(id, cx, cy, s) {
  const h = s / 2; g.save(); g.lineWidth = Math.max(2, s / 12); g.lineCap = 'round';
  if (id === 102002) { // 火元素
    g.fillStyle = 'rgba(255,255,255,.95)';
    g.beginPath(); g.moveTo(cx, cy - h); g.quadraticCurveTo(cx + h, cy, cx + h * .35, cy + h * .6);
    g.quadraticCurveTo(cx, cy + h, cx - h * .35, cy + h * .6); g.quadraticCurveTo(cx - h, cy, cx, cy - h); g.fill();
    g.fillStyle = 'rgb(232,126,52)';
    g.beginPath(); g.ellipse(cx, cy + h * .25, h * .3, h * .42, 0, 0, 7); g.fill();
  } else if (id === 102004) { // 冰元素：六角雪花
    g.strokeStyle = 'rgba(255,255,255,.95)';
    for (let i = 0; i < 6; i++) {
      const a = i * Math.PI / 3;
      g.beginPath(); g.moveTo(cx, cy); g.lineTo(cx + Math.cos(a) * h, cy + Math.sin(a) * h); g.stroke();
      g.beginPath();
      g.moveTo(cx + Math.cos(a) * h * .55, cy + Math.sin(a) * h * .55);
      g.lineTo(cx + Math.cos(a + .5) * h * .8, cy + Math.sin(a + .5) * h * .8); g.stroke();
    }
  } else if (id === 102028) { // 装箱
    g.fillStyle = 'rgba(255,255,255,.95)'; g.fillRect(cx - h * .8, cy - h * .5, h * 1.6, h * 1.2);
    g.strokeStyle = 'rgb(40,192,176)'; g.beginPath(); g.moveTo(cx - h * .8, cy - h * .1); g.lineTo(cx + h * .8, cy - h * .1); g.stroke();
  } else if (id === 102041) { // 壶/罐
    g.fillStyle = 'rgba(255,255,255,.95)';
    g.beginPath(); g.ellipse(cx, cy + h * .15, h * .55, h * .62, 0, 0, 7); g.fill();
    g.fillRect(cx - h * .18, cy - h * .95, h * .36, h * .4);
    g.beginPath(); g.moveTo(cx + h * .5, cy); g.quadraticCurveTo(cx + h * 1.05, cy + h * .2, cx + h * .5, cy + h * .5);
    g.lineWidth = Math.max(2, s / 10); g.strokeStyle = 'rgba(255,255,255,.95)'; g.stroke();
  } else if (id === 102027) { // 滤网
    g.fillStyle = 'rgba(255,255,255,.95)';
    g.beginPath(); g.moveTo(cx - h * .85, cy - h * .5); g.lineTo(cx + h * .85, cy - h * .5);
    g.lineTo(cx + h * .5, cy + h * .7); g.lineTo(cx - h * .5, cy + h * .7); g.closePath(); g.fill();
    g.strokeStyle = 'rgb(52,176,128)'; g.lineWidth = Math.max(1, s / 16);
    for (let i = -2; i <= 2; i++) { g.beginPath(); g.moveTo(cx + i * h * .22, cy - h * .35); g.lineTo(cx + i * h * .13, cy + h * .55); g.stroke(); }
  } else if (id === 102019) { // 水滴
    g.fillStyle = 'rgba(255,255,255,.95)';
    g.beginPath(); g.moveTo(cx, cy - h * .9); g.quadraticCurveTo(cx + h * .8, cy + h * .2, cx, cy + h * .8);
    g.quadraticCurveTo(cx - h * .8, cy + h * .2, cx, cy - h * .9); g.fill();
  } else if (id === 0) { // 占位（首字）
    g.fillStyle = 'rgba(255,255,255,.35)'; g.fillRect(cx - h * .8, cy - h * .8, h * 1.6, h * 1.6);
  }
  g.restore();
}

g.fillStyle = 'rgb(4,5,8)'; g.fillRect(0, 0, W, H);
text('四工位图标候选（我先按编号画近似形状，真机是素材图）', 32, 32, 20, 'rgb(238,243,252)');

const stations = [
  { name: '捣锤区', key: '1', col: [58, 122, 220], id: 102004, why: '做干冰 → 冰元素' },
  { name: '火系区', key: 'H', col: [232, 126, 52], id: 102002, why: '喷火枪 → 火元素' },
  { name: '化学区', key: 'K', col: [158, 106, 224], id: 102019, why: '取液 → 水滴（待替换）' },
  { name: '萃茶区', key: 'P', col: [52, 176, 128], id: 102041, why: '泡茶 → 壶/罐' },
  { name: '打包台', key: '空格', col: [40, 192, 176], id: 102028, why: '封杯出餐 → 装箱' },
];

const CW = 280, CH = 170;
stations.forEach((st, i) => {
  const x = 32 + i * (CW + 14), y = 70;
  rr(x, y, CW, CH, 12, 'rgb(' + st.col.join(',') + ')');
  rr(x + CW * .38, y + 44, CW * .62, CH - 44 - 12, 0, 'rgb(' + st.col.map(v => Math.min(255, v + 40)).join(',') + ')');
  g.fillStyle = 'rgba(255,255,255,.20)'; g.fillRect(x + CW * .38, y + 44, CW * .62, 2);
  text(st.name, x + CW * .40, y + 24, 22, 'rgb(255,255,255)');
  rr(x + CW - 40, y + 10, 30, 24, 6, 'rgba(0,0,0,.26)');
  text(st.key, x + CW - 25, y + 23, 13, 'rgb(255,255,255)', 'center');
  // 图标（左列）
  art(st.id, x + 42, y + CH / 2, 64);
  // 编号 + 理由
  text('素材号 ' + st.id, x + 12, y + CH + 26, 15, 'rgb(255,214,130)');
  text(st.why, x + 12, y + CH + 48, 14, 'rgb(176,190,216)');
});

text('打包台/工位的键位胶囊、名称行、内容区提亮都按定稿规范画的；这里只验证图标语义', 32, H - 60, 14, 'rgb(176,190,216)');
text('102027(滤网) 备选给萃茶区；102041(壶/罐) 与 102027 二选一', 32, H - 34, 14, 'rgb(176,190,216)');

fs.writeFileSync(path.join(ROOT, 'preview/icon-test.png'), await canvas.encode('png'));
console.log('已生成：preview/icon-test.png');
