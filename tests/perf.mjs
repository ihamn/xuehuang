// 鍙祴"娓告垙閫昏緫鏈韩"鏈夊蹇紙涓嶈窇鏂█銆佷笉鎵撳嵃锛夛細鎵惧嚭鍐掔儫鎱㈠湪鍝?//   node tests/perf.mjs
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
  querySelector: sel => (sel === '#go' || sel === '#again' ? mk() : (doc._byId[sel.slice(1)] || mk())), querySelectorAll: () => [] };
const sandbox = { document: doc, console, window: { addEventListener() {}, removeEventListener() {} },
  Math, JSON, Date, Object, Array, String, Number, Boolean, isNaN, parseInt, parseFloat,
  setTimeout: () => 0, clearTimeout: () => {} };
sandbox.globalThis = sandbox; sandbox.window.document = doc;
vm.createContext(sandbox);
vm.runInContext(code, sandbox, { filename: 'snowking<script>' });
const K = sandbox.__SNOWKING__;
K.start('fast');
const G = K.G();
G.fx = false;
G.nextArrive = 1e9;

const t = (label, fn) => { const a = process.hrtime.bigint(); fn(); const b = process.hrtime.bigint(); console.log(`${label}: ${Number(b - a) / 1e6}ms`); };

t('閫?20 鍗?, () => { for (let n = 0; n < 20; n++) K.spawnOrder(); });
t('鎺?600 甯э紙10 绉掓父鎴忔椂闂达紝鏃犺緭鍏ワ級', () => { K.resetClock(); for (let f = 1; f <= 600; f++) K.tick(f * 33); });
t('鎺?1800 甯э紙30 绉掞級', () => { K.resetClock(); for (let f = 1; f <= 1800; f++) K.tick(f * 33); });
const slip = G.slips[0];
if (slip) t('鍚屼竴寮犲皬绁ㄦ寜 200 涓?pressStep', () => { for (let n = 0; n < 200; n++) K.pressStep(slip); });
console.log('鍦ㄥ埗', K.wipCount(), '灏忕エ', G.slips.length, '璁㈠崟', G.orders.length, '鍑洪', G.served);

