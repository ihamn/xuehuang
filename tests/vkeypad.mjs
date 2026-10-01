// vkeypad.mjs —— 虚拟按键组件（preview/手机按键-微量测试.html）的**微量测试**
//
//   node tests/vkeypad.mjs
//
// 它验什么（都是"搬进改良版"之前必须成立的）：
//   ① 键位表就是唯一真相：按钮集合与 VKP.KEYMAP 不许漂移
//   ② 空格必须同时给 key=' ' 与 code='Space'（游戏两个判据都用）
//   ③ 发出的必须是真 KeyboardEvent 形状（bubbles、可取消、带 __vkp 标记）
//   ④ 按下/抬手 → keydown/keyup **成对且有序**（按住类玩法全靠这个）
//   ⑤ 组件只用 .vk- 前缀，不碰游戏的 .act/.st/.rec/.mode/.queue（否则游戏会选错元素）
//   ⑥ 页面里 $('id') 引用的每个 id 都真实存在（搬页面时最容易错的就是这个）
//
// ⚠️ 它不验"手机上触摸好不好按"——那必须真机看。
import fs from 'node:fs';
import path from 'node:path';
import { loadPage } from './_fakedom.mjs';   // ★ 假 DOM 只有一份（见该文件顶部注释）

const ROOT = path.resolve(import.meta.dirname, '..');
const FILE = path.join(ROOT, 'preview', '手机按键-微量测试.html');
const html = fs.readFileSync(FILE, 'utf8');

let bad = 0;
const chk = (ok, msg) => { console.log(`  ${ok ? '✓' : '✗'} ${msg}`); if (!ok) bad++; };

/* ---------- 用共享假 DOM 把页面里的脚本真跑一遍 ---------- */
const env = loadPage(html);
const { ctx, els, declaredIds, received } = env;
const VKP = ctx.VKP;

console.log('虚拟按键组件 · 微量测试');
chk(!!VKP, '组件挂到了 window.VKP');

// ① 键位表
const keys = VKP.KEYMAP.map(x => x.key).join(',');
chk(keys === 'b,h,c,p, ,Escape,a,s', `键位表正确（${keys}）`);
chk(els.padMain.children.length === VKP.KEYMAP.length, `主键区按钮数 = 键位表条目数（${els.padMain.children.length}）`);
chk(els.padNum.children.length === 8, `数字键 8 个（实际 ${els.padNum.children.length}）`);
let drift = '';
for (let k = 0; k < VKP.KEYMAP.length; k++) {
  const b = els.padMain.children[k], spec = VKP.KEYMAP[k];
  if (b.getAttribute('data-vkey') !== spec.key || b.getAttribute('data-vcode') !== spec.code) drift += spec.key + ' ';
}
chk(!drift, `按钮与键位表不漂移${drift ? '（漂移：' + drift + '）' : ''}`);

// ②③ 事件形状：空格
const got = [];
ctx.addEventListener('keydown', e => got.push({ key: e.key, code: e.code, bub: e.bubbles, cancel: e.cancelable, tag: !!e.__vkp }));
VKP.fire('keydown', ' ');
chk(got.length === 1 && got[0].key === ' ' && got[0].code === 'Space', `空格同时给 key=' ' 与 code='Space'`);
chk(got[0].bub === true && got[0].cancel === true && got[0].tag === true, '事件形状：bubbles + cancelable + __vkp 标记');
chk(VKP.specOf('1').code === 'Digit1', '数字键 code = Digit1…Digit8');

// ④ 按下/抬手 → keydown/keyup 成对有序（走真实接线：pointerdown/pointerup）
const seq = [];
ctx.addEventListener('keydown', e => { if (e.key === 'b') seq.push('down'); });
ctx.addEventListener('keyup', e => { if (e.key === 'b') seq.push('up'); });
const btnB = els.padMain.children[0];
btnB._ev.pointerdown.forEach(f => f({ preventDefault() {} }));
chk(els.padMain.children[0].classList.contains('on'), '按下时按钮高亮（.on）');
btnB._ev.pointerup.forEach(f => f({ preventDefault() {} }));
chk(seq.join('>') === 'down>up', `按下/抬手 → keydown/keyup 成对有序（实际 ${seq.join('>')}）`);
chk(!btnB.classList.contains('on'), '抬手后高亮消失');

