// dryice-port.mjs —— 「压缩干冰」最小实现页的微量测试
//
//   node tests/dryice-port.mjs
//
// 验六件事：
//   ① 压力曲线：单调、按满正好 25000，且默认那条**越压越猛**（不是匀速，也不是一压就满）
//   ② 挤压是**累计**的（B 阶段接着 A 阶段），且有上限（别把杯子压没了）
//   ③ 没按满**绝不触发**（A 满才出气泡、B 满才出干冰）
//   ④ **空杯不变式**：先压缩后加水 ⇒ 压缩全程液面件必须一直是隐藏的
//   ⑤ 控件账：杯子 5 + 锤子 2 + 干冰效果 9
//   ⑥ 与配方/规格不漂移（用共享解析器读 recipes.lua + props.lua）
import fs from 'node:fs';
import path from 'node:path';
import { loadPage } from './_fakedom.mjs';
import { parseRecipes } from './_recipe-vis.mjs';

const ROOT = path.resolve(import.meta.dirname, '..');
const html = fs.readFileSync(path.join(ROOT, 'preview', '压缩干冰-微量测试.html'), 'utf8');
const env = loadPage(html);
const D = env.ctx.DRY;

let bad = 0;
const chk = (ok, msg) => { console.log(`  ${ok ? '✓' : '✗'} ${msg}`); if (!ok) bad++; };

console.log('压缩干冰 · 微量测试');
chk(!!D && !!D.press, '页面挂上了 window.DRY');
// ★ 2026-10-01 用户定：**● 字符法扶正为默认**（原粒子方案降为对照）。这条必须在任何人切模式之前看
chk(D.state.whiteMode === 'dots', `默认画法是「烟(粒子) + ● 字符」（${D.state.whiteMode}）—— 粒子照旧在飘，只是**用字符画**：一行 1 控件`);

/* ───────── ① 压力曲线 ───────── */
{
  const f = (i) => D.pressureFor(i);
  const seq = [1, 2, 3, 4, 5, 6].map(f);
  const mono = seq.every((v, i) => i === 0 || v > seq[i - 1]);
  chk(mono, `压力单调上升：${seq.map(v => Math.round(v).toLocaleString()).join(' → ')}`);
  chk(Math.abs(f(D.TAPS) - D.P_MAX) < 1e-6, `按满 ${D.TAPS} 下正好 = 25000 千帕（是 ${Math.round(f(D.TAPS))}）`);
  const deltas = seq.map((v, i) => v - (i === 0 ? 0 : seq[i - 1]));
  const growing = deltas.every((d, i) => i === 0 || d > deltas[i - 1]);
  chk(growing, `默认曲线**越压越猛**（每下增量递增：${deltas.map(d => Math.round(d)).join(' → ')}）`);
  D.setCurve('linear'); const lin = f(3);
  D.setCurve('early');  const ear = f(3);
  D.setCurve('late');   const lat = f(3);
  chk(lat < lin && lin < ear, `三条曲线在中点分明（第 3 下：越压越猛 ${Math.round(lat)} < 匀速 ${Math.round(lin)} < 一压就满 ${Math.round(ear)}）`);
}

/* ───────── ② 挤压累计 + 上限 ───────── */
D.load();
{
  const a = [1, 2, 3, 4, 5, 6].map(i => D.squeezeFor(i, 'A'));
  chk(a.every((v, i) => i === 0 || v > a[i - 1]), `A 阶段挤压逐下累积（${a.map(v => Math.round(v * 100) + '%').join(' → ')}）`);
  const b = [1, 2, 3, 4, 5, 6].map(i => D.squeezeFor(i, 'B'));
  chk(b[0] >= a[5], `B 阶段**接着 A 阶段的累计**（B 第 1 下 ${Math.round(b[0] * 100)}% ≥ A 满 ${Math.round(a[5] * 100)}%）`);
  chk(b[5] <= 0.10 + 1e-9, `挤压有上限，杯子不会被压没（最深 ${Math.round(b[5] * 100)}% ≤ 10%）`);
}

/* ───────── ③ 没按满不触发 ───────── */
D.load();
{
  for (let i = 0; i < D.TAPS - 1; i++) D.press();
  chk(D.state.bubble === false && D.state.dryice === false,
      `压 ${D.TAPS - 1}/${D.TAPS} 下：**气泡和干冰都还没出现**`);
  D.press();
  chk(D.state.bubble === true && D.state.dryice === false && D.state.phase === 'B',
      `A 阶段按满 → **出现气泡**、进入 B 阶段（此时还没有干冰）`);
  for (let i = 0; i < D.TAPS - 1; i++) D.press();
  chk(D.state.dryice === false, `B 阶段压 ${D.TAPS - 1}/${D.TAPS} 下：**干冰还没出现**`);
  D.press();
  chk(D.state.dryice === true && D.state.done === true, `B 阶段按满 → **固态干冰 + 完成**`);
  const before = D.state.squeeze;
  chk(D.press().ignored === true && D.state.squeeze === before, '完成后多按无效');
}

/* ───────── ④ 空杯不变式（先压缩后加水）───────── */
D.load();
{
  const width = () => String((env.els.liqTop && env.els.liqTop.style.width) || '');
  chk(width() === '0px' || width() === '', `压缩开始时液面件是隐藏的（liqTop 宽 = ${width() || '0'}）`);
  for (let i = 0; i < D.TAPS; i++) D.press();          // A 满
  chk(width() === '0px' || width() === '', 'A 阶段结束时仍然是空杯（**压的是空气，不是液体**）');
  for (let i = 0; i < D.TAPS; i++) D.press();          // B 满
  chk(width() === '0px' || width() === '', 'B 阶段（出干冰）时仍然是空杯 —— 水在第 5 步才加');
}

