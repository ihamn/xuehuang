// 澶嶇幇"鐜拌悆閫熸憾鍜栧暋鍑洪閫昏緫鐤戜技寰幆"锛?//   node tests/repro-instcoffee.mjs
// 鎵嬫硶锛氳嚜宸遍€犱竴鍗?鐜拌悆閫熸憾鍜栧暋"锛堜笉闈犻殢鏈猴級锛屼粠璧风エ鍒板嚭椁愪竴姝ユ鎵撴棩蹇楋紝
//        鐪嬫湁娌℃湁鍝竴姝ヨ鍙嶅鍋氥€佹垨鑰呭崱浣忎笉璧般€?// 鑳屾櫙锛氳繖涓厤鏂规槸涓ソ鐢ㄧ殑鏋佺鏍锋湰 鈥斺€?4 姝ラ噷鏈?3 姝ュ湪鍚屼竴涓伐浣嶏紙钀冭尪鍖猴級锛?//        姝ｅソ鍘嬪埌"灏忕エ鍦ㄥ悓涓€涓伐浣嶈繛缁仛澶氭"鍜?鏈€鍚庝竴姝ユ槸鎵撳寘鍙?杩欎袱鏉¤竟鐣屻€?import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const ROOT = path.resolve(import.meta.dirname, '..');
const html = fs.readFileSync(path.join(ROOT, '闆帇鐨勫悗鍘?html'), 'utf8');
const i = html.indexOf('<script>'), j = html.lastIndexOf('</script>');
const code = html.slice(i + 8, j);

/* ---------------- 鏋佺畝鍋?DOM锛堜笌 smoke.mjs 鍚屾锛?---------------- */
const IDS = ['daybar','clock','clk','clksub','btnPause','btnRestart','btnAuto','btnTicket','orders','orderCount',
  'sMoney','sRent','sServed','sBad','sCombo','sAuto','sKitchen','sArrive','sLeftWait','hint','live','stations','book',
  'slip','slipT','slipS','ghostCursor','toasts','flash','pack','rdyBadge','veil'];

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
    get firstChild() { return el.children[0] || null; },
  };
  return el;
}
function attachKids(el) {
  el._kids = el._kids || {};
  el._kid = (k) => el._kids[k] || (el._kids[k] = attachKids(mkEl('div')));
  el.querySelector = (s) => fakeQuery(el, s, true);
  el.querySelectorAll = (s) => fakeQuery(el, s, false);
  return el;
}
const REG = { st: [], act: [] };
function fakeQuery(root, sel, one) {
  const out = [];
  for (const s of sel.split(',').map(x => x.trim())) {
    if (s === '.st') out.push(...REG.st);
    else if (s.startsWith('.st[data-st=')) out.push(REG.st.find(x => x.dataset.st === s.match(/"(.*?)"/)[1]));
    else if (s === '.act') out.push(...REG.act);
    else if (s.startsWith('.act[data-act=')) out.push(REG.act.find(x => x.dataset.act === s.match(/"(.*?)"/)[1]));
    else if (s === '.queue') out.push(root._queue);
    else out.push(root._kid(s));
  }
  const list = out.filter(Boolean);
  return one ? (list[0] || null) : list;
}
const doc = {
  _byId: {}, body: mkEl('body'), documentElement: mkEl('html'),
  createElement: (t) => { const el = attachKids(mkEl(t)); el._go = mkEl('button'); el._modes = []; el._again = mkEl('button'); return el; },
  querySelector(sel) {
    if (sel === '#go' || sel === '#again') return mkEl('button');
    if (sel.startsWith('#')) return this._byId[sel.slice(1)] || null;
    return fakeQuery(this.body, sel, true);
  },
  querySelectorAll(sel) { return fakeQuery(this.body, sel, false); },
  elementFromPoint: () => null, addEventListener() {},
};
for (const id of IDS) doc._byId[id] = attachKids(mkEl('div', id));
for (const st of ['shake', 'fire', 'chem', 'brew', 'pack']) {
  const el = attachKids(mkEl('div', 'st')); el.dataset.st = st;
  el._queue = attachKids(mkEl('div', 'queue')); el._queue.dataset.q = st;
  el._act = attachKids(mkEl('button', 'act')); el._act.dataset.act = st;
  REG.st.push(el); REG.act.push(el._act);
}
doc._byId['stations'].querySelector = (s) => (s === '.st' ? REG.st : fakeQuery(doc._byId['stations'], s, true));
doc._byId['stations'].querySelectorAll = (s) => (s === '.st' ? REG.st.slice() : fakeQuery(doc._byId['stations'], s, false));

const sandbox = {
  document: doc, console,
  window: { addEventListener() {}, removeEventListener() {} },
  Math, JSON, Date, Object, Array, String, Number, Boolean, isNaN, parseInt, parseFloat,
  setTimeout: () => 0, clearTimeout: () => {}, setInterval: () => 0, clearInterval: () => {},
};
sandbox.globalThis = sandbox;
sandbox.window.document = doc;
vm.createContext(sandbox);
vm.runInContext(code, sandbox, { filename: 'snowking<script>' });
const K = sandbox.__SNOWKING__;
const CAP = K.CFG.kitchen.maxWip;

