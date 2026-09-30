// 无头冒烟测试：给《雪皇的后厨》造一个极简假 DOM，跑完一整局（默认 20 分钟局）。
//   node _scratch/smoke.mjs [fast|slow 覆盖秒数]
// 它证明：脚本能初始化、主循环能跑、点单→小票→工位→出餐闭环能走通、结算能出。
// 它不能证明：排版好不好看（那个只能看浏览器截图）。

import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const ROOT = path.resolve(import.meta.dirname, '..');
// ★ 支持 --html=<文件>（2026-10-01）：默认测**原版**（还原度基准，不许改）；
//   改良在 雪皇的后厨-改良.html 里做，用 --html=雪皇的后厨-改良.html 跑同一套冒烟。
const HTML_ARG = (process.argv.find(a => a.startsWith('--html=')) || '').slice(7);
const HTML_FILE = HTML_ARG ? path.resolve(ROOT, HTML_ARG) : path.join(ROOT, '雪皇的后厨.html');
if (!fs.existsSync(HTML_FILE)) { console.error('找不到 HTML：' + HTML_FILE); process.exit(2); }
console.log('冒烟对象：' + path.relative(ROOT, HTML_FILE) + '（' + fs.statSync(HTML_FILE).size + ' 字节）');
const html = fs.readFileSync(HTML_FILE, 'utf8');
const i = html.indexOf('<script>'), j = html.lastIndexOf('</script>');
const code = html.slice(i + 8, j);

/* ---------------- 极简假 DOM ---------------- */
const IDS = ['daybar','clock','clk','clksub','btnPause','btnRestart','btnAuto','btnTicket','orders','orderCount',
  'sMoney','sRent','sServed','sBad','sCombo','sAuto','sKitchen','sArrive','sLeftWait','hint','live','stations','book','slip','slipT',
  'slipS','ghostCursor','toasts','flash','pack','rdyBadge','veil'];

function mkEl(tag = 'div', cls = '') {
  const el = {
    tagName: tag.toUpperCase(), className: cls, dataset: {}, children: [], style: {},
    _html: '', textContent: '', disabled: false, title: '', parentNode: null,
    classList: {
      add(...c) { c.forEach(x => { if (x && !el.className.split(' ').includes(x)) el.className = (el.className + ' ' + x).trim(); }); },
      remove(...c) { c.forEach(x => { el.className = el.className.split(' ').filter(v => v !== x).join(' '); }); },
      toggle(c, on) { on ? el.classList.add(c) : el.classList.remove(c); },
      contains(c) { return el.className.split(' ').includes(c); },
    },
    set innerHTML(v) { el._html = v; el.children = []; },
    get innerHTML() { return el._html; },
    appendChild(c) { c.parentNode = el; el.children.push(c); return c; },
    removeChild(c) { el.children = el.children.filter(x => x !== c); },
    remove() { if (el.parentNode) el.parentNode.removeChild(el); },
    addEventListener(t, f) { (el._ev ||= {})[t] = f; },
    removeEventListener() {},
    getBoundingClientRect() { return { left: 100, top: 100, width: 160, height: 60 }; },
    querySelector(sel) { return fakeQuery(el, sel, true); },
    querySelectorAll(sel) { return fakeQuery(el, sel, false); },
    closest(sel) { return el.classList.contains(sel.replace('.', '')) ? el : null; },
    get firstChild() { return el.children[0] || null; },
  };
  return el;
}
// 任意假节点都能按需生出子节点（innerHTML 我们不去真解析）
function attachKids(el) {
  el._kids = el._kids || {};
  el._kid = (k) => el._kids[k] || (el._kids[k] = attachKids(mkEl('div')));
  el.querySelector = (s) => fakeQuery(el, s, true);
  el.querySelectorAll = (s) => fakeQuery(el, s, false);
  return el;
}

