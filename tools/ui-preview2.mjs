// ui-preview.mjs —— 按《雪皇-视觉规范.md》把界面画成一张图（真字体 + 真间距 + 真配色）
//
//   node tools/ui-preview.mjs [--out=preview/ui.png] [--w=1815] [--h=900]
//
// 为什么要有它：改代码前的"看图确认"环节。
//   之前是"改代码 → 部署 → 用户进游戏看 → 不满意 → 再改"，一个来回很贵；
//   有了这张图，风格/排版/图标能先定死，再往代码里落。
//
// ★ 所有数值与 lua/src/skin.lua 一致；三处（本文件 / skin.lua / 视觉规范.md）改动要同步。
//   真机画布 1815×900（≈2.02:1），不是 1600×900。
//
// ★★ 视觉规则（用户逐轮定的，别改）：
//   ① 有**整屏黑色打底**，UI 压在其上
//   ② 按钮要**撑满空间**，不留大片空白
//   ③ 字号要**内敛**，不靠粗体拉层次
//   ④ **步骤**（该做什么）比**区域名**略大一档：step 28 > title 26
//   ⑤ **只给步骤加底衬，区域名不加**；底衬用**同色系压暗**（不是纯黑）→ 对比够且色彩不脏
import fs from 'node:fs';
import path from 'node:path';
import { createCanvas, GlobalFonts } from '@napi-rs/canvas';

const ROOT = path.resolve(import.meta.dirname, '..');
const argOf = (n, d) => { const h = process.argv.find(a => a.startsWith('--' + n + '=')); return h ? h.slice(n.length + 3) : d; };
const W = Number(argOf('w', 1815)), H = Number(argOf('h', 900));
const OUT = path.resolve(ROOT, argOf('out', 'preview/ui.png'));

// ══════════════ 规范数值（与 skin.lua 同一份）══════════════
const T = {
  safe: 24,
  gap: { xs: 4, s: 8, m: 16, l: 24, xl: 32 },
  font: { display: 32, step: 28, title: 26, head: 20, body: 16, small: 13, tiny: 11 },
  size: {
    stationW: 684, stationH: 208, packW: 1391, packH: 192,
    panelW: 352, panelH: 736, orderW: 320, orderH: 136,
    hudW: 1391, hudH: 72, iconL: 30, iconS: 22, barH: 8, edgeW: 6,
    bigIcon: 96, midIcon: 64,
  },
  color: {
    shake: [58, 122, 220], fire: [232, 126, 52], chem: [158, 106, 224], brew: [52, 176, 128],
    pack: [40, 192, 176],
    hudBg: [14, 17, 26], panelBg: [27, 32, 51], cardBg: [35, 43, 66], slotBg: [18, 21, 31],
    text: [238, 243, 252], dim: [176, 190, 216], gold: [255, 214, 130],
    good: [122, 232, 160], warn: [255, 196, 96], bad: [255, 122, 132], onColor: [255, 255, 255],
  },
};
const rgb = a => 'rgb(' + a[0] + ',' + a[1] + ',' + a[2] + ')';
// 压暗做底衬：保持色相只降亮度 —— 比纯黑叠上去更"有色"，不脏
const dim = (a, k) => 'rgb(' + Math.round(a[0] * (k || 0.30)) + ',' + Math.round(a[1] * (k || 0.30)) + ',' + Math.round(a[2] * (k || 0.30)) + ')';
const lift = (a, d) => 'rgb(' + Math.min(255, a[0] + (d || 34)) + ',' + Math.min(255, a[1] + (d || 34)) + ',' + Math.min(255, a[2] + (d || 34)) + ')';

// ── 中文字体 ──
let FAMILY = 'sans-serif';
for (const f of ['C:/Windows/Fonts/msyh.ttc', 'C:/Windows/Fonts/msyhbd.ttc', 'C:/Windows/Fonts/simhei.ttf', 'C:/Windows/Fonts/simsun.ttc']) {
  if (fs.existsSync(f)) { try { GlobalFonts.registerFromPath(f, 'UICN'); FAMILY = 'UICN'; break; } catch { /* 下一个 */ } }
}

const canvas = createCanvas(W, H);
const g = canvas.getContext('2d');
g.textBaseline = 'middle';

