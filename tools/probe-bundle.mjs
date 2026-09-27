// probe-bundle.mjs —— 跑合成产物，打印全部日志（含 pcall 吞掉的错误）
//   node tools/probe-bundle.mjs [dist/xuehuang.lua] [--frames=200]
//
// 存在意义：`pcall` 包住的错误只会打在日志里，而 sim-run 的过滤器会漏掉它们。
// 这个工具把**每一行**都打出来，用来定位"启动失败但看不出为什么"。
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const argOf = (n, d) => { const h = process.argv.find(a => a.startsWith('--' + n + '=')); return h ? h.slice(n.length + 3) : d; };
const BUNDLE = path.resolve(ROOT, process.argv.slice(2).find(a => !a.startsWith('--')) || 'dist/xuehuang.lua');
const FRAMES = Number(argOf('frames', 200));
const SIM = 'D:/miliastra-beyond-simulator';

const { createRuntime } = await import(pathToFileURL(path.join(SIM, 'client/lua-runtime/src/index.js')).href);
const rt = createRuntime({ canvasWidth: 1280, canvasHeight: 720 });
const root = rt.addRoot({ name: 'Canvas', kind: 'container' })
root.SetActive(true)   // ★ 必须激活：未激活时 scriptCanRun=false，OnUpdate 不会跑;
for (const [i, k] of [[1, 'image'], [2, 'textbox'], [3, 'cursor'], [4, 'container']]) rt.registerTemplate(i, { kind: k });
rt.mountScript({ path: 'main', source: fs.readFileSync(BUNDLE, 'utf8'), control: root, params: { autoplay: 1 } });
for (let f = 0; f < FRAMES; f++) rt.step(1 / 30);

console.log(`=== ${path.relative(ROOT, BUNDLE)} · ${FRAMES} 帧 · 全部日志 ===`);
for (const l of (rt.logs || [])) console.log(`  [${l.level}] ${l.text}`);
console.log(`=== 挂载错误 ${(rt.mountErrors || []).length} 条 ===`);
for (const e of (rt.mountErrors || [])) console.log('  ' + e);
rt.destroy();
