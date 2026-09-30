// fire-port.mjs —— 火焰算法（网页版）的微量测试
//
//   node tests/fire-port.mjs
//
// 背景：火焰的"数字来源"是 lua/src/props.lua 的 P.spec.fire + P.fire；
//   网页版是为了**快速看效果**把它照搬成 JS。既然是照搬，就必须能验：
//   ① 取值域：热量只能落在 1..25（调色板只有 25 级，越界会画出黑块）
//   ② 火源：最底 3 行（SOURCE_ROWS）在"喷火"时必须是满热
//   ③ 包络：越往上越窄（三角形），顶行基本是暗的 —— 这是它像火而不像柱子的原因
//   ④ 传播：跑若干帧后，火要**往上长**（中段变亮），不能原地不动
import fs from 'node:fs';
import path from 'node:path';
import { loadPage } from './_fakedom.mjs';

const ROOT = path.resolve(import.meta.dirname, '..');
const html = fs.readFileSync(path.join(ROOT, 'preview', '手机按键-微量测试.html'), 'utf8');
const env = loadPage(html);

let bad = 0;
const chk = (ok, msg) => { console.log(`  ${ok ? '✓' : '✗'} ${msg}`); if (!ok) bad++; };

const F = env.ctx.VKFIRE, STEP = env.ctx.VKFIRE_STEP, SET = env.ctx.VKFIRE_SET_FIRING;
console.log('火焰算法 · 微量测试');
chk(!!F && !!STEP && !!SET, '测试缝可用（VKFIRE / VKFIRE_STEP）');
if (!F || !STEP) { console.log('\n微量测试：无法继续'); process.exit(2); }

chk(F.cols === 16 && F.rows === 27, `网格 16×27（实际 ${F.cols}×${F.rows}）`);
chk(F.heat.length === 16 * 27, `热量表长度 = ${16 * 27}`);

SET(true);
for (let i = 0; i < 40; i++) STEP();

// ① 取值域
let lo = Infinity, hi = -Infinity;
for (const v of F.heat) { if (v < lo) lo = v; if (v > hi) hi = v; }
chk(lo >= 1 && hi <= 25, `热量取值域 1..25（实际 ${lo}..${hi}）`);

const at = (c, r) => F.heat[(r - 1) * F.cols + c];   // 取某格热量

// ② 火源：底部几行必须够热（★ 不能断言"恒为 25"：每帧 seed 之后，上面一行会传播下来
//    覆盖它 —— 这是 DOOM 火焰的固有行为。要验的是"火源在管事"，不是"数值不被覆盖"。）
// ★ 只看**包络之内**的格子：源行的两个角本来就在三角形之外（r=25 行只覆盖 0.06~14.94 列），
//   那里恒为 1 是对的 —— 我第一版没按包络取格，误报"火源没管事"。
const halfAt = (r) => { const t = (F.rows - r) / Math.max(1, F.rows - 1); return Math.max(0.5, Math.floor(F.cols / 2) * Math.pow(1 - t, 0.9)); };
const inEnv = (c, r) => Math.abs(c - (F.cols - 1) / 2) <= halfAt(r);
let srcMin = 99, srcN = 0;
for (let r = F.rows - 2; r <= F.rows; r++)
  for (let c = 0; c < F.cols; c++) if (inEnv(c, r)) { srcN++; if (at(c, r) < srcMin) srcMin = at(c, r); }
chk(srcMin >= 18, `包络内的源行都足够热（${srcN} 格，最小值 ${srcMin} ≥ 18）`);

// ③ 包络：逐行数"亮格（>5）"，自下而上应当收窄
const lit = [];
for (let r = 1; r <= F.rows; r++) { let n = 0; for (let c = 0; c < F.cols; c++) if (at(c, r) > 5) n++; lit.push(n); }   // lit[0]=顶
const topLit = lit[0] + lit[1];
const midLit = lit[Math.floor(F.rows / 2)];
const botLit = lit[F.rows - 2] + lit[F.rows - 1];
chk(topLit <= 4, `顶部基本是暗的（最上两行亮格 ${topLit}）`);
chk(botLit > midLit, `底部比中段宽（底两行 ${botLit} > 中段单行 ${midLit}）`);
let shrinkOk = true;
for (let r = F.rows - 3; r >= 3; r--) if (lit[r] > lit[r + 1] + 2) shrinkOk = false;   // 允许随机抖动，但不许"倒长"
chk(shrinkOk, '自下而上单调收窄（三角形包络，允许 ±2 抖动）');

// ④ 传播：中段应该被点亮过（不是只有底部亮）
let midBright = 0;
for (let c = 0; c < F.cols; c++) if (at(c, Math.floor(F.rows / 2)) > 5) midBright++;
chk(midBright > 0, `火确实往上长了（中段亮格 ${midBright}）`);

// ⑤ 开火 vs 收火：★ 两边都必须"先跑够帧再测"——我第一版 SET(true) 后没推进就测量，
//    等于把同一个状态测了两次（31 vs 31 假失败）。
const sumHeat = () => { let s = 0; for (const v of F.heat) s += v; return s; };
SET(false);
for (let i = 0; i < 90; i++) STEP();
const sumIdle = sumHeat();
SET(true);
for (let i = 0; i < 30; i++) STEP();
const sumOn = sumHeat();
console.log(`    [对照] 总热量：收火 ${sumIdle} / 开火 ${sumOn}（满格基准 ${16 * 27 * 25}）`);
chk(sumOn > sumIdle * 3, `开火比收火旺得多（收火 ${sumIdle} → 开火 ${sumOn}，高 ${Math.round((sumOn / sumIdle - 1) * 100)}%）——火焰开/关在算法上差别明显（"按一下保持"靠这个才看得出来）`);

console.log(bad ? `\n微量测试：${bad} 项失败` : '\n微量测试：全部通过 ✓');
process.exit(bad ? 1 : 0);