// ══════════════ 基础绘制 ══════════════
function roundRect(x, y, w, h, r, fill) {
  g.beginPath();
  const rr = Math.min(r, w / 2, h / 2);
  g.moveTo(x + rr, y);
  g.arcTo(x + w, y, x + w, y + h, rr);
  g.arcTo(x + w, y + h, x, y + h, rr);
  g.arcTo(x, y + h, x, y, rr);
  g.arcTo(x, y, x + w, y, rr);
  g.closePath();
  g.fillStyle = fill; g.fill();
}
function text(s, x, y, size, col, align, weight) {
  g.font = ((weight || '') + ' ' + size + 'px ' + FAMILY).trim();
  g.fillStyle = col; g.textAlign = align || 'left';
  g.fillText(s, x, y);
}
// 量文字宽度（加底衬时按实际宽度画）
function textW(s, size, weight) {
  g.font = ((weight || '') + ' ' + size + 'px ' + FAMILY).trim();
  return g.measureText(s).width;
}
// ★ 带底衬的"内容"文字：底衬 = 同色系压暗（规则 ⑤）
//   ★★ 底衬**固定宽度**（由调用方给 w），**不按文字长度伸缩** ——
//      伸缩会显得零碎不好看，而且每张卡宽度不一，视觉上很乱。
function textOnChip(s, x, cy, size, baseCol, col, w) {
  const hh = size * 1.7;
  roundRect(x, cy - hh / 2, w, hh, 6, dim(baseCol, 0.30));
  text(s, x + 12, cy, size, col || 'rgb(255,255,255)', 'left');
}
// 图标（真机是素材图；这里用几何形状示意大小与位置）
function icon(kind, cx, cy, s, col) {
  g.save();
  g.strokeStyle = col; g.fillStyle = col;
  g.lineWidth = Math.max(2, s / 9);
  g.lineCap = 'round';
  const h = s / 2;
  switch (kind) {
    case 'check': g.beginPath(); g.moveTo(cx - h * .6, cy); g.lineTo(cx - h * .1, cy + h * .5); g.lineTo(cx + h * .7, cy - h * .5); g.stroke(); break;
    case 'cross': g.beginPath(); g.moveTo(cx - h * .5, cy - h * .5); g.lineTo(cx + h * .5, cy + h * .5); g.moveTo(cx + h * .5, cy - h * .5); g.lineTo(cx - h * .5, cy + h * .5); g.stroke(); break;
    case 'warn': g.beginPath(); g.moveTo(cx, cy - h * .85); g.lineTo(cx + h * .9, cy + h * .6); g.lineTo(cx - h * .9, cy + h * .6); g.closePath(); g.fill(); break;
    case 'info': g.beginPath(); g.arc(cx, cy, h * .85, 0, 7); g.stroke(); text('i', cx, cy + 1, s * .68, col, 'center', 'bold'); break;
    case 'play': g.beginPath(); g.moveTo(cx - h * .5, cy - h * .72); g.lineTo(cx + h * .82, cy); g.lineTo(cx - h * .5, cy + h * .72); g.closePath(); g.fill(); break;
    case 'clock': g.beginPath(); g.arc(cx, cy, h * .85, 0, 7); g.stroke(); g.beginPath(); g.moveTo(cx, cy); g.lineTo(cx, cy - h * .55); g.moveTo(cx, cy); g.lineTo(cx + h * .42, cy); g.stroke(); break;
    case 'coin': g.beginPath(); g.arc(cx, cy, h * .85, 0, 7); g.fill(); break;
    case 'hammer': g.fillRect(cx - h * .78, cy - h * .38, h * 1.2, h * .52); g.fillRect(cx + h * .06, cy - h * .34, h * .32, h * 1.25); break;
    case 'flame': g.beginPath(); g.moveTo(cx, cy - h * .9); g.quadraticCurveTo(cx + h * .85, cy, cx + h * .3, cy + h * .62); g.quadraticCurveTo(cx, cy + h, cx - h * .3, cy + h * .62); g.quadraticCurveTo(cx - h * .85, cy, cx, cy - h * .9); g.fill(); break;
    case 'flask': g.beginPath(); g.moveTo(cx - h * .3, cy - h * .82); g.lineTo(cx + h * .3, cy - h * .82); g.lineTo(cx + h * .3, cy - h * .12); g.lineTo(cx + h * .72, cy + h * .76); g.lineTo(cx - h * .72, cy + h * .76); g.lineTo(cx - h * .3, cy - h * .12); g.closePath(); g.fill(); break;
    case 'leaf': g.beginPath(); g.ellipse(cx, cy, h * .5, h * .85, 0.5, 0, 7); g.fill(); break;
    case 'box': g.fillRect(cx - h * .78, cy - h * .5, h * 1.56, h * 1.2); g.strokeStyle = 'rgba(0,0,0,.28)'; g.beginPath(); g.moveTo(cx - h * .78, cy - h * .12); g.lineTo(cx + h * .78, cy - h * .12); g.stroke(); break;
    default: break;
  }
  g.restore();
}

// ══════════════ 0. 整屏黑色打底（规则 ①）══════════════
g.fillStyle = 'rgb(4,5,8)'; g.fillRect(0, 0, W, H);

