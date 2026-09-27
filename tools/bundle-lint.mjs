// bundle-lint.mjs —— 校验合成产物：**字符串里的非 ASCII 必须已经被转义**
//   node tools/bundle-lint.mjs dist/xuehuang.lua
//
// 为什么需要它：真机的 Lua 逐字节读源码。如果字符串里留着裸的非 ASCII 字节，
// 真机会直接**加载失败**（表现可能是"脚本没生效/画面全空"），而本地模拟器只用 latin1
// 读一遍也未必报错 —— 这类问题必须在上传前卡住。
//
// 规则（和 tools/lua-test.mjs 的 stripNonAscii 对应）：
//   · 注释里允许非 ASCII（真机本来就接受 UTF-8 注释）
//   · 长字符串 [[...]] 里不允许（无法转义，只能删）
//   · 普通字符串字面量里不允许（应已转成 \ddd）
//   · 代码区不允许
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const file = path.resolve(ROOT, process.argv[2] || 'dist/xuehuang.lua');
const bytes = fs.readFileSync(file);
const s = bytes.toString('latin1');            // 逐字节看
const problems = [];
let line = 1, i = 0;
const n = s.length;
const isNL = c => c === '\n' || c === '\r';
const ctx = at => JSON.stringify(s.slice(Math.max(0, at - 40), at + 40).replace(/[^\x20-\x7e]/g, '.'));

while (i < n) {
  const c = s[i];
  if (c === '\n') { line++; i++; continue; }
  if (c === '-' && s[i + 1] === '-') { const nl = s.indexOf('\n', i); i = nl < 0 ? n : nl; continue; }
  if (c === '[') {
    const m = /^\[(=*)\[/.exec(s.slice(i));
    if (m) {
      const close = ']' + m[1] + ']';
      const e = s.indexOf(close, i);
      const stop = e < 0 ? n : e + close.length;
      const seg = s.slice(i, stop);
      if (/[^\x00-\x7F]/.test(seg)) problems.push(`第 ${line} 行 长字符串里有非 ASCII：${ctx(i)}`);
      i = stop;
      continue;
    }
  }
  if (c === '"' || c === "'") {
    const q = c; i++;
    while (i < n) {
      const d = s[i];
      if (d === '\\') { i += 2; continue; }
      if (d === q) { i++; break; }
      if (isNL(d)) { i++; continue; }
      if (s.charCodeAt(i) > 127) { problems.push(`第 ${line} 行 字符串里有裸非 ASCII：${ctx(i)}`); i++; continue; }
      i++;
    }
    continue;
  }
  if (s.charCodeAt(i) > 127) { problems.push(`第 ${line} 行 代码区有非 ASCII：${ctx(i)}`); i++; continue; }
  i++;
}

console.log(`${path.relative(ROOT, file)}  ${bytes.length} 字节 / ${line} 行`);
if (!problems.length) {
  console.log('  ✓ 通过：字符串里的非 ASCII 都已转义（可以上传真机）');
  process.exit(0);
}
console.log(`  ✗ ${problems.length} 处问题：`);
for (const p of problems.slice(0, 12)) console.log('    ' + p);
process.exit(1);