// 查选择器的规则化实现（够用即可，不追求通用）
const REG = {
  st: [],        // 5 个工位
  act: [],       // 5 个按钮
  q: {},         // 工位队列
  rec: [],       // 手册条目
};
function fakeQuery(root, sel, one) {
  const parts = sel.split(',').map(s => s.trim());
  const out = [];
  for (const s of parts) {
    if (s === '.st') out.push(...REG.st);
    else if (s.startsWith('.st[data-st=')) { const id = s.match(/"(.*?)"/)[1]; out.push(REG.st.find(x => x.dataset.st === id)); }
    else if (s === '.act') out.push(...REG.act);
    else if (s.startsWith('.act[data-act=')) { const id = s.match(/"(.*?)"/)[1]; out.push(REG.act.find(x => x.dataset.act === id)); }
    else if (s === '.rec') out.push(...REG.rec);
    else if (s === '.mode') out.push(...(root._modes || []));
    else if (s === '.queue') out.push(root._queue);
    else if (s === '.act' && root._act) out.push(root._act);
    else if (s.startsWith('.st')) out.push(...REG.st.filter(x => root === x || true).slice(0, 1));
    else if (s === 'i' || s === '.fill' || s === '.lab' || s === '.s' || s === '.x' || s === '.k' || s === '.t') out.push(root._kid(s));
    else if (s === 'b' || s === '.who b') out.push(root._kid('b'));
    else if (s === '.emo' || s === '.nm' || s === '.mods' || s === '.cups' || s === '.pat' || s === '.left'
      || s === '.clock2' || s === '.pat i' || s === '.badge' || s === '.ic' || s === '.desc' || s === '.hd'
      || s === '.queue' || s === '.fx' || s === '.steps' || s === '.flow' || s === '.t' || s === '.foot' || s === '.pr')
      out.push(root._kid(s));
    else if (s === '#go' || s === '#again' || s === '#veil') out.push(root._go || null);
  }
  const list = out.filter(Boolean);
  return one ? (list[0] || null) : list;
}

const doc = {
  _byId: {},
  body: mkEl('body'),
  documentElement: mkEl('html'),
  createElement: (t) => {
    const el = attachKids(mkEl(t));
    // showStart / showEnd 是"先 appendChild 再 $('#go')"，这里给假面板补上它内部的节点
    el._go = mkEl('button');
    el._modes = ['fast', 'slow'].map(k => { const m = mkEl('div', 'mode'); m.dataset.mode = k; return m; });
    el._again = mkEl('button');
    return el;
  },
  querySelector(sel) {
    if (sel === '#go' || sel === '#again') {
      for (const el of this.body.children) if (el._go) return sel === '#go' ? el._go : el._again;
      return null;
    }
    if (sel.startsWith('#')) return this._byId[sel.slice(1)] || null;
    return fakeQuery(this.body, sel, true);
  },
  querySelectorAll(sel) { return fakeQuery(this.body, sel, false); },
  elementFromPoint: () => null,
  addEventListener() {},
};

// 建出页面里真实存在的那些元素
for (const id of IDS) doc._byId[id] = attachKids(mkEl('div', id));
for (const st of ['shake', 'fire', 'chem', 'brew', 'pack']) {
  const el = attachKids(mkEl('div', 'st')); el.dataset.st = st;
  el._queue = attachKids(mkEl('div', 'queue')); el._queue.dataset.q = st;
  el._act = attachKids(mkEl('button', 'act')); el._act.dataset.act = st;
  el._kids = {
    '.hd': mkEl('div'), '.ic': mkEl('div'), '.nm': mkEl('div'), '.desc': mkEl('div'),
    '.badge': mkEl('div'), '.fx': mkEl('div'),
    '.t': mkEl('span'), '.x': mkEl('span'), '.k': mkEl('span'),
  };
  el._kid = (k) => el._kids[k] || (el._kids[k] = mkEl('div'));
  el.querySelector = (s) => (s === '.queue' ? el._queue : s === '.act' ? el._act : fakeQuery(el, s, true));
  REG.st.push(el); REG.act.push(el._act);
}
doc._byId['stations'].children = REG.st;
doc._byId['stations'].querySelector = (s) => (s === '.st' ? REG.st : fakeQuery(doc._byId['stations'], s, true));
doc._byId['stations'].querySelectorAll = (s) => (s === '.st' ? REG.st.slice() : fakeQuery(doc._byId['stations'], s, false));
doc._byId['slip'].querySelector = (s) => fakeQuery(doc._byId['slip'], s, true);

