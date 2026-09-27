import fs from 'node:fs';
const dir = 'C:/Users/netease/AppData/LocalLow/miHoYo/原神/BeyondLocal/190800866/Beyond_Debug_Log';
const files = fs.readdirSync(dir).filter(x => x.endsWith('.gia')).sort().reverse().slice(0, 2);
for (const f of files) {
  const txt = fs.readFileSync(dir + '/' + f).toString('utf8');
  const hits = [...txt.matchAll(/\[(host|input|view|雪皇)\]([^\x00-\x08\x0b\x0c\x0e-\x1f]{0,160})/g)]
    .map(m => ('[' + m[1] + ']' + m[2]).replace(/\s+/g, ' ').trim());
  const byKey = {};
  for (const h of hits) { const m = h.match(/^\[input\] 按键 (\S+) → (.+)$/); if (m) { const k = m[1] + ' | ' + m[2].slice(0, 22); byKey[k] = (byKey[k] || 0) + 1; } }
  console.log('══ ' + f + '  (' + hits.length + ' 条) ══');
  console.log('  按键统计:');
  for (const [k, n] of Object.entries(byKey).sort((a, b) => b[1] - a[1])) console.log('    ×' + String(n).padStart(3) + '  ' + k);
  console.log('  关键行:');
  const seen = new Set();
  for (const h of hits) { if (/按键 /.test(h)) continue; if (seen.has(h)) continue; seen.add(h); console.log('    ' + h.slice(0, 150)); }
  console.log('');
}
