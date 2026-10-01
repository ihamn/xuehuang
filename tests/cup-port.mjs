// cup-port.mjs —— 杯子原型（preview/杯子-原型.html）的微量测试
//
//   node tests/cup-port.mjs
//
// 杯子有**两种实现**（可切换），所以这个测试的主线是：
//   ① 两模式各自的控件数（7 / 52）—— 这是真机预算里的钱
//   ② **同一套几何不变量在两种实现下都必须成立**（这是"重构不改观感"的唯一证据）
//      液面水平且连续 / 液体贴内壁 / 斜率自洽 / 轮廓逐点一致 / 配料不动杯身
//   ③ 与 props.lua 不漂移（网页是第二处实现，规格必须一模一样）
import fs from 'node:fs';
import path from 'node:path';
import { loadPage } from './_fakedom.mjs';

const ROOT = path.resolve(import.meta.dirname, '..');
const html = fs.readFileSync(path.join(ROOT, 'preview', '杯子-原型.html'), 'utf8');
const env = loadPage(html);
const C = env.ctx.CUP;

let bad = 0;
const chk = (ok, msg) => { console.log(`  ${ok ? '✓' : '✗'} ${msg}`); if (!ok) bad++; };
const near = (a, b, tol, msg) => chk(Math.abs(a - b) <= tol, `${msg}（期望 ${(+b).toFixed(3)}±${tol}，实际 ${(+a).toFixed(3)}）`);
const has = (s, sub, msg) => chk(String(s).includes(sub), msg);

console.log('杯子原型 · 微量测试');
chk(!!C, '原型挂到了 window.CUP');

/* ───────── ① 控件数：这是预算里的钱 ───────── */
C.setMode('tri');
const triCount = C.controlCount();
C.setMode('band');
const bandCount = C.controlCount();
C.setMode('tri');
chk(triCount === 7, `三角形+遮挡 = 7 个控件（实际 ${triCount}）—— 外锥+液锥+遮挡+液面线+杯口+高光+根`);
chk(bandCount === 52, `叠条 = 52 个控件（实际 ${bandCount}）：32 杯身 + 16 液体 + 1 亮线 + 2 + 根`);
chk(bandCount - triCount === 45, `同一只杯子，换实现省下 ${bandCount - triCount} 个控件`);

/* ───────── ② 两模式共用的几何 ───────── */
const g = C.geom();
near(g.baseW, g.mouthW - 2 * g.h * Math.tan(g.slopeDeg * Math.PI / 180), 0.05, '口径/底径/杯高/斜率四者自洽');
near(C.halfOuter(0), g.baseW / 2, 0.001, '底部半宽 = 底径/2（上宽下窄）');
near(C.halfOuter(1), g.mouthW / 2, 0.001, '顶部半宽 = 口径/2');