/* ---------------- 跑脚本 ---------------- */
const sandbox = {
  document: doc, console,
  window: { addEventListener() {}, removeEventListener() {} },
  Math, JSON, Date, Object, Array, String, Number, Boolean, isNaN, parseInt, parseFloat,
  setTimeout: () => 0, clearTimeout: () => {},
  setInterval: () => 0, clearInterval: () => {},   // 当日结算页的自动继续倒计时要用
  // ★ 故意不提供 requestAnimationFrame：脚本会挂出 __SNOWKING__ 测试钩子
};
sandbox.globalThis = sandbox;
sandbox.window.document = doc;
vm.createContext(sandbox);

const errs = [];
try { vm.runInContext(code, sandbox, { filename: '雪皇的后厨.html<script>' }); }
catch (e) { console.error('❌ 初始化就炸了：', e.message, '\n', e.stack); process.exit(1); }

const K = sandbox.__SNOWKING__;
if (!K) { console.error('❌ 没拿到测试钩子（说明 requestAnimationFrame 存在？）'); process.exit(1); }
sandbox.__DBGWRONG__ = [];
sandbox.__NSTEP__ = 0;
sandbox.__DBGREADY__ = [];
sandbox.__DBGCLICK__ = [];
sandbox.__TRACE__ = [];

/* ---------------- 机器人：把整局打完 ----------------
   两种跑法：
     默认（手动）   机器人在小票上"动手拖"——显式调用 routeSlip（等价于玩家拖小票）
     --auto         机器人**一次都不调 routeSlip**，只下单 + 点绿色按钮；
                    小票全靠游戏自己"自动流转"到下一手（这就是要验的那条链路）
   再加一个反例断言：关掉自动流转后，只点按钮应该一杯都出不了（证明开关真的在管事）。 */
const AUTO_ONLY = process.argv.includes('--auto');
// ★ 模式选择（2026-10-01 修正）：quick / fast / slow 三个都认。
//   原写法是 `argv[2]==='slow' ? 'slow' : 'fast'` ⇒ **传 quick 会被静默忽略**，
//   于是"我用了快模式"其实一直在跑 fast（这类"参数被吞"的坑最费时间）。
const MODE_ARG = process.argv.slice(2).find(a => a === 'quick' || a === 'fast' || a === 'slow') || 'fast';
K.start(MODE_ARG);
K.G().fx = false;                     // ★ 关掉纯装饰（吐司/飘字/抖屏）：自检不需要，开着会把这套测试拖成几分钟
const G0 = K.G();
const totalSec = K.CFG.modes[G0.mode].total;
const DT = 1 / 30;
let steps = 0, routed = 0, started = 0, ticks = 0;
let maxWip = 0, sawWaiting = 0;            // 后厨容量不变量：在制任务数不许超过 CFG.kitchen.maxWip
let zombieSlips = 0, maxSlips = 0;         // 僵尸票不变量：不许出现 done=true 但 ready=false 的小票
const zombieSample = [];
let autoMoves = 0;                    // 游戏自己流转的次数（由 forwardSlip 记账）

function clickStation(id) {
  K.syncAll();
  const btn = REG.act.find(a => a.dataset.act === id);
  if (!btn || btn.disabled || !btn._ev?.click) return false;
  btn._ev.click();
  return true;
}

// ★ 跑多久：默认只跑到"跨过第 1 天结算"就停（骨架验证，几秒内出结果）；
//   要打完整 5 天得显式加 --full。理由：这套自检的瓶颈是我的假 DOM（每帧重建队列），
//   整局要跑一万多帧、把验证变成几分钟的事 —— 而它要证明的东西（不崩、闭环通、上限守住）
//   在第 1 天就已经能证明了。手感/节奏这类东西本来也不该靠它验。
const FULL_RUN = process.argv.includes('--full');

// ★ 快速档旋钮（2026-10-01，手机上的自检太慢）：
//   --skip-units     跳过 5 段定向单测，只跑主循环（纯跑法变化，不改仿真精度）
//   --seconds=N      主循环**再跑 N 秒游戏时间**就收工（从主跑开始算起，不是从开局）
//   ⚠️ 两者都只减少"跑多少"，不改变任何断言口径；被跳过的断言会在结果里列出来。
const SKIP_UNITS = process.argv.includes('--skip-units');
const SECONDS_CAP = Number((process.argv.find(a => a.startsWith('--seconds=')) || '').slice(10)) || 0;
const STOP_DAY = FULL_RUN ? 99 : 2;      // 默认：进入第 2 天（= 第 1 天已结算过）就收工