// ══════════════ 1. HUD 条 ══════════════
{
  const x = T.safe, y = T.safe, w = T.size.hudW, h = T.size.hudH, cy = y + h / 2;
  roundRect(x, y, w, h, 10, 'rgba(20,24,36,.96)');
  icon('clock', x + 30, cy, 22, rgb(T.color.gold));
  text('雪皇的后厨', x + 52, cy, T.font.head, rgb(T.color.gold), 'left');
  text('第 1/5 天', x + 300, cy - 12, T.font.small, rgb(T.color.dim));
  text('04:59', x + 300, cy + 12, T.font.head, rgb(T.color.text), 'left');
  let dx = x + 500;
  const stat = (k, val, label, col) => {
    icon(k, dx, cy, T.size.iconS, col);
    text(val, dx + 18, cy, T.font.body, col, 'left');
    text(label, dx + 18 + textW(val, T.font.body) + T.gap.s, cy, T.font.small, rgb(T.color.dim));
    dx += 190;
  };
  stat('coin', '12', '今日出餐', rgb(T.color.good));
  stat('warn', '1', '流失', rgb(T.color.bad));
  stat('check', '2', '在制', rgb(T.color.text));
  text('按 1/H/K/P 做工位   ·   空格打包', x + w - 28, cy, T.font.small, rgb(T.color.dim), 'right');
}

// ══════════════ 2. 工位卡片 2×2（684×208，撑满左区）══════════════
const gridX = T.safe, gridTop = T.safe + T.size.hudH + T.gap.xl;
const stations = [
  { name: '捣锤区', key: '1', ic: 'hammer', col: T.color.shake, step: '砸苹果', prog: '连按 2/4', frac: .5, active: true },
  { name: '火系区', key: 'H', ic: 'flame', col: T.color.fire, step: '等待小票', prog: '', frac: 0, active: false },
  { name: '化学区', key: 'K', ic: 'flask', col: T.color.chem, step: '取溴水 10mL', prog: '按住', frac: .3, active: true },
  { name: '萃茶区', key: 'P', ic: 'leaf', col: T.color.brew, step: '等待小票', prog: '', frac: 0, active: false },
];
stations.forEach((st, i) => {
  const x = gridX + (i % 2) * (T.size.stationW + T.gap.l);
  const y = gridTop + Math.floor(i / 2) * (T.size.stationH + T.gap.l);
  roundRect(x, y, T.size.stationW, T.size.stationH, 14, st.active ? lift(st.col) : rgb(st.col));
  roundRect(x, y + 20, T.size.edgeW, T.size.stationH - 40, 3, 'rgba(255,255,255,.42)');
  // 左：图标块
  const ic = T.size.bigIcon, ix = x + T.gap.l, iy = y + (T.size.stationH - ic) / 2;
  roundRect(ix, iy, ic, ic, 14, 'rgba(0,0,0,.16)');
  icon(st.ic, ix + ic / 2, iy + ic / 2, ic * .5, 'rgba(255,255,255,.95)');
  // 右：信息区
  const tx = ix + ic + T.gap.l, tw = x + T.size.stationW - T.gap.l - tx;
  // 区域名：**不加底衬**（规则 ⑤）
  text(st.name, tx, y + 44, T.font.title, rgb(T.color.onColor), 'left');
  const kw = 34, kx = x + T.size.stationW - T.gap.l - kw;
  roundRect(kx, y + 30, kw, 28, 7, 'rgba(0,0,0,.26)');
  text(st.key, kx + kw / 2, y + 45, T.font.small, rgb(T.color.onColor), 'center');
  // 步骤：**加同色系底衬**，固定宽度铺满（规则 ⑤）
  textOnChip(st.step, tx, y + 98, T.font.step, st.col, 'rgb(255,255,255)', tw);
  const by = y + T.size.stationH - T.gap.l - T.size.barH;
  roundRect(tx, by, tw, T.size.barH, T.size.barH / 2, 'rgba(0,0,0,.28)');
  if (st.frac > 0) roundRect(tx, by, Math.max(6, tw * st.frac), T.size.barH, T.size.barH / 2, 'rgba(255,255,255,.95)');
  if (st.prog) text(st.prog, x + T.size.stationW - T.gap.l, by - 16, T.font.small, 'rgba(255,255,255,.8)', 'right');
});

