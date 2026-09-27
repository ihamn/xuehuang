// 模板索引回归测试：注册成**真机那种大数字 + 乱序**，看 hello.lua 能不能自己认出来
//   node tools/test-prefab-detect.mjs
//
// 为什么值得有：zuma 第一版只扫 1~32，用户"明明存为模板了"却全报 nil，白查了一轮。
// 这条测试就是让那个坑不再犯：只要索引落在大数字空间、且顺序是乱的，也必须认出来。
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const ENTRY = 'D:/miliastra-beyond-simulator/client/lua-runtime/src/index.js';
if (!fs.existsSync(ENTRY)) { console.log('跳过：没找到模拟器运行时'); process.exit(0); }

const { createRuntime } = await import(pathToFileURL(ENTRY).href);
const source = fs.readFileSync(path.join(ROOT, 'lua', 'src', 'hello.lua'), 'utf8');

const BASE = 1073741824;
// 故意乱序、且都不在 1~32 里（真机就是这样）
const CASES = [
  { name: '乱序大数字', tpl: { [BASE + 30]: 'image', [BASE + 22]: 'textbox', [BASE + 27]: 'cursor', [BASE + 19]: 'container' },
    expect: { img: BASE + 30, text: BASE + 22, cursor: BASE + 27, panel: BASE + 19 } },
  { name: '只有必需的三个', tpl: { [BASE + 5]: 'textbox', [BASE + 9]: 'image', [BASE + 40]: 'cursor' },
    expect: { img: BASE + 9, text: BASE + 5, cursor: BASE + 40, panel: undefined } },
  { name: '只建两个（图片+文本框，没有光标区）', tpl: { [BASE + 7]: 'image', [BASE + 8]: 'textbox' },
    expect: { img: BASE + 7, text: BASE + 8, cursor: undefined, panel: undefined } },
  { name: '老式小索引', tpl: { 3: 'image', 7: 'textbox', 11: 'cursor', 15: 'container' },
    expect: { img: 3, text: 7, cursor: 11, panel: 15 } },
];

let bad = 0;
for (const c of CASES) {
  const rt = createRuntime({ canvasWidth: 1280, canvasHeight: 720 });
  const root = rt.addRoot({ name: 'Canvas', kind: 'container' });
  for (const [idx, kind] of Object.entries(c.tpl)) rt.registerTemplate(Number(idx), { kind, name: kind });
  rt.mountScript({ path: 'main', source, control: root, params: {} });
  for (let f = 0; f < 10; f++) rt.step(1 / 30);
  const txt = (rt.logs || []).map(l => l.text).join('\n');
  const line = (txt.match(/自动认模板：.*/) || ['<没这行>'])[0];
  const okImg = c.expect.img == null || line.includes(`img=${c.expect.img}`);
  const okTxt = c.expect.text == null || line.includes(`text=${c.expect.text}`);
  const okCur = c.expect.cursor == null || line.includes(`cursor=${c.expect.cursor}`);
  const okPan = c.expect.panel == null || line.includes(`panel=${c.expect.panel}`);
  const built = /控件已建/.test(txt);
  const ok = okImg && okTxt && okCur && okPan && built;
  console.log(`${ok ? '✓' : '✗'} [${c.name}] ${line}  ${built ? '已建控件' : '★ 没建出控件'}`);
  if (!ok) { bad++; console.log('   期望：' + JSON.stringify(c.expect)); }
  rt.destroy();
}
console.log(bad ? `\n✗ ${bad} 项不合格` : '\n✓ 全部通过：大数字 / 乱序 / 缺容器 都能认出来');
process.exit(bad ? 1 : 0);