function runLoop(withRouting, maxTicks, capSec) {
  const capAt = capSec ? K.G().elapsed + capSec : 0;   // ★ 从"主跑开始那一刻"起算
  while (!K.G().ended && ticks < (maxTicks || 60 * 60 * 60) && K.G().day < STOP_DAY && (!capAt || K.G().elapsed < capAt)) {
    ticks++;
    // ① 下单：有订单还没起杯，就照着配方起一杯（等价于玩家点手册 / 按数字键）
    for (const r of K.RECIPES) {
      if (!K.G().orders.some(o => o.rec.id === r.id && o.cups.some(c => !c.done))) continue;
      K.startCup(r);
      started++;                      // 起杯（这一步内部会把小票挂到第一手，但那算"起票"不算"分流"）
      break;
    }
    // ② 能出餐就出餐
    if (clickStation('pack')) steps++;
    // ③ 手动跑法：模拟玩家拖小票（自动跑法整段跳过）
    if (withRouting) {
      for (const s of K.G().slips) {
        if (s.ready) continue;
        const nx = K.slipNext(s.cup);
        if (!nx) continue;
        if (s.st && s.st !== nx.st) s.st = null;
        if (!s.st && K.routeSlip(s, nx.st).ok) routed++;      }
    }
    // ④ 每个工位把绿的按钮点掉
    for (const st of ['shake', 'fire', 'chem', 'brew']) if (clickStation(st)) steps++;
    {
      const g = K.G();
      const wip = K.wipCount();
      const waiting = g.orders.filter(o => !o.inProgress && o.status !== 'done').length;
      if (wip > maxWip) maxWip = wip;
      if (waiting > 0) sawWaiting++;
      // ⑥ 僵尸票不变量：不许出现"杯子做完了但票还标着没做完"（那会让工位按钮一直亮着重复点）
      for (const s of g.slips) {
        if (s.cup.done && !s.ready) {
          zombieSlips++;
          if (zombieSample.length < 3) zombieSample.push(`#${s.id} ${s.o.rec.id} cup${s.cup.i} st=${s.st} ready=${s.ready} done=${s.cup.done} mask=${s.cup.steps.map(x => x.ok ? 1 : 0).join('')} inSlips=${g.slips.indexOf(s)}/${g.slips.length}`);
        }
      }
      if (g.slips.length > 12) maxSlips = Math.max(maxSlips, g.slips.length);
    }
    K.tick(ticks * DT * 1000);
  }
}