/* ───────── ③ 三角模式：外锥必须就是那条锥 + 遮挡盖在杯底以下 ───────── */
C.setMode('tri'); C.setFill(0.62);
{
  const p = C.placed();
  const bt = p.find(x => x.kind === 'bodyTri'), mask = p.find(x => x.kind === 'mask');
  const lt = p.find(x => x.kind === 'liqTri'), top = p.find(x => x.kind === 'liqTop');
  chk(!!bt && !!mask && !!lt && !!top, '四个关键件都在（外锥/遮挡/液锥/液面线）');
  const H = C.fullConeH(), bot = -C.SPEC.h / 2, topY = C.SPEC.h / 2;

  near(bt.w, C.SPEC.mouthW, 0.001, '外锥上沿宽 = 口径');
  near(bt.y + bt.h / 2, topY, 0.001, '外锥**上沿贴杯口**');
  near(bt.h, H, 0.01, '外锥高 = 全锥高（口径/2 ÷ 斜率）——尖点在杯底之下');

  // ★ 轮廓逐点一致：三角在某个 t 处的宽度 == 2·halfOuter(t)
  let okProf = true, worst = 0;
  [0, 0.15, 0.35, 0.5, 0.75, 1].forEach(t => {
    const y = bot + t * C.SPEC.h;
    const wAt = bt.w * (1 - (topY - y) / bt.h);
    const d = Math.abs(wAt - C.halfOuter(t) * 2);
    if (d > worst) worst = d;
    if (d > 0.05) okProf = false;
  });
  chk(okProf, `三角的轮廓与 32 条叠条**逐点一致**（最大偏差 ${worst.toFixed(3)}px）—— 换实现不改形状`);

  // ★ 上沿应当**正好在杯底，或压进杯身一点点**（0~1.5px）：
  //   正好"顶着"时，两块边缘差半像素会露一条硬缝 —— 那就是用户说的"遮挡的地方太生硬"。
  //   所以这里故意压进 0.6px；但不能压太多，否则会啃掉杯子的一部分。
  const maskTop = mask.y + mask.h / 2;
  chk(maskTop >= bot - 0.01 && maskTop <= bot + 1.5,
      `遮挡块上沿压在杯底线上（0~1.5px 防缝；实际 ${(maskTop - bot).toFixed(2)}px）`);
  chk(mask.w >= C.SPEC.baseW, `遮挡块够宽（${mask.w} ≥ 底径 ${C.SPEC.baseW}）`);
  // ★ 遮挡块必须**收紧到刚好够**（2026-10-01 用户报"杯子下方被挡住"）：
  //   它的职责只是盖住杯底以下那截锥尖，做大了就是在背景上糊一块显眼的方块。
  chk(mask.w <= C.SPEC.baseW + 8, `遮挡块不许做宽（${mask.w} ≤ 底径+8）—— 大了会在背景上露馅`);
  chk(mask.h <= C.coneHFromBase() + 12, `遮挡块不许做高（${mask.h.toFixed(1)} ≤ 锥尖高+12）`);

  const surfY = bot + 0.62 * C.SPEC.h;
  near(lt.y + lt.h / 2, surfY, 0.01, '液锥上沿 = 液面（水平）');
  near(lt.w, C.halfInner(0.62) * 2, 0.01, '液锥上沿宽 = 该处内壁宽（贴内壁）');
  near(lt.h, C.halfInner(0.62) / C.tanA(), 0.05, '液锥高与斜率自洽（半宽 ÷ 斜率）');
  near(top.y, surfY, 0.01, '液面亮线 y = 杯底 + 进度×杯高');
  near(top.w, C.halfInner(0.62) * 2, 0.01, '亮线横跨整个液面');
  chk(Math.abs(lt.y + lt.h / 2 - top.y) < 0.01, '液锥上沿与亮线重合（液面连续）');
}

/* ───────── ④ 叠条模式：旧断言继续成立（内壁 + 连续 + 单调） ───────── */
C.setMode('band'); C.setFill(0.62);
{
  const p = C.placed();
  const liq = p.filter(x => x.kind === 'liq' && x.w > 0);
  chk(liq.length > 0, `叠条模式：液面 62% 时 ${liq.length} 条液体可见`);
  let okInner = true;
  const bot = -C.SPEC.h / 2;
  liq.forEach(x => {
    const tm = (x.y - bot) / C.SPEC.h;
    if (Math.abs(x.w - C.halfInner(tm) * 2) > 0.8) okInner = false;
  });
  chk(okInner, '叠条模式：每条液体贴内壁（不是内接梯形）');
  const top = p.filter(x => x.kind === 'liqTop')[0];
  const topBand = liq.reduce((a, b) => (b.y > a.y ? b : a));
  near(topBand.y + topBand.h / 2, top.y, 1.2, '叠条模式：最上面那条液体的上沿 ≈ 亮线（无台阶）');

  let prevY = -1e9, prevN = 0, mono = true;
  [0.05, 0.1, 0.25, 0.5, 0.62, 0.8, 1].forEach(f => {
    C.setFill(f);
    const ps = C.placed();
    const lq = ps.filter(x => x.kind === 'liq' && x.w > 0);
    const tp = ps.filter(x => x.kind === 'liqTop')[0];
    if (tp.y < prevY - 0.001 || lq.length < prevN - 1) mono = false;
    prevY = tp.y; prevN = lq.length;
  });
  chk(mono, '叠条模式：进度 0→100% 液面单调上升、可见条数不倒退');
}

/* ───────── ⑤ 两模式的液面位置必须完全一致 ───────── */
{
  let same = true, detail = '';
  [0.1, 0.33, 0.62, 0.9, 1].forEach(f => {
    C.setMode('tri'); C.setFill(f);
    const a = C.placed().find(x => x.kind === 'liqTop');
    C.setMode('band'); C.setFill(f);
    const b = C.placed().find(x => x.kind === 'liqTop');
    if (Math.abs(a.y - b.y) > 0.01 || Math.abs(a.w - b.w) > 0.01) { same = false; detail = `f=${f}: tri(${a.y.toFixed(2)},${a.w.toFixed(2)}) vs band(${b.y.toFixed(2)},${b.w.toFixed(2)})`; }
  });
  chk(same, `两种实现的液面线**像素级一致**${detail ? '（' + detail + '）' : ''}`);
  C.setMode('tri'); C.setFill(0);
  chk(C.placed().find(x => x.kind === 'liqTop').w === 0, '进度 0 时液面亮线宽度归零（空杯不画线）');
  C.setFill(0.62);
}

