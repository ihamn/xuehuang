// lemon-hammer.mjs —— 「柠檬锤」最小试玩页（preview/柠檬锤-微量测试.html）的微量测试
//
//   node tests/lemon-hammer.mjs
//
// 验五件事（前两条是 2026-10-01 用户报的问题）：
//   ① **锤子方向**：锤头在**下**、锤杆在**上**（倒 T = 捣锤），同轴（上一版我放反了）
//   ② **杯子与锤子大小匹配**：两者共用同一套设计像素 + 同一个缩放（结构保证，不靠记数字）
//   ③ 一次下锤 = 一次连按（不许多记/少记）
//   ④ 没按满绝不触发；按满只触发一次，多按无效
//   ⑤ 液面在次数里均分涨
import fs from 'node:fs';
import path from 'node:path';
import { loadPage } from './_fakedom.mjs';
import { parseRecipes } from './_recipe-vis.mjs';

const ROOT = path.resolve(import.meta.dirname, '..');
const html = fs.readFileSync(path.join(ROOT, 'preview', '柠檬锤-微量测试.html'), 'utf8');
const env = loadPage(html);
const H = env.ctx.HMR;
const css = html.slice(html.indexOf('<style>'), html.indexOf('</style>'));

let bad = 0;
const chk = (ok, msg) => { console.log(`  ${ok ? '✓' : '✗'} ${msg}`); if (!ok) bad++; };
const rule = (sel) => (css.match(new RegExp(sel.replace('#', '\\#') + '\\{[^}]*\\}')) || [''])[0];
const px = (sel, prop) => { const m = rule(sel).match(new RegExp(prop + ':(-?[\\d.]+)(?:px)?')); return m ? Number(m[1]) : NaN; };
// bottom 可能是 "198px" 或 "16px"；用 calc 的不在此列
// bottom 可能是 `bottom:0`（无 px）或 `bottom:198px` —— 同 ① 的坑，正则要容忍两种
const bottomPx = (sel) => { const m = rule(sel).match(/bottom:(-?[\d.]+)(?:px)?/); return m ? Number(m[1]) : NaN; };

console.log('柠檬锤 · 微量测试');
chk(!!H, '页面挂上了 window.HMR');