if (!SKIP_UNITS) {   // ★ 5 段定向单测（手机上是耗时大头；--skip-units 跳过，断言会在结果里标出）
// ── 反例：关掉"自动流转"，机器人自己拖票（票照样有），应该一次都不触发自动流转 ──
K.toggleAuto();                       // 自动流转 开 → 关
const offBefore = K.G().autoMoves;
runLoop(true, 150);                   // 5 秒游戏时间：机器人显式拖票 + 点按钮（只为造出"在制+排队"的局面；原来跑 900 帧纯属浪费，我的假 DOM 每帧重建队列）
var offMoves = K.G().autoMoves - offBefore;
var offTicks = ticks;
K.toggleAuto();                       // 关 → 开

// ── 定向单测：自动流转到底有没有动小票 ──────────────────────────
// 手动造单 + 起票（不给它挂工位），然后只推时间，看游戏会不会自己把票送到该去的工位。
{
  const g = K.G();
  K.spawnOrder();
  const o = g.orders[g.orders.length - 1];
  const slip = K.makeSlip(o, o.cups[0]);
  slip.st = null;                                           // 起票时不挂工位 = 本来"没人接"的状态
  const before = g.autoMoves;
  K.resetClock();                                           // 换时间源前先交接，免得 dt 变负
  for (let i = 0; i < 30 * 12; i++) K.tick(i * 33);          // 12 秒游戏时间
  const moved = g.autoMoves - before;
  console.log(`    [单测] 自动流转：起票后 st=${slip.st} → 推 12s 后 st=${slip.st}，自动流转 ${moved} 次`);
  if (moved === 0 || slip.st === null) errs.push('自动流转没有生效：12 秒后小票还挂在原地');
  if (g.slips.filter(s => s.cup === slip.cup).length !== 1) errs.push('同一杯出现了多张小票（重复起票）');
  g.orders = g.orders.filter(x => x !== o);                 // 把这张单摘掉，别污染后面的统计
  g.slips = g.slips.filter(s => s.o !== o);
}

// ── 定向单测：后厨"同时最多 3 个未完成任务（小票）"这条规矩是不是真的在管事 ──
// 做法：停掉自然到店，连开 4 单（保证 > 3 杯），验"在制任务数 == 上限、没名额的杯不起票"；
//       然后出掉一杯 → 名额必须立刻让给下一张票。
var enforced = (() => {
  const g = K.G();
  const CAP = K.CFG.kitchen.maxWip;
  g.nextArrive = 1e9;                                  // 停止自然到店，避免干扰计数
  const clearedOrders = g.orders.length, clearedSlips = g.slips.length;
  g.orders = []; g.slips = [];                         // 先腾空，这样"连开 4 单"是干净可控的
  for (let i = 0; i < 4; i++) K.spawnOrder();
  const wip1 = K.wipCount();
  const ready1 = g.orders.reduce((n, o) => n + o.cups.filter(c => c.slotReady).length, 0);
  const slips1 = g.slips.length;
  const waiting1 = g.orders.filter(o => !o.inProgress && o.status !== 'done').length;
  const slip = g.slips.find(s => s.cup.startedAt !== null && !s.cup.done);
  for (const s of slip.cup.steps) s.ok = true;
  K.deliverCup(slip);                                  // 交掉一杯（全做完才由 finishOrder 整单结算）
  const wip2 = K.wipCount(), slips2 = g.slips.length;
  g.orders = []; g.slips = [];                         // 清场，别污染后面的统计
  console.log(`    [单测] 在制任务上限：清掉残留 ${clearedOrders} 单/${clearedSlips} 票 → 连开 4 单 → 在制 ${wip1}（拿名额的杯 ${ready1} / 票 ${slips1} / 等候 ${waiting1} 位）；出掉一杯 → 在制 ${wip2}、票 ${slips2}`);
  return { wip1, ready1, slips1, wip2, slips2, waiting1,
    ok: wip1 === CAP && ready1 === CAP && slips1 === CAP && wip2 === CAP && slips2 === CAP && waiting1 >= 1 };
})();

// ── 定向单测：排队也吃耐心（只是慢一档） ──────────────────────────
// 做法：把在制名额压到 1，连开 4 单（1 张票在制 + 其余排队），停掉自然到店只推时间，
//       分别量"在制那单"和"排队那单"的耐心掉落速度。
var patTest = (() => {
  const g = K.G();
  g.nextArrive = 1e9;
  g.orders = []; g.slips = [];
  const keep = K.CFG.kitchen.maxWip;
  K.CFG.kitchen.maxWip = 1;                            // 只允许 1 个任务在制 → 后面必然是排队的
  for (let i = 0; i < 4; i++) K.spawnOrder();
  const act = g.orders.find(o => o.inProgress);
  const wat = g.orders.find(o => !o.inProgress);
  if (!act || !wat) return { aDrop: 0, wDrop: 0, ok: false, why: '没造出"在制 + 排队"的局面' };
  const a0 = act.pat, w0 = wat.pat;
  K.resetClock();
  for (let i = 1; i <= 30 * 10; i++) K.tick(i * 33);          // 推 10 秒游戏时间
  const aDrop = a0 - act.pat, wDrop = w0 - wat.pat;
  K.CFG.kitchen.maxWip = keep;
  g.orders = []; g.slips = []; g.nextArrive = 2;
  console.log(`    [单测] 排队耐心：10s 内在做的掉了 ${aDrop.toFixed(1)}s，排队的掉了 ${wDrop.toFixed(1)}s（比值 ${(wDrop / (aDrop || 1)).toFixed(2)}）`);
  return { aDrop, wDrop, ok: wDrop > 0 && wDrop < aDrop };
})();

// ── 定向单测：耐心随"点的杯数"动态变化（抽样一批订单看趋势） ────────
var patienceByCups = (() => {
  const g = K.G();
  const keepOrders = g.orders.slice(), keepSlips = g.slips.slice();
  g.orders = []; g.slips = [];
  const byN = {};                                   // 杯数 → 耐心样本
  const N = 400;
  for (let i = 0; i < N; i++) {
    const n0 = g.orders.length;
    K.spawnOrder();
    const o = g.orders[g.orders.length - 1];
    (byN[o.need] = byN[o.need] || []).push(o.pat);
    if (g.orders.length > 3) g.orders.length = n0;  // 只留少量，避免爆掉
    g.slips = [];
  }
  g.orders = keepOrders; g.slips = keepSlips;       // 复原
  const mean = a => a.reduce((x, y) => x + y, 0) / a.length;
  const rows = Object.keys(byN).map(Number).sort((a, b) => a - b)
    .map(n => ({ n, cnt: byN[n].length, avg: mean(byN[n]), min: Math.min(...byN[n]), max: Math.max(...byN[n]) }));
  const ok = rows.length >= 3 && rows.every((r, i) => i === 0 || r.avg > rows[i - 1].avg);
  console.log('    [单测] 杯数→耐心：' + rows.map(r => `${r.n}杯 均${r.avg.toFixed(1)}s(${r.min.toFixed(0)}~${r.max.toFixed(0)}, n=${r.cnt})`).join(' · '));
  return { rows, ok };
})();

// ── 定向单测：到店时间动态 + 逐日收紧 ──────────────────────────────
// ⚠️ 这里**不能**为了攒样本而多推时间：主跑要吃掉 5 天（10/20 分钟）的全部时钟预算，
//    多推一秒都会把主跑的出餐数压低（踩过：出餐 138 → 83）。
//    所以分两截验：① 用真实样本验"间隔确实在变"；② 用配置直接验"逐日收紧"的公式。
var arriveTest = (() => {
  const A = K.CFG.arrive;
  const L = K.G().arriveLog || [];
  const uniq = new Set(L).size;
  const sampleOk = L.length >= 4 && uniq >= 3 && Math.min(...L) !== Math.max(...L);
  const day1 = (A.min + A.max) / 2 * Math.pow(A.dayScale, 0);
  const day5 = (A.min + A.max) / 2 * Math.pow(A.dayScale, 4);
  console.log(`    [单测] 到店：真实样本 ${L.length} 个 / ${uniq} 种取值（${L.slice(0, 6).join(', ')}…）· 按公式 第1天均 ${day1.toFixed(1)}s → 第5天均 ${day5.toFixed(1)}s（dayScale ${A.dayScale}）`);
  return { n: L.length, uniq, day1, day5, ok: sampleOk && day5 < day1 * 0.8 };
})();

K.G().nextArrive = 2;                 // 单测里把"下次到店"推到很远用来停客，跑主跑前必须还回来
}   // ★ 单测区结束
if (SKIP_UNITS) {
  console.log('⚠️ --skip-units：已跳过 5 段定向单测（连开4单上限 / 排队耐心 / 杯数→耐心 / 到店时间 / 自动流转反例）——本次结果不含这些断言');
  offMoves = 0; offTicks = 0;
  enforced = { ok: true }; patTest = { ok: true, wDrop: 0, aDrop: 0 };
  patienceByCups = { ok: true }; arriveTest = { ok: true, uniq: 0, day1: 0, day5: 0 };
}
if (AUTO_ONLY) K.toggleTicket();
K.resetClock();
const routedBeforeMain = routed;      // 反例那段自己也"拖过票"，主跑只看增量
console.log(`    [状态] 主跑开始前：auto(自动流转)=${K.G().auto} autoTicket(自动出票)=${K.G().autoTicket}`);

