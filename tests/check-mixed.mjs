// 鍙煡涓€浠朵簨锛氭贩鐐硅鍗曠殑**绗簩鏉?*鑳戒笉鑳借繘鍚庡帹锛堟嬁鍒板悕棰?+ 鍑虹エ + 鑳藉紑宸ワ級
//   node tests/check-mixed.mjs
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
const ROOT = path.resolve(import.meta.dirname, '..');
const html = fs.readFileSync(path.join(ROOT, '闆帇鐨勫悗鍘?html'), 'utf8');
const i = html.indexOf('<script>'), j = html.lastIndexOf('</script>');
const code = html.slice(i + 8, j);

const mk = () => {
  const el = { dataset: {}, children: [], style: {}, classList: { add() {}, remove() {}, toggle() {}, contains: () => false },
    _html: '', textContent: '', appendChild() {}, removeChild() {}, remove() {}, addEventListener() {}, removeEventListener() {},
    querySelector: () => mk(), querySelectorAll: () => [], getBoundingClientRect: () => ({ left: 0, top: 0, width: 0, height: 0 }),
    set innerHTML(v) { el._html = v; }, get innerHTML() { return el._html; }, get firstChild() { return null; } };
  return el;
};
const doc = { _byId: {}, body: mk(), createElement: () => mk(), addEventListener() {}, elementFromPoint: () => null,
  querySelector: s => (s === '#go' || s === '#again' ? mk() : (doc._byId[s.slice(1)] || mk())), querySelectorAll: () => [] };
const sandbox = { document: doc, console, window: { addEventListener() {}, removeEventListener() {} },
  Math, JSON, Date, Object, Array, String, Number, Boolean, isNaN, parseInt, parseFloat,
  setTimeout: () => 0, clearTimeout: () => {} };
sandbox.globalThis = sandbox; sandbox.window.document = doc;
vm.createContext(sandbox);
vm.runInContext(code, sandbox, { filename: 'snowking<script>' });
const K = sandbox.__SNOWKING__;
K.start('fast');
const G = K.G();
G.nextArrive = 1e9;                 // 鍙墜鍔ㄩ€犲崟
G.fx = false;

// 閫犱竴涓?蹇呭畾涓ゆ澂娣风偣"鐨勫崟锛氱洿鎺ョ収 drinkPlan 鐨勭粨鏋勬墜鎼擄紝閬垮厤闅忔満
function makeMix(){
  const a = K.RECIPES.find(r => r.id === 'newton');     // 5 姝ワ紝杞?  const b = K.RECIPES.find(r => r.id === 'instcoffee'); // 4 姝ワ紝鍏?tap
  return { a, b };
}
const { a, b } = makeMix();
G.orders = []; G.slips = [];
const o = {
  id: ++G.oid, name: 'TEST', rec: a, lines: [{ rec: a, n: 1 }, { rec: b, n: 1 }], ice: '姝ｅ父', sugar: '姝ｅ父绯?,
  cups: [], need: 2, pat: 200, patMax: 200, born: G.elapsed, made: 0, delivered: 0, status: 'wait',
  priority: false, inProgress: false, queueNo: 0, waitAnnounced: false, patBonus: 0,
  makeup: `1脳${a.name} + 1脳${b.name}`,
};
let idx = 0;
for (const line of o.lines) for (let k = 0; k < line.n; k++) {
  o.cups.push({ i: idx++, rec: line.rec, err: false, done: false, startedAt: null, finishedAt: null, slotReady: false,
    steps: line.rec.steps.map(s => ({ ...s, ok: false, done: 0 })) });
}
G.orders.push(o);
K.refreshSlots();

const cup0 = o.cups[0], cup1 = o.cups[1];
const t = (c) => `鏉?{c.i}(${c.rec.id}) slotReady=${c.slotReady} 绁?${G.slips.some(s => s.cup === c) ? '鏈? : '娌℃湁'} startedAt=${c.startedAt}`;
console.log(`鍦ㄥ埗鍚嶉涓婇檺 ${K.CFG.kitchen.maxWip} 路 璁㈠崟 ${o.makeup}`);
console.log('  閫犲崟鍚? : ' + t(cup0) + ' | ' + t(cup1));