/* ───────── ① 方向：锤头在下、锤杆在上、同轴 ───────── */
{
  const head = H.HM.head, stem = H.HM.stem;
  chk(H.hammerCount() === 2, `锤子 = ${H.hammerCount()} 个控件（锤头 + 锤杆）`);
  chk(head.w > stem.w, `锤头比锤杆宽（${head.w} > ${stem.w}）—— 这就是那一横`);
  chk(head.h < stem.h, `锤头比锤杆矮（${head.h} < ${stem.h}）`);
  // ★ 方向：锤头贴着自己的下沿（bottom:0），锤杆坐在锤头**上面**（bottom = 锤头高）
  const headBottom = px('#hmHead', 'bottom');
  const stemBottom = px('#hmStem', 'bottom');
  chk(headBottom === 0, `锤头贴在**下面**（#hmHead bottom:${headBottom}）—— 上一版我把它放在上面，方向反了`);
  chk(stemBottom >= head.h, `锤杆坐在锤头**上面**（#hmStem bottom:${stemBottom} ≥ 锤头高 ${head.h}）`);
  chk(/translateX\(-50%\)/.test(rule('#hmHead')) && /translateX\(-50%\)/.test(rule('#hmStem')),
      '锤头/锤杆同轴（都 translateX(-50%)）—— 错开就不成 T');
  const plungeCss = css.slice(css.indexOf('@keyframes plunge'));
  chk(/@keyframes plunge/.test(css) && /translateY\(/.test(plungeCss.slice(0, 220)),
      '下锤用**垂直位移**（捣锤就是这么用的），不再绕顶端摆 ⇒ 也省掉了枢轴容器');
}

/* ───────── ② 大小匹配：同一套设计像素 + 同一个缩放 ───────── */
{
  // 杯子的设计尺寸就在页面里（CUP），锤子也用它做单位
  const cup = H.CUP;
  chk(cup.mouthW === 100 && cup.baseW === 69.2 && cup.h === 198,
      `杯子用**已圈定规格**：口径 ${cup.mouthW} / 底径 ${cup.baseW} / 高 ${cup.h}`);
  chk(H.headVsMouth() < 1 && H.headVsMouth() > 0.4,
      `锤头能进杯口又不像筷子（锤头 ${H.HM.head.w} / 杯口 ${cup.mouthW} = ${(H.headVsMouth() * 100).toFixed(0)}%）`);
  // ★ 结构保证：只有 #scene 带缩放，杯子和锤子自己都不许缩放（否则又会各缩各的）
  chk(/scale\(var\(--zoom/.test(rule('#scene')), '#scene 用 --zoom 缩放（整个场景一起缩）');
  chk(!/scale\(/.test(rule('#cupWrap')), '#cupWrap **自己不带缩放**（上一版写死 ×2.4，才和锤子对不上）');
  chk(!/scale\(/.test(rule('#hmWrap')), '#hmWrap 也不带缩放');
  chk(!/scale\(/.test(rule('#hmHead')) && !/scale\(/.test(rule('#hmStem')), '锤子两个件都不单独缩放');
  // 锤子挂在杯口上方：idle 时锤头底边在杯口之上（gap）
  const cupTopFromSceneBottom = bottomPx('#cupWrap') + cup.h;   // 杯口在场景里的高度
  const hmBottom = bottomPx('#hmWrap');
  chk(hmBottom >= cupTopFromSceneBottom, `锤子挂在杯口上方（#hmWrap bottom:${hmBottom} ≥ 杯口 ${cupTopFromSceneBottom}）`);
  // 下锤行程：要能穿过杯口、且不穿出杯底
  const gap = H.HM.gap, plunge = H.HM.plunge;
  chk(plunge > gap, `下锤行程穿过杯口（${plunge} > 间隙 ${gap}）—— 否则锤头进不了杯子`);
  chk(plunge < gap + cup.h, `下锤行程不穿出杯底（${plunge} < 间隙 ${gap} + 杯高 ${cup.h}）`);
  // 缩放滑条只影响场景
  H.setZoom(1.4);
  chk(Math.abs(H.state.zoom - 1.4) < 1e-9, '缩放可调（×1.4）');
  chk(Number(env.els.scene.style['--zoom']) === 1.4, `缩放作用在 #scene 上（--zoom=${env.els.scene.style['--zoom']}）—— 杯子与锤子一起变`);
  H.setZoom(1);
}

/* ───────── ③ 一次下锤 = 一次连按 ───────── */
H.load('dry1');
{
  const r1 = H.press();
  chk(r1.hits === 1, `按 1 下 → 连按记 **1** 次（实际 ${r1.hits}）`);
  chk(H.swingCount() === 1, '按下后进入"下锤中"');
  chk(H.press().hits === 2, '再按 1 下 → 2 次');
}

/* ───────── ④⑤ 没按满不触发 / 按满只触发一次 ───────── */
//   ★ 这里**不再验"液面均分涨"**：锤子不加水（那条规则属于"按压"类步骤 pump），
//     已经由 tests/cup-player.mjs 在"加满空杯"那一步上验过了。
H.load('apple');
{
  const st = H.STEPS.apple;
  for (let i = 1; i < st.taps; i++) H.press();
  chk(H.state.toppings.apple === 0, `砸 ${st.taps - 1}/${st.taps} 下：**苹果块还没出现**（没捣够不出料）`);
  const r = H.press();
  chk(H.state.toppings.apple >= 1 && r.done, `砸满 ${st.taps}/${st.taps} 下 → **苹果块出现** + 完成`);
  const before = H.state.toppings.apple;
  chk(H.press().ignored === true && H.state.toppings.apple === before, '完成后多按无效（不会越捣越多）');
}
// 压缩出干冰：按满才出干冰，且**必须接着第 2 步**才有"固态"
H.load('dry1');
{
  const st = H.STEPS.dry1;
  for (let i = 0; i < st.taps; i++) H.press();
  chk(H.state.states.bubble === true && H.state.states.dryice === false,
      `压满 ${st.taps} 下 → 先出**气泡**（还没到固态干冰）`);
}
H.load('dry2');
{
  const st = H.STEPS.dry2;
  for (let i = 1; i < st.taps; i++) H.press();
  chk(H.state.states.dryice === false, `继续压缩 ${st.taps - 1}/${st.taps} 下：**干冰还没出来**`);
  H.press();
  chk(H.state.states.dryice === true, `压满 ${st.taps} 下 → **固态干冰出现**`);
}

/* ───────── ⑥ 只放"锤子的活"，且与配方一一对应 ───────── */
{
  // 共享解析器（见 tests/_recipe-vis.mjs 头部的踩坑记录）
  const RECIPES = parseRecipes(fs.readFileSync(path.join(ROOT, 'lua', 'src', 'recipes.lua'), 'utf8'));
  const recipeHammer = [];
  Object.keys(RECIPES).forEach(id => RECIPES[id].steps.forEach((s, i) => {
    if (s.press === 'hammer') recipeHammer.push({ name: RECIPES[id].name, idx: i + 1, taps: s.taps });
  }));
  const pageSteps = H.HAMMER_STEPS.map(k => H.STEPS[k]);
  chk(recipeHammer.length === 4, `配方里标记"柠檬锤"的步有 ${recipeHammer.length} 个（捣果肉 + 压缩干冰）`);
  chk(pageSteps.length === recipeHammer.length, `试玩页只放这 ${pageSteps.length} 步（不多不少）`);
  let mismatch = 0;
  recipeHammer.forEach(r => {
    const hit = pageSteps.find(s => (s.recipe || '').includes(r.name) && (s.recipe || '').includes('第' + r.idx + '步'));
    if (!hit || hit.taps !== r.taps) { mismatch++; console.log(`      ✗ 配方 [${r.name} 第${r.idx}步 taps=${r.taps}] 在页面上对不上`); }
  });
  chk(mismatch === 0, '页面的每张牌都对应配方里那一步（产品名 + 第几步 + 次数都对得上）');
  // ★ 反向：非锤子的连按步（按压/摇晃）不许出现在这个页面上
  const banned = ['加满空杯', '摇匀', '加满冰'];
  const found = pageSteps.filter(s => banned.some(b => (s.label + s.recipe).includes(b)));
  chk(found.length === 0, `页面上没有"按压/摇晃"类的活（加满/摇匀/加冰）—— 拿锤子去干那些是口径不对`);
  // 锤子不加水：液面是这一步固定的，按多少下都不变
  const snap = H.STEPS[H.HAMMER_STEPS[0]].fill;
  H.load(H.HAMMER_STEPS[0]);
  H.press();
  chk(H.state.fill === snap, `锤子**不涨液面**（按一下后仍是 ${(H.state.fill * 100).toFixed(0)}%）—— 加水是"注入"类步骤的事`);
}

/* ───────── ⑦ 键盘挡按住连发 ───────── */
chk(/e\.repeat/.test(html), '键盘绑定挡了 e.repeat（按住不放不会连发成十几下）');

/* ───────── ⑧ 与 props.lua 不漂移 ───────── */
{
  const lua = fs.readFileSync(path.join(ROOT, 'lua', 'src', 'props.lua'), 'utf8');
  const blk = lua.slice(lua.indexOf('cup = {'), lua.indexOf('cone = {'));
  const num = (k) => parseFloat((blk.match(new RegExp(k + '\\s*=\\s*([\\d.]+)')) || [])[1]);
  chk(H.CUP.mouthW === num('mouthW') && H.CUP.baseW === num('baseW') && H.CUP.h === num('h'),
      `页面杯子规格与 props.lua 一致（${H.CUP.mouthW}/${H.CUP.baseW}/${H.CUP.h}）`);
}

console.log(bad ? `\n微量测试：${bad} 项失败` : '\n微量测试：全部通过 ✓');
process.exit(bad ? 1 : 0);