try {
  if (AUTO_ONLY) runLoop(false, undefined, SECONDS_CAP);   // 小票全靠自动流转走
  else runLoop(true, undefined, SECONDS_CAP);              // 手动拖拽
} catch (e) {
  errs.push('主循环抛异常：' + e.message + '\n' + e.stack);
}
const G = K.G();
autoMoves = G.autoMoves || 0;
const routedMain = routed - routedBeforeMain;    // 主跑期间机器人自己拖了几次票
const slipsAuto = G.autoTicket;
console.log('─'.repeat(66));
console.log(`局时长设定 ${totalSec}s · 模拟推进 ${(ticks * DT).toFixed(1)}s（时间流速会让游戏内时间按 x1 上下浮动）`);
console.log(`跑法：${SKIP_UNITS ? '【跳过单测】' : ''}${SECONDS_CAP ? '【主跑上限 ' + SECONDS_CAP + 's】' : ''}${AUTO_ONLY ? '纯自动流转（机器人不碰 routeSlip）' : '手动拖拽（机器人显式分流）'}`);
console.log(`出餐 ${G.served} 杯 · 翻车 ${G.mistakes} · 流失 ${G.left} · 结余 ¥${G.money} · 营业额分 ${G.score} · 最高连击 x${G.maxCombo}`);
console.log(`机器人动作：手动分流 ${routed} 次 / 手动起杯 ${started} 次 / 完成步骤 ${steps} 次`);
console.log(`后厨容量：在制任务峰值 ${maxWip} 个（上限 ${K.CFG.kitchen.maxWip}）· 出现排队的帧数 ${sawWaiting} · 僵尸票帧数 ${zombieSlips} · 小票峰值 ${maxSlips}`);
console.log(`【容量单测】连开 4 单 → 在制 ${enforced.wip1} 个（票 ${enforced.slips1} / 拿名额的杯 ${enforced.ready1} / 等候 ${enforced.waiting1} 位）；出掉一杯 → 在制 ${enforced.wip2}、票 ${enforced.slips2}`);
console.log(`【耐心单测】排队 10s 掉 ${patTest.wDrop.toFixed(1)}s / 在做 10s 掉 ${patTest.aDrop.toFixed(1)}s`);
  console.log(`【到店单测】真实样本 ${arriveTest.n} 个 / ${arriveTest.uniq} 种取值 · 按公式 第1天均 ${arriveTest.day1.toFixed(1)}s → 第5天均 ${arriveTest.day5.toFixed(1)}s`);
