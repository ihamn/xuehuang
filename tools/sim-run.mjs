// 雪皇的后厨 · 本地试玩驱动（在千星客户端 Lua 运行时里真跑我们的脚本）
//
// 为什么要有它：真机（沙箱编辑器）拿反馈要几分钟一轮，而且只能看到最后结果。
// 这个驱动用社区模拟器（miliastra-beyond-simulator 的 client/lua-runtime，Fengari 上的 Lua 5.3）
// 在本地把脚本真跑起来：控件真的是 Instantiate 出来的、光标事件真的是派发的，
// 于是"画面上会出现什么""脚本会不会崩"在**上传之前**就能看见。
//
// ★ 它不是真机证明。模拟器与真机必然有差异（32 位整数、imageType 之类），这里过了不等于真机过了。
//
// 用法：
//   node tools/sim-run.mjs lua/src/hello.lua                  # 跑 90 帧，打印日志 + 控件统计
//   node tools/sim-run.mjs lua/src/hello.lua --frames=600 --json=dist/tree.json
//
// 模拟器在哪：见 tools/sim-root.mjs（XUEHUANG_SIM → 仓内 third_party/beyond-sim → D:/miliastra-beyond-simulator）。找不到就退出码 0 跳过。

import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { SIM_ENTRY, SIM_FOUND, reportMissingSim } from './sim-root.mjs';

const ROOT = path.resolve(import.meta.dirname, '..');
const argOf = (name, dflt) => {
  const hit = process.argv.find(a => a === '--' + name || a.startsWith('--' + name + '='));
  if (!hit) return dflt;
  const eq = hit.indexOf('=');
  return eq >= 0 ? hit.slice(eq + 1) : true;
};
const scriptArg = process.argv.slice(2).find(a => !a.startsWith('--'));

const ENTRY = SIM_ENTRY;
if (!SIM_FOUND) {
  reportMissingSim('试玩台');
  process.exit(0);
}

// ── 画布与控件模板：与真机编辑器里要建的 4 个模板一一对应（见 lua/src/hello.lua 顶部说明）
// 基线是手机 16:9（1280×720）—— 官方给的 2D 布局基准，整屏构图必须在这儿完整可见
const W = Number(argOf('w', 1280));
const H = Number(argOf('h', 720));
const FRAMES = Number(argOf('frames', 90));
const JSON_OUT = argOf('json', null);
const SCRIPT = path.resolve(ROOT, scriptArg || 'lua/src/hello.lua');

if (!fs.existsSync(SCRIPT)) { console.error('脚本不存在：' + SCRIPT); process.exit(1); }
const source = fs.readFileSync(SCRIPT, 'utf8');

const { createRuntime, walkControls, unpackRgba } = await import(pathToFileURL(ENTRY).href);
const rt = createRuntime({ canvasWidth: W, canvasHeight: H });

const root = rt.addRoot({ name: 'Canvas', kind: 'container' })
root.SetActive(true)   // ★ 必须激活：未激活时 scriptCanRun=false，OnUpdate 不会跑;   // 客户端控件容器（挂脚本的"画布"）
rt.registerTemplate(1, { kind: 'image', name: 'Img' });           // 图片控件（工位底/进度条/小票卡）
rt.registerTemplate(2, { kind: 'textbox', name: 'Text' });        // 文本框（所有文字）
rt.registerTemplate(3, { kind: 'cursor', name: 'CursorArea' });   // 光标检测区（点工位）
rt.registerTemplate(4, { kind: 'container', name: 'Panel' });     // 容器（玩区/面板分组）

const mounted = rt.mountScript({
  path: 'main',
  source,
  control: root,
  params: {
    imgPrefab: 1, textPrefab: 2, cursorPrefab: 3, panelPrefab: 4,
    diag: 1,
  },
});

// 推帧：每帧派发一次 Tick（模拟器按 OnUpdate 回调）
for (let f = 0; f < FRAMES; f++) rt.step(1 / 30);