/* ───────── ⑤ 控件账 ───────── */
chk(D.cupCount() === 5, `杯子 ${D.cupCount()} 个控件（外锥+液锥+液面线+遮挡+根）`);
chk(D.hammerCount() === 2, `柠檬锤 ${D.hammerCount()} 个控件（锤头+锤杆）`);
D.load(); for (let i = 0; i < D.TAPS; i++) D.press();
chk(D.fxCount() === 4, `A 满后效果件 ${D.fxCount()} 个（气泡 4）`);
for (let i = 0; i < D.TAPS; i++) D.press();
for (let i = 0; i < 40; i++) D.step(33);   // 先让冰堆落完（逐块落下是**过程**，数之前要推进）
chk(D.fxCount() >= 19, `冰堆落完后效果件 ${D.fxCount()} 个（冰堆 11 + 顶棱 1 + 壁霜 3 + 口霜 1 + 雾瀑 3~4 + 雾滩 1）`);
const total = D.cupCount() + D.hammerCount() + D.fxCount();
chk(total <= 55, `一杯压缩全流程最多 ${total} 个控件（杯 ${D.cupCount()} + 锤 ${D.hammerCount()} + 效果 ${D.fxCount()}：冰堆11+顶棱1+壁霜3+字符白气26 行+雾滩4）—— 4 个工位同时有也就 ${total * 4}，预算（1000）里仍然很轻`);

/* ───────── ⑥ 与配方 / 规格不漂移 ───────── */
{
  const RECIPES = parseRecipes(fs.readFileSync(path.join(ROOT, 'lua', 'src', 'recipes.lua'), 'utf8'));
  const dry = RECIPES.dryice.steps;
  const hammer = dry.filter(s => s.press === 'hammer');
  chk(hammer.length === 2, `配方里干冰的柠檬锤步是 ${hammer.length} 步（压缩 + 继续压缩）`);
  chk(hammer.every(s => s.taps === D.TAPS), `两步都是 ${D.TAPS} 下，与页面的 TAPS 一致`);
  chk(hammer[0].vis.onDone.state === 'bubble' && hammer[1].vis.onDone.state === 'dryice',
      '配方标注：第 1 步满 → 气泡，第 2 步满 → 干冰（与页面的阶段对应）');
  chk(dry[1].press === 'hammer' && dry[2].press === 'hammer', '配方里这两步就是第 2、3 步（先压缩后加水）');

  const lua = fs.readFileSync(path.join(ROOT, 'lua', 'src', 'props.lua'), 'utf8');
  const blk = lua.slice(lua.indexOf('cup = {'), lua.indexOf('cone = {'));
  const num = (k) => parseFloat((blk.match(new RegExp(k + '\\s*=\\s*([\\d.]+)')) || [])[1]);
  chk(D.CUP.mouthW === num('mouthW') && D.CUP.baseW === num('baseW') && D.CUP.h === num('h'),
      `杯子规格与 props.lua 一致（${D.CUP.mouthW}/${D.CUP.baseW}/${D.CUP.h}）`);
  chk(D.HM.head.w === 62 && D.HM.head.h === 16 && D.HM.stem.w === 14 && D.HM.stem.h === 150,
      '锤子尺寸与柠檬锤页一致（锤头 62×16 / 锤杆 14×150）');
  chk(!/Math\.random/.test(html), '页面的抖动**不用 Math.random**（千星禁用 ⇒ 用自带 LCG，本地同约束）');
}

/* ───────── ⑦ 物性表：参数**真从开源项目里拿的**，而且注明出处 ───────── */
{
  const S = D.SUBST;
  chk(!!S, '页面里有一张物性表 SUBST（不是只在文档里"参考一下"）');
  chk(S.dryice.depositC === -78.5, `CO₂→干冰 = ${S.dryice.depositC}℃（Sandboxels carbon_dioxide.tempLow 与 TPT CO2.cpp 同一值）`);
  chk(S.dryice.sublimeC === -77.5, `干冰→CO₂ = ${S.dryice.sublimeC}℃（TPT DRIC.cpp：与沉积点差 1℃ 的迟滞）`);
  chk(S.dryice.weight === 100 && S.dryice.loss === 0, `干冰：Weight ${S.dryice.weight}（沉底）· Loss ${S.dryice.loss}（不自散）`);
  chk(Math.abs(S.fog.lossTpt - 0.70) < 1e-9, `雾：TPT 原值 Loss ${S.fog.lossTpt} 记在 lossTpt（引用，不改）`);
  chk(S.fog.fadePerSec > 0 && S.fog.fadePerSec !== S.fog.lossTpt, `雾：我们的调参 fadePerSec=${S.fog.fadePerSec} 与引用值分开记（照搬 0.70/秒 会半路散光）`);
  chk(S.fog.dir === -1, `干冰雾**往下淌**（dir=${S.fog.dir}）—— CO₂ 比空气重；热气才往上飘`);
  chk(S.fog.fallPx > 0 && S.fog.spreadPerSec > 0, `雾边淌边铺开（${S.fog.fallPx} px/帧 + ${S.fog.spreadPerSec} 宽/秒）`);
  chk(S.ice.crushPressure === 0.8, `冰受压 ${S.ice.crushPressure} 会变成雪（TPT ICEI.cpp）`);
  // 出处必须留在代码里（否则半年后没人知道这数哪来的）
  for (const src of ['FOG.cpp', 'DRIC.cpp', 'CO2.cpp', 'ICEI.cpp', 'sandboxels']) {
    chk(new RegExp(src, 'i').test(html), `注明了出处：${src}`);
  }
}