// 再验一条容易漏的：手指滑出按钮（pointerleave）也必须补 keyup，否则游戏以为一直按着
const seq2 = [];
ctx.addEventListener('keydown', e => { if (e.key === 'p') seq2.push('down'); });
ctx.addEventListener('keyup', e => { if (e.key === 'p') seq2.push('up'); });
const btnP = els.padMain.children[3];
btnP._ev.pointerdown.forEach(f => f({ preventDefault() {} }));
btnP._ev.pointerleave.forEach(f => f({ preventDefault() {} }));
chk(seq2.join('>') === 'down>up', `手指滑出按钮也补 keyup（实际 ${seq2.join('>')}）——不补会让"按住类"停不下来`);

// ⑤ 不碰游戏的保留类名
const reserved = ['.act', '.st', '.rec', '.mode', '.queue'];
const polluted = reserved.filter(r => html.includes('class="' + r.slice(1)) || new RegExp('\\' + r + '\\s*\\{').test(html));
chk(polluted.length === 0, `组件没有占用游戏的类名${polluted.length ? '（占用了 ' + polluted.join(',') + '）' : ''}`);

// ⑥ 页面里引用的 id 都真实存在
const ids = [...html.matchAll(/\$\('([A-Za-z0-9_]+)'\)/g)].map(m => m[1]);
const missing = [...new Set(ids)].filter(id => !new RegExp('id="' + id + '"').test(html));
chk(missing.length === 0, `$('id') 引用的 id 都存在${missing.length ? '（缺：' + missing.join(',') + '）' : ''}`);

// ⑦ 交互语义（2026-10-01 定稿）：按一下 → **枪筒冒火** → **出餐的就是这支冒着火的枪筒**
//   注意它**不是**"再按一下熄灭"的开关模型，也不是"另有一个杯子被送走"：
//   一次按键 = 一次完整动作（点火 → 停顿 → 本体带火飞出 → 新的回来），期间 busy 守卫。
const F7 = ctx.VKFIRE, SV = ctx.VKSERVE;
if (!F7 || !SV) { chk(false, '页面暴露了 VKFIRE / VKSERVE 测试缝'); }
else {
  const key = (type) => ctx.dispatchEvent(new ctx.KeyboardEvent(type, { key: 'h' }));
  const before = Number(els.stServed.textContent);
  key('keydown');
  chk(F7.firing === true, '按一下 → 枪筒冒火（latch：不用按住）');
  key('keyup');
  chk(F7.firing === true, '★ 抬手不熄火（这是"保持"的关键，早期版本 keyup 会熄火）');
  chk(Number(els.stServed.textContent) === before + 1, `点着即出餐一次（已出餐 ${els.stServed.textContent}）`);
  chk(els.prop.className.includes('out'), '★ 出餐的是**枪筒本体**：它自己带着火播飞出动画');
  chk(SV.busy() === true, '动作期间处于 busy');
  key('keydown');
  chk(Number(els.stServed.textContent) === before + 1, '动作期间再按不重复出餐（busy 守卫）');
  await new Promise(r => setTimeout(r, SV.resetMs + 150));
  chk(SV.busy() === false, '动作结束后 busy 复位');
  chk(!els.prop.className.includes('out'), '枪筒飞走后又回来了（动画类名已清空）');
  chk(F7.firing === false, '★ 回来的是**新的、未点火**的枪筒');
  key('keydown');
  chk(Number(els.stServed.textContent) === before + 2, `可以再来一次（累计 ${els.stServed.textContent}）`);
}

