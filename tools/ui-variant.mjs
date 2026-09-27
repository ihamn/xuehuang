// 两版对比：底衬范围不同、深浅不同
//   A「只暗内容区」：区域名那行 + 图标那列 = 原色；其余整块暗
//   B「只留名称行」：区域名那行 = 原色；图标列也一起暗
import fs from 'node:fs';
import path from 'node:path';
import { createCanvas, GlobalFonts } from '@napi-rs/canvas';

const ROOT = path.resolve(import.meta.dirname, '..');
const argOf = (n, d) => { const h = process.argv.find(a => a.startsWith('--' + n + '=')); return h ? h.slice(n.length + 3) : d; };
const VARIANT = argOf('variant', 'A');
const W = Number(argOf('w', 1815)), H = Number(argOf('h', 900));
const OUT = path.resolve(ROOT, argOf('out', 'preview/ui.png'));

const T = {
  safe: 24, gap: { xs: 4, s: 8, m: 16, l: 24, xl: 32 },
  font: { display: 32, step: 28, title: 26, head: 20, body: 16, small: 13, tiny: 11 },
  size: { stationW: 684, stationH: 208, packW: 1391, packH: 192, panelW: 352, orderW: 320, orderH: 136,
          hudW: 1391, hudH: 72, iconS: 22, barH: 8, edgeW: 6, bigIcon: 96, midIcon: 64 },
  color: {
    shake: [58, 122, 220], fire: [232, 126, 52], chem: [158, 106, 224], brew: [52, 176, 128], pack: [40, 192, 176],
    text: [238, 243, 252], dim: [176, 190, 216], gold: [255, 214, 130],
    good: [122, 232, 160], warn: [255, 196, 96], bad: [255, 122, 132], onColor: [255, 255, 255],
  },
};
const rgb = a => 'rgb(' + a[0] + ',' + a[1] + ',' + a[2] + ')';
// ★★ 内容区底衬 = 卡片色 **提亮半档**（用户："内容区底衬低半档"）
//   注意方向：**不是压暗**。压暗是我理解反了 —— 底色本来是亮的，内容区要比它**浅**才"低半档"。
const dim = (a, d) => 'rgb(' + Math.min(255, a[0] + (d || 30)) + ',' + Math.min(255, a[1] + (d || 30)) + ',' + Math.min(255, a[2] + (d || 30)) + ')';

let FAMILY = 'sans-serif';
for (const f of ['C:/Windows/Fonts/msyh.ttc', 'C:/Windows/Fonts/msyhbd.ttc', 'C:/Windows/Fonts/simhei.ttf']) {
  if (fs.existsSync(f)) { try { GlobalFonts.registerFromPath(f, 'UICN'); FAMILY = 'UICN'; break; } catch { /* next */ } }
}
const canvas = createCanvas(W, H);
const g = canvas.getContext('2d');
g.textBaseline = 'middle';