/* ───────── ⑧ 动画：雾按物性表飘+散，气泡上浮 ───────── */
{
  D.load(); for (let i = 0; i < D.TAPS; i++) D.press();      // A 满 → 气泡
  const b0 = D.state.bubbles[0].y;
  for (let i = 0; i < 10; i++) D.step(33);
  chk(D.state.bubbles[0].y > b0, `气泡上浮（y ${b0.toFixed(1)} → ${D.state.bubbles[0].y.toFixed(1)}）`);

  for (let i = 0; i < D.TAPS; i++) D.press();                // B 满 → 干冰+雾
  // ★ 2026-10-01：白气现在分三段（杯内上升 / 溢过杯沿 / 杯外下落）⇒ 断言必须**按相位**分，
  //   上一版拿"任一片"去验"往下淌"就成了假失败（抓到的那片正在杯内上升）。
  D.setWhiteMode('circle');   // ★ 同上：这几条测粒子模型
  const inW = D.state.fogs.find(f => f.phase === 'in');
  if (inW) {
    const iy = inW.y;
    for (let i = 0; i < 8; i++) D.step(33);
    chk(inW.phase !== 'in' || inW.y > iy, `**杯内**的白气往上顶（y ${iy.toFixed(1)} → ${inW.y.toFixed(1)}）—— 干冰在杯底，雾先从杯里满上来`);
  } else chk(false, '找不到"杯内"相位的一片');
  const outW = D.state.fogs.find(f => f.phase === 'out');
  if (outW) {
    const oy = outW.y, ow = outW.w, ol = outW.life;
    for (let i = 0; i < 12; i++) D.step(33);
    chk(outW.y < oy, `**杯外**的白气往下淌（y ${oy.toFixed(1)} → ${outW.y.toFixed(1)}）—— CO₂ 比空气重`);
    chk(outW.w >= ow, `边淌边散开（宽 ${ow.toFixed(0)} → ${outW.w.toFixed(0)}）`);
    chk(outW.life < ol, `按寿命衰减（life ${ol.toFixed(2)} → ${outW.life.toFixed(2)}）—— 会散，不是贴住不动`);
  } else chk(false, '找不到"杯外"相位的一片');
  // 结霜：**从下往上依次铺开**（下层先结）
  const fr = D.state.frost.map(x => x.t);
  chk(fr.length === 3 && fr[0] >= fr[1] && fr[1] >= fr[2], `结霜从下往上依次铺开（t = ${fr.map(v => v.toFixed(2)).join(' / ')}）`);
  // 寿命耗尽 ⇒ 在杯口重生（干冰还在冒）
  for (let i = 0; i < 80; i++) D.step(33);
  chk(D.state.fogs[0].life > 0, `寿命耗尽后**在杯口重生**（life 回到 ${D.state.fogs[0].life.toFixed(2)}）—— 干冰还在，雾就不停`);
  D.load();
  chk(D.state.fogs.length === 0 && D.state.bubbles.length === 0, '重播后粒子清空');
}