// ══════════════ 3. 打包台（1391×192，撑满左区）══════════════
{
  const x = gridX, y = gridTop + 2 * T.size.stationH + T.gap.xl + T.gap.xl;
  const w = T.size.packW, h = T.size.packH;
  roundRect(x, y, w, h, 14, rgb(T.color.pack));
  roundRect(x, y + 20, T.size.edgeW, h - 40, 3, 'rgba(255,255,255,.42)');
  const ic = T.size.midIcon, ix = x + T.gap.l, iy = y + (h - ic) / 2;
  roundRect(ix, iy, ic, ic, 14, 'rgba(0,0,0,.16)');
  icon('box', ix + ic / 2, iy + ic / 2, ic * .5, 'rgba(255,255,255,.95)');
  const tx = ix + ic + T.gap.l;
  // 标题（标签）不加底衬
  text('打包台', tx, y + 48, T.font.head, rgb(T.color.onColor), 'left');
  const kw = 52, kx = tx + 76;
  roundRect(kx, y + 34, kw, 28, 7, 'rgba(0,0,0,.26)');
  text('空格', kx + kw / 2, y + 49, T.font.small, rgb(T.color.onColor), 'center');
  // 清单：加底衬（固定宽度）
  text('可交付 2 杯', tx, y + 108, T.font.small, 'rgba(255,255,255,.8)');
  textOnChip('干冰干柠檬水 · 白芝麻火麒麟', tx + 100, y + 108, T.font.step, T.color.pack, 'rgb(255,255,255)', 440);
  text('按空格全部交付', x + w - T.gap.l - 40, y + h - 30, T.font.small, 'rgba(255,255,255,.75)', 'right');
  icon('play', x + w - T.gap.l - 22, y + h - 30, 18, 'rgba(255,255,255,.8)');
}

// ══════════════ 4. 订单面板（352×736，贴右）══════════════
{
  const x = W - T.safe - T.size.panelW, y = T.safe + T.size.hudH + T.gap.xl;
  const w = T.size.panelW, h = H - y - T.safe;
  roundRect(x, y, w, h, 12, 'rgba(24,29,46,.97)');
  text('等候区 / 在制', x + T.gap.m, y + 32, T.font.head, rgb(T.color.gold), 'left');
  icon('info', x + w - T.gap.m - 10, y + 32, 18, rgb(T.color.dim));
  const orders = [
    { who: '后厨实习生', tag: '在制', col: T.color.shake, what: '正常糖 去冰   已做 1/3', frac: .82 },
    { who: '挑剔的美食家', tag: '等候 #1', col: T.color.dim, what: '七分糖 常温   已做 0/2', frac: .45 },
  ];
  orders.forEach((o, i) => {
    const oy = y + 64 + i * (T.size.orderH + T.gap.m);
    roundRect(x + T.gap.m, oy, T.size.orderW, T.size.orderH, 10, rgb(T.color.cardBg));
    roundRect(x + T.gap.m, oy + 16, 4, T.size.orderH - 32, 2, rgb(o.col));
    const tx = x + T.gap.m + 4 + T.gap.m;
    text(o.who, tx, oy + 42, T.font.head, rgb(T.color.text), 'left');
    const tw = textW(o.tag, T.font.small) + 16;
    roundRect(x + T.gap.m + T.size.orderW - T.gap.m - tw, oy + 28, tw, 26, 6, 'rgba(0,0,0,.22)');
    text(o.tag, x + T.gap.m + T.size.orderW - T.gap.m - tw / 2, oy + 41, T.font.small, rgb(o.col), 'center');
    // 要求：加底衬（固定宽度；底色用该卡的状态色系）
    textOnChip(o.what, tx, oy + 86, T.font.body, o.col, rgb(T.color.text), T.size.orderW - T.gap.m * 2 - 16);
    const bw = T.size.orderW - T.gap.m * 2 - 4;
    const by = oy + T.size.orderH - T.gap.m - T.size.barH;
    roundRect(tx, by, bw, T.size.barH, T.size.barH / 2, rgb(T.color.slotBg));
    const pc = o.frac < .3 ? T.color.bad : (o.frac < .6 ? T.color.warn : T.color.good);
    roundRect(tx, by, Math.max(6, bw * o.frac), T.size.barH, T.size.barH / 2, rgb(pc));
    text(Math.round(o.frac * 100) + '%', tx + bw, by - 16, T.font.small, rgb(pc), 'right');
  });
  text('（最多 5 位顾客）', x + w / 2, y + h - 26, T.font.small, rgb(T.color.dim), 'center');
}

// ══════════════ 标注 ══════════════
g.strokeStyle = 'rgba(255,255,255,.10)'; g.lineWidth = 1;
g.strokeRect(T.safe, T.safe, W - T.safe * 2, H - T.safe * 2);
text('安全边距 24', T.safe + 8, T.safe + 14, 11, 'rgba(255,255,255,.30)');
text('视觉规范 v5 · 真机画布 ' + W + '×' + H + ' · 步骤带同色系底衬（区域名不带）', W / 2, H - 12, 11, 'rgba(255,255,255,.35)', 'center');

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, await canvas.encode('png'));
console.log('已生成：' + path.relative(process.cwd(), OUT) + '  ' + W + '×' + H + '  字体=' + FAMILY);