/* ---------------- 鑷繁閫犱竴鍗?鐜拌悆閫熸憾鍜栧暋" ---------------- */
const RECIPE = 'instcoffee';
K.start('fast');
const G = K.G();
G.nextArrive = 1e9;                        // 鍙墜鍔ㄩ€犲崟锛屽埆璁╄嚜鐒跺埌搴楁彃杩涙潵
G.orders = []; G.slips = [];
const rec = K.RECIPES.find(r => r.id === RECIPE);
const o = {
  id: ++G.oid, name: 'TEST', rec, ice: 'normal', sugar: 'normal',
  cups: [], need: 1, pat: 99, patMax: 99, born: G.elapsed,
  made: 0, delivered: 0, status: 'wait', grew: false,
  priority: false, inProgress: false, queueNo: 0, waitAnnounced: false
};
o.cups.push({ i: 0, err: false, done: false, startedAt: null, finishedAt: null, slotReady: false, steps: rec.steps.map(s => ({ ...s, ok: false })) });
G.orders.push(o);
K.refreshSlots();
const cup = o.cups[0];

console.log('-'.repeat(72));
console.log(`order #${o.id}: ${o.rec.name} (${o.rec.id}) 路 ${o.need} cup 路 steps:`);
cup.steps.forEach((s, k) => console.log(`   ${k + 1}. [${K.S[s.st].name}] ${s.t}`));
console.log(`slots: slotReady=${cup.slotReady} 路 wip=${K.wipCount()}/${CAP}`);
console.log('-'.repeat(72));

// 鈽?娉ㄦ剰锛歳efreshSlots() 閲?鑷姩鍑哄皬绁?宸茬粡缁欒繖寮犳澂璧疯繃绁ㄤ簡 鈥斺€?鐩存帴鐢ㄥ畠锛?//   鍒啀閫犵浜屽紶锛堟垜绗竴鐗堝氨鏄嚜宸?makeSlip 閫犱簡閲嶅绁紝鎵嶇湅鎴?寰幆"锛夈€?K.refreshSlots();
let slip = G.slips.find(s => s.cup === cup);
if (!slip) { slip = K.makeSlip(o, cup); }
const route1 = K.routeSlip(slip, slip.st || cup.steps[0].st);
console.log(`slip=#${slip.id} (鏉?${cup.i}) 路 route -> ${cup.steps[0].st}  ${route1.ok ? 'ok' : 'REJECT: ' + route1.why}`);
console.log(`鍚屼竴鏉殑灏忕エ鏁帮紙蹇呴』涓?1锛夛細${G.slips.filter(s => s.cup === cup).length}`);
console.log('-'.repeat(72));

const log = [];
let guard = 0, delivered = false;
while (!delivered && guard++ < 60) {
  K.syncAll();
  const nx = K.slipNext(cup);
  const packReady = cup.done && slip.ready;
  const id = packReady ? 'pack' : (cup.done ? 'pack' : nx.st);
  const btn = REG.act.find(a => a.dataset.act === id);
  const armed = btn && !btn.disabled && btn._ev?.click;
  if (!armed) { log.push(`STUCK: station ${id} button not armed (disabled=${btn && btn.disabled})`); break; }
  const before = cup.steps.filter(s => s.ok).length;
  const label = btn.querySelector('.t').textContent;
  const slipsBefore = G.slips.length;
  btn._ev.click();
  const after = cup.steps.filter(s => s.ok).length;
  log.push(`click [${id}] "${label}"  ok ${before}->${after}  ready=${slip.ready} done=${cup.done} wip=${K.wipCount()} slips=${slipsBefore}->${G.slips.length} inList=${G.slips.includes(slip)} sameObj=${G.slips[0] === slip}`);
  if (guard > 6) break;
  if (cup.done && slip.ready) {
    K.syncAll();
    const pb = REG.act.find(a => a.dataset.act === 'pack');
    if (pb && !pb.disabled && pb._ev?.click) {
      pb._ev.click();
      delivered = !G.slips.includes(slip);
      log.push(`deliver -> delivered=${delivered} served=${G.served}`);
    }
  }
  K.tick(guard * 33);
}
console.log(log.join('\n'));
console.log('-'.repeat(72));
console.log(`actions=${guard} delivered=${delivered} slips_left=${G.slips.length} steps_done=${cup.steps.filter(s => s.ok).length}/${cup.steps.length}`);
const bad = [];
if (!delivered) bad.push('NOT DELIVERED (stuck)');
if (guard > 12) bad.push(`too many actions (${guard}) - possible loop`);
if (G.slips.length) bad.push(`${G.slips.length} slips left`);
console.log(bad.length ? 'FAIL: ' + bad.join(' / ') : 'PASS: instcoffee chain is fine (no loop)');
process.exit(bad.length ? 1 : 0);