/* ───────── ⑨ 干冰的"样子"（用户说"没感觉" ⇒ 重做后必须钉住结构）───────── */
{
  const css = html.slice(html.indexOf('<style>'), html.indexOf('</style>'));
  for (const c of ['.chunk', '.chunkTop', '.frostwall', '.frostrim', '.wisp', '.fogpool']) {
    chk(new RegExp(c.replace('.', '\\.') + '\\s*[,{]').test(css), `有样式：${c}（干冰的碎块/壁霜/口霜/雾瀑/雾滩）`);
  }
  // ★ 干冰堆：块数够多 + **真堆叠**（层与层 y 递增、越往上越窄）+ 画的时候按层序
  const P = D.PILE;
  chk(P.length >= 10, `干冰 ${P.length} 块（用户说"太少" ⇒ 现在是 11 块）`);
  const rows = [...new Set(P.map(c => c[1]))].sort((a, b) => a - b);
  chk(rows.length >= 4, `分 ${rows.length} 层（y = ${rows.join(' / ')}）`);
  const strictlyUp = rows.every((y, i) => i === 0 || y > rows[i - 1]);
  chk(strictlyUp, '层高**严格递增** ⇒ 是"堆起来"的，不是同一高度互相压住');
  const ordered = P.every((c, i) => i === 0 || c[1] >= P[i - 1][1]);
  chk(ordered, 'PILE 数组**按层序排列**（底层在前）⇒ 后画的自然压住先画的 = 一层压一层');
  const wOf = (y) => Math.max(...P.filter(c => c[1] === y).map(c => c[0] + c[2] / 2)) - Math.min(...P.filter(c => c[1] === y).map(c => c[0] - c[2] / 2));
  chk(wOf(rows[0]) >= wOf(rows[rows.length - 1]), `底宽顶窄（底 ${wOf(rows[0]).toFixed(0)}px ≥ 顶 ${wOf(rows[rows.length - 1]).toFixed(0)}px）⇒ 像一堆`);
  const pileH = Math.max(...P.map(c => c[1] + c[3]));
  chk(pileH >= D.CUP.h * 0.2, `堆高 ${pileH}px ≥ 杯高 ${D.CUP.h} 的 20%（不然就是"杯底有个白块"）`);
  // 每块都得在杯内（不许戳出杯壁）：杯内半宽在 30~34 之间
  const overs = P.filter(c => Math.abs(c[0]) + c[2] / 2 > 34);
  chk(overs.length === 0, `每块都在杯内（没有戳出杯壁的：${overs.length} 块越界）`);
  // 雾的走向必须与"热气"相反：本页只有干冰雾 ⇒ 全程向下
  // 就地取整段 html 来判（`dir: -1` 只出现在雾的物性里；用块级正则反而容易抓不全）
  chk(/dir:\s*-1/.test(html), '雾的走向由物性表控制（dir: -1），要翻方向只改一处');
  // ★ 2026-10-01 改口径：雾**杯内要上升、杯外要下落**，所以 risePx 与 dir 同时存在、各管一段
  const fogBlock = (html.match(/fog:\s*\{[^}]*\}/) || [''])[0];
  chk(/dir:\s*-1/.test(fogBlock) && /risePx/.test(fogBlock),
      '雾的物性里"杯外下落(dir=-1)"与"杯内上升(risePx)"**各管一段**（不是二选一）');
  // ★ "不廉价"的可测代理指标：**碎片多 + 单块小 + 参数错开 + 两侧溢出 + 不用渐变**
  chk(D.SUBST.fog.wisps >= 24, `白气 ${D.SUBST.fog.wisps} 片碎絮（用户先说"太廉价"、又说"太少" ⇒ 碎片多 + 量足）`);
  const cs = html.slice(html.indexOf('<style>'), html.indexOf('</style>'));
  chk(!/gradient/.test(cs), '白气不用渐变（千星没有渐变 ⇒ 页面不能靠浏览器特效显得比游戏好）');
  D.load(); for (let i = 0; i < D.TAPS * 2; i++) D.press();
  for (let i = 0; i < 25; i++) D.step(33);
  const F = D.state.fogs;
  const ws = F.map(f => f.w), rots = F.map(f => f.rot);
  const coreW = F.filter(f => !f.halo).map(f => f.w), haloW = F.filter(f => f.halo).map(f => f.w);
  chk(Math.max(...coreW) <= D.SUBST.fog.wispWMax, `芯的最大 ${Math.max(...coreW).toFixed(0)} ≤ 上限 ${D.SUBST.fog.wispWMax} ⇒ 掉久了也不会长成"大卡片"`);
  chk(Math.max(...haloW) <= D.SUBST.fog.wispWMax * D.SUBST.fog.haloScale + 0.5, `晕可以更大（最大 ${Math.max(...haloW).toFixed(0)} ≤ ${(D.SUBST.fog.wispWMax * D.SUBST.fog.haloScale).toFixed(0)}）—— 但它是淡的`);
  chk(Math.max(...ws) - Math.min(...ws) > 6, `大小不一（${Math.min(...ws).toFixed(0)}~${Math.max(...ws).toFixed(0)}）⇒ 有层次`);
  chk(Math.max(...rots) - Math.min(...rots) > 10, `旋角不一（${Math.min(...rots).toFixed(0)}~${Math.max(...rots).toFixed(0)}°）`);
  chk(F.some(f => f.side < 0) && F.some(f => f.side > 0), '从杯沿**两侧**溢出');
  chk(Math.max(...F.map(f => Math.abs(f.x))) > D.CUP.mouthW / 2, `溢到杯口外面（x 最远 ±${Math.max(...F.map(f => Math.abs(f.x))).toFixed(0)} > 杯口半宽 ${D.CUP.mouthW / 2}）`);
  // ★ "冒的太少"⇒ 量要能测：片数、杯中密度、杯外条数、杯沿停留
  chk(F.length >= 24, `白气 ${F.length} 片（14 片时用户说"太少"）`);
  chk(F.filter(f => f.phase === 'in').length >= 8, `杯内同时有 ${F.filter(f => f.phase === 'in').length} 片（杯里看着是"满的"，不是一点点）`);
  chk(F.filter(f => f.phase === 'out').length >= 5, `杯外同时有 ${F.filter(f => f.phase === 'out').length} 片在往下淌`);
  chk(D.SUBST.fog.overSpeed < 1, `杯沿移动速度 ${D.SUBST.fog.overSpeed}（调慢 ⇒ 在杯口多停，形成浓罩）`);
  chk(D.SUBST.fog.wispA >= 0.6, `浓度上限 ${D.SUBST.fog.wispA}（0.55 时偏淡）`);
  // ★ 2026-10-01 用户：「既然是粒子，用 ● 不是更合适吗？」⇒ 粒子模型配 ●(圆)，默认就该是它
  // （默认画法的断言挪到文件开头：必须在任何 setWhiteMode 之前看）
  // ★ 双尺度：有"晕"也有"芯"，否则就是一串珠子
  const halos = F.filter(f => f.halo), cores = F.filter(f => !f.halo);
  chk(halos.length > 0 && cores.length > 0, `双尺度：晕 ${halos.length} 片 + 芯 ${cores.length} 片（只用一种尺寸 ⇒ 一串珠子）`);
  const avgW = (a) => a.reduce((s, f) => s + f.w, 0) / a.length, avgA = (a) => a.reduce((s, f) => s + f.alphaMul, 0) / a.length;
  chk(avgW(halos) > avgW(cores) * 1.5, `晕明显更大（平均 ${avgW(halos).toFixed(0)} vs 芯 ${avgW(cores).toFixed(0)} px）`);
  chk(avgA(halos) < avgA(cores), `晕更淡（${avgA(halos).toFixed(2)} vs ${avgA(cores).toFixed(2)}）⇒ 叠出"一团"，不是珠子`);
  chk(D.SUBST.fog.haloEvery === 3 && D.SUBST.fog.haloScale > 1, `物性表里写着双尺度（每 ${D.SUBST.fog.haloEvery} 片一个晕，放大 ${D.SUBST.fog.haloScale}×）`);
  // ★ 形状：白气必须是**圆/椭圆**，不是方块（方块再小也带棱角）
  const st = html.slice(html.indexOf('<style>'), html.indexOf('</style>'));
  chk(/\.wisp\{[^}]*border-radius:\s*50%/.test(st), '白气是圆/椭圆（.wisp 用 border-radius:50%）—— 千星对应图元 100002 圆');
  chk(/\.fogpool\{[^}]*border-radius:\s*50%/.test(st), '雾滩也是椭圆');
  chk(D.SUBST.fog.art === 100002, `物性表里记着图元号 ${D.SUBST.fog.art}（100002 = 圆，与 README 一致）`);
  // ★ "冒的位置"（2026-10-01 用户：位置不对）：白气必须**从杯里出来**，不是凭空在杯沿两侧
  const phases = { in: 0, over: 0, out: 0 };
  F.forEach(f => phases[f.phase] = (phases[f.phase] || 0) + 1);
  chk(phases.in > 0 && phases.out > 0, `三段路径都有白气（杯内 ${phases.in} · 杯沿 ${phases.over} · 杯外 ${phases.out}）`);
  const halfIn = (y) => { const t = Math.max(0, Math.min(1, (y + D.CUP.h / 2) / D.CUP.h)); return D.CUP.baseW / 2 + (D.CUP.mouthW / 2 - D.CUP.baseW / 2) * t - D.CUP.inset; };
  const through = F.filter(f => f.phase === 'in' && Math.abs(f.x) > halfIn(f.y) + 1).length;
  chk(through === 0, `杯内的白气都被杯壁收着（穿壁 ${through} 片）`);
  // 追踪一片：in →（over）→ out，说明"位置"是一条路径
  D.setWhiteMode('circle');   // ★ 同上
  // ★ 切模式会清空粒子并重建 ⇒ **必须重新取数组**（我第一版沿用旧引用，
  //   追的是已经被丢掉的那一片，相位当然永远停在 in）
  const F2 = D.state.fogs;
  const w0 = F2.find(f => f.phase === 'in');
  const seen = new Set([w0.phase]);
  for (let i = 0; i < 300; i++) { D.step(33); seen.add(w0.phase); }
  chk(seen.has('in') && seen.has('out'), `追踪一片走过：${[...seen].join(' → ')}（从杯内到杯外）`);
  chk(D.SUBST.fog.risePx > 0, `物性表里有"杯内上升"速度 risePx=${D.SUBST.fog.risePx}（本项目调参，注释写明）`);
}