// ── 结果 ──
// walkControls(root, fn) 是"遍历并回调"，不是"返回树"（我第一版写错了，它要求第二个参数是函数）
const flat = [];
for (const r of (rt.roots || [])) walkControls(r, c => flat.push(c));
const logs = (rt.logs || []).filter(l => l.level === 'error' || l.level === 'warn');
const texts = flat.filter(c => c && c.text).map(c => c.text);
const colorCount = {};
for (const c of flat) {
  if (c && c.imageColor != null) {
    try { const [r, g, b] = unpackRgba(c.imageColor); colorCount[`#${r.toString(16).padStart(2,'0')}${g.toString(16).padStart(2,'0')}${b.toString(16).padStart(2,'0')}`] = 1; } catch {}
  }
}
// 控件类型字段是 typeofName（不是 __kind —— 我第一版读错了，所以"可见图片控件"一直是 0）
const isImg = c => c && (c.typeofName || '').indexOf('Image') >= 0;

console.log('='.repeat(70));
console.log(`雪皇试玩台：${path.relative(ROOT, SCRIPT)}（${source.length} 字符）`);
console.log(`  画布 ${W}x${H} · 跑 ${FRAMES} 帧（1/30 秒/帧 = ${(FRAMES/30).toFixed(1)}s 游戏时间）`);
console.log('='.repeat(70));
console.log('\n--- 日志（print / printerr / lua-error）---');
for (const l of (rt.logs || []).slice(-40)) console.log(`  [${l.level}] ${l.text}`);
console.log('\n--- 沙箱里的控件树 ---');
console.log(`  控件总数（含画布）：${flat.length}   ← 平台上限 1000/组`);
console.log(`  可见图片控件：${flat.filter(c => isImg(c) && c.visible !== false && c.active !== false).length}`);
console.log(`  颜色种类：${Object.keys(colorCount).length}`);
console.log(`  文本：${texts.length ? texts.map(t => JSON.stringify(t)).join(' | ') : '（没有文本）'}`);
if (logs.length) console.log(`\n⚠ 有 ${logs.length} 条 warn/error 日志，往上翻看`);
if (JSON_OUT) {
  const out = path.resolve(ROOT, JSON_OUT);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  // ★★ 必须把"相对父控件的坐标"累加成**绝对坐标**再导出。
  //   我们的视觉件是嵌套的（杯子底下挂着液体/斜条/高光、火底下挂着 432 个格子），
  //   子控件存的是相对父控件中心的偏移 → 直接当绝对坐标画，所有东西会叠在画布中心
  //   （我第一版就是这么错的：满屏只有一个炮筒）。深度优先的顺序正好就是绘制顺序。
  const abs = [];
  const childrenOf = c => c.children || c.childControls || c.controls || [];
  function walkAbs(c, ox, oy, depth) {
    if (!c) return;
    const x = ox + (c.anchoredPositionX || 0);
    const y = oy + (c.anchoredPositionY || 0);
    abs.push({ c, x, y, depth });
    for (const k of childrenOf(c)) walkAbs(k, x, y, depth + 1);
  }
  for (const r of (rt.roots || [])) walkAbs(r, 0, 0, 0);

  fs.writeFileSync(out, JSON.stringify({ canvas: { w: W, h: H }, script: path.relative(ROOT, SCRIPT), frames: FRAMES, controls: abs.map(({ c, x, y, depth }) => ({
    kind: c.typeofName, name: c.name, text: c.text, x, y, depth,
    // ★ imageId 必须导出：运行时的 ImageControl **是有 imageId 的**（scene.js 的默认字段 +
    //   SetImage 就写它）。我第一版没导 → 渲染器只知道"这是个矩形"，三角形/圆环全被画成方块，
    //   于是误判成"模拟器不认素材号"。其实是导出漏字段（教训：先查运行时再下结论）。
    art: c.imageId, artSrc: c.imageSource,
    w: c.sizeDeltaX, h: c.sizeDeltaY, color: c.imageColor, visible: c.visible,
    // ★ rot 必须一起导出：杯子的"斜条"是靠 localRotationZ 转出锥形的，
    //   不带旋转的话渲染出来所有斜条都是竖直的 → 杯子看着是个方桶（我踩过）
    rot: c.localRotationZ, active: c.active,
  })) }, null, 1));
  console.log(`\n控件树已导出：${path.relative(process.cwd(), out)}`);
}
rt.destroy();
process.exit(logs.some(l => l.level === 'error') ? 1 : 0);