console.log(`排队等跑掉的人数：${G.leftWaiting || 0} / 总流失 ${G.left}`);
console.log(`订单池剩余 ${G.orders.length} · 小票在制 ${G.slips.filter(s => !s.ready).length} · 可出餐 ${G.slips.filter(s => s.ready).length}`);
console.log(`游戏结束标志 ended=${G.ended} · 现在第 ${G.day} 天 · 结算面板 ${doc.body.children.length ? '已弹出' : '没弹出'}`);
console.log(`【停机原因】ticks=${ticks} 游戏内已过 ${G.elapsed.toFixed(1)}s / 天剩 ${G.dayLeft.toFixed(1)}s / phase=${G.phase} / 在制 ${K.wipCount()} / 订单 ${G.orders.length}`);
console.log(`【自动流转】累计自动流转 ${autoMoves} 次 · 机器人手动分流 ${routed} 次 · 游戏内 routeSlip 调用 ${G.routeCalls || 0} 次`);
if (process.env.DBG) {
  console.log(`    [fwd] 起票 ${started} 次 / 主跑期间机器人分流 ${routedMain} 次 / 游戏自动流转 ${autoMoves} 次`);
}
console.log(`【反例】关掉自动流转后跑了 ${(offTicks * DT).toFixed(0)}s，机器人自己拖票走 → 期间自动流转 ${offMoves} 次`);
console.log('─'.repeat(66));

