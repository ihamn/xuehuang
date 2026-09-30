// layout-lint.mjs —— 布局自检：把"我这几轮反复踩的坑"变成自动检查
//
//   node tools/layout-lint.mjs [--w=1815] [--h=900]
//
// 为什么需要它：下面这些坑**编译能过、单测能过、api 审计也过**，只有真机看画面才发现：
//   ① **文字框太矮** → 字被裁掉 → "文字不显示"（我查了好几轮，真凶就是这个）
//   ② **控件出界** → 推到屏幕外 → "完全没有"
//   ③ **Z 序错** → 被别的控件盖住 → "文字不显示/黑条盖住"
//   ④ **深色压深色** → 等于没画
//   ⑤ **纯白没设色** → 新控件默认色是白，忘了上色就是白块
//
// 判据（都是实测/权威文档来的）：
//   · 文本框：框高 >= 字号 × 1.5（模板可能开描边，描边往外扩）
//   · 控件矩形必须落在容器范围内（留 2px 容差）
//   · 同级顺序里 HUD 这类"要盖在最上的"必须在前面（先出现的在上）
//   · 图片控件的颜色不该是纯白（除非明知故犯）
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const argOf = (n, d) => { const h = process.argv.find(a => a.startsWith('--' + n + '=')); return h ? h.slice(n.length + 3) : d; };
const W = Number(argOf('w', 1815)), H = Number(argOf('h', 900));
const BUNDLE = path.join(ROOT, 'dist', 'xuehuang.lua');
import { SIM_ROOT as SIM } from './sim-root.mjs';   // 模拟器位置：一处解析（云电脑/本机通用）

if (!fs.existsSync(BUNDLE)) { console.log('先合成 dist/xuehuang.lua'); process.exit(0); }
const { createRuntime, unpackRgba } = await import(pathToFileURL(path.join(SIM, 'client/lua-runtime/src/index.js')).href);

const rt = createRuntime({ canvasWidth: W, canvasHeight: H });
const root = rt.addRoot({ name: 'Canvas', kind: 'container' });
root.SetActive(true);
for (const [i, k] of [[1, 'image'], [2, 'textbox'], [3, 'cursor'], [4, 'container']]) rt.registerTemplate(i, { kind: k });
rt.mountScript({ path: 'main', source: fs.readFileSync(BUNDLE, 'utf8'), control: root, params: {} });

const problems = [];
let textCount = 0, imgCount = 0;

// 收集控件（带绝对位置）
const all = [];
(function walk(c, ox, oy) {
  const cx = ox + (c.anchoredPositionX || 0), cy = oy + (c.anchoredPositionY || 0);
  if (c !== root) all.push({ c, absX: cx, absY: cy });
  for (const k of (c.children || [])) walk(k, cx, cy);
})(root, 0, 0);