// ⑧ 样式 lint：**translateX(-50%) 是"绝对定位居中"的配套写法**，
//   用在非绝对定位的元素上会把元素整体左移半个宽度（这次真踩了：#cone 冒火时左移 90px，
//   看起来就是"火没冒在枪筒上"）。规则级检查：凡含 translateX(-50%) 的规则，自己必须带 position:absolute。
const styles = html.slice(html.indexOf('<style>'), html.indexOf('</style>'));
// ★ 先把 @keyframes 整块剥掉：它的 0% / 22% / 100% 不是选择器，
//   第一版没剥，于是把三个关键帧当成"冒犯规则"误报（测试自己踩了一次）。
function stripKeyframes(s) {
  let out = s;
  for (;;) {
    const at = out.indexOf('@keyframes');
    if (at < 0) return out;
    const open = out.indexOf('{', at);
    let depth = 0, i = open;
    for (; i < out.length; i++) { if (out[i] === '{') depth++; else if (out[i] === '}') { depth--; if (!depth) break; } }
    out = out.slice(0, at) + out.slice(i + 1);
  }
}
const stripped = stripKeyframes(styles);
const rules = [...stripped.matchAll(/([^{}]+)\{([^{}]*)\}/g)]
  .map(m => ({ sel: m[1].trim(), body: m[2] }))
  .filter(r => !/^[\d.]+%$/.test(r.sel));
const offenders = rules.filter(r => r.body.includes('translateX(-50%)') && !r.body.includes('position:absolute'));
if (offenders.length) offenders.forEach(o => console.log('      冒犯规则：' + o.sel));
chk(offenders.length === 0, 'CSSLINT：用 translateX(-50%) 居中的规则，自己都声明了 position:absolute');

// ⑨ 比例旋钮（2026-10-01 新增）：点"=筒口宽"应当把火焰底宽改成 ≈180px，读数也要跟着变
//   —— 否则旋钮就是摆设（用户调半天没反应）。
if (env.attrEls) {
  // ★ "=筒口宽"按钮已改成**按当前筒口动态算**（写死 11.25 会随枪筒预设失准）
  const btn = env.attrEls.find(e => e.getAttribute('data-cell') === 'fit');
  chk(!!btn, '找到「=筒口宽」比例按钮（fit）');
  if (btn) {
    btn._ev.click[0]();
    chk(/100%/.test(els.roInfo.textContent), `读数显示「火底宽 = 筒口宽」（${els.roInfo.textContent}）`);
  }
  const sBtn = env.attrEls.find(e => e.getAttribute('data-scale') === '0.7');
  chk(!!sBtn, '找到整支缩放按钮');
  if (sBtn) { sBtn._ev.click[0](); chk(/0\.7/.test(els.roScale.textContent), `缩放读数已更新（${els.roScale.textContent}）`); }
}

// ⑩ 形状剖面（2026-10-01）："细梗长三角"是个**几何性质**，要能断言，不能只靠肉眼
const HALF = ctx.VKFIRE_HALF, SHAPE = ctx.VKFIRE_SHAPE, APPLY = ctx.VKFIRE_APPLY_SHAPE;
if (!HALF || !SHAPE || !APPLY) { chk(false, '页面暴露了形状测试缝'); }
else {
  APPLY('tri');
  const tri = SHAPE();
  chk(tri.cols === 16 && tri.rows === 27 && tri.stem === 0, `三角（现状）16×27 无梗（${tri.cols}×${tri.rows} stem=${tri.stem}）`);
  chk(HALF(tri.rows) >= HALF(1), '三角：底部比顶部宽');

  APPLY('stem');
  const st = SHAPE();
  chk(st.cols === 9 && st.rows === 36, `细梗长三角：窄而高（${st.cols}×${st.rows}）`);
  chk(HALF(st.rows) <= 0.5, `★ 最底行只留中间 1 格 = 那根"梗"（half=${HALF(st.rows)}）`);
  chk(HALF(st.rows - st.stem - 1) > 1, `梗上面开始展开（half=${HALF(st.rows - st.stem - 1).toFixed(2)}）`);
  chk(HALF(1) <= 0.5, `顶部收成尖（half=${HALF(1)}）`);
  // ★ 只验"梗以上"：梗本身是**故意的一跳**（窄 → 宽），从底往上整体不是单调的。
  //   我第一版把梗也算进单调性里 → 假失败（测试写错，不是形状错）。
  let mono = true;
  for (let r = 2; r <= st.rows - st.stem; r++) if (HALF(r) < HALF(r - 1) - 0.01) { mono = false; break; }
  chk(mono, '细梗长三角：梗以上自下而上宽度单调不增（没有忽宽忽窄）');
  chk(HALF(st.rows - st.stem) > HALF(st.rows), '梗与上面那一段之间**故意有宽度跳变**（这就是"梗"）');

  APPLY('candle');
  const cd = SHAPE();
  let maxAt = 1, maxV = -1;
  for (let r = 1; r <= cd.rows; r++) { const v = HALF(r); if (v > maxV) { maxV = v; maxAt = r; } }
  chk(maxAt > 1 && maxAt < cd.rows, `烛焰：最宽处在中段（第 ${maxAt}/${cd.rows} 行）`);
  chk(HALF(cd.rows) < maxV && HALF(1) < maxV, '烛焰：两端都比中段窄');

  APPLY('tri');
}

