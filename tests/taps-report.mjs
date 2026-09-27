// 手感速查：把每款产品的"手法分布"打出来（不跑整局，几秒）
//   node tests/taps-report.mjs
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const ROOT = path.resolve(import.meta.dirname, '..');
const html = fs.readFileSync(path.join(ROOT, '雪皇的后厨.html'), 'utf8');
const i = html.indexOf('<script>'), j = html.lastIndexOf('</script>');
const code = html.slice(i + 8, j);

const mk = () => {
  const el = { dataset: {}, children: [], style: {}, classList: { add() {}, remove() {}, toggle() {}, contains: () => false },
    _html: '', textContent: '', appendChild() {}, removeChild() {}, remove() {}, addEventListener() {}, removeEventListener() {},
    querySelector: () => mk(), querySelectorAll: () => [], getBoundingClientRect: () => ({ left: 0, top: 0, width: 0, height: 0 }),
    set innerHTML(v) { el._html = v; }, get innerHTML() { return el._html; }, get firstChild() { return null; } };
  return el;
};
const doc = { _byId: {}, body: mk(), createElement: () => mk(),
  querySelector: sel => (sel === '#go' || sel === '#again' ? mk() : (doc._byId[sel.slice(1)] || mk())),
  querySelectorAll: () => [], addEventListener() {}, elementFromPoint: () => null };
const sandbox = { document: doc, console, window: { addEventListener() {}, removeEventListener() {} },
  Math, JSON, Date, Object, Array, String, Number, Boolean, isNaN, parseInt, parseFloat,
  setTimeout: () => 0, clearTimeout: () => {} };
sandbox.globalThis = sandbox;
sandbox.window.document = doc;
vm.createContext(sandbox);
vm.runInContext(code, sandbox, { filename: 'snowking<script>' });

const R = sandbox.__SNOWKING__.RECIPES;
const LABEL = { tap: 'tap', mash: 'mash', hold: 'hold' };
console.log('recipe interaction fingerprints (key: they must NOT all look the same)');
console.log('-'.repeat(74));
let tapOnly = 0;
for (const r of R) {
  const dist = { tap: 0, mash: 0, hold: 0 };
  let total = 0;
  const detail = r.steps.map(s => {
    dist[s.kind]++;
    total += (s.kind === 'mash' ? s.taps : 1);
    return s.kind === 'mash' ? `${s.t} [mash x${s.taps}]` : `${s.t} [${LABEL[s.kind]}]`;
  });
  if (dist.mash === 0 && dist.hold === 0) tapOnly++;
  console.log(`${r.id} | ${r.source} | tap=${dist.tap} mash=${dist.mash} hold=${dist.hold} | actions=${total}`);
  console.log(`   ${detail.join(' -> ')}`);
}
console.log('-'.repeat(74));
const kindsUsed = new Set(R.flatMap(r => r.steps.map(s => s.kind)));
const mashTaps = new Set(R.flatMap(r => r.steps.filter(s => s.kind === 'mash').map(s => s.taps)));
console.log(`kinds used: ${[...kindsUsed].join(' / ')} | mash tiers: ${[...mashTaps].sort().join(', ')}`);
const bad = [];
if (kindsUsed.size < 2) bad.push('only one interaction kind (no differentiation)');
if (tapOnly === R.length) bad.push('every recipe is tap-only');
if (mashTaps.size < 2) bad.push('mash has only one tier (pound == compress)');
const ic = R.find(r => r.id === 'instcoffee');
if (!ic || !ic.steps.every(s => s.kind === 'tap' || s.st === 'pack')) bad.push('instcoffee is not on the light-handed path');
console.log(bad.length ? '\nFAIL: ' + bad.join(' / ') : '\nPASS: differentiation holds (tap / mash / hold all in use, tiers separated)');
process.exit(bad.length ? 1 : 0);
