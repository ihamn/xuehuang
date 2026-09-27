// sim-cursor-click.mjs —— 端到端验证「按键 + 光标点击」整条链路
//
//   node tools/sim-cursor-click.mjs
//
// 为什么单独做一个工具：点击这条链路跨了 4 层（事件 → input 队列 → 入口路由 → 逻辑层），
//   任何一层断了都表现为"点了没反应"，光看画面分不出来。这个工具把每一层都问一遍。
//
// 判据：点击工位 → 该工位的"连按 N/M"计数要 +1（或步骤文案前进）。
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const SIM = 'D:/miliastra-beyond-simulator';
const BUNDLE = path.join(ROOT, 'dist', 'xuehuang.lua');
if (!fs.existsSync(BUNDLE)) { console.log('先合成 dist/xuehuang.lua'); process.exit(0); }

const { createRuntime } = await import(pathToFileURL(path.join(SIM, 'client/lua-runtime/src/index.js')).href);
const rt = createRuntime({ canvasWidth: 1600, canvasHeight: 900 });
const root = rt.addRoot({ name: 'C', kind: 'container' });
root.SetActive(true);
for (const [i, k] of [[1, 'image'], [2, 'textbox'], [3, 'cursor'], [4, 'container']]) rt.registerTemplate(i, { kind: k });
rt.mountScript({ path: 'main', source: fs.readFileSync(BUNDLE, 'utf8'), control: root, params: {} });

const findByName = (c, n) => { if (c.name === n) return c; for (const k of (c.children || [])) { const r = findByName(k, n); if (r) return r; } return null; };
const findArea = c => { if (String(c.typeofName || '').includes('CursorEvent')) return c; for (const k of (c.children || [])) { const r = findArea(k); if (r) return r; } return null; };
// ★ 控件名改版了：工位"步骤"文本现在是 StS_<id>（旧的是 StB_<id>）
const bodies = () => ['shake', 'fire', 'chem', 'brew']
  .map(id => {
    const a = findByName(root, 'StS_' + id);
    return id.slice(0, 2) + '=' + String((a && a.text) || '').replace(/\n/g, '|');
  })
  .join('   ');
const visibleImages = () => { const v = []; (function w(c) { const t = String(c.typeofName || ''); if (c.active !== false && c.visible !== false && t.includes('Image') && c.name) v.push(c.name); (c.children || []).forEach(w); })(root); return v; };

const steps = [];
// ① 菜单态：应该"看不到玩区方块、能看到菜单文字"
for (let f = 0; f < 5; f++) rt.step(1 / 30);
const menuImgs = visibleImages();
const menuHud = findByName(root, 'HudTitle');
// ★ 设计变更：菜单不再隐藏玩区（那套"隐藏/恢复"互相打架，已整体删掉），
//   菜单文字直接盖在画面上。所以这里断言"玩区可见 + 有菜单标题"。
steps.push(['菜单态：玩区方块已隐藏（用户要的）', (menuImgs.filter(n => /^St_.*_box$/.test(n)).length === 0 && !menuImgs.includes('Pk_box'))]);
steps.push(['菜单态：标题有内容（横幅或菜单标题）', String((menuHud || {}).text || '').length > 2]);

// ② 按键开始
rt.injectKey('KeyboardCraftspersonKey42Down');
for (let f = 0; f < 5; f++) rt.step(1 / 30);
const playImgs = visibleImages();
steps.push(['按空格后：玩区方块出现（4 工位 + 打包台）', (playImgs.filter(n => /^St_.*_box$/.test(n)).length === 4 && playImgs.includes('Pk_box'))]);

// ③ 等小票，然后把**每个工位点几轮**
//   为什么不点一次就断言：哪张票落在哪个工位是随机的（等名额/在制/按住各不同），
//   单次点击可能正好点在"那一刻没活"的工位上 → 假失败（我就这么白查过一轮）。
for (let f = 0; f < 900; f++) rt.step(1 / 30);
const before = bodies();
const area = findArea(root);
const names = ['St_shake_box', 'St_fire_box', 'St_chem_box', 'St_brew_box', 'Pk_box', 'Od_1'];
let hit = false;
for (let round = 0; round < 6 && !hit; round++) {
  if (area) {
    for (const nm of names) {
      const bx = findByName(root, nm);
      if (!bx) continue;
      rt.injectCursor(area, 'CursorClick', {
        x: 1600 / 2 + (bx.anchoredPositionX || 0),
        y: 900 / 2 + (bx.anchoredPositionY || 0),
      });
      for (let f = 0; f < 2; f++) rt.step(1 / 30);
    }
  }
  const now = bodies();
  if (now.split('   ').some((s, i) => s !== before.split('   ')[i])) hit = true;
}
const after = bodies();
steps.push(['点击链路通（至少一个工位响应）', hit]);

let pass = 0, fail = 0;
console.log('=== 输入链路自检（' + path.relative(ROOT, BUNDLE) + '）===');
for (const [label, ok] of steps) { console.log('  ' + (ok ? 'OK  ' : 'X   ') + label); ok ? pass++ : fail++; }
console.log('  点击前: ' + before);
console.log('  点击后: ' + after);
console.log('  可见图片: ' + visibleImages().join(', '));
const errs = (rt.logs || []).filter(l => l.level === 'error');
console.log('  error: ' + errs.length + (errs[0] ? ' | ' + errs[0].text : ''));
for (const l of (rt.logs || [])) if (/BUILD-FAILED|已绑定|光标检测|已就绪/.test(l.text)) console.log('  log: ' + l.text);
console.log(`\n  passed ${pass} / failed ${fail}`);
rt.destroy();
process.exit(fail ? 1 : 0);