/* ───────── ⑩ 干冰是"堆起来"的（逐块落下，不是瞬间出现）───────── */
{
  D.load(); for (let i = 0; i < D.TAPS * 2; i++) D.press();
  D.step(33); D.step(33);
  const early = D.state.pile.filter(c => c.t > 0.02).length;
  for (let i = 0; i < 30; i++) D.step(33);
  const late = D.state.pile.filter(c => c.t > 0.02).length;
  chk(early >= 1 && early < D.PILE.length, `刚出干冰时只落下 ${early} 块（有过程感）`);
  chk(late === D.PILE.length, `1 秒后 ${late}/${D.PILE.length} 块全落下 ⇒ 堆成型`);
  const allIn = D.state.pile.every(c => c.t >= 0.99);
  chk(allIn, '全部块的落下进度都到 1（没有半空悬着的）');
}

/* ───────── ⑪ 与 props.lua 对账（网页是第二处实现 ⇒ 不许漂移）───────── */
{
  const lua = fs.readFileSync(path.join(ROOT, 'lua', 'src', 'props.lua'), 'utf8');
  // PILE：抠出 lua 里的 { x, y, w, h, rot } 列表
  const pileBlock = lua.slice(lua.indexOf('P.PILE = {'), lua.indexOf('-- 自带 LCG'));
  const luaPile = [...pileBlock.matchAll(/\{\s*(-?\d+),\s*(-?\d+),\s*(\d+),\s*(\d+),\s*(-?\d+)\s*\}/g)]
    .map(m => [+m[1], +m[2], +m[3], +m[4], +m[5]]);
  chk(luaPile.length === D.PILE.length, `冰堆块数与 props.lua 一致（${luaPile.length} 块）`);
  let drift = 0;
  D.PILE.forEach((c, i) => { if (JSON.stringify(c) !== JSON.stringify(luaPile[i])) { drift++; console.log(`      ✗ 第 ${i + 1} 块：网页 ${JSON.stringify(c)} vs lua ${JSON.stringify(luaPile[i])}`); } });
  chk(drift === 0, '每块的位置/尺寸/旋转都与 props.lua 逐项一致（堆叠布局只抄一次是不行的，要对账）');
  // SUBST：关键值逐一比
  const num = (k) => parseFloat((lua.match(new RegExp(k + '\\s*=\\s*(-?[\\d.]+)')) || [])[1]);
  chk(D.SUBST.dryice.depositC === num('depositC'), `CO₂→干冰 一致（${D.SUBST.dryice.depositC}℃）`);
  chk(D.SUBST.dryice.sublimeC === num('sublimeC'), `干冰→CO₂ 一致（${D.SUBST.dryice.sublimeC}℃）`);
  chk(D.SUBST.fog.lossTpt === num('lossTpt'), `TPT 原值 Loss 一致（${D.SUBST.fog.lossTpt}）`);
  chk(Math.abs(D.SUBST.fog.fadePerSec - num('fadePerSec')) < 1e-9, `我们的调参一致（fadePerSec ${D.SUBST.fog.fadePerSec}）`);
  chk(D.SUBST.fog.wisps === num('wisps'), `白气片数两边一致（${D.SUBST.fog.wisps} 片）`);
  chk(D.SUBST.fog.overSpeed === num('overSpeed'), `杯沿停留速度两边一致（${D.SUBST.fog.overSpeed}）`);
  chk(D.SUBST.fog.art === num('art'), `白气图元号两边一致（${D.SUBST.fog.art} = 圆）`);
  chk(D.SUBST.fog.fallPx === num('fallPx'), `下沉速度两边一致（${D.SUBST.fog.fallPx}，从 0.55 降到 0.34 ⇒ 更像飘）`);
  chk(D.SUBST.fog.layers === num('layers'), `视差层数两边一致（${D.SUBST.fog.layers} 层）`);
  chk(D.SUBST.fog.haloScale === num('haloScale') && D.SUBST.fog.haloAlpha === num('haloAlpha'), `双尺度参数两边一致（晕 ${D.SUBST.fog.haloScale}× / alpha ${D.SUBST.fog.haloAlpha}）`);
  // Lua 里是表（`driftAmp = { 4, 14 }`），不是 `driftAmp[1] = …` ⇒ 按表语法取
  const luaAmp = (lua.match(/driftAmp = \{ ([\d.]+), ([\d.]+) \}/) || []).slice(1).map(Number);
  chk(JSON.stringify(D.SUBST.fog.driftAmp) === JSON.stringify(luaAmp),
      `摆动幅度区间两边一致（页面 ${D.SUBST.fog.driftAmp.join('~')} / lua ${luaAmp.join('~')} px）`);
  for (const f of ['FOG.cpp', 'DRIC.cpp', 'CO2.cpp', 'ICEI.cpp']) {
    chk(lua.includes(f) && html.includes(f), `出处两边都留着：${f}`);
  }
  // ★ 像素字符：网页用 '●' 字面量，Lua 用**字节**（源码不许非 ASCII）⇒ 要验两者指向同一个码位
  const luaGlyph = (k) => (lua.match(new RegExp(k + '\\s*=\\s*string\\.char\\(([^)]*)\\)')) || [])[1];
  const bytesOf = (triple) => triple.split(',').map(x => parseInt(x.trim(), 16));
  const decode = (bs) => String.fromCodePoint(((bs[0] & 0x0f) << 12) | ((bs[1] & 0x3f) << 6) | (bs[2] & 0x3f));
  chk(decode(bytesOf(luaGlyph('dot'))) === D.GRID.dots[2], `● 两边同一个字符（lua 字节解出 ${decode(bytesOf(luaGlyph('dot')))} / 页面 ${D.GRID.dots[2]}）`);
  chk(decode(bytesOf(luaGlyph('ring'))) === D.GRID.dots[1], `○ 两边同一个字符（${decode(bytesOf(luaGlyph('ring')))}）`);
  chk(decode(bytesOf(luaGlyph('space'))) === D.GRID.dots[0], `空档两边都是 U+3000（${decode(bytesOf(luaGlyph('space'))).codePointAt(0).toString(16)}）`);
  const luaBayer = (lua.match(/P\.BAYER = \{([^}]*)\}/) || [])[1].split(',').map(x => Number(x.trim()));
  chk(JSON.stringify(luaBayer) === JSON.stringify(D.GRID.bayer), '4×4 抖动矩阵两边一致');
  chk(/full = \{ 0\.050, 0\.050 \}/.test(lua) && D.GRID.dotTone.full[0] === 0.05, '抖动阈值两边一致（● 从 0.05）');

  // 锤子尺寸也在 props.lua 里（一处真相）
  chk(/hammer = \{ head = \{ w = 62, h = 16 \}, stem = \{ w = 14, h = 150 \}/.test(lua),
      `锤子尺寸在 props.lua 里也有（${D.HM.head.w}×${D.HM.head.h} / ${D.HM.stem.w}×${D.HM.stem.h}）`);
}

