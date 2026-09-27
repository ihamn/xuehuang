// lua-check.mjs —— 给 Lua 源文件做**词法检查**（不需要装 Lua 解释器）
//   node tools/lua-check.mjs lua/src/hello.lua
//   node tools/lua-check.mjs --gil dist/1073741826.gil.bak      # 检查关卡存档里"嵌进去的那份脚本"
//   node tools/lua-check.mjs --all                              # 全部 lua/src/*.lua
//
// ★ 为什么不是完整的语法检查：真机的 Lua 是**逐字节**读源码的，而中文注释的字节里会出现
//   引号/反斜杠之类的字节，通过模拟器（Fengari）加载时会被误判成语法错误 —— 那些是假警报。
//   所以这里只做**词法检查**：字符串是否闭合、长括号是否配对、注释块是否闭合。
//   它能抓到的正是最要命的一类错误：**转义写错导致整个脚本编译失败**（比如我曾在拼接注释时
//   把 `\n` 弄丢，结果 `-- 注释` 把下一行代码吞掉，真机上就是整份脚本编译不过）。
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');

function lexCheck(name, src) {
  const problems = [];
  let i = 0, line = 1;
  const n = src.length;
  const at = () => `第 ${line} 行`;
  while (i < n) {
    const c = src[i];
    if (c === '\n') { line++; i++; continue; }
    // 长括号 [[ ... ]] / [=[ ... ]=]（字符串或注释块）
    if (c === '[') {
      const m = /^\[(=*)\[/.exec(src.slice(i));
      if (m) {
        const close = ']' + m[1] + ']';
        const start = i + m[0].length;
        const end = src.indexOf(close, start);
        if (end < 0) { problems.push(`${at()} 长括号 ${m[0]} 没有闭合（缺 ${close}）`); break; }
        line += (src.slice(i, end).match(/\n/g) || []).length;
        i = end + close.length;
        continue;
      }
    }
    // 注释
    if (c === '-' && src[i + 1] === '-') {
      const m = /^--\[(=*)\[/.exec(src.slice(i));
      if (m) {
        const close = ']' + m[1] + ']';
        const start = i + m[0].length;
        const end = src.indexOf(close, start);
        if (end < 0) { problems.push(`${at()} 块注释 --${m[0]} 没有闭合（缺 ${close}）`); break; }
        line += (src.slice(i, end).match(/\n/g) || []).length;
        i = end + close.length;
        continue;
      }
      const nl = src.indexOf('\n', i);
      i = nl < 0 ? n : nl;
      continue;
    }
    // 字符串
    if (c === '"' || c === "'") {
      const q = c; const startLine = line;
      i++;
      let closed = false;
      while (i < n) {
        if (src[i] === '\\') { i += 2; continue; }
        if (src[i] === '\n') { problems.push(`第 ${startLine} 行 字符串没有闭合（用 ${q} 开头，换行前没结束）`); break; }
        if (src[i] === q) { closed = true; i++; break; }
        i++;
      }
      if (!closed) { if (!problems.some(p => p.includes(`第 ${startLine} 行`))) problems.push(`第 ${startLine} 行 字符串没有闭合`); break; }
      continue;
    }
    i++;
  }
  // 额外的硬检查**只对入口文件**做：模块文件（被 require 的那种）本来就没有生命周期函数，
  // 对它们报"缺少 OnInit"是假警报（我第一版就这么误报过 6 次）。
  // 入口文件必须显式标记 `-- @entry`（别用模糊启发式：game.lua 注释里写了“入口”就被误判过）
  const isEntry = /^--\s*@entry/m.test(src);
  if (isEntry) {
    for (const need of ['function OnInit', 'function OnStart', 'function OnUpdate']) {
      if (!src.includes(need)) problems.push(`缺少 ${need}（真机按固定名字查生命周期）`);
    }
    if (!/return\s*\{[^}]*OnInit/.test(src)) problems.push('结尾缺少 `return { OnInit = ... }`（打包/单文件上传需要）');
  }
  return problems;
}

function report(label, src) {
  const lines = src.split('\n').length;
  const bytes = Buffer.byteLength(src, 'utf8');
  const problems = lexCheck(label, src);
  console.log(`${label}  ${bytes} 字节 / ${lines} 行`);
  if (!problems.length) { console.log('  ✓ 词法检查通过'); return 0; }
  for (const p of problems) console.log('  ✗ ' + p);
  return 1;
}

const argv = process.argv.slice(2);
if (argv[0] === '--gil') {
  const gil = path.resolve(ROOT, argv[1] || 'dist/1073741826.gil.bak');
  const raw = fs.readFileSync(gil).toString('latin1');
  const start = raw.indexOf('-- hello.lua');
  const endMark = 'function OnDestroy() end';
  const end = raw.lastIndexOf(endMark);
  if (start < 0 || end < 0) { console.log('存档里没找到脚本体'); process.exit(1); }
  const src = raw.slice(start, end + endMark.length);
  console.log(`存档：${path.basename(gil)}`);
  const bad = report('  存档内嵌脚本', src);
  for (const k of ['xuehuang-hello', 'IMG_VERIFY_DONE', 'Enum.ImageSource', '控件[']) {
    console.log(`    ${k} : ${src.split(k).length - 1} 次`);
  }
  process.exit(bad);
}
if (argv[0] === '--all') {
  const dir = path.join(ROOT, 'lua', 'src');
  let bad = 0;
  for (const f of fs.readdirSync(dir).filter(x => x.endsWith('.lua'))) {
    bad += report('lua/src/' + f, fs.readFileSync(path.join(dir, f), 'utf8')) ? 1 : 0;
  }
  process.exit(bad ? 1 : 0);
}
const f = path.resolve(ROOT, argv[0] || 'lua/src/hello.lua');
process.exit(report(path.relative(ROOT, f), fs.readFileSync(f, 'utf8')) ? 1 : 0);
