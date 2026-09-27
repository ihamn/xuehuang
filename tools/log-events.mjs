// log-events.mjs —— 把真机日志按**发生顺序**读出来（含 r2 的按键探针）
//
//   node tools/log-events.mjs                  # 读最新的日志
//   node tools/log-events.mjs --n=2            # 读最新 2 份
//   node tools/log-events.mjs --file=xxx.gia   # 指定文件
//   node tools/log-events.mjs --grep=KDOWN     # 只显示含某串的行
//
// 为什么重写 read-log.mjs：那份只认 [host]/[input]/[view]/[雪皇] 四个标签，
// 而 r2 的判据是 [KTARGET]/[KDOWN]/[KUP]，会被漏掉（排查时最怕这个）。

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const DIR = path.join(os.homedir(), 'AppData', 'LocalLow', 'miHoYo', '原神', 'BeyondLocal', '190800866', 'Beyond_Debug_Log');
const argOf = (n, d) => { const h = process.argv.find(a => a.startsWith('--' + n + '=')); return h ? h.slice(n.length + 3) : d; };
const N = Number(argOf('n', 1));
const FILE = argOf('file', '');
const GREP = argOf('grep', '');

if (!fs.existsSync(DIR)) { console.log('没有日志目录：' + DIR); process.exit(0); }
const files = FILE
  ? [FILE]
  : fs.readdirSync(DIR).filter(f => f.endsWith('.gia')).sort().reverse().slice(0, N);

for (const f of files) {
  const full = path.isAbsolute(f) ? f : path.join(DIR, f);
  if (!fs.existsSync(full)) { console.log('没有这个日志：' + full); continue; }
  const buf = fs.readFileSync(full);
  const txt = buf.toString('utf8');

  // 标签清单：老四样 + r2 探针 + 常用 ASCII 探针
  const TAGS = ['KTARGET', 'KDOWN', 'KUP', 'host', 'input', 'view', '雪皇', 'bind', 'act', 'key',
    'LOGIC', 'REJECT', 'ARRIVE', 'SLIP', 'CAP', 'STATE'];
  const re = new RegExp('\\[(' + TAGS.join('|') + ')(?:\\s[^\\]]*)?\\]([^\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f]{0,160})', 'g');
  let hits = [...txt.matchAll(re)].map(m => ('[' + m[1] + ']' + m[2]).replace(/\s+/g, ' ').trim());
  if (GREP) hits = hits.filter(h => h.includes(GREP));

  console.log('══════ ' + path.basename(full) + '  ' + new Date(fs.statSync(full).mtimeMs).toLocaleString()
    + '  ' + buf.length + ' 字节  ' + hits.length + ' 条 ══════');
  for (const h of hits) console.log('  ' + h);
  console.log('');
}