function roundRect(x, y, w, h, r, fill) {
  g.beginPath();
  const rr = Math.min(r, w / 2, h / 2);
  g.moveTo(x + rr, y); g.arcTo(x + w, y, x + w, y + h, rr); g.arcTo(x + w, y + h, x, y + h, rr);
  g.arcTo(x, y + h, x, y, rr); g.arcTo(x, y, x + w, y, rr); g.closePath();
  g.fillStyle = fill; g.fill();
}
function text(s, x, y, size, col, align) {
  g.font = size + 'px ' + FAMILY; g.fillStyle = col; g.textAlign = align || 'left'; g.fillText(s, x, y);
}
function textW(s, size) { g.font = size + 'px ' + FAMILY; return g.measureText(s).width; }
function icon(kind, cx, cy, s, col) {
  g.save(); g.strokeStyle = col; g.fillStyle = col; g.lineWidth = Math.max(2, s / 9); g.lineCap = 'round';
  const h = s / 2;
  switch (kind) {
    case 'check': g.beginPath(); g.moveTo(cx - h * .6, cy); g.lineTo(cx - h * .1, cy + h * .5); g.lineTo(cx + h * .7, cy - h * .5); g.stroke(); break;
    case 'warn': g.beginPath(); g.moveTo(cx, cy - h * .85); g.lineTo(cx + h * .9, cy + h * .6); g.lineTo(cx - h * .9, cy + h * .6); g.closePath(); g.fill(); break;
    case 'info': g.beginPath(); g.arc(cx, cy, h * .85, 0, 7); g.stroke(); text('i', cx, cy + 1, s * .68, col, 'center'); break;
    case 'play': g.beginPath(); g.moveTo(cx - h * .5, cy - h * .72); g.lineTo(cx + h * .82, cy); g.lineTo(cx - h * .5, cy + h * .72); g.closePath(); g.fill(); break;
    case 'clock': g.beginPath(); g.arc(cx, cy, h * .85, 0, 7); g.stroke(); g.beginPath(); g.moveTo(cx, cy); g.lineTo(cx, cy - h * .55); g.moveTo(cx, cy); g.lineTo(cx + h * .42, cy); g.stroke(); break;
    case 'coin': g.beginPath(); g.arc(cx, cy, h * .85, 0, 7); g.fill(); break;
    case 'hammer': g.fillRect(cx - h * .78, cy - h * .38, h * 1.2, h * .52); g.fillRect(cx + h * .06, cy - h * .34, h * .32, h * 1.25); break;
    case 'flame': g.beginPath(); g.moveTo(cx, cy - h * .9); g.quadraticCurveTo(cx + h * .85, cy, cx + h * .3, cy + h * .62); g.quadraticCurveTo(cx, cy + h, cx - h * .3, cy + h * .62); g.quadraticCurveTo(cx - h * .85, cy, cx, cy - h * .9); g.fill(); break;
    case 'flask': g.beginPath(); g.moveTo(cx - h * .3, cy - h * .82); g.lineTo(cx + h * .3, cy - h * .82); g.lineTo(cx + h * .3, cy - h * .12); g.lineTo(cx + h * .72, cy + h * .76); g.lineTo(cx - h * .72, cy + h * .76); g.lineTo(cx - h * .3, cy - h * .12); g.closePath(); g.fill(); break;
    case 'leaf': g.beginPath(); g.ellipse(cx, cy, h * .5, h * .85, 0.5, 0, 7); g.fill(); break;
    case 'box': g.fillRect(cx - h * .78, cy - h * .5, h * 1.56, h * 1.2); break;
    default: break;
  }
  g.restore();
}

g.fillStyle = 'rgb(4,5,8)'; g.fillRect(0, 0, W, H);

// ── HUD ──
{
  const x = T.safe, y = T.safe, w = T.size.hudW, h = T.size.hudH, cy = y + h / 2;
  roundRect(x, y, w, h, 10, 'rgba(20,24,36,.96)');
  icon('clock', x + 30, cy, 22, rgb(T.color.gold));
  text('雪皇的后厨', x + 52, cy, T.font.head, rgb(T.color.gold));
  text('第 1/5 天', x + 300, cy - 12, T.font.small, rgb(T.color.dim));
  text('04:59', x + 300, cy + 12, T.font.head, rgb(T.color.text));
  let dx = x + 500;
  const stat = (k, val, label, col) => {
    icon(k, dx, cy, T.size.iconS, col);
    text(val, dx + 18, cy, T.font.body, col);
    text(label, dx + 18 + textW(val, T.font.body) + T.gap.s, cy, T.font.small, rgb(T.color.dim));
    dx += 190;
  };
  stat('coin', '12', '今日出餐', rgb(T.color.good));
  stat('warn', '1', '流失', rgb(T.color.bad));
  stat('check', '2', '在制', rgb(T.color.text));
  text('按 1/H/K/P 做工位   ·   空格打包', x + w - 28, cy, T.font.small, rgb(T.color.dim), 'right');
}

