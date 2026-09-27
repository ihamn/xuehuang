// ui-oracle.mjs —— 表现层"真值判定"：把游戏摆到确定状态，读客户端画面上的文字对不对
//
//   node tools/ui-oracle.mjs             # 判定
//   node tools/ui-oracle.mjs --seconds=N # 扫描时长（默认 30 秒游戏时间）
//
// 为什么需要：用户的诊断是「按键无效指的是客户端上看不到状态更新」。
//   也就是**逻辑在动、画面没动**。这类问题必须两边分开量：
//   逻辑层 → lua/test/*.lua；表现层 → **本工具**（读客户端控件树的真实文字）。
//   2026-09-27 就是靠它抓到"工位卡说无活、小票卡说按 X"的自相矛盾显示。
//
// 小票行已删除（小票只当后台数据）⇒ 玩家唯一的操作反馈面 = **工位卡 + HUD 提示行**，
//   所以本工具的判据全部压在工位卡上：只要"逻辑上有活"，工位卡就必须说要做什么。

import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const argOf = (n, d) => { const h = process.argv.find(a => a.startsWith('--' + n + '=')); return h ? h.slice(n.length + 3) : d; };
const W = Number(argOf('w', 1280)), H = Number(argOf('h', 720));
const SECONDS = Number(argOf('seconds', 30));
const BUNDLE = path.resolve(ROOT, argOf('bundle', 'dist/xuehuang.lua'));
const SIM = 'D:/miliastra-beyond-simulator';
const { createRuntime } = await import(pathToFileURL(path.join(SIM, 'client/lua-runtime/src/index.js')).href);

const rt = createRuntime({ canvasWidth: W, canvasHeight: H });
const root = rt.addRoot({ name: 'Canvas', kind: 'container' });
root.SetActive(true);
for (const [i, k] of [[1, 'image'], [2, 'textbox'], [3, 'cursor'], [4, 'container']]) rt.registerTemplate(i, { kind: k });

// ★ 运行时把脚本 print 收进 rt.logs（没有可注入的 onLog；options.log 是方法名，传了无效）
function logLines() { return (rt.logs || []).map(x => String(x.text || '')); }

rt.mountScript({
  path: 'main',
  source: fs.readFileSync(BUNDLE, 'utf8'),
  control: root,
  // autoplay=1 让脚本自己开门进 play；stateEvery=1 每帧吐一行状态，便于逐帧对齐
  params: { autoplay: 1, keyLog: 0, stateEvery: 1 },
});

const DT = 1 / 30;
function findCtrl(name) {
  let out = null;
  (function walk(c) {
    if (out) return;
    if (String(c.name || '') === name) { out = c; return; }
    for (const k of (c.children || [])) walk(k);
  })(root);
  return out;
}
function textOf(name) { const c = findCtrl(name); return c ? String(c.text === undefined ? '' : c.text) : ''; }

let pass = 0, fail = 0;
function ok(c, m) { if (c) { pass++; console.log('  OK  ' + m); } else { fail++; console.log('  X   ' + m); } }

// ══ 逐帧扫描：同一帧内比较"逻辑状态"与"工位卡文字" ══
const workRe = /work=\[([^\]]*)\]/;
function lastStateLine() {
  const all = logLines().filter(x => x.indexOf('[STATE]') >= 0);
  return all.length ? all[all.length - 1] : null;
}
const STATIONS = ['shake', 'fire', 'chem', 'brew'];
let framesWithWork = 0, checked = 0, framesWithSlipCards = 0;
const bad = [];

for (let f = 0; f < Math.round(SECONDS / DT); f++) {
  rt.step(DT);
  // 小票行必须真的没了（控件名以 Sl 开头）
  if (findCtrl('SlW1') || findCtrl('Sl1')) framesWithSlipCards++;

  const line = lastStateLine();
  if (!line) continue;
  const m = workRe.exec(line);
  if (!m) continue;
  let anyWork = false;
  const cards = {};
  for (const sid of STATIONS) cards[sid] = textOf('StS_' + sid);
  for (const piece of m[1].split(' ')) {
    const sid = String(piece.split(':')[0] || '').trim();
    if (piece.includes(':-')) continue;
    anyWork = true;
    checked++;
    const st = cards[sid] === undefined ? '' : cards[sid];
    // 有活 → 必须是"要做什么"或"有活·等名额"，绝不能是"无活/等待小票"
    if (st.indexOf('无活') >= 0 || st.indexOf('等待小票') >= 0) {
      bad.push(line.trim() + '  但 StS_' + sid + ' = "' + st + '"');
    }
  }
  if (anyWork) framesWithWork++;
}

console.log('— 表现层 oracle（小票行已删除；工位卡是唯一反馈面）—');
console.log(`  扫描 ${SECONDS}s · 有活帧 ${framesWithWork} · 核对工位帧 ${checked}`);

ok(framesWithWork > 0, '整局里出现过"工位有活"的帧（' + framesWithWork + ' 帧）——为 0 时工位卡永远无活，玩家就会觉得"按键没反应"');
ok(checked > 0, '核对过 ' + checked + ' 个"有活"的工位帧');
const uniqBad = [...new Set(bad)];
ok(uniqBad.length === 0, '有活时工位卡必须显示"要做什么" —— 违反 ' + uniqBad.length + ' 次'
  + (uniqBad.length ? '\n       ' + uniqBad.slice(0, 3).join('\n       ') : ''));
ok(framesWithSlipCards === 0, '小票卡控件已彻底从画面移除（' + framesWithSlipCards + ' 帧还见到）');
ok(textOf('HudClock').indexOf('天') >= 0, 'HUD 时钟显示天数 → 画面确实进了玩区');

console.log('\n  最后 2 行状态行（逻辑侧真值）：');
for (const l of logLines().filter(x => x.indexOf('[STATE]') >= 0).slice(-2)) console.log('    ' + l.trim());
console.log('  当前四个工位卡（画面侧真值）：');
for (const s of STATIONS) console.log(`    StS_${s.padEnd(6)} = "${textOf('StS_' + s)}"`);
console.log(`    HudTip       = "${textOf('HudTip')}"`);
console.log(`    Pk_list      = "${textOf('Pk_list')}"`);

console.log(`\n结果：passed ${pass} / failed ${fail}`);
rt.destroy();
process.exit(fail ? 1 : 0);
