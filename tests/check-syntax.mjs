// 内嵌脚本自检：把 <script> 抠出来做语法检查（浏览器里出语法错会整页白屏，所以这一步必须有）。
//   node tests/check-syntax.mjs
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const ROOT = path.resolve(import.meta.dirname, '..');
const html = fs.readFileSync(path.join(ROOT, '雪皇的后厨.html'), 'utf8');
const i = html.indexOf('<script>'), j = html.lastIndexOf('</script>');
if (i < 0 || j < 0) { console.error('✗ 找不到 <script> 块'); process.exit(1); }
const js = html.slice(i + 8, j);
const tmp = path.join(ROOT, 'tests', '.game.tmp.js');
fs.writeFileSync(tmp, js);
try {
  execFileSync(process.execPath, ['--check', tmp], { stdio: 'pipe' });
  console.log(`内嵌脚本语法检查：通过（${js.length} 字符）`);
} catch (e) {
  console.error('✗ 语法错误：\n' + (e.stderr ? e.stderr.toString() : e.message));
  process.exit(1);
} finally {
  fs.rmSync(tmp, { force: true });
}
