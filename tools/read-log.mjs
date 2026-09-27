import fs from 'node:fs';
const dir = 'C:/Users/netease/AppData/LocalLow/miHoYo/原神/BeyondLocal/190800866/Beyond_Debug_Log';
const files = fs.readdirSync(dir).filter(f => f.endsWith('.gia')).sort().reverse().slice(0, 3);
console.log('读 ' + files.length + ' 个日志\n');
for (const f of files) {
  const raw = fs.readFileSync(dir + '/' + f);
  const txt = raw.toString('utf8');
  // 抽出所有形如 [模块] 内容 的片段
  const hits = [...txt.matchAll(/\[(host|input|view|雪皇|雪皇[^\]]*)\]([^\x00-\x08\x0b\x0c\x0e-\x1f]{0,150})/g)].map(m => ('[' + m[1] + ']' + m[2]).replace(/\s+/g, ' ').trim());
  console.log('══════ ' + f + '  (' + hits.length + ' 条) ══════');
  for (const h of hits.slice(0, 60)) console.log('  ' + h.slice(0, 170));
  console.log('');
}