// 鎶婂悕棰濆帇鍒?1锛屾ā鎷?娣风偣璁㈠崟鐨勭浜屾澂鎶笉鍒板悕棰?杩欑鏈€鍧忔儏鍐?K.CFG.kitchen.maxWip = 1;
G.orders = [o]; G.slips = [];
o.cups.forEach(c => { c.slotReady = false; c.startedAt = null; });
K.refreshSlots();
K.tick(1); K.tick(33);
console.log(`  [鍚嶉=1 鏃禲 ${t(cup0)} | ${t(cup1)}`);
console.log(`  鈫?涓ゆ澂閮藉繀椤?*鏈夌エ**锛堟病鍚嶉鐨勯偅寮犱細琚爣鎴?绛夊悕棰?锛屼絾缁濅笉鑳芥秷澶憋級`);

// 鈽?鎸夊崟濉睜锛氬悕棰?3銆佷竴鍗?2 鏉?鈫?涓ゆ澂閮借鍦ㄦ睜閲岋紙涓嶈兘绗竴鏉紑宸ュ氨鎶婄浜屾澂鎸ゅ嚭鍘伙級
K.CFG.kitchen.maxWip = 3;
G.orders = [o]; G.slips = [];
o.cups.forEach(c => { c.slotReady = false; c.startedAt = null; });
K.refreshSlots();
const pool1 = o.cups.map(c => c.slotReady).join(',');
// 璁╃涓€鏉紑宸ワ紙鍐?startedAt锛夛紝鍐嶉噸绠楀悕棰濓紝鐪嬬浜屾澂浼氫笉浼氳韪㈠嚭鍘?o.cups[0].startedAt = 1;
K.refreshSlots();
const pool2 = o.cups.map(c => c.slotReady).join(',');
console.log(`  [鍚嶉=3] 濉叆鍚庝袱鏉祫鏍?${pool1} 鈫?绗竴鏉紑宸ュ悗=${pool2}`);
console.log(`  鈫?閮藉繀椤绘槸 true,true锛堝悓鍗曠殑鏉竴璧疯繘姹狅級`);
K.CFG.kitchen.maxWip = 3;

// 鑷姩鍑虹エ锛堟瘡甯?syncStats 浼氳皟 ensureTickets锛夆€斺€旀帹涓€甯ц瀹冭窇
K.tick(1); K.tick(33);
console.log('  鎺ㄤ竴甯у悗: ' + t(cup0) + ' | ' + t(cup1));

// 鎶婄涓€鏉暣鏉″仛瀹岋紙璧扮湡瀹炵殑 pressStep + deliverCup 璺緞锛?function finishCup(cup, o) {
  const slip = G.slips.find(s => s.cup === cup) || K.makeSlip(o, cup);
  let guard = 0;
  while (!cup.done && guard++ < 40) {
    const nx = K.slipNext(cup);
    if (!nx) break;
    K.routeSlip(slip, nx.st);
    K.pressStep(slip);
    if (nx.kind === 'hold') { nx.holdOn = true; for (let f = 0; f < 60 && !nx.ok; f++) K.tickHolds(0.05); }
  }
  if (cup.done) K.deliverCup(slip);
}
finishCup(cup0, o);
console.log(`  鏉? 鍋氬畬骞朵氦鎺夊悗: made=${o.made}/${o.need} 鍦ㄥ埗=${K.wipCount()}`);
K.refreshSlots(); K.tick(66);
console.log('           : ' + t(cup0) + ' | ' + t(cup1));

const slides = G.slips.map(s => `#${s.id}(鏉?{s.cup.i}@${s.cup.rec.id})`).join(' ');
console.log(`  褰撳墠灏忕エ: ${slides || '锛堟病鏈夛級'}`);

// 缁撹
const bad = [];
if (!G.slips.some(s => s.cup === cup1)) bad.push('绗簩鏉病鏈夌エ 鈫?鐜╁浼氫互涓?绗簩鏉仛涓嶄簡"锛堣繖灏辨槸鏈疆淇殑 bug锛?);
if (cup1.startedAt !== null && !G.slips.some(s => s.cup === cup1) && !cup1.done) bad.push('绗簩鏉紑宸ヤ簡浣嗘病鏈夌エ');
if (pool1 !== 'true,true') bad.push(`鍚嶉澶熸椂娌℃妸鍚屽崟鐨勬澂涓€璧峰～杩涙睜锛?{pool1}锛塦);
if (pool2 !== 'true,true') bad.push(`绗竴鏉紑宸ュ悗鎶婂悓鍗曠浜屾澂鎸ゅ嚭浜嗘睜锛?{pool2}锛塦);
console.log(bad.length ? '\n鉁?' + bad.join(' / ') : '\n鉁?娣风偣璁㈠崟鐨勬瘡涓€鏉兘鏈夎嚜宸辩殑绁?);
process.exit(bad.length ? 1 : 0);

