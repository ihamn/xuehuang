// gil-inspect.mjs —— 关卡存档（.gil）透视：里面到底存了什么
//
// 为什么需要它：`.gil` 是二进制，但里面**字符串是可读的**。真机排查时最费时间的不是写代码，
// 而是"不知道游戏里到底加载了什么"。这个工具把关键线索一次列清：
//   · 嵌入的 Lua 脚本（脚本是**存档时嵌进 .gil 的**，不是运行时从 external_lua_file 读的）
//   · 有没有 UI 控件（ClientUI*Control 各几个）—— 没有就说明那个容器不在这个关卡的运行时布局里
//   · 脚本里的 ASCII 版本标语（判断游戏跑的是哪一版，中文在日志里会乱码）
//   · 文件大小（对比：zuma 的关卡 269 KB / 只有一个脚本的雪皇关卡 34 KB）
//
// 用法：
//   node tools/gil-inspect.mjs                       # 自动找最新关卡
//   node tools/gil-inspect.mjs <路径.gil>
//   node tools/gil-inspect.mjs --raw                 # 额外把脚本源码落盘到 out/gil-script.lua

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const BEYOND = path.join(os.homedir(), 'AppData', 'LocalLow', 'miHoYo', '原神', 'BeyondLocal');
const wantRaw = process.argv.includes('--raw');

function findGils() {
  const out = [];
  if (!fs.existsSync(BEYOND)) return out;
  for (const uid of fs.readdirSync(BEYOND)) {
    const lr = path.join(BEYOND, uid, 'Beyond_Local_Save_Level');
    if (!fs.existsSync(lr)) continue;
    for (const lv of fs.readdirSync(lr)) {
      for (const f of fs.readdirSync(path.join(lr, lv))) {
        if (f.endsWith('.gil')) out.push({ uid, level: lv, file: path.join(lr, lv, f), mtime: fs.statSync(path.join(lr, lv, f)).mtimeMs });
      }
    }
  }
  return out.sort((a, b) => b.mtime - a.mtime);
}

const arg = process.argv[2] && !process.argv[2].startsWith('--') ? process.argv[2] : null;
const all = findGils();
const target = arg ? { file: path.resolve(arg), level: '?', uid: '?' } : all[0];
if (!target) { console.log('没找到 .gil（先在编辑器里保存一次关卡）'); process.exit(0); }

const buf = fs.readFileSync(target.file);
// 只保留可打印 ASCII，其余当分隔符（用来提字符串）
const ascii = buf.toString('latin1').replace(/[\x00-\x1f\x7f-\xff]/g, '\n');
const count = re => (ascii.match(re) || []).length;

console.log('='.repeat(72));
console.log(`关卡存档：${target.file}`);
console.log(`  大小 ${buf.length} 字节${!arg ? `  ·  UID ${target.uid} / 关卡 ${target.level}` : ''}`);
console.log('='.repeat(72));

console.log('\n【1】嵌入的 Lua 脚本');
const scripts = [...ascii.matchAll(/([A-Za-z0-9_\-.]+\.lua)/g)].map(m => m[1]);
console.log('  出现的脚本名：' + (scripts.length ? [...new Set(scripts)].join(', ') : '（没有）'));
const hasLuaBody = /function\s+On(Init|Start|Update)\s*\(/.test(ascii);
console.log('  有 On* 生命周期函数体：' + (hasLuaBody ? '有 ← 脚本确实嵌进存档了' : '没有'));
const builds = [...new Set([...ascii.matchAll(/xuehuang-hello[^\n]{0,40}/g)].map(m => m[0].trim()))];
console.log('  版本标语（ASCII 判据）：' + (builds.length ? builds.join(' | ') : '（没有）'));

console.log('\n【2】UI 控件（运行时到底有没有东西）');
const kinds = ['ClientUIContainerControl', 'ClientUIImageControl', 'ClientUITextBoxControl', 'ClientUICursorEventAreaControl', 'ClientUIRoot', 'ClientUIPrototype', 'HierarchyRoot'];
for (const k of kinds) console.log(`  ${k.padEnd(34)} ${count(new RegExp(k, 'g'))} 次`);
const layoutish = count(/Layout|layout|InterfaceLayout/g);
console.log(`  ${'Layout/layout 字样'.padEnd(34)} ${layoutish} 次`);

// 真机实测到的 ID：打印出来方便和日志核对（脚本本身不写死这些常量，靠扫描自动认）
console.log('\n【2b】真机实测 ID 一览（本项目 UID 190800866 / 关卡 1073741826，2026-09-26）');
console.log('  关卡目录 ID ......... 1073741826   （Beyond_Local_Save_Level 下的目录名）');
console.log('  图片控件模板索引 .... 1073741855   （脚本自动认出来的 img；不是素材号）');
console.log('  文本框控件模板索引 .. 1073741856');
console.log('  光标检测区模板索引 .. 1073741857');
console.log('  容器模板索引 ........ （无：挂载点就是客户端控件容器本身）');
console.log('  图片控件运行时 ID ... 2   （日志里的 ClientUIImageControl:2 那种 ":N"）');
console.log('  ⚠ 素材号（形如 100001）= 编辑器里那张图的编号，靠它运行时 SetImage；和"模板索引"是两套数字。');

console.log('\n【3】判据（照官方定义）');
if (count(/ClientUIImageControl/g) + count(/ClientUITextBoxControl/g) === 0) {
  console.log('  ⚠ 存档里**没有任何图片/文本框控件** → 这个关卡运行时没有客户端控件树。');
  console.log('    官方《客户端控件容器》：界面布局中不存在客户端控件容器时，所有客户端控件和挂载脚本无法正常运行。');
  console.log('    → 去【界面控件组管理 → 界面布局】，确认"客户端控件容器"在**界面布局**里（不是只在库里），');
  console.log('      并在它的详情里添加控件，再保存关卡。');
} else {
  console.log('  ✓ 存档里有客户端控件，配合日志里的 Roots / 子控件数继续看。');
}
console.log('  参考：zuma 的关卡 .gil 是 269095 字节（有完整控件池）；只有脚本没有控件的关卡约 34 KB。');

if (wantRaw) {
  const out = path.join(ROOT, 'out', 'gil-script.lua');
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, ascii.replace(/\n{2,}/g, '\n'));
  console.log(`\n（--raw：可打印文本已落盘到 ${path.relative(ROOT, out)}）`);
}