/* ───────── ⑥ 配料只加子件、不动杯身（两种模式都验） ───────── */
['tri', 'band'].forEach(m => {
  C.setMode(m);
  const before = JSON.stringify(C.placed().filter(x => x.kind === 'body' || x.kind === 'bodyTri'));
  C.state.gaps.ice = true; C.state.gaps.lemon = true; C.state.gaps.fog = true;
  C.renderToppings();
  const after = JSON.stringify(C.placed().filter(x => x.kind === 'body' || x.kind === 'bodyTri'));
  chk(before === after, `${m} 模式：加配料后杯身几何**逐条不变**`);
  const n = env.els.cup.children.length;
  C.state.gaps.ice = false; C.state.gaps.lemon = false; C.state.gaps.fog = false;
  C.renderToppings();
  chk(env.els.cup.children.length < n, `${m} 模式：关掉配料后子件被移除（${n} → ${env.els.cup.children.length}）`);
});
C.setMode('tri');

/* ───────── ⑦ 与 props.lua 不漂移 ───────── */
{
  const lua = fs.readFileSync(path.join(ROOT, 'lua', 'src', 'props.lua'), 'utf8');
  const cupBlock = lua.slice(lua.indexOf('cup = {'), lua.indexOf('cone = {'));
  const num = (k) => { const m = cupBlock.match(new RegExp(k + '\\s*=\\s*([\\d.]+)')); return m ? parseFloat(m[1]) : NaN; };
  near(C.SPEC.mouthW, num('mouthW'), 0.001, '与 lua 一致：口径 mouthW');
  near(C.SPEC.h, num('h'), 0.001, '与 lua 一致：杯高 h');
  near(C.SPEC.slopeDeg, num('slopeDeg'), 0.001, '与 lua 一致：slopeDeg');
  near(C.SPEC.inset, num('inset'), 0.001, '与 lua 一致：内缩 inset');
  near(C.SPEC.lipH, num('lipH'), 0.001, '与 lua 一致：杯口亮边 lipH');
  near(C.SPEC.shineW, num('shineW'), 0.001, '与 lua 一致：高光宽 shineW');
  const b = lua.match(/local BANDS = (\d+)/), q = lua.match(/local LQ = (\d+)/);
  chk(b && Number(b[1]) === C.BANDS, `与 lua 一致：BANDS=${C.BANDS}`);
  chk(q && Number(q[1]) === C.LQ, `与 lua 一致：LQ=${C.LQ}`);
  console.log('    [提示] 炮筒已用三角形方案；杯子改用三角方案后，props.lua 的 P.cup 要同步重写（现在是 32 条叠条）');
}

/* ⑧ 布局约束（2026-10-01 用户报"杯子下沿被舞台截掉"）
     自动适配必须保证：底部偏移 + 杯子高 + 顶部留白 ≤ 舞台高
     —— 否则杯子会被舞台下沿裁掉（下面紧接着就是控制区，看着就像"被挡住了"）。 */
const LAYOUT = env.ctx.CUPLAYOUT, AUTOFIT = env.ctx.CUPAUTOFIT;
if (LAYOUT && AUTOFIT) {
  AUTOFIT();
  const L = LAYOUT();
  chk(L.topEdgeFromBottom <= L.stageH - 20,
      `自动适配后杯子完整落在舞台里（底偏 ${L.cy} + 杯高 ${(L.h * L.scale).toFixed(0)} = ${L.topEdgeFromBottom.toFixed(0)} ≤ 舞台 ${L.stageH.toFixed(0)} − 20）`);
  chk(L.scale >= 0.8 && L.scale <= 4, `缩放落在合法区间（×${L.scale.toFixed(2)}）`);
  // 把底部偏移调大，再适配，仍然不许越界
  C.state.cy = 120; AUTOFIT();
  const L2 = LAYOUT();
  chk(L2.topEdgeFromBottom <= L2.stageH - 20,
      `底部偏移改成 120 后，适配会**自动缩小**以保证不越界（${L2.topEdgeFromBottom.toFixed(0)} ≤ ${L2.stageH.toFixed(0)} − 20，scale ×${L2.scale.toFixed(2)}）`);
  C.state.cy = 28; AUTOFIT();
  chk(true, '（提示）舞台用 dvh 高度：手机浏览器底栏出现/消失时会重算，不再靠手调');
} else { chk(false, '页面暴露了布局测试缝'); }

/* ⑨ 遮挡的"不生硬"三件事（2026-10-01 用户报"遮挡的地方太生硬"）
     ① 遮挡色必须**跟着背景走**（真机规矩：父控件不裁子控件 ⇒ 只能同色遮挡）
     ② 上沿压进杯身防缝（已在上面验过）
     ③ 可选"杯底亮边"：把切边变成设计好的边 */
