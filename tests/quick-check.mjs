// 快速核对两件事（每次只跑几秒）：
//   ① 同一杯**不能**有多张票（重复票 bug）
//   ② 后厨同时只能有 3 个未完成任务（你要的那条规矩）
//   node tests/quick-check.mjs
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const ROOT = path.resolve(import.meta.dirname, '..');
const html = fs.readFileSync(path.join(ROOT, '雪皇的后厨.html'), 'utf8');
const i = html.indexOf('<script>'), j = html.lastIndexOf('</script>');
const code = html.slice(i + 8, j);

/* 极简假 DOM（只够脚本初始化 + syncAll 用） */
const IDS = ['daybar','clock','clk','clksub','btnPause','btnRestart','btnAuto','btnTicket','orders','orderCount',
  'sMoney','sRent','sServed','sBad','sCombo','sAuto','sKitchen','sArrive','sLeftWait','hint','live','stations','book',
  'slip','slipT','slipS','ghostCursor','toasts','flash','pack','rdyBadge','veil'];
const mk = (t = 'div', c = '') => {
  const el = { tagName: t.toUpperCase(), className: c, dataset: {}, children: [], style: {}, _html: '',
    textContent: '', disabled: false, title: '', parentNode: null,
    classList: { add() {}, remove() {}, toggle() {}, contains: () => false },
    set innerHTML(v) { el._html = v; el.children = []; }, get innerHTML() { return el._html; },
    appendChild(x) { x.parentNode = el; el.children.push(x); return x; },
    removeChild(x) { el.children = el.children.filter(y => y !== x); },
    remove() {}, addEventListener() {}, removeEventListener() {},
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 100, height: 40 }),
    get firstChild() { return el.children[0] || null; } };
  el._kids = {};
  el._kid = k => el._kids[k] || (el._kids[k] = mk());
  el.querySelector = s => el._kid(s);
  el.querySelectorAll = () => [];
  return el;
};
const REG = { st: [] };
const doc = {
  _byId: {}, body: mk(), documentElement: mk(),
  createElement: t => { const e = mk(t); e._go = mk('button'); e._modes = []; e._again = mk('button'); return e; },
  querySelector(sel) {
    if (sel === '#go' || sel === '#again') {          // 开局面板/结算是先 append 再 $()
      for (const el of this.body.children) if (el._go) return sel === '#go' ? el._go : el._again;
      return mk('button');
    }
    if (sel.startsWith('#')) return this._byId[sel.slice(1)] || null;
    if (sel.startsWith('.st[data-st=')) return REG.st.find(x => x.dataset.st === sel.match(/"(.*?)"/)[1]) || mk();
    if (sel.startsWith('.act')) return mk('button');
    return mk();
  },
  querySelectorAll: () => [], elementFromPoint: () => null, addEventListener() {},
};
for (const id of IDS) doc._byId[id] = mk('div', id);
for (const st of ['shake', 'fire', 'chem', 'brew', 'pack']) {
  const e = mk('div', 'st'); e.dataset.st = st; e._queue = mk(); e._act = mk('button');
  e.querySelector = s => (s === '.queue' ? e._queue : s === '.act' ? e._act : e._kid(s));
  REG.st.push(e);
}
doc._byId['stations'].querySelectorAll = () => REG.st;
doc._byId['stations'].querySelector = s => (s === '.st' ? REG.st[0] : mk());

const sandbox = { document: doc, console, window: { addEventListener() {}, removeEventListener() {} },
  Math, JSON, Date, Object, Array, String, Number, Boolean, isNaN, parseInt, parseFloat,
  setTimeout: () => 0, clearTimeout: () => {} };
sandbox.globalThis = sandbox;
sandbox.window.document = doc;
vm.createContext(sandbox);
vm.runInContext(code, sandbox, { filename: 'snowking<script>' });
const K = sandbox.__SNOWKING__;

K.start('fast');
const G = K.G();
const CAP = K.CFG.kitchen.maxWip;
G.nextArrive = 1e9;                    // 手动造单，别让到店插进来
G.orders = []; G.slips = [];

/* ① 连开 8 单，看：在制杯数 ≤ 3、同一杯只有一张票 */
for (let n = 0; n < 8; n++) K.spawnOrder();
const wip = K.wipCount();
const perCup = {};
for (const s of G.slips) perCup[s.cup] = (perCup[s.cup] || 0) + 1;
const dupCups = Object.values(perCup).filter(v => v > 1).length;
const slotReady = G.orders.reduce((a, o) => a + o.cups.filter(c => c.slotReady).length, 0);
console.log(`① 连开 8 单（共 ${G.orders.reduce((a, o) => a + o.need, 0)} 杯，${G.orders.length} 单）`);
console.log(`   在制任务 = ${wip}（上限 ${CAP}）· 拿到开工名额的杯 = ${slotReady} · 已起票 = ${G.slips.length} · 重复票的杯 = ${dupCups}`);
console.log(`   票明细：${G.slips.map(s => `#${s.id}(杯${s.cup.i}@${s.o.rec.id},st=${s.st})`).join(' ')}`);

/* ② 反复"出餐一杯"，看名额是不是一张一张补、且永远不超 3 */
let maxWip = wip, maxDup = dupCups;
for (let k = 0; k < 6; k++) {
  const slip = G.slips.find(s => s.cup.startedAt !== null && !s.cup.done);
  if (!slip) break;
  for (const st of slip.cup.steps) st.ok = true;
  K.deliver(slip);
  const w = K.wipCount();
  maxWip = Math.max(maxWip, w);
  const cnt = {};
  for (const s of G.slips) cnt[s.cup] = (cnt[s.cup] || 0) + 1;
  maxDup = Math.max(maxDup, Object.values(cnt).filter(v => v > 1).length);
  console.log(`   出餐第 ${k + 1} 杯 → 在制 ${w} · 票 ${G.slips.length} · 出餐累计 ${G.served}`);
}

let bad = 0;
const chk = (ok, msg) => { console.log((ok ? '  ✓ ' : '  ✗ ') + msg); if (!ok) bad++; };
chk(maxWip <= CAP, `后厨同时最多 ${CAP} 个未完成任务：实测峰值 ${maxWip}`);
chk(maxDup === 0, `同一杯没有重复票：重复峰值 ${maxDup}`);
chk(G.served >= 1, `出餐链路通：累计出餐 ${G.served} 杯`);
console.log(bad ? `\n✗ ${bad} 项不合格` : '\n✓ 两条规矩都守住了');
process.exit(bad ? 1 : 0);
