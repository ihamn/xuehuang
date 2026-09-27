// backup-gil.mjs —— 改关卡/进游戏之前，先把关卡存档留一份
//   node tools/backup-gil.mjs           # 备份最新存档（带时间戳，最多留 20 份）
//   node tools/backup-gil.mjs --list    # 看有哪些备份
//
// 为什么要有它：关卡存档（.gil）是**唯一**装着关卡+脚本的东西，编辑器里手滑一次就没了。
// 我自己会跑它，用户不需要知道。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const BEYOND = path.join(os.homedir(), 'AppData', 'LocalLow', 'miHoYo', '原神', 'BeyondLocal');
const HIST = path.join(ROOT, 'dist', 'gil-history');
const KEEP = 20;

const gils = [];
if (fs.existsSync(BEYOND)) {
  for (const uid of fs.readdirSync(BEYOND)) {
    const lr = path.join(BEYOND, uid, 'Beyond_Local_Save_Level');
    if (!fs.existsSync(lr)) continue;
    for (const lv of fs.readdirSync(lr)) {
      for (const f of fs.readdirSync(path.join(lr, lv))) {
        if (!f.endsWith('.gil')) continue;
        const p = path.join(lr, lv, f);
        gils.push({ p, uid, lv, f, m: fs.statSync(p).mtimeMs, size: fs.statSync(p).size });
      }
    }
  }
}
gils.sort((a, b) => b.m - a.m);
if (!gils.length) { console.log('没找到关卡存档'); process.exit(0); }

if (process.argv.includes('--list')) {
  if (!fs.existsSync(HIST)) { console.log('还没有备份'); process.exit(0); }
  for (const f of fs.readdirSync(HIST).sort().reverse())
    console.log(`  ${f}  ${fs.statSync(path.join(HIST, f)).size} 字节`);
  process.exit(0);
}

fs.mkdirSync(HIST, { recursive: true });
const stamp = new Date().toISOString().slice(5, 16).replace(/[-:T]/g, '');
let n = 0;
for (const g of gils) {
  const dst = path.join(HIST, `${g.f.replace(/\.gil$/, '')}-${stamp}.gil`);
  fs.copyFileSync(g.p, dst);
  // 顺手留一份"最近一份"固定名，方便手动还原
  fs.copyFileSync(g.p, path.join(ROOT, 'dist', `${g.f}.bak`));
  console.log(`备份 ${g.f}（${g.size} 字节）→ ${path.relative(ROOT, dst)}`);
  n++;
}
const all = fs.readdirSync(HIST).sort();
for (const old of all.slice(0, Math.max(0, all.length - KEEP))) fs.unlinkSync(path.join(HIST, old));
console.log(n ? `共备份 ${n} 个；历史保留 ${Math.min(all.length, KEEP)} 份` : '没有可备份的存档');