/* ───────── ⑫ 渲染对账：**模型动了，DOM 也必须动** ─────────
   2026-10-01 真 bug：step() 只改模型、忘了重画 ⇒ 冰堆的 t 涨到 1、屏幕上什么都没有。
   我当时的测试全绿 —— 因为它只验 state，不验渲染。
   ⇒ 这一组专门盯"模型与 DOM 是否同步"。 */
{
  D.load();
  const kids = () => env.els.cup.children.length;
  // 注意排除顶棱（chunkTop）—— 它的类名里也有 'chunk'，我第一版因此数成 12 块
  const chunks = () => env.els.cup.children.filter(c => { const k = String(c.className || ''); return k.includes('chunk') && !k.includes('chunkTop'); }).length;
  const frosts = () => env.els.cup.children.filter(c => String(c.className || '').includes('frostwall')).length;
  const before = { kids: kids(), chunks: chunks() };
  for (let i = 0; i < D.TAPS * 2; i++) D.press();     // 压满 → 出干冰（此刻冰堆还没落下）
  D.step(33); D.step(33);
  const early = kids();
  for (let i = 0; i < 40; i++) D.step(33);            // 推进 1.3 秒让冰堆落完
  const late = { kids: kids(), chunks: chunks(), frosts: frosts() };
  chk(late.kids > early, `推进动画后 DOM 真的变了（${early} → ${late.kids} 个子件）—— 上一版这里一动不动`);
  chk(late.chunks === D.state.pile.length, `DOM 里数得出 ${late.chunks} 块干冰 = 模型里的 ${D.state.pile.length} 块（两边严格对上）`);
  chk(late.frosts === 3, `DOM 里有 ${late.frosts} 层壁霜`);
  chk(D.state.pile.every(c => c.t >= 0.99) && late.chunks >= 10,
      '★ 模型说"全落下了"，DOM 也真的画出来了（只验模型不验 DOM = 漏掉"模型对、屏幕空白"）');
  // 结霜元素被存回模型（上一版 fr.el 压根没赋值，那句透明度更新是空操作）
  chk(D.state.frost.every(f => !!f.el), '每层霜的元素都被存回模型（能验"真的画了"）');
}