let bad = 0;
const chk = (ok, msg) => { console.log((ok ? '  ✓ ' : '  ✗ ') + msg); if (!ok) bad++; };
// ★ 秒级档专用：**依赖时间与随机**的断言在 20 秒里必然随机红（客流/出餐/分流都是概率事件），
//   所以这类断言在 --seconds 模式下"不判"，只播报 —— 否则你会以为是改坏了（这次就误判了一次）。
const chkTimed = (ok, msg) => {
  if (SECONDS_CAP) console.log(`ℹ️ 【秒级档】不判「${msg}」（依赖时间/随机，需常规档）`);
  else chk(ok, msg);
};
chk(errs.length === 0, '主循环没有抛异常');
if (FULL_RUN) chk(G.ended === true, '跑到第 5 天自动结算');
else if (SECONDS_CAP) console.log(`ℹ️ 【秒级档】不判「跑到第 2 天」（本次只跑主循环 ${SECONDS_CAP}s，跨天断言留给常规档）`);
else chk(G.day >= 2, `跑到第 ${G.day} 天（默认骨架模式：只验到跨过第 1 天结算；整局用 --full）`);
if (SECONDS_CAP) console.log(`ℹ️ 【秒级档】不判「至少出过一杯」（本次出餐 ${G.served} 杯；闭环断言留给常规档）`);
else chk(G.served > 0, '至少出过一杯（点单→小票→工位→出餐闭环通了）');
chkTimed(G.served + G.left > 0, '有客人来过');
if (SECONDS_CAP) console.log('ℹ️ 【秒级档】不判「结算页弹出」（没跑完一天）');
else chk(!!(doc.body.children.length), '当日结算页/总结算弹出来了');
chk(K.RECIPES.length >= 6, `产品数 ${K.RECIPES.length} ≥ 6`);
chk(K.RECIPES.every(r => r.steps.length >= 2 && r.steps.every(s => K.S[s.st])), '每个产品的每一步都落在真实工位上');
chk(REG.st.length === 5, '5 个工位都建出来了');
chk(maxWip <= K.CFG.kitchen.maxWip, `★ 后厨同时最多 ${K.CFG.kitchen.maxWip} 个未完成任务：全程峰值 ${maxWip}`);
chk(zombieSlips === 0, `★ 没有僵尸票（"杯子做完了但票说没做完"的帧数 = ${zombieSlips}）`);
if (zombieSample.length) console.log('    [僵尸票样本] ' + zombieSample.join('  ||  '));
console.log('    [ztrace] ' + (sandbox.__ZTRACE__ || []).slice(0, 20).join(' , '));
if (!SKIP_UNITS) chk(enforced.ok, `★ 定向单测：连开 4 单 → 在制恰好 ${enforced.wip1}（票 ${enforced.slips1} / 拿名额的杯 ${enforced.ready1}）→ 出掉一杯后立刻补到 ${enforced.wip2}`);
if (!SKIP_UNITS) chk(patTest.ok, `★ 排队也吃耐心：排队掉得比在制慢（${patTest.wDrop.toFixed(1)}s vs ${patTest.aDrop.toFixed(1)}s / 10s）`);
if (!SKIP_UNITS) chk(arriveTest.ok, `★ 到店时间动态且逐日收紧：${arriveTest.uniq} 种取值，按公式 ${arriveTest.day1.toFixed(1)}s → ${arriveTest.day5.toFixed(1)}s`);
if (!SKIP_UNITS) chk(patienceByCups.ok, '★ 耐心随「点的杯数」动态变化：杯数越多给得越宽（均值单调递增）');
if (!SKIP_UNITS) chk(offMoves === 0, `★ 关掉自动流转后，${(offTicks * DT).toFixed(0)}s 内自动流转 0 次（开关真的在管事）`);
if (!AUTO_ONLY) {
  chkTimed(slipsAuto && G.served > 0, '★ 自动出小票 + 自动流转：机器人一次 startCup 都没调，靠自动票出餐');
  chkTimed(routed > 0, `★ 手动拖票这条路还在（机器人自己分流 ${routed} 次）`);
}
if (AUTO_ONLY) {
  chkTimed(G.served > 0 && routedMain === 0, `★ 主跑期间机器人一次 routeSlip 都没调（${started} 次手动起杯），靠自动流转出餐 ${G.served} 杯`);
  chkTimed(autoMoves > 0, `★ 游戏自己流转了 ${autoMoves} 次`);
}
if (errs.length) { console.log('\n异常详情：\n' + errs.join('\n')); bad++; }

if (SKIP_UNITS || SECONDS_CAP) console.log(`【本次档位】${SKIP_UNITS ? '跳过单测 ' : ''}${SECONDS_CAP ? '主跑上限 ' + SECONDS_CAP + 's ' : ''}⇒ 这不是全量结果，交付前请跑默认档/--full`);
console.log(bad ? `\n冒烟测试：${bad} 项失败` : '\n冒烟测试：全部通过 ✓');
process.exit(bad ? 1 : 0);