// ── 工位卡 ──
const gridX = T.safe, gridTop = T.safe + T.size.hudH + T.gap.xl;
const NAME_ROW_H = 72;                      // 区域名那一行的高度（原色保留区）
const stations = [
  { name: '捣锤区', key: '1', ic: 'hammer', col: T.color.shake, step: '砸苹果', prog: '连按 2/4', frac: .5, active: true },
  { name: '火系区', key: 'H', ic: 'flame', col: T.color.fire, step: '等待小票', prog: '', frac: 0, active: false },
  { name: '化学区', key: 'K', ic: 'flask', col: T.color.chem, step: '取溴水 10mL', prog: '按住', frac: .3, active: true },
  { name: '萃茶区', key: 'P', ic: 'leaf', col: T.color.brew, step: '等待小票', prog: '', frac: 0, active: false },
];
const lift = (a, d) => 'rgb(' + Math.min(255, a[0] + d) + ',' + Math.min(255, a[1] + d) + ',' + Math.min(255, a[2] + d) + ')';
stations.forEach((st, i) => {
  const x = gridX + (i % 2) * (T.size.stationW + T.gap.l);
  const y = gridTop + Math.floor(i / 2) * (T.size.stationH + T.gap.l);
  const w = T.size.stationW, h = T.size.stationH;
  // ★ 底色一律纯原色（不做"有活就提亮" —— 那会和内容区压暗打架、颜色发花）
  roundRect(x, y, w, h, 14, rgb(st.col));

  const ic = T.size.bigIcon, iw = T.gap.l + ic + T.gap.l;   // 图标列宽（含两侧留白）
  // ★★ 内容区底衬：**提亮半档**（用户："内容区底衬低半档" —— 是比卡片浅，不是深）
  //   底边**上收 radius**，否则直角会切掉卡片圆角
  const RAD = 14;
  roundRect(x + iw, y + NAME_ROW_H, w - iw, h - NAME_ROW_H - RAD, 0, dim(st.col, 40));
  if (VARIANT === 'B') {
    // B 版：连图标列一起提亮（只留名称行原色）
    roundRect(x, y + NAME_ROW_H, iw, h - NAME_ROW_H - RAD, 0, dim(st.col, 40));
  }
  // 左色条
  roundRect(x, y + 20, T.size.edgeW, h - 40, 3, 'rgba(255,255,255,.42)');
  // ★ 分隔线：内容区顶边（2px 半透明白），让"名称行 / 内容区"分界更明确
  g.fillStyle = 'rgba(255,255,255,.20)';
  g.fillRect(x + iw, y + NAME_ROW_H, w - iw, 2);
  // 图标（在图标列里垂直居中）
  const ix = x + T.gap.l, iy = y + (h - ic) / 2;
  icon(st.ic, ix + ic / 2, iy + ic / 2, ic * .5, 'rgba(255,255,255,.95)');
  // 区域名：在名称行里（原色，不加底衬）
  text(st.name, x + iw, y + NAME_ROW_H / 2 + 2, T.font.title, rgb(T.color.onColor));
  // 键位胶囊（名称行右侧）
  const kw = 34, kx = x + w - T.gap.l - kw;
  roundRect(kx, y + NAME_ROW_H / 2 - 14, kw, 28, 7, 'rgba(0,0,0,.26)');
  text(st.key, kx + kw / 2, y + NAME_ROW_H / 2 + 1, T.font.small, rgb(T.color.onColor), 'center');
  // 步骤（内容区里）
  text(st.step, x + iw + 16, y + NAME_ROW_H + 44, T.font.step, 'rgb(255,255,255)');
  // 进度条
  const bw = w - iw - T.gap.l - 16, bx = x + iw + 16, by = y + h - T.gap.l - T.size.barH;
  roundRect(bx, by, bw, T.size.barH, T.size.barH / 2, 'rgba(0,0,0,.32)');
  if (st.frac > 0) roundRect(bx, by, Math.max(6, bw * st.frac), T.size.barH, T.size.barH / 2, 'rgba(255,255,255,.95)');
  if (st.prog) text(st.prog, x + w - T.gap.l - 16, by - 16, T.font.small, 'rgba(255,255,255,.8)', 'right');
});

