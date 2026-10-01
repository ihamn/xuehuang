// fakedom-coverage.mjs —— **测试台自己的测试**：假 DOM 必须覆盖页面用到的每一个 DOM API
//
//   node tests/fakedom-coverage.mjs
//
// 为什么要它：2026-10-01 一天里，"假 DOM 没实现某个 API"让测试**假失败/假通过**了 6 次
//   （querySelectorAll / style.setProperty / appendChild 不设 parentNode / 没有 remove()
//    / innerHTML 不清空子件 / 没有 classList.toggle）。
//   每一次都是"撞到了才补"，而**撞不到的那些会静默地让测试失去意义**。
//   所以这里做一个**静态覆盖检查**：页面里用到的 DOM API，假 DOM 必须都有。
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const fake = fs.readFileSync(path.join(ROOT, 'tests', '_fakedom.mjs'), 'utf8');
const pages = ['preview/手机按键-微量测试.html', 'preview/杯子-原型.html'];

// 页面里出现的 DOM API 名字（只查"像 API 的"调用）
const API_RE = /\.(classList\.[a-z]+|appendChild|removeChild|remove|setAttribute|getAttribute|addEventListener|removeEventListener|getBoundingClientRect|querySelectorAll|querySelector|setProperty|getPropertyValue|insertBefore|replaceChildren|firstChild|children)\b/g;

const used = new Map();
for (const p of pages) {
  const t = fs.readFileSync(path.join(ROOT, p), 'utf8');
  for (const m of t.matchAll(API_RE)) used.set(m[1], (used.get(m[1]) || 0) + 1);
}

let bad = 0;
console.log('测试台覆盖检查（假 DOM vs 原型页用到的 DOM API）');
const missing = [];
for (const [name, n] of [...used.entries()].sort((a, b) => b[1] - a[1])) {
  const leaf = name.split('.').pop();               // classList.toggle → toggle
  const has = fake.includes(name) || fake.includes(leaf + '(') || fake.includes(leaf + ':') || fake.includes(leaf + ' ');
  console.log(`  ${has ? '✓' : '✗'} ${name.padEnd(22)} 页面里用了 ${n} 处`);
  if (!has) { missing.push(name); bad++; }
}
if (missing.length) console.log('\n缺：' + missing.join(', ') + '\n⇒ 补进 tests/_fakedom.mjs，否则相关断言会静默失真');
console.log(bad ? `\n覆盖检查：${bad} 个 API 未实现` : '\n覆盖检查：全部通过 ✓');
process.exit(bad ? 1 : 0);
