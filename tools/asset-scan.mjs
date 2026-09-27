// asset-scan.mjs —— 从 .gil 关卡存档里把"素材号 → 名字"挖出来，建成一张表
//   node tools/asset-scan.mjs [gil路径]
//
// 背景：官方文档**没有**素材号一览（只讲类型：单色/彩色、普通/三宫格/九宫格）。
//   但关卡存档里会记录"这一关用到的素材"，而且很可能带名字 ——
//   于是我们能从自己已经用过的素材里，逐条攒出一张**实测表**。
import fs from 'node:fs';
import path from 'node:path';

const DEFAULT = 'C:/Users/netease/AppData/LocalLow/miHoYo/原神/BeyondLocal/190800866/Beyond_Local_Save_Level/1073741825/1073741825.gil';
const file = process.argv[2] || DEFAULT;
if (!fs.existsSync(file)) { console.log('找不到：' + file); process.exit(0); }
const buf = fs.readFileSync(file);
const latin = buf.toString('latin1');

// 找出所有 100000..109999 的素材号候选（用字节邻域排除长数字的一部分）
const ids = new Map();
for (const m of latin.matchAll(/(?<![0-9])(10[0-9]{4})(?![0-9])/g)) {
  const id = Number(m[1]);
  if (!ids.has(id)) ids.set(id, []);
  ids.get(id).push(m.index);
}
console.log(`${path.basename(file)}  ${buf.length} 字节`);
console.log(`形如 10xxxx 的素材号候选：${ids.size} 个\n`);

// 在每个素材号的**附近**找名字：前后各 260 字节范围内出现的可读串/中文
function namesNear(offset) {
  const from = Math.max(0, offset - 260), to = Math.min(buf.length, offset + 260);
  const chunk = buf.subarray(from, to);
  const out = [];
  // 中文（UTF-8）
  for (const m of chunk.toString('utf8').matchAll(/[\u4e00-\u9fff][\u4e00-\u9fff0-9A-Za-z_]{1,15}/g)) out.push(m[0]);
  // 英文标识（UI_xxx / Icon_xx / Btn_xx 之类）
  for (const m of chunk.toString('latin1').matchAll(/[A-Za-z][A-Za-z0-9_]{4,40}/g)) {
    if (/^(UI_|Icon|Img|Image|Btn|Button|Panel|Bg|Box|Mark|Item)/i.test(m[0])) out.push(m[0]);
  }
  return [...new Set(out)].slice(0, 6);
}

const rows = [];
for (const [id, offs] of [...ids.entries()].sort((a, b) => a[0] - b[0])) {
  const cand = [];
  for (const o of offs.slice(0, 3)) cand.push(...namesNear(o));
  rows.push({ id, count: offs.length, names: [...new Set(cand)].slice(0, 6) });
}

console.log('素材号   出现次数   附近的名字（不保证对应，需人工核对）');
for (const r of rows) {
  console.log(`  ${r.id}   ${String(r.count).padStart(3)}     ${r.names.join('  ') || '(没找到名字)'}`);
}

// 顺便找"素材/图片资产"这类分类名，看看存档里怎么称呼它们
const cats = new Set();
for (const m of buf.toString('utf8').matchAll(/[\u4e00-\u9fff]{2,10}素材[\u4e00-\u9fff]{0,6}/g)) cats.add(m[0]);
for (const m of buf.toString('utf8').matchAll(/[\u4e00-\u9fff]{2,10}资产[\u4e00-\u9fff]{0,6}/g)) cats.add(m[0]);
if (cats.size) {
  console.log('\n存档里出现过的"素材/资产"字样：');
  console.log('  ' + [...cats].slice(0, 20).join('  '));
}
