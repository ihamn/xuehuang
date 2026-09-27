// design-shot.mjs —— 给 preview/design 的设计稿出图（**输出路径固定**，不会乱丢文件）
//
//   node tools/design-shot.mjs              # 全部出图
//   node tools/design-shot.mjs 火            # 只出名字里含"火"的
//
// ★ 规则（2026-09-27 用户要求）：**最新稿永远叫固定名字，旧的进 archive/**。
//   所以这里写死了"源 html → 目标 png"，出图永远覆盖同一个文件、不产生 v2/v3 副本。
//
// ★★ 为什么要"一张一张地通过子进程出图"（踩过的坑）：
//   Edge headless 在 Windows 上**连续**调用（哪怕每次都换 --user-data-dir）会在第 3 次左右
//   直接把宿主 node 进程干掉（退出码 0xC0000409 = stack buffer overrun）。
//   单独跑任何一张都正常 ⇒ 不是稿子的问题，是"同步等待子进程"的链太深。
//   ⇒ 改成：每张图都用一个**全新的 node 子进程**去跑一次 Edge，出完即退。进程间彻底隔离。

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const ROOT = path.resolve(import.meta.dirname, '..');
const DIR = path.join(ROOT, 'preview', 'design');
// ★ 参数规则（踩过）：**不要用中文做命令行参数** —— Windows 上经 node 子进程传递会丢/乱码，
//   结果是"子进程没匹配到任何稿子、父进程还以为出了图"。改成传**数字索引**，跨进程绝对安全。
const argOne = process.argv.indexOf('--one');
const onlyIndex = argOne >= 0 ? Number(process.argv[argOne + 1]) : -1;
const filter = (process.argv[2] && !process.argv[2].startsWith('--')) ? process.argv[2] : '';

// 源 → 目标（同一目录、同名 PNG；尺寸按稿子内容给）
// still:true = 出图时带 #still（页面里的动画/火焰会定住一帧；无头截图跑无限动画会卡死）
const SHOTS = [
  { html: '形状-杯子.html',            w: 1240, h: 1180 },
  { html: '形状-炮筒.html',            w: 1300, h: 1500 },
  { html: '火-尺寸15x25与12x20.html',  w: 1000, h: 540, still: true },
  { html: '演出-工位动作.html',         w: 1240, h: 1180, still: true },
  { html: '界面-工位状态.html',         w: 1560, h: 1250 },
];

const EDGE = [
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
].find(p => fs.existsSync(p));
if (!EDGE) { console.log('找不到 Edge，无法出图'); process.exit(1); }

const fileUrl = p => 'file:///' + p.replace(/\\/g, '/').split('/').map(encodeURIComponent).join('/');

function shoot(s) {
  const src = path.join(DIR, s.html);
  if (!fs.existsSync(src)) { console.log(`  跳过（没有源）：${s.html}`); return false; }
  const out = path.join(DIR, s.html.replace(/\.html$/, '.png'));
  // ★ 覆盖前先把旧图归档（规则：最新叫固定名，旧的进 archive/）
  if (fs.existsSync(out)) {
    const arc = path.join(DIR, 'archive', '出图历史');
    fs.mkdirSync(arc, { recursive: true });
    const stamp = new Date(fs.statSync(out).mtimeMs).toISOString().slice(5, 16).replace(/[-:T]/g, '').replace(/(\d{4})(\d{2})/, '$1$2');
    fs.renameSync(out, path.join(arc, `${s.html.replace(/\.html$/, '')}-${stamp}.png`));
  }
  const tmp = path.join(ROOT, '.edge-tmp', String(Date.now()) + '-' + Math.floor(Math.random() * 1e6));
  fs.mkdirSync(tmp, { recursive: true });
  spawnSync(EDGE, [
    '--headless=new', '--disable-gpu', '--hide-scrollbars',
    '--no-first-run', '--no-default-browser-check',
    `--user-data-dir=${tmp}`,
    '--force-device-scale-factor=1',
    `--window-size=${s.w},${s.h}`,
    '--virtual-time-budget=3000',
    `--screenshot=${out}`,
    fileUrl(src) + (s.still ? '#still' : ''),
  ], { stdio: ['ignore', 'ignore', 'ignore'], timeout: 60000 });
  fs.rmSync(tmp, { recursive: true, force: true });
  const ok = fs.existsSync(out);
  console.log(`  ${ok ? '✓' : '✗'} ${s.html.padEnd(20)} → ${path.basename(out)}${ok ? `  ${(fs.statSync(out).size / 1024).toFixed(0)} KB` : '（失败）'}`);
  return ok;
}

const targets = SHOTS.filter(s => !filter || s.html.includes(filter));

// 单张模式：只出第 onlyIndex 张（被父进程用索引调用）
if (onlyIndex >= 0) {
  const s = SHOTS[onlyIndex];
  if (!s) { console.log('  索引越界：' + onlyIndex); process.exit(1); }
  process.exit(shoot(s) ? 0 : 1);
}

// 多张模式：**每张交给一个新的 node 子进程**（隔离，避免连续调用 Edge 崩宿主）
let done = 0;
for (const s of targets) {
  const idx = SHOTS.indexOf(s);
  spawnSync(process.execPath, [import.meta.filename, '--one', String(idx)],
    { stdio: ['ignore', 'inherit', 'ignore'], timeout: 120000 });
  const out = path.join(DIR, s.html.replace(/\.html$/, '.png'));
  if (fs.existsSync(out)) done++;
  else console.log(`  ✗ ${s.html}（子进程没出图）`);
}
console.log(`\n共出图 ${done} / ${targets.length} 张（输出路径固定，不会有 v2/v3 副本）`);
