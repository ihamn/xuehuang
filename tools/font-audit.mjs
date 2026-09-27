// font-audit.mjs —— 检查最终产物里**会显示的文字**有没有原神字体不支持的字符
//
//   node tools/font-audit.mjs dist/xuehuang.lua
//
// 为什么需要它：原神没有 emoji 字体，emoji 在真机上会变成豆腐块/空白（用户实测）。
//   这类问题本地模拟器看不出来（模拟器用的是浏览器字体，什么都能画），
//   所以必须**在上传前**静态拦下来。
//
// 判定依据（保守白名单，只放"原神界面确实会显示"的区间）：
//   · ASCII 可见字符        U+0020..U+007E     （英文/数字/标点，标题里的 · 之外都能用）
//   · CJK 统一汉字          U+4E00..U+9FFF     （中文）
//   · CJK 标点              U+3000..U+303F     （、。「」《》…）
//   · 全角形式              U+FF00..U+FFEF     （（）：；！？等全角）
//   · 常用几何/箭头符号      U+2190..U+25FF     （→ ★ ● ◆ ▲ ⚠ 等；真机截图证实 ◆ 能显示）
//   · 制表/破折号            U+2010..U+2027     （—— … 等）
//   · 空白                  U+0009/U+000A/U+000D
// 其余一律视为"字体可能不支持"（emoji U+1F300+、杂项符号 U+2600 以上大部分等）。
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const file = path.resolve(ROOT, process.argv[2] || 'dist/xuehuang.lua');
if (!fs.existsSync(file)) { console.log('文件不存在：' + file); process.exit(0); }

// ★ 按 latin1 逐字节读：产物里的中文是 \ddd 字节转义，必须逐字节处理
const src = fs.readFileSync(file, 'latin1');

// 只看**字符串字面量**（注释不进游戏画面，无所谓；代码区的中文注释也被 strip 过）
function stringLiterals(s) {
  const out = [];
  let i = 0, line = 1;
  const n = s.length;
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
        out.push({ text: s.slice(i, stop), line });
        i = stop;
        continue;
      }
    }
    if (c === '"' || c === "'") {
      const q = c; const start = i; i++;
      while (i < n) {
        const d = s[i];
        if (d === '\\') { i += 2; continue; }
        if (d === q) { i++; break; }
        if (d === '\n') { line++; i++; continue; }
        i++;
      }
      out.push({ text: s.slice(start, i), line });
      continue;
    }
    i++;
  }
  return out;
}

// 把 Lua 十进制转义 \229\164\169 还原成字符（我们的中文就是这么存的）
function decode(s) {
  // \ddd 还原成字节 → 再按 UTF-8 解释（这样中文才正确）
  const bytes = [];
  for (let i = 0; i < s.length; i++) {
    const m = /^\\(\d{1,3})/.exec(s.slice(i));
    if (m) { bytes.push(Number(m[1]) & 0xff); i += m[0].length - 1; continue; }
    const cp = s.codePointAt(i);
    if (cp < 128) { bytes.push(cp); i += 0; continue; }
    for (const b of Buffer.from(String.fromCodePoint(cp), 'utf8')) bytes.push(b);
    i += String.fromCodePoint(cp).length - 1;
  }
  return Buffer.from(bytes).toString('utf8');
}

const ok = cp =>
  (cp >= 0x20 && cp <= 0x7e) ||
  (cp >= 0x4e00 && cp <= 0x9fff) ||
  (cp >= 0x3000 && cp <= 0x303f) ||
  (cp >= 0xff00 && cp <= 0xffef) ||
  (cp >= 0x2190 && cp <= 0x25ff) ||
  (cp >= 0x2010 && cp <= 0x2027) ||
  cp === 0x09 || cp === 0x0a || cp === 0x0d ||
  cp === 0x00b7 || cp === 0x00d7;   // · 和 × 原神会用

const bad = new Map();
for (const { text, line } of stringLiterals(src)) {
  const decoded = decode(text);
  for (const ch of decoded) {
    const cp = ch.codePointAt(0);
    if (ok(cp)) continue;
    const key = ch;
    if (!bad.has(key)) bad.set(key, { cp, line, ctx: decoded.replace(/\n/g, ' ').slice(0, 60) });
  }
}

console.log(`${path.relative(ROOT, file)}  字符串字面量 ${stringLiterals(src).length} 处`);
if (!bad.size) { console.log('  ✓ 通过：所有会显示的文字都在字体白名单内'); process.exit(0); }
console.log(`  ✗ ${bad.size} 种字符可能显示不出来（真机上会变豆腐块/空白）：`);
for (const [ch, v] of [...bad.entries()].slice(0, 20)) {
  console.log(`    ${JSON.stringify(ch)}  U+${v.cp.toString(16).toUpperCase().padStart(4, '0')}  首次出现在第 ${v.line} 行   ${v.ctx}`);
}
process.exit(1);
