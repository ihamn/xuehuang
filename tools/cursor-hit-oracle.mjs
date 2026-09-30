// cursor-hit-oracle.mjs —— 光标命中判据：**点每张卡的"可见中心"，必须命中它自己**
//
//   node tools/cursor-hit-oracle.mjs                 # 默认量 dist/xuehuang.lua
//   node tools/cursor-hit-oracle.mjs <bundle.lua>    # 量指定产物（源码先 --entry=xuehuang 合成）
//
// ★ 为什么要有它（2026-10-01）：原来的光标回归（tools/sim-cursor-click.mjs）只要
//   "点到某张卡有进展"就算过——而 2×2 工位里 y=0 的那两张（化学/萃茶）在任何
//   y 轴符号错误下都**镜像不变**，于是那一版判据一直绿，真机上"上面一排点不动"
//   却没人发现。**判据必须逐张卡要求"命中自己"**，而不是"随便哪张有反应"。
//
// ★ 负对照（必须能红，否则这个判据没有价值）：
//     node tools/cursor-hit-oracle.mjs dist/xuehuang.lua
//   ⇒ 该产物是 2026-10-01 之前的写法（IN.hit 里 y 被镜像），上面一排 + 打包台应当 **红**。
//   红了**不许改判据**，先查坐标系（真机口径：光标 API 与控件 anchoredPosition 同为
//   画布中心为原点、y 向上 → 只平移、不翻符号）。
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { SIM_ROOT as SIM } from './sim-root.mjs';

const ROOT = path.resolve(import.meta.dirname, '..');
const W = 1815, H = 900;                                   // 真机画布
const BUNDLE = path.resolve(ROOT, process.argv[2] || 'dist/xuehuang.lua');
if (!fs.existsSync(BUNDLE)) { console.log('找不到产物：' + BUNDLE + '（先用 tools/lua-test.mjs --entry=xuehuang 合成）'); process.exit(0); }

const { createRuntime } = await import(pathToFileURL(path.join(SIM, 'client/lua-runtime/src/index.js')).href);
const rt = createRuntime({ canvasWidth: W, canvasHeight: H });
const root = rt.addRoot({ name: 'C', kind: 'container' });
root.SetActive(true);
for (const [i, k] of [[1, 'image'], [2, 'textbox'], [3, 'cursor'], [4, 'container']]) rt.registerTemplate(i, { kind: k });
rt.mountScript({ path: 'main', source: fs.readFileSync(BUNDLE, 'utf8'), control: root, params: {} });

const byName = (c, n) => { if (c.name === n) return c; for (const k of (c.children || [])) { const r = byName(k, n); if (r) return r; } return null; };
const findArea = (c) => { if (String(c.typeofName || '').includes('CursorEvent')) return c; for (const k of (c.children || [])) { const r = findArea(k); if (r) return r; } return null; };

// 命中结果解析：新产物打 [CLICK] raw=.. canvas=.. hit=..；旧产物打「鼠标点击 (x,y) → 命中 X」
function parseHit(logs) {
  const texts = logs.map(l => l.text);
  const modern = texts.filter(t => t.includes('[CLICK]')).pop();
  if (modern) { const m = modern.match(/hit=(\S+)/); return { hit: m ? m[1] : '?', line: modern }; }
  const legacy = texts.filter(t => t.includes('命中')).pop();
  if (legacy) { const m = legacy.match(/命中\s*(\S+)/); return { hit: m ? m[1] : '?', line: legacy }; }
  return { hit: '?', line: '(没有点击日志)' };
}

for (let f = 0; f < 5; f++) rt.step(1 / 30);
const A = findArea(root);
if (!A) { console.log('✗ 控件树里没有「光标检测区域」→ 鼠标点击不可用'); process.exit(1); }

// 菜单：点屏幕开门营业（原版语义），再跑一会儿让小票发出来
rt.injectCursor(A, 'CursorClick', { x: W / 2, y: H / 2 });
for (let f = 0; f < 150; f++) rt.step(1 / 30);

const CASES = [
  ['St_shake_box', 'shake', '捣锤区'],
  ['St_fire_box', 'fire', '火系区'],
  ['St_chem_box', 'chem', '化学区'],
  ['St_brew_box', 'brew', '萃茶区'],
  ['Pk_box', 'pack', '打包台'],
];

console.log(`光标命中判据 · ${path.relative(ROOT, BUNDLE)} · 画布 ${W}x${H}`);
let pass = 0, fail = 0;
for (const [name, expect, label] of CASES) {
  const c = byName(root, name);
  if (!c) { console.log(`  ✗ ${label}：控件 ${name} 不存在`); fail++; continue; }
  const marks = rt.logs.length;
  rt.injectCursor(A, 'CursorClick', { x: W / 2 + (c.anchoredPositionX || 0), y: H / 2 + (c.anchoredPositionY || 0) });
  for (let f = 0; f < 3; f++) rt.step(1 / 30);
  const { hit, line } = parseHit(rt.logs.slice(marks));
  const ok = hit === expect;
  ok ? pass++ : fail++;
  console.log(`  ${ok ? '✓' : '✗'} ${label}（${name}）期望 ${expect} / 实际 ${hit}`);
  if (!ok) console.log(`      ${line}`);
}
console.log(`\n结果：passed ${pass} / failed ${fail}`);
if (fail) console.log('★ 判据红了：先查坐标系（光标 API 与控件 anchoredPosition 是否同一套 y 口径），不要改判据。');
process.exit(fail ? 1 : 0);