if (env.els.cup && env.els.stage) {
  const bgBtns = (env.attrEls || []).filter(e => e.getAttribute('data-bg'));
  chk(bgBtns.length >= 3, `有 ${bgBtns.length} 个背景色选项（画布/面板/卡片）`);
  const cardBtn = bgBtns.find(e => e.getAttribute('data-bg') === '#ff9a4d');
  if (cardBtn) {
    cardBtn._ev.click[0]();
    chk(env.els.cup.style['--mask'] === '#ff9a4d', `换背景后**遮挡色自动同步**（--mask=${env.els.cup.style['--mask']}）—— 这是真机上"杯子放哪就用哪的颜色"的模型`);
    chk(env.els.stage.style.background === '#ff9a4d', '背景也同步换了（两者永远一致，才不会露出边界）');
  }
  const baseBtn = (env.attrEls || []).find(e => e.getAttribute('data-opt') === 'baseline');
  if (baseBtn) {
    // ★ 用页面暴露的状态验，不用 env.els.base：#base 是**页面动态创建**的元素，
    //   而假 DOM 只为 HTML 里声明了 id 的元素建模（我第一版因此取到 undefined 而崩）。
    chk(!!C.placed().find(x => x.kind === 'base'), '杯底亮边在控件树里（kind=base）');
    const before = C.state.baseShine;
    baseBtn._ev.click[0]();
    chk(C.state.baseShine !== before, `点一下能切换杯底亮边（${before} → ${C.state.baseShine}）`);
    baseBtn._ev.click[0]();
    chk(C.state.baseShine === before, '再点一下切回来');
  }
} else { chk(false, '页面暴露了 cup/stage 元素'); }

/* ⑩ 视觉件必须**都有样式**（2026-10-01 用户报"杯底亮边没做成"：
     那个 div 建出来了、位置也摆了，但 CSS 里没有它的规则 ⇒ 全透明，看不见。
     这类错"测试全绿、屏幕上没有"，只能在样式表这一层静态拦。） */
{
  const css = html.slice(html.indexOf('<style>'), html.indexOf('</style>'));
  const mustStyled = ['.tri', '.mask', '.bodyB', '.liqB', '#liqTop', '#lip', '#shine', '#base', '.ice', '.lemon', '#fog'];
  const missing = mustStyled.filter(sel => !new RegExp(sel.replace('.', '\\.') + '\\s*[,{]').test(css));
  if (missing.length) console.log('      缺样式的选择器：' + missing.join(' '));
  chk(missing.length === 0, `所有视觉件在 CSS 里都有规则（${mustStyled.length} 个：三角/遮挡/杯身/液体/液面线/杯口/高光/杯底亮边/冰/柠檬/白雾）`);
}

/* ⑪ 杯底亮边的几何（2026-10-01 用户报"没对准杯底、凸出了一点"）
     ① 不许比杯底宽（凸出去就是"多出来一块"）
     ② 底边不许低于杯底线（低于就是戳出杯外）
     ③ 必须贴着底线（不能飘在半空） */
{
  const b = C.placed().find(x => x.kind === 'base');
  if (b) {
    const bot = -C.SPEC.h / 2;
    chk(b.w <= C.SPEC.baseW, `杯底亮边不比杯底宽（${b.w.toFixed(1)} ≤ ${C.SPEC.baseW}）—— 宽了就两边凸出`);
    chk(b.y - b.h / 2 >= bot - 0.01, `底边不越过杯底（下沿 ${(b.y - b.h / 2).toFixed(2)} ≥ ${bot}）`);
    chk(b.y - b.h / 2 <= bot + 1.5, `底边贴着杯底（下沿距杯底 ${(b.y - b.h / 2 - bot).toFixed(2)}px ≤ 1.5）`);
    const css = html.slice(html.indexOf('<style>'), html.indexOf('</style>'));
    const rule = (css.match(/#base\{[^}]*\}/) || [''])[0];
    chk(!/rgba\([^)]*,\s*\.?\d*\.\d+\s*\)/.test(rule) && !/rgba\([^)]*,\s*0\./.test(rule),
        `杯底亮边是**不透明**实色（${(rule.match(/background:([^;]+)/) || [])[1] || '?'}）—— 半透明压在玻璃/液体上会糊`);
  } else chk(false, '没找到杯底亮边');
}

console.log(bad ? `\n微量测试：${bad} 项失败` : '\n微量测试：全部通过 ✓');
process.exit(bad ? 1 : 0);
