// check-level-script.mjs —— 验收"编辑器里的关卡到底存了哪一版脚本"
//
// 为什么需要：踩过两次的机制 —— 编辑器里的脚本是**内存里的一份副本**，
//   把 .lua 放上磁盘 ≠ 改到编辑器那份；**"保存关卡"也不会自动重读磁盘文件**。
//   所以"我改了文件"和"游戏里跑的是新版"是两件事，必须能一眼查出来。
//   本工具直接读关卡存档（.gil），检查里面嵌的脚本带哪个版本标语。
//
// 用法：
//   node tools/check-level-script.mjs                 # 检查所有关卡
//   node tools/check-level-script.mjs 1073741825      # 只查某个关卡
//
// 判据（ASCII，不怕中文乱码）：
//   期望看到 BUILD 标语 = xuehuang-r2-dbg，且找得到新功能标记（forwardSlip / [KTARGET]）
//   如果还是 d2 / core / hello ⇒ 编辑器里那份副本没更新 ⇒ 去"重新导入脚本"

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const BEYOND = path.join(os.homedir(), 'AppData', 'LocalLow', 'miHoYo', '原神', 'BeyondLocal');
const only = process.argv[2] || null;

// 版本标语清单（新的排前面）+ 新版才有的功能标记
// ★ 必须带 "BUILD" 前缀判断：`xuehuang-core` 这个串在 host.lua 的日志文案里也出现，
//   直接 includes() 会把新版误判成 core（我这个工具第一版就踩了这个坑）。
const BUILD_RE = /xuehuang-(r\d[-\w]*|d2|core|hello)/g;
const MARKERS = ['xuehuang-r3', 'xuehuang-r2-dbg', 'xuehuang-r2', 'xuehuang-r1', 'xuehuang-d2', 'xuehuang-core', 'xuehuang-hello'];
// 真正的版本标语：只认 `BUILD = '...'` / `BUILD=...` 这种上下文
function buildTags(text) {
  return [...new Set([...text.matchAll(/BUILD\s*=\s*'?(xuehuang-[-\w]+)/g)].map(m => m[1]))];
}
function anyBuildTag(text) {
  const t = buildTags(text);
  return t.length ? t : ['（没有 BUILD 标语）'];
}
const FEATURES = [
  ['forwardSlip', '点小票=立刻送工位（r1）'],
  ['[KTARGET]', '按键探针（r2）'],
  ['wipGateCount', '名额硬上界（r1 修的 bug）'],
  ['__IN_ACT', '键回调直呼（d2 就有）'],
  ["pack2", '出餐备用键 Z（r3）'],
];
const EXPECT = 'xuehuang-r3';
const DISK = ['dist/xuehuang.lua', 'out/xuehuang.lua'].map(p => path.join(path.resolve(import.meta.dirname, '..'), p));

function levels() {
  const out = [];
  if (!fs.existsSync(BEYOND)) return out;
  for (const uid of fs.readdirSync(BEYOND)) {
    const lr = path.join(BEYOND, uid, 'Beyond_Local_Save_Level');
    if (!fs.existsSync(lr)) continue;
    for (const lv of fs.readdirSync(lr)) {
      if (only && lv !== only) continue;
      const gil = path.join(lr, lv, lv + '.gil');
      const luaDir = path.join(lr, lv, 'external_lua_file');
      if (fs.existsSync(gil)) out.push({ uid, lv, gil, luaDir });
    }
  }
  return out;
}

console.log('— 磁盘上的脚本（我要部署的就是它）—');
for (const p of DISK) {
  if (!fs.existsSync(p)) { console.log(`  （没有）${path.relative(process.cwd(), p)}`); continue; }
  const t = fs.readFileSync(p, 'latin1');
  const stat = fs.statSync(p);
  console.log(`  ${path.relative(process.cwd(), p).padEnd(24)} ${String(stat.size).padStart(8)} 字节  ${new Date(stat.mtimeMs).toLocaleString()}  标语=${anyBuildTag(t).join(' , ')}`);
}

const ls = levels();
if (!ls.length) { console.log('\n没找到关卡存档（先在编辑器里打开/保存一次关卡）'); process.exit(0); }

console.log('\n— 关卡存档里嵌的脚本（游戏真正跑的那一份）—');
let bad = 0;
for (const L of ls) {
  const t = fs.readFileSync(L.gil, 'latin1');
  const tags = buildTags(t);
  const feats = FEATURES.map(([k, label]) => `${k}=${t.includes(k) ? '有' : '无'}（${label}）`);
  const ok = tags.includes(EXPECT);
  if (!ok) bad++;
  console.log(`\n  关卡 ${L.lv}（UID ${L.uid}）  ${new Date(fs.statSync(L.gil).mtimeMs).toLocaleString()}  ${fs.statSync(L.gil).size} 字节`);
  console.log(`    版本标语: ${tags.length ? tags.join(' , ') : '（没找到 BUILD 标语）'}`);
  for (const f of feats) console.log(`    ${f}`);
  console.log(`    判定: ${ok ? `✓ 是新版（${EXPECT}）` : `✗ 不是 ${EXPECT} —— 编辑器里那份副本没更新，要去"重新导入脚本"`}`);
  // 磁盘副本对一下
  const dst = path.join(L.luaDir, 'xuehuang.lua');
  if (fs.existsSync(dst)) {
    const dt = fs.readFileSync(dst, 'latin1');
    console.log(`    磁盘副本 external_lua_file/xuehuang.lua: ${fs.statSync(dst).size} 字节  标语=${anyBuildTag(dt).join(' , ')}`);
  } else {
    console.log(`    磁盘副本: 没有（${path.relative(process.cwd(), L.luaDir)}）`);
  }
}

console.log('\n────────────────────────────────────────────');
if (bad) {
  console.log(`结论：${bad} 个关卡里还不是 ${EXPECT}。请到编辑器里【重新导入脚本】再【保存关卡】，`);
  console.log('      然后重跑本命令确认变成新版再进关卡（顺序不要颠倒）。');
} else {
  console.log(`结论：关卡里已是 ${EXPECT}，可以进关卡了。`);
  console.log('      进去后：点屏幕开门 → 按 Y/H/K/P 做工位 → 有一杯全绿时按【空格】或【Z】出餐。');
}