// ⑪ 字符渲染模式（模拟千星：分层文本框 + 表意空格 + 方形格）
const CHARMODE = ctx.VKFIRE_CHARMODE, LAYERS_FN = ctx.VKFIRE_LAYERS;
if (CHARMODE && LAYERS_FN && els.btnChar) {
  els.btnChar._ev.click[0]();
  chk(CHARMODE() === true, '点按钮切进「字符 █」模式');
  const boxes = LAYERS_FN();
  chk(boxes.length === 4, `按热度分了 4 层文本框（实际 ${boxes.length}）`);
  chk(boxes.every(b => b.style.display !== 'none'), '4 层都显示出来');
  const all = boxes.map(b => b.textContent || '').join('');
  chk(all.includes('\u2588'), '层里有方块字符 █');
  chk(all.includes('\u3000'), '空格用的是 U+3000 表意空格（普通空格不等宽，会错位）');
  const ro = els.roCell.textContent.match(/([\d.]+)×([\d.]+)/);
  chk(!!ro && ro[1] === ro[2], `字符模式下格子被强制成方形（${els.roCell.textContent}）——字形不能单独拉伸`);
  els.btnChar._ev.click[0]();
  chk(CHARMODE() === false, '再点切回「方块」模式');
}

// ⑫ 枪筒预设（2026-10-01）：要求是"更细、更陡、更小"——这是**几何性质**，要能断言
const CONE = ctx.VKCONE, CONE_APPLY = ctx.VKCONE_APPLY;
if (CONE && CONE_APPLY) {
  const slope = (c) => (c.mw - c.tipw) / 2 / c.th;      // 锥面"每单位高的横向收进量"= 离竖直的角度
  CONE_APPLY('gun');
  const gun = CONE();
  CONE_APPLY('torch2');
  const t2 = CONE();
  chk(t2.mw < gun.mw, `火炬·更细：筒口更窄（${gun.mw} → ${t2.mw}）`);
  chk(t2.totalH > gun.totalH, `整体更长（总高 ${gun.totalH} → ${t2.totalH}）`);
  chk(t2.th > gun.th, `锥体更高（${gun.th} → ${t2.th}）`);
  chk(t2.tipw < gun.tipw, `锥尖更细（${gun.tipw} → ${t2.tipw}）`);
  // ★ "更陡" = 锥面更接近竖直（每单位高的横向收进量更小）
  chk(slope(t2) < slope(gun), `锥面更陡/更接近竖直（收进量 ${slope(gun).toFixed(3)} → ${slope(t2).toFixed(3)}）`);
  chk(/100%|筒口/.test(els.roInfo.textContent), `读数按当前枪筒算（${els.roInfo.textContent.slice(0, 60)}…）`);
  CONE_APPLY('gun');                                     // 还原，别影响后面
} else { chk(false, '页面暴露了枪筒测试缝'); }