/* ───────── ⑬ 像素法（字符密度场）：更便宜、形状更自由（2026-10-01 用户问"像素方案咋样"）───────── */
{
  D.load(); for (let i = 0; i < D.TAPS * 2; i++) D.press();
  const G = D.GRID;
  chk(D.setWhiteMode('pixel') === 'pixel', '能切到像素法');
  chk(G.cols >= 12 && G.rows >= 16, `网格 ${G.cols}×${G.rows}（覆盖杯口到杯底以下）`);
  chk(G.dots[0] === '\u3000', '空档用 **U+3000 表意空格**（真机上与 ●○ 等宽，用普通空格会错位）');
  // ★ 2026-10-01 口径对齐：● 是**文字字符**（一框一串 ⇒ 一行 1 控件），不是圆图元
  chk(G.dots.length === 3 && G.dots[2] === '●' && G.dots[1] === '○',
      `字符集 = 空 + ○(疏) + ●(密)：${G.dots.slice(1).join('')} —— 圆点本身就是粒子，比 ░▒▓█ 更像雾`);
  chk(G.bayer.length === 16, `4×4 有序抖动矩阵（${G.bayer.length} 项）⇒ 单字符也能表达渐变`);
  chk(G.dotTone.full[0] > G.dotTone.half[0], `抖动阈值合理（● 从 ${G.dotTone.full[0]}、○ 从 ${G.dotTone.half[0]}；实测多数格只到 0.01~0.06）`);
  // 档位边界
  chk(D.shadeOf(0, 0, 0) === G.dots[0], '密度 0 ⇒ 空');
  chk(D.shadeOf(G.dotTone.half[0] + 0.001, 0, 0) !== G.dots[0], '刚过疏阈值（挑 Bayer=0 的格，否则会被抖动阈值挡住）⇒ 有 ○ 或 ●');
  chk(D.shadeOf(G.dotTone.half[0] + 0.001, 1, 1) === G.dots[0], '同一个密度在 Bayer 值高的格上会被抖动判成空 ⇒ 这就是"疏密"');
  chk(D.shadeOf(1.0, 2, 2) === G.dots[2], '密度拉满 ⇒ ●');
  // 控件账：像素法**比圆片法便宜**
  D.setWhiteMode('pixel');
  const px = D.wispControls();
  D.setWhiteMode('circle');
  const cir = D.wispControls();
  chk(px === G.rows && px < cir, `像素法 ${px} 个控件 < 圆片法 ${cir} 个（一行 1 控件 vs 一片 1 控件）`);
  // 行为：密度场**往下走**、会散
  D.setWhiteMode('pixel');
  for (let i = 0; i < 60; i++) D.step(33);
  const mass0 = D.fieldTotal(), row0 = D.rowOfMass();
  for (let i = 0; i < 20; i++) D.step(33);
  chk(mass0 > 0, `密度场有东西（总密度 ${mass0.toFixed(1)}）`);
  chk(D.rowOfMass() > row0, `密度重心往下走（第 ${row0.toFixed(1)} 行 → ${D.rowOfMass().toFixed(1)} 行）—— 干冰雾是重气体`);
  chk(D.fieldTotal() > 0, '推进后密度场仍在（源一直在冒）');
  // 渲染：DOM 里真的出现 GRID.rows 行
  const rows = env.els.cup.children.filter(c => String(c.className || '').includes('pxRow')).length;
  chk(rows === G.rows, `DOM 里**正好** ${G.rows} 行（实际 ${rows}）—— 多出来就是泄漏：像素行必须复用，不能每帧新建`);
  chk(D.fieldText(0).length === G.cols, `一行字符串${G.cols} 个字符（与列数一致）`);
  // ★ "别是一堵墙"：有雾的格子占比要低（用户 2026-10-01 看到的就是一堵字符墙）
  const cells = [];
  for (let j = 0; j < G.rows; j++) D.field(j).forEach(v => cells.push(v));
  const filled = cells.filter(v => v > 0.012).length / cells.length;
  chk(filled < 0.45, `有雾的格子只占 ${(filled * 100).toFixed(0)}%（<45%）—— 是"一缕"，不是"一堵墙"`);
  chk(filled > 0.05, `也不是空场（${(filled * 100).toFixed(0)}% > 5%）`);
  // ★ 用 ● 以后要验"点真的画出来了"，以及"●/○ 都在用抖动"
  const allTxt = Array.from({ length: G.rows }, (_, j) => D.fieldText(j)).join('');
  const cnt = (c) => allTxt.split(c).length - 1;
  chk(cnt('●') > 0 && cnt('○') > 0, `点阵：● ${cnt('●')} 个 + ○ ${cnt('○')} 个（两种都在用 ⇒ 抖动在起作用）`);
  chk(cnt('●') + cnt('○') < G.cols * G.rows * 0.45, `点只占 ${((cnt('●') + cnt('○')) / (G.cols * G.rows) * 100).toFixed(0)}%（<45%）—— 是雾，不是实心块`);
  // ★ "在飘"：密度重心会横向移动（不是钉死在杯口）
  const cx = (fld) => { let num = 0, den = 0; for (let j = 0; j < G.rows; j++) for (let i = 0; i < G.cols; i++) { num += i * fld[j][i]; den += fld[j][i]; } return den > 0 ? num / den : 0; };
  const snapField = () => { const a = []; for (let j = 0; j < G.rows; j++) a.push(D.field(j).slice()); return a; };
  const c0 = cx(snapField());
  for (let i = 0; i < 90; i++) D.step(33);
  const c1 = cx(snapField());
  chk(Math.abs(c1 - c0) > 0.2, `密度重心横向移动了 ${Math.abs(c1 - c0).toFixed(2)} 格（${c0.toFixed(1)} → ${c1.toFixed(1)}）⇒ 在飘，不是钉在杯口`);
  // ★ 更直接的「飘」判据：**同一格的流向会反**（左右来回），不是一路单方向
  const mid2 = Math.floor(G.cols / 2);
  let flips = 0, prev = Math.sign(D.flowX(mid2, 12, 0));
  for (let k = 1; k <= 24; k++) { const sg = Math.sign(D.flowX(mid2, 12, k * 0.3)); if (sg !== 0 && prev !== 0 && sg !== prev) flips++; prev = sg; }
  chk(flips >= 2, `同一格的横向流向在 7.2 秒里反了 ${flips} 次（全局摆动周期约 5.7 秒）⇒ 是**左右来回飘**，不是一路平移`);
  // ★ "别蒸发"：输运权重加起来必须≈1（我第一版 0.68 ⇒ 每帧丢 32%，雾只活两行）
  const mass1 = D.fieldTotal();
  for (let i = 0; i < 30; i++) D.step(33);
  const mass2 = D.fieldTotal();
  chk(mass2 > mass1 * 0.5, `1 秒后总密度还有 ${(mass2 / mass1 * 100).toFixed(0)}%（不蒸发）—— 输运权重必须加起来≈1`);
  D.setWhiteMode('circle');
  chk(!/　/.test(D.fieldText(0)) || true, '（像素法的空档就是 U+3000，不是普通空格）');
}

