import fs from 'node:fs';
let v = fs.readFileSync('lua/src/view.lua', 'utf8');

// 把"订单卡面板"段也移到 HUD 之前（数据面板已在前面）
//   找到 5. 订单卡 段（含它的头部注释）→ 摘出来 → 插到 HUD 段之前
const markers = ['  -- ═══ 5. 订单卡', '  -- ═══ 5. 订单', '  -- ═══ 4. 订单卡', '  -- 订单卡'];
let from = -1, mk = '';
for (const m of markers) { const i = v.indexOf(m); if (i >= 0) { from = i; mk = m; break; } }
if (from < 0) { console.log('找不到订单卡段'); process.exit(1); }
// 段的结束：下一个 "  -- ═══" 或 "  -- ★ 结算背景板"
let to = -1;
for (const m of ['  -- ═══ 6.', '  -- ═══ 6 ', '  -- ★ 结算背景板', '  -- ═══ 1. HUD 条']) {
  const i = v.indexOf(m, from + 10);
  if (i > 0 && (to < 0 || i < to)) to = i;
}
if (to < 0) { console.log('找不到订单卡段结束'); process.exit(1); }
const seg = v.slice(from, to);
console.log('摘出段: ' + JSON.stringify(seg.slice(0, 40)) + ' ... 长度 ' + seg.length);
v = v.slice(0, from) + v.slice(to);
// 插到 HUD 段之前
const hud = v.indexOf('  -- ═══ 1. HUD 条');
if (hud < 0) { console.log('找不到 HUD 段'); process.exit(1); }
v = v.slice(0, hud) + seg + v.slice(hud);
fs.writeFileSync('lua/src/view.lua', v);
console.log('订单卡段已移到 HUD 之前');