// ⑬ 横向缩放滑块 + 自动适配（2026-10-01 用户："手机上需要比例缩小横条"）
const SCALE = ctx.VKSCALE, AUTOFIT = ctx.VKAUTOFIT, CELLF = ctx.VKCELL;
if (SCALE && AUTOFIT && CELLF && els.scaleRange) {
  chk(els.scaleRange.getAttribute('min') === '0.3' && els.scaleRange.getAttribute('max') === '1.5', '横条范围 0.3~1.5');
  els.scaleRange._ev.input[0]({ target: { value: '0.42' } });
  chk(Math.abs(SCALE() - 0.42) < 0.001, `拖横条 → 缩放跟着变（×${SCALE()}）`);
  chk(/0\.42/.test(els.roScale.textContent), `读数跟着变（${els.roScale.textContent}）`);

  const sBtn2 = env.attrEls.find(e => e.getAttribute('data-scale') === '0.7');
  if (sBtn2) {
    sBtn2._ev.click[0]();
    chk(Math.abs(parseFloat(els.scaleRange.value) - 0.7) < 0.001, `点预设按钮 → 横条同步到 0.7（${els.scaleRange.value}）`);
  }

  // ★ 自动适配：要**验公式**，不能只验"是个数"
  ctx.VKCONE_APPLY('torch1');
  ctx.VKFIRE_APPLY_SHAPE('tri');
  const c = ctx.VKCONE(), cell = CELLF();
  AUTOFIT();
  const need = c.totalH + 27 * cell.h + 10;
  const exp = Math.round(Math.max(0.3, Math.min(1.5, (cell.stageH - 44) / need)) * 100) / 100;
  chk(Math.abs(SCALE() - exp) < 0.011, `自动适配 = (舞台高-44)/整支高，取 2 位小数（期望 ×${exp}，实际 ×${SCALE()}）`);
  chk(SCALE() < 1, `自动适配确实把小了（×${SCALE()}）——手机上不会一进来就顶出屏幕`);
} else { chk(false, '页面暴露了缩放/适配测试缝'); }

// ⑭ 火焰底边 ↔ 火炬顶边（2026-10-01 用户要求"对齐"）
const ALIGN = ctx.VKALIGN, GAP_APPLY = ctx.VKGAP_APPLY;
if (ALIGN && GAP_APPLY && els.alignRange && els.fireWrap) {
  chk(ALIGN().gap === 0, `默认对齐量 = 0（实际 ${ALIGN().gap}）—— "火的下部与火炬上部严丝合缝"`);
  chk(els.roAlign.textContent.includes('已对齐'), `读数写明已对齐（${els.roAlign.textContent.slice(0, 24)}…）`);
  els.alignRange._ev.input[0]({ target: { value: '12' } });
  chk(ALIGN().gap === 12, `拖微调横条 → 对齐量变 12（实际 ${ALIGN().gap}）`);
  chk(els.fireWrap.style['--fireGap'] === '12px', `CSS 变量也变了（--fireGap=${els.fireWrap.style['--fireGap']}）`);
  chk(/上抬 12px/.test(els.roAlign.textContent), '读数说明方向（正数=火往上抬）');
  GAP_APPLY(0);
  chk(ALIGN().gap === 0, '可以调回 0');

  // 静态检查：火焰必须**锚在 #prop 顶边**（bottom:100%），否则"对齐"根本无从谈起
  const st = html.slice(html.indexOf('<style>'), html.indexOf('</style>'));
  const rule = (st.match(/#fireWrap\{[^}]*\}/) || [''])[0];
  chk(/bottom:100%/.test(rule), '静态：#fireWrap 用 bottom:100% 锚在 #prop 顶边（= 火炬顶边）');
  chk(/margin-bottom:var\(--fireGap/.test(rule), '静态：偏移量走 --fireGap 变量（不是写死的 -6px）');
  chk(!/margin-bottom:-6px/.test(rule), '静态：旧的"压进筒口 6px"写法已不存在');
} else { chk(false, '页面暴露了对齐测试缝'); }

/* ⑮ 视觉件必须都有样式（同 ⑩：建出来没上色 = 看不见，测试全绿、屏幕空白） */
{
  const css = styles.slice(0, styles.indexOf('@keyframes') >= 0 ? styles.indexOf('@keyframes') : styles.length);
  const need = ['#mouth', '#inner', '#grip', '#tri', '#shine', '#fireWrap', '.charlayer', '#prop'];
  const missing = need.filter(sel => !new RegExp(sel.replace('.', '\\.') + '\\s*[,{]').test(styles));
  if (missing.length) console.log('      缺样式的选择器：' + missing.join(' '));
  chk(missing.length === 0, `炮筒页所有视觉件在 CSS 里都有规则（${need.length} 个）`);
}

console.log(bad ? `\n微量测试：${bad} 项失败` : '\n微量测试：全部通过 ✓');
process.exit(bad ? 1 : 0);
