// collect-shots.mjs —— 把"用户发来的截图"从 DSH 附件目录复制到项目的 screenshots/
//   node tools/collect-shots.mjs
//
// 为什么要这个：用户发的截图落在 DSH 附件目录（哈希文件名，认不出来），
//   而项目自己的渲染图在 preview/ —— 两者混在一起很难找。
//   这里按"时间 + 尺寸 + 文件大小"把**用户发的大图**挑出来，重命名成看得懂的名字。
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const SRC = 'C:/Users/netease/.dsh/attachments/v1/objects';
const DST = path.join(ROOT, 'screenshots');

// 已知的用户截图（时间 → 说明）。哈希来自这次会话的附件记录。
const KNOWN = [
  { hash: 'f90b1cf2605d9c8e', name: '01-游戏内-最早一次（白框色块那版）', at: '09-27 00:31' },
  { hash: '0d02f3613f7d1530', name: '02-游戏内-深色小块那版', at: '09-27 01:34' },
  { hash: '0703b5f1cf6e479d', name: '03-游戏内-有深色横条、无字', at: '09-27 01:39' },
  { hash: 'e4d4a4cd3ff3928b', name: '04-编辑器-素材库-功能图标单色1', at: '09-27 09:59' },
  { hash: 'd97a0f6823d4f98b', name: '05-编辑器-素材库-功能图标单色2', at: '09-27 09:59' },
  { hash: 'd3e9a46d1835c363', name: '06-编辑器-素材库-玩法图标单色', at: '09-27 09:59' },
  { hash: 'e2b3ea114d063b45', name: '07-编辑器-素材库-装饰图案单色', at: '09-27 09:59' },
  { hash: '9bff24a11de76543', name: '08-编辑器-素材库-底板单色1', at: '09-27 09:59' },
  { hash: '1f08ef9cf310f74a', name: '09-编辑器-素材库-底板单色2', at: '09-27 09:59' },
  { hash: '1d9bf13e489e71c6', name: '10-编辑器-素材库-底板单色3', at: '09-27 09:59' },
  { hash: '0bed57912ffa0ae8', name: '11-编辑器-素材库-手柄焦点提示', at: '09-27 09:59' },
];

fs.mkdirSync(DST, { recursive: true });
const all = fs.readdirSync(SRC, { recursive: true }).filter(f => !f.includes('.'));
let n = 0, miss = [];
for (const k of KNOWN) {
  const hit = all.find(f => f.startsWith(k.hash.slice(0, 2)) && path.basename(f).startsWith(k.hash));
  if (!hit) { miss.push(k.hash); continue; }
  const src = path.join(SRC, hit);
  const ext = path.extname(hit) || '.png';
  const dst = path.join(DST, k.name + ext);
  fs.copyFileSync(src, dst);
  n++;
}
// 顺带写一份索引，说明每张是什么
const lines = ['# 截图索引', '',
  '> 用户发来的截图（从 DSH 附件目录复制而来，原文件在 `C:\\Users\\netease\\.dsh\\attachments\\v1\\objects\\`）。',
  '> 我自己的渲染图在 `preview/`，别混。', ''];
for (const k of KNOWN) lines.push(`- \`${k.name}.png\`  —— ${k.at}`);
lines.push('', '## 这些截图当时暴露的问题（备考）', '',
  '- **01 / 02**：早期版本 —— 色块没有文字、有"深色小块"（文本框自带不透明底）、有白框',
  '- **03**：出现了顶部深色横条（说明 Z 序修对了），**但横条里没有文字** → 后来查明是"文本框太矮被裁"',
  '- **04~11**：编辑器素材库截图 —— 据此建了「素材号实测表」，并发现基础形状只有 6 个图元', '');
fs.writeFileSync(path.join(DST, 'INDEX.md'), lines.join('\n'));

console.log(`已复制 ${n} 张到 screenshots/`);
if (miss.length) console.log('没找到:', miss.join(', '));