// ── 打包台 ──
{
  const x = gridX, y = gridTop + 2 * T.size.stationH + T.gap.xl + T.gap.xl;
  const w = T.size.packW, h = T.size.packH, col = T.color.pack;
  roundRect(x, y, w, h, 14, rgb(col));
  const icx = T.size.midIcon, iw = T.gap.l + icx + T.gap.l;
  roundRect(x + iw, y + NAME_ROW_H, w - iw, h - NAME_ROW_H - 14, 0, dim(col, 40));
  if (VARIANT === 'B') roundRect(x, y + NAME_ROW_H, iw, h - NAME_ROW_H - 14, 0, dim(col, 40));
  roundRect(x, y + 20, T.size.edgeW, h - 40, 3, 'rgba(255,255,255,.42)');
  const ix = x + T.gap.l, iy = y + (h - icx) / 2;
  icon('box', ix + icx / 2, iy + icx / 2, icx * .5, 'rgba(255,255,255,.95)');
  text('打包台', x + iw, y + NAME_ROW_H / 2 + 2, T.font.head, rgb(T.color.onColor));
  const kw = 52, kx = x + iw + 76;
  roundRect(kx, y + NAME_ROW_H / 2 - 14, kw, 28, 7, 'rgba(0,0,0,.26)');
  text('空格', kx + kw / 2, y + NAME_ROW_H / 2 + 1, T.font.small, rgb(T.color.onColor), 'center');
  text('可交付', x + iw + 16, y + NAME_ROW_H + 48, T.font.small, 'rgba(255,255,255,.75)');
  text('干冰干柠檬水 · 白芝麻火麒麟', x + iw + 90, y + NAME_ROW_H + 46, T.font.step, 'rgb(255,255,255)');
  text('按空格全部交付', x + w - T.gap.l - 40, y + h - 30, T.font.small, 'rgba(255,255,255,.75)', 'right');
  icon('play', x + w - T.gap.l - 22, y + h - 30, 18, 'rgba(255,255,255,.8)');
}

// ── 订单面板 ──
{
  const x = W - T.safe - T.size.panelW, y = T.safe + T.size.hudH + T.gap.xl;
  const w = T.size.panelW, h = H - y - T.safe;
  roundRect(x, y, w, h, 12, 'rgba(24,29,46,.97)');
  text('等候区 / 在制', x + T.gap.m, y + 32, T.font.head, rgb(T.color.gold));
  icon('info', x + w - T.gap.m - 10, y + 32, 18, rgb(T.color.dim));
  const orders = [
    { who: '后厨实习生', tag: '在制', col: T.color.shake, what: '正常糖 去冰   已做 1/3', frac: .82 },
    { who: '挑剔的美食家', tag: '等候 #1', col: T.color.dim, what: '七分糖 常温   已做 0/2', frac: .45 },
  ];
  orders.forEach((o, i) => {
    const oy = y + 64 + i * (T.size.orderH + T.gap.m);
    const cardBg = [35, 43, 66];
    roundRect(x + T.gap.m, oy, T.size.orderW, T.size.orderH, 10, rgb(cardBg));
    // 内容区加深（名称行 = 顾客名那一行）
    roundRect(x + T.gap.m, oy + 60, T.size.orderW, T.size.orderH - 60 - 10, 0, dim(cardBg, 34));
    roundRect(x + T.gap.m, oy + 16, 4, T.size.orderH - 32, 2, rgb(o.col));
    const tx = x + T.gap.m + 4 + T.gap.m;
    text(o.who, tx, oy + 34, T.font.head, rgb(T.color.text));
    const tw = textW(o.tag, T.font.small) + 16;
    roundRect(x + T.gap.m + T.size.orderW - T.gap.m - tw, oy + 22, tw, 26, 6, 'rgba(0,0,0,.22)');
    text(o.tag, x + T.gap.m + T.size.orderW - T.gap.m - tw / 2, oy + 35, T.font.small, rgb(o.col), 'center');
    text(o.what, tx, oy + 90, T.font.body, rgb(T.color.text));
    const bw = T.size.orderW - T.gap.m * 2 - 4, by = oy + T.size.orderH - T.gap.m - T.size.barH;
    roundRect(tx, by, bw, T.size.barH, T.size.barH / 2, 'rgba(0,0,0,.32)');
    const pc = o.frac < .3 ? T.color.bad : (o.frac < .6 ? T.color.warn : T.color.good);
    roundRect(tx, by, Math.max(6, bw * o.frac), T.size.barH, T.size.barH / 2, rgb(pc));
    text(Math.round(o.frac * 100) + '%', tx + bw, by - 16, T.font.small, rgb(pc), 'right');
  });
  text('（最多 5 位顾客）', x + w / 2, y + h - 26, T.font.small, rgb(T.color.dim), 'center');
}

text('方案 ' + VARIANT + ' · 底衬只到"区域名那行以下"，深度 ×0.52（不太暗）', W / 2, H - 12, 12, 'rgba(255,255,255,.45)', 'center');
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, await canvas.encode('png'));
console.log('已生成：' + path.relative(process.cwd(), OUT) + '  方案 ' + VARIANT);