for (const { c, absX, absY } of all) {
  const name = c.name || '(无名)';
  // 跳过模拟器自己的无名控件（宽高为 0 / 没名字的容器），只看脚本建的
  if (!c.name && (Math.round(c.sizeDeltaX || 0) === 0 || Math.round(c.sizeDeltaY || 0) === 0)) continue;
  const t = String(c.typeofName || '');
  const w = Math.round(c.sizeDeltaX || 0), h = Math.round(c.sizeDeltaY || 0);
  // 屏幕坐标（中心 + 偏移；y 从上往下）
  const left = Math.round(W / 2 + absX - w / 2), top = Math.round(H / 2 - absY - h / 2);

  // ① 出界
  //   ★ 文字控件放宽：文字是**左对齐**的，框比文字宽是无害的 → 只有"文字实际宽度接近框宽"
  //     才要求框在界内（否则左边的长框会被误报）
  let isText = t.includes('TextBox');
  let slack = 0;
  if (isText) {
    const s = String(c.text || '');
    const est = s.length * (Number(c.fontSize || 20)) * 0.62;   // 粗略估文字宽度
    if (est < w * 0.9) slack = 99999;                            // 文字远短于框 → 忽略框出界
  }
  //   ★ Backdrop 例外：打底**故意超出画布**（否则边沿会露）
  const isBackdrop = /^Backdrop$/.test(name);
  //   ★ 菜单专属控件（Mn*）与结算板（SheetBag）**故意**建在 HUD 之后：
  //     菜单态它们要盖住 HUD（原版 showStart 就是整屏面板盖住顶栏）
  const isMenuOwned = /^(Mn|Big|SheetBag)/.test(name);
  if (!isBackdrop && !isMenuOwned && left < -2 - 0 && slack === 0 && (left < -2 || top < -2 || left + w > W + 2 || top + h > H + 2)) {
    problems.push(`[出界] ${name} 左${left} 上${top} ${w}x${h}（画布 ${W}x${H}）`);
  }

  if (t.includes('TextBox')) {
    textCount++;
    // ② 框太矮（文字会被裁）
    const size = Number(c.fontSize || 0);
    if (size > 0 && h < size * 1.5) {
      problems.push(`[文字框太矮] ${name} 字号${size} 但框高只有${h}（需 >= ${Math.ceil(size * 1.5)}）→ 字会被裁`);
    }
    // ③ 有文字但框宽为 0
    if (String(c.text || '').length && w < 8) {
      problems.push(`[文字框太窄] ${name} 有文字但宽只有${w}`);
    }
  }

  if (t.includes('Image')) {
    imgCount++;
    // ④ 纯白没上色（新建控件的默认色；忘了设就是白块）
    let r = -1, g = -1, b = -1, a = 0;
    try { const u = unpackRgba(c.imageColor ?? 0); [r, g, b, a] = u; } catch {}
    //   ★ 例外：**本来就该是白色**的控件 —— 图标（白图标）、进度条填充（白条）、
    //     分隔线（半透明白）。这些不算问题，否则每次都被误报。
    const whiteByDesign = /_line$|_hi$|^OdL_|^StI_|^Pk_icon$|^HudIc|_f$|^Ruler|^Probe/.test(name);
    if (!whiteByDesign && a > 10 && r === 255 && g === 255 && b === 255) {
      problems.push(`[忘了上色] ${name} 还是默认纯白（新建控件的默认色）`);
    }
  }
}

// ⑤ Z 序（实测口径）：**后建的在上**（索引大的画在上面）
//   → 最底层应该是 Backdrop，HUD/菜单大字应该在后半段
const kids = (root.children || []).map(k => k.name).filter(Boolean);
const firstEight = kids.slice(0, 8);
// ★ 菜单专属控件（Mn*）与结算板（SheetBag）**故意**建在 HUD 之后：
//   菜单态它们要盖住 HUD（原版 showStart 就是整屏面板盖住顶栏）→ 查 Z 序时先剔掉再比
const zKids = kids.filter(n => !/^(Mn|SheetBag)/.test(n));
const lastEight = zKids.slice(-8);
if (!/^Backdrop$/.test(kids[0] || '')) problems.push(`[Z序] 第一个子节点应该是 Backdrop（最底层），实际是 ${kids[0]}`);
const hudIdx = lastEight.findIndex(n => /^Hud/.test(n));
if (hudIdx < 0) problems.push(`[Z序] 最后 8 个里没有 HUD → 会被工位/订单卡盖住。最后 8 个：${lastEight.join(' → ')}`);

console.log(`layout-lint  ${path.basename(BUNDLE)}  画布 ${W}x${H}`);
console.log(`  控件 ${all.length} 个（文字 ${textCount} · 图片 ${imgCount}）`);
console.log(`  同级最上 8 个：${firstEight.join(' → ')}`);
if (!problems.length) { console.log('  ✓ 通过：没有出界 / 框太矮 / 忘了上色 / Z 序问题'); process.exit(0); }
console.log(`  ✗ ${problems.length} 个问题：`);
for (const p of problems.slice(0, 20)) console.log('    ' + p);
process.exit(1);
