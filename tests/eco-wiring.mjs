// eco-wiring.mjs —— 环保凭证的**接线检查**（静态）
//
//   node tests/eco-wiring.mjs
//
// 为什么要有它：凭证要落到 **4 个地方**（当日累加器初始化 / 每天归零 / 出餐累加 / 两个结算页显示）。
//   lua/test/eco_test.lua 验的是**算得对**；这个文件验的是**接得上**——
//   漏掉任何一处都不会报错，只会表现为"某天结算页上是空的/数字一路累加"。
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const state = read('lua/src/state.lua');
const day = read('lua/src/day.lua');
const order = read('lua/src/order.lua');
const view = read('lua/src/view.lua');

let bad = 0;
const chk = (ok, msg) => { console.log(`  ${ok ? '✓' : '✗'} ${msg}`); if (!ok) bad++; };
const count = (s, re) => [...s.matchAll(re)].length;

console.log('环保凭证 · 接线检查');
chk(/today = \{[\s\S]{0,160}?eco = \{/.test(state), 'state.lua：初始 today 里带 eco 累加器');
chk(/s\.today = \{[\s\S]{0,160}?eco = \{/.test(day), 'day.lua：**每天归零**也重建 eco（漏了就会一路累加）');
chk(/rec = \{[\s\S]{0,240}?eco = s\.today\.eco/.test(day), 'day.lua：结算时把当日 eco 记进 dayStats');
chk(/s\.today\.eco/.test(order), 'order.lua：出餐时累加 eco');
chk(count(view, /ecoLines\(/g) >= 3, `view.lua：ecoLines 有定义 + **两个结算页各用一次**（共出现 ${count(view, /ecoLines\(/g)} 次，至少 3）`);
chk(/BigL4/.test(view) && /BigL5/.test(view), 'view.lua：L4/L5 两个文本位已建（旧的结算大字只有 3 行）');
chk(/controls = \{ v\.big\.title[\s\S]{0,220}?v\.big\.line5 \}/.test(view), 'view.lua：L4/L5 进了 controls（否则结算时不会被 SetVisible）');
chk(/setText\(v\.big\.line4, ''\); setText\(v\.big\.line5, ''\)/.test(view), 'view.lua：回菜单时清空 L4/L5（否则菜单上会挂着上一局的凭证）');
chk(/co2FixedG/.test(read('lua/src/recipes.lua')), 'recipes.lua：干冰那款有 co2FixedG（唯一真的固化了 CO₂ 的产品）');
chk(/BigL4/.test(view) && /BigL5/.test(view), 'view.lua：L4/L5 两个文本位在（固化量 + 感谢）');
chk(!/BigL6/.test(view) && /津巴布韦元/.test(view), 'view.lua：没有 L6（不单独占一行），津元直接跟在固化量后面输出');
chk(!/人体排碳|joulePerPress|bodyEff|glucoseJ|co2PerGlucose/.test(view), 'view.lua：**排碳那套**不出现（换币种可以，讲排碳不行）');
chk(/eco = \{ fixed = 0, zwd = 0 \}/.test(state) && /eco = \{ fixed = 0, zwd = 0 \}/.test(day), 'state/day：累加器是 { fixed, zwd }（固化量 + 已折好的津元，每天归零）');
chk(!/joulePerPress|bodyEff|glucoseJ|co2PerGlucose/.test(read('lua/src/recipes.lua')),
    'recipes.lua：**排碳计算**已彻底删除（固化量 + 碳价 + 津元保留）');
chk(/zwdPerMg/.test(read('lua/src/recipes.lua')), 'recipes.lua：津元是**成品常数 zwdPerMg**（提前算好）');
chk(!/carbonPrice|zwdPerUsd|cnyPerUsd/.test(read('lua/src/recipes.lua')), 'recipes.lua：碳价/汇率这些中间量已删除（结算时不再换算）');
chk(/固定下来的减碳|固化/.test(read('lua/src/recipes.lua')), 'recipes.lua：保留着"固化量"的推导注释（0.5 L × 0.04% ÷ 22.4 × 44）');
// ★ 环保相关行**不许出现 %d**（实测：这个运行时里 %d 遇到大浮点会抛 JS 级异常，
//   pcall 都接不住 ⇒ 游戏硬崩。所以只许 %.2f）
{
  const lines = view.split('\n').filter(l => /eco|固化|津巴布韦|zwd|fixed/i.test(l) && /string\.format/.test(l));
  const badFmt = lines.filter(l => /%[0-9.]*[diouxX]/.test(l));
  chk(badFmt.length === 0, `环保相关格式化只用浮点占位符（%d/%i 会硬崩；检查了 ${lines.length} 行）`);
  if (badFmt.length) badFmt.forEach(l => console.log('      ✗ ' + l.trim()));
}
chk(!/%[0-9.]*d/.test(read('lua/src/recipes.lua')), 'recipes.lua 里也没有 %d 格式化');

console.log(bad ? `\n接线检查：${bad} 项失败` : '\n接线检查：全部通过 ✓');
process.exit(bad ? 1 : 0);
