// recipe-parser.mjs —— **体检解析器本身**（它错了，下游所有断言都会骗人）
import fs from 'node:fs';
import path from 'node:path';
import { parseRecipes } from './_recipe-vis.mjs';

const ROOT = path.resolve(import.meta.dirname, '..');
const lua = fs.readFileSync(path.join(ROOT, 'lua', 'src', 'recipes.lua'), 'utf8');
const R = parseRecipes(lua);
let bad = 0;
const chk = (ok, msg) => { console.log(`  ${ok ? '✓' : '✗'} ${msg}`); if (!ok) bad++; };

console.log('配方解析器 · 体检');
const ids = Object.keys(R);
chk(ids.length === 6, `认出 6 个产品（实际 ${ids.length}：${ids.join(' ')}）`);
const total = ids.reduce((n, id) => n + R[id].steps.length, 0);
chk(total === 26, `共 26 步（实际 ${total}）—— 每步都解析出来，没有"被静默吃掉"的`);
let noText = 0, noVis = 0;
ids.forEach(id => R[id].steps.forEach((s, i) => {
  if (!s.t) { noText++; console.log(`      ✗ [${id}] 第 ${i + 1} 步没解析出文案`); }
  if (!s.vis || Object.keys(s.vis).length === 0) { noVis++; console.log(`      ✗ [${id}] 第 ${i + 1} 步没解析出 vis`); }
}));
chk(noText === 0 && noVis === 0, '每步都有文案与 vis（文案/字段都解析出来了）');
// ★ 这一条专治"嵌套表截断"：带 onDone 且**后面还有别的字段**的那一步，后面的字段必须还在
const dry = R.dryice.steps[2];
chk(dry && dry.vis && dry.vis.onDone && dry.vis.onDone.state === 'dryice',
    'onDone 解析成嵌套对象（不是被拍平成顶层 state）');
chk(dry && dry.vis && dry.vis.quip === '0.04% 也是本店的客人。',
    `★ onDone 之后的字段没被截掉（quip = ${dry && dry.vis && dry.vis.quip}）—— 这条就是那个"懒匹配到第一个 }, "的坑`);
// 器具步与手法
// 两个口径要分清：**"只有 tool"**（杯子完全不动，如咖啡前三步）= 4；
//   **"含 tool"**（还有个 pulse 之类的表现，如掏枪筒同时闪光）= 5
const toolOnly = ids.flatMap(id => R[id].steps.filter(s => Object.keys(s.vis).every(k => k === 'tool')));
const toolAny = ids.flatMap(id => R[id].steps.filter(s => s.vis.tool));
chk(toolOnly.length === 4, `"只有 tool"的器具步 4 个（咖啡 3 + 枪筒 1，实际 ${toolOnly.length}）`);
chk(toolAny.length === 5, `"含 tool"的步 5 个（掏枪筒那步还有个闪光，实际 ${toolAny.length}）`);
const hammer = ids.flatMap(id => R[id].steps.map((s, i) => ({ id, i: i + 1, s })).filter(x => x.s.press === 'hammer'));
chk(hammer.length === 4, `柠檬锤步 4 个（${hammer.map(h => h.id + '#' + h.i).join(' ')}）`);
console.log(bad ? `\n体检：${bad} 项失败` : '\n体检：全部通过 ✓');
process.exit(bad ? 1 : 0);
