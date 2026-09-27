// gil-extract-lua.mjs —— 从 .gil 关卡存档里把**嵌入的 Lua** 抠出来落盘
//
// 为什么需要：项目没有 git，也没有 out/ 目录；能代表"当时真机跑的那一版"的物证只剩
// 编辑器保存生成的 .gil（dist/*.gil.bak 和 dist/gil-history/*.gil）。
// 这些文件里嵌着脚本源码（脚本是保存进存档的），所以**能从存档里恢复旧版本**。
//
// 用法：
//   node tools/gil-extract-lua.mjs                 # 扫全部 .gil，逐个报告并落盘
//   node tools/gil-extract-lua.mjs <文件.gil>       # 只处理一个
//   node tools/gil-extract-lua.mjs --list           # 只列表，不落盘

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const ROOT = path.resolve(import.meta.dirname, '..');
const OUT = path.join(ROOT, 'dist', 'gil-lua');
const listOnly = process.argv.includes('--list');

function gilFiles() {
  const out = [];
  const push = (p, tag) => { if (fs.existsSync(p)) out.push({ p, tag }); };
  push(path.join(ROOT, 'dist', '1073741825.gil.bak'), 'dist-bak-1825');
  push(path.join(ROOT, 'dist', '1073741826.gil.bak'), 'dist-bak-1826');
  push(path.join(ROOT, 'dist', '1073741827.gil.bak'), 'dist-bak-1827');
  push(path.join(ROOT, '临时.gil'), 'root-临时');
  const hist = path.join(ROOT, 'dist', 'gil-history');
  if (fs.existsSync(hist)) {
    for (const f of fs.readdirSync(hist)) if (f.endsWith('.gil')) out.push({ p: path.join(hist, f), tag: 'hist/' + f });
    const nested = path.join(hist, 'gil-history');
    if (fs.existsSync(nested)) {
      for (const f of fs.readdirSync(nested)) if (f.endsWith('.gil')) out.push({ p: path.join(nested, f), tag: 'hist/nested-' + f });
    }
  }
  return out;
}

// .gil 里 Lua 是**明文嵌入**的（UTF-8）。切出"看起来像 Lua 源"的最大连续块。
function extractLua(buf) {
  const text = buf.toString('utf8');
  const chunks = [];
  const re = /xuehuang-hello[^\x00]*/g;
  // 找脚本起点：最常见的入口标记是模块注释/版本标语；退化为找最长含 OnUpdate 的区间
  const marks = [];
  let m;
  while ((m = re.exec(text)) !== null) marks.push(m.index);
  const anchors = ['-- ═', 'local H = require', 'function OnStart', 'xuehuang-hello'];
  for (const a of anchors) {
    let i = 0;
    while ((i = text.indexOf(a, i)) !== -1) { marks.push(i); i += 1; }
  }
  for (const start of marks) {
    // 向前扩到行首
    let s = start; while (s > 0 && text[s - 1] !== '\n') s -= 1;
    // 向后取一块（脚本约 100~400KB）
    for (const len of [420000, 220000, 120000, 60000, 20000]) {
      const chunk = text.slice(s, s + len);
      if (/function\s+On(Init|Start|Update)\s*\(/.test(chunk)) { chunks.push(chunk); break; }
    }
  }
  if (!chunks.length) return null;
  // 取最长的那块，并裁掉后面夹杂的二进制垃圾：截到最后一个能闭合的合理行
  chunks.sort((a, b) => b.length - a.length);
  let best = chunks[0];
  const bad = best.search(/[\uFFFD]/);
  if (bad > 1000) best = best.slice(0, bad);
  return best;
}

const files = process.argv[2] && !process.argv[2].startsWith('--')
  ? [{ p: path.resolve(process.argv[2]), tag: 'arg' }]
  : gilFiles();

if (!files.length) { console.log('没有找到 .gil'); process.exit(0); }
if (!listOnly) fs.mkdirSync(OUT, { recursive: true });

const rows = [];
for (const f of files) {
  const buf = fs.readFileSync(f.p);
  const lua = extractLua(buf);
  const st = fs.statSync(f.p);
  const row = { tag: f.tag, gil: path.relative(ROOT, f.p), bytes: buf.length, lua: lua ? lua.length : 0, sha: lua ? crypto.createHash('sha1').update(lua).digest('hex').slice(0, 10) : '-' };
  if (lua && !listOnly) {
    const name = f.tag.replace(/[\\/]/g, '_').replace(/\.gil$/i, '') + '.lua';
    const dest = path.join(OUT, name);
    fs.writeFileSync(dest, lua);
    row.saved = path.relative(ROOT, dest);
  }
  rows.push({ ...row, mtime: st.mtime.toISOString().replace('T', ' ').slice(0, 19) });
}

console.log('tag'.padEnd(30) + 'mtime'.padEnd(21) + 'gil字节'.padStart(9) + '  lua字节'.padStart(9) + '  sha1(10)   落盘');
for (const r of rows) {
  console.log(r.tag.padEnd(30) + r.mtime.padEnd(21) + String(r.bytes).padStart(9) + '  ' + String(r.lua).padStart(9) + '  ' + r.sha + '  ' + (r.saved || ''));
}
const uniq = new Set(rows.filter(r => r.lua > 0).map(r => r.sha));
console.log(`\n共 ${rows.length} 个存档，其中 ${rows.filter(r => r.lua > 0).length} 个抠出脚本，${uniq.size} 个不同版本。`);
