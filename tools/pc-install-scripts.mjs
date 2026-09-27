// pc-install-scripts.mjs —— 把 Lua 脚本直接放进千星沙箱的关卡存档目录（external_lua_file）
//
// 为什么要有它：编辑器里"选择与脚本映射关联的本地文件"那个对话框会报
//   「不允许访问 C:\Users\<user>\AppData\LocalLow\miHoYo\原神\BeyondLocal\<UID>\Beyond_Local_Save_Level\<关卡ID>\external_lua_file」
//   但**那个目录本身是可写的**（zuma 项目实测能读能列能写）—— 报错的是对话框，不是权限。
//   所以干脆绕过对话框，直接把文件放进去；编辑器里再建映射时就能看到它们。
//
// ⚠️ 云电脑重置会清空这个目录（脚本没了）→ 回来重跑这一条即可。
// ⚠️ 换了脚本还要**重新确认映射 + 重进关卡**（映射关系只能人在编辑器里点）。
//
// 用法：
//   node tools/pc-install-scripts.mjs                 # 放进找到的所有关卡目录
//   node tools/pc-install-scripts.mjs --dry           # 只看会放哪儿，不写
//   node tools/pc-install-scripts.mjs --level=1073741826
//   node tools/pc-install-scripts.mjs --file=lua/src/hello.lua   # 只放指定脚本
//
// 默认放：lua/src/hello.lua（最小验证脚本）+ 若存在 dist/xuehuang.lua（打包产物）也一起放。

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const dry = args.includes('--dry');
const onlyLevel = (args.find(a => a.startsWith('--level=')) || '').slice(8) || null;
const onlyFile = (args.find(a => a.startsWith('--file=')) || '').slice(7) || null;

// 默认投放清单（源文件 → 落地的文件名）
const FILES = onlyFile
  ? [{ name: path.basename(onlyFile), src: path.resolve(ROOT, onlyFile) }]
  : [
      { name: 'hello.lua', src: path.join(ROOT, 'lua', 'src', 'hello.lua') },
      { name: 'xuehuang.lua', src: path.join(ROOT, 'out', 'xuehuang.lua'), optional: true },
    ];

const BEYOND = path.join(os.homedir(), 'AppData', 'LocalLow', 'miHoYo', '原神', 'BeyondLocal');

/** 找 <BeyondLocal>/<UID>/Beyond_Local_Save_Level/<关卡ID>/external_lua_file */
function findTargets() {
  const out = [];
  if (!fs.existsSync(BEYOND)) return out;
  for (const uid of fs.readdirSync(BEYOND)) {
    const levelRoot = path.join(BEYOND, uid, 'Beyond_Local_Save_Level');
    if (!fs.existsSync(levelRoot)) continue;
    for (const level of fs.readdirSync(levelRoot)) {
      if (onlyLevel && level !== onlyLevel) continue;
      const dir = path.join(levelRoot, level, 'external_lua_file');
      if (fs.existsSync(dir)) out.push({ uid, level, dir });
    }
  }
  return out;
}

const sha = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const todo = FILES.filter(f => {
  if (fs.existsSync(f.src)) return true;
  if (!f.optional) throw new Error('源文件不存在：' + f.src);
  return false;                      // optional 且不存在 → 跳过
});

const targets = findTargets();
if (!targets.length) {
  console.log('没找到 external_lua_file 目录：' + BEYOND);
  console.log('  → 说明这台机器上还没进过千星沙箱的关卡（先在编辑器里打开一次关卡，目录就会建出来）');
  process.exit(0);
}

console.log(`目标目录 ${targets.length} 个：`);
for (const t of targets) {
  console.log(`  UID ${t.uid} / 关卡 ${t.level}`);
  console.log(`    ${t.dir}`);
  for (const f of todo) {
    const dst = path.join(t.dir, f.name);
    const before = fs.existsSync(dst) ? sha(dst) : null;
    if (!dry) fs.copyFileSync(f.src, dst);
    const after = sha(f.src);
    const mark = before === null ? '新增' : (before === after ? '内容相同（没变）' : '已更新');
    console.log(`    ${dry ? '将放' : '已放'} ${f.name}  ${fs.statSync(f.src).size} 字节  sha256=${after.slice(0, 16)}…  ${mark}`);
  }
}
console.log('');
console.log(dry ? '（--dry：什么都没写）' : '完成。');
console.log('⚠️ 接下来必须在编辑器里做的事（工具替代不了）：');
console.log('   1) 把这个 lua 建/确认到"脚本映射"上（映射关系只能人在编辑器里点）');
console.log('   2) 脚本必须挂在**客户端控件**上（挂主屏会报"找不到挂载控件"）');
console.log('   3) 脚本变量填模板索引：imgPrefab=1 textPrefab=2 cursorPrefab=3 panelPrefab=4');
console.log('   4) 换过脚本后要**重进关卡**才生效');
console.log('   5) 进关卡后看日志里的 ASCII 版本标语（搜 "BUILD=xuehuang"）确认跑的是哪一版');