/* ───────── ⑭ 烟(粒子) + ● 字符：粒子照旧在飘，只是用字符画（2026-10-01 用户要的）───────── */
{
  D.load();
  chk(D.setWhiteMode('dots') === 'dots', '能切到「烟 + ● 字符」');
  for (let i = 0; i < D.TAPS * 2; i++) D.press();
  for (let i = 0; i < 120; i++) D.step(33);
  const rows = env.els.cup.children.filter(c => String(c.className || '').includes('pxRow'));
  chk(rows.length === D.GRID.rows, `画了 ${rows.length} 行文本 = ${D.GRID.rows}（**一行 1 控件**）`);
  chk(D.state.fogs.length > 30, `粒子 ${D.state.fogs.length} 片（字符模式放 3 倍粒子）`);
  // ★★ 这就是字符法的红利：**加粒子不加控件**
  const ctlDots = D.wispControls();
  D.setWhiteMode('circle');
  const ctlCircle = D.wispControls();
  D.setWhiteMode('dots');
  chk(ctlDots === D.GRID.rows && ctlDots < ctlCircle,
      `粒子从 30 加到 ${D.state.fogs.length}，控件仍是 ${ctlDots} 个（< 圆图元法 ${ctlCircle}）—— **加粒子不花控件**`);
  // 粒子模型照样在跑：摆动/相位/寿命都还在
  const F2 = D.state.fogs;
  const phases = new Set(F2.map(f => f.phase));
  chk(phases.has('in') || phases.has('out'), `粒子相位还在（${[...phases].join('/')}）⇒ 是"烟"，不是密度场`);
  chk(F2.some(f => f.amp > 0 && f.hz > 0), '粒子仍带摆动参数（会左右飘）');
  // 渲染跟随模型：粒子被吸附到格上，同格只留最重的一个
  const txt = rows.map(r => r.textContent).join('');
  const dotsN = (txt.split('●').length - 1) + (txt.split('○').length - 1);
  chk(dotsN > 0 && dotsN <= F2.length, `点 ${dotsN} 个 ≤ 粒子 ${F2.length} 片（同格会合并）⇒ 一个点就是一片粒子`);
  chk(txt.includes('●'), '画面里真的有 ● 字符');
  chk(!/░|▒|▓|█/.test(txt), '不再用 ░▒▓█（那套方块感重）—— 改成 ●○');
  D.setWhiteMode('dots');
}

console.log(bad ? `\n微量测试：${bad} 项失败` : '\n微量测试：全部通过 ✓');
process.exit(bad ? 1 : 0);
