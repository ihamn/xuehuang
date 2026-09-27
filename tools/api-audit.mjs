// api-audit.mjs —— 用官方 API 的 LuaLS 注解，系统性审计我们的 Lua 代码
//
//   node tools/api-audit.mjs
//
// 为什么需要它：真机上"字段/方法/枚举成员名写错"或"给只读字段赋值"**不会报错**，
//   只会静静不生效（或被 pcall 吞掉）—— 表现就是"代码看着全对、画面上没动静"。
//   注解文件（lua/types/mihoyo_client_ui_api.d.lua，社区按官方文档整理）标了每个
//   字段/方法/枚举成员与**只读性**，拿它对照我们的代码，就能在上传前揪出这类问题。
//
// 已抓到的真实 bug（示例）：
//   · `up:GetParent()` —— 官方没有 GetParent 方法，`parent` 是**字段** → 真机静默失效
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const DTS = path.join(ROOT, 'lua', 'types', 'mihoyo_client_ui_api.d.lua');
if (!fs.existsSync(DTS)) { console.log('缺注解文件：lua/types/mihoyo_client_ui_api.d.lua'); process.exit(0); }

// ── 1. 解析注解 ──
const dts = fs.readFileSync(DTS, 'utf8').split('\n');
const classes = {};          // 类 → { fields:{name:{type,ro}}, methods:Map(name→参数个数) }
const enums = {};            // 枚举类名 → Set(成员)
const gameFns = new Map();   // game.Fn → 参数个数
let cur = null;
let lastDocParams = [];

const ensure = n => (classes[n] = classes[n] || { fields: {}, methods: new Map() });
const enumEnsure = n => (enums[n] = enums[n] || new Set());

for (const raw of dts) {
  const line = raw.replace(/\r$/, '');
  const mc = /^---@class\s+(\w+)/.exec(line);
  if (mc) {
    cur = mc[1];
    if (/^Enum/.test(cur)) enumEnsure(cur); else ensure(cur);
    continue;
  }
  if (cur && /^Enum/.test(cur)) {
    const me = /^\s*---@field\s+(\w+)\s/.exec(line);
    if (me) { enumEnsure(cur).add(me[1]); continue; }
  }
  if (cur && !/^Enum/.test(cur)) {
    const mf = /^\s*---@field\s+(\w+)\s+([^\s#]+)\s*(?:#\s*(.*))?$/.exec(line);
    if (mf) { ensure(cur).fields[mf[1]] = { type: mf[2], ro: /只读/.test(mf[3] || '') }; continue; }
  }
  const mp = /^\s*---@param\s+(\w+)/.exec(line);
  if (mp) { lastDocParams.push(mp[1]); continue; }
  // ★ 方法按**类名**归属：注解文件里类声明与方法定义并不相邻
  //   （ClientUIBaseControl 声明在 561 行、它的方法在 1130 行之后），
  //   用"当前 @class"会把所有方法都算到最后一个类头上。
  const mm = /^\s*function\s+([\w.]+)[:.]([\w]+)\s*\(([^)]*)\)/.exec(line);
  if (mm) {
    const [, cls, name, argsRaw] = mm;
    const declared = argsRaw.trim() === '' ? 0 : argsRaw.split(',').length;
    const cnt = declared || lastDocParams.length;
    if (cls === 'game') gameFns.set(name, cnt);
    else ensure(cls).methods.set(name, cnt);
    lastDocParams = [];
    continue;
  }
  if (!/^\s*$/.test(line) && !/^\s*---/.test(line)) lastDocParams = [];
}

// 汇总"控件"的字段与方法（我们的代码是泛型地操作控件的）
const CTRL = Object.keys(classes).filter(c => /Control$/.test(c) || c === 'Script' || c === 'Game' || c === 'CursorEventData');
const ALL_FIELDS = {};
const ALL_METHODS = new Map();
for (const cn of CTRL) {
  const c = classes[cn];
  if (!c) continue;
  for (const [f, v] of Object.entries(c.fields)) {
    ALL_FIELDS[f] = ALL_FIELDS[f] || { ro: true };
    if (!v.ro) ALL_FIELDS[f].ro = false;
  }
  for (const [m, n] of c.methods) if (!ALL_METHODS.has(m)) ALL_METHODS.set(m, n);
}
const ENUM_MEMBERS = {};
for (const [e, set] of Object.entries(enums)) ENUM_MEMBERS[e.replace(/^Enum/, '')] = set;

// ── 2. 审计源码 ──
const FILES = ['xuehuang.lua', 'host.lua', 'view.lua', 'input.lua', 'game.lua', 'kitchen.lua', 'order.lua', 'day.lua', 'state.lua', 'config.lua', 'recipes.lua'];
const OWN_OBJECTS = new Set(['CFG', 'V', 'H', 'C', 'STATE', 'G', 'K', 'O', 'S', 'R', 'D', 'IN', 'self', 's', 'v', 'e', 'r', 'o', 'c', 'p', 'sl', 'st', 'cup', 'rec', 'nx', 'cfg', 'hostCfg', 'slot', 'card', 't', 'u', 'args']);
const LUA_STR = new Set(['find', 'gsub', 'sub', 'format', 'len', 'rep', 'match', 'gmatch', 'byte', 'char', 'upper', 'lower', 'reverse', 'insert', 'remove', 'concat', 'sort', 'unpack', 'pack']);
const OWN_METHODS = new Set();
const problems = { ro: [], missMethod: [], missEnum: [], argCount: [], missGame: [] };

for (const f of FILES) {
  const p = path.join(ROOT, 'lua', 'src', f);
  if (!fs.existsSync(p)) continue;
  const src = fs.readFileSync(p, 'utf8');
  for (const m of src.matchAll(/function\s+(?:\w+)\.(\w+)\s*\(/g)) OWN_METHODS.add(m[1]);
  for (const m of src.matchAll(/function\s+(?:\w+)\.(\w+)\.(\w+)\s*\(/g)) OWN_METHODS.add(m[2]);
  src.split('\n').forEach((line, i) => {
    const code = line.replace(/--.*$/, '');
    const at = `${f}:${i + 1}`;
    // ① 只读字段赋值
    for (const m of code.matchAll(/(\w+)\.(\w+)\s*=[^=]/g)) {
      const [, obj, field] = m;
      if (OWN_OBJECTS.has(obj)) continue;
      if (!(field in ALL_FIELDS)) continue;
      if (ALL_FIELDS[field].ro) problems.ro.push({ at, field, text: line.trim() });
    }
    // ② 方法不存在 / ④ 参数个数
    // ★ 手写扫描：方法调用后面跟一对**配对**的括号，正则处理不了嵌套
    for (const m of code.matchAll(/(\w+):(\w+)\s*\(/g)) {
      const meth = m[2];
      const open = m.index + m[0].length - 1;
      let depth = 0, close = -1;
      for (let k = open; k < code.length; k++) {
        const ch = code[k];
        if (ch === '(') depth++;
        else if (ch === ')') { depth--; if (depth === 0) { close = k; break; } }
      }
      if (close < 0) continue;
      const args = code.slice(open + 1, close);
      if (LUA_STR.has(meth) || OWN_METHODS.has(meth) || meth === 'GetChildren') continue;
      if (!ALL_METHODS.has(meth)) { problems.missMethod.push({ at, field: meth, text: line.trim() }); continue; }
      // ★ 按**顶层括号深度**切逗号：`w or (size * 12), h` 这种不能数成 3 个
      const topLevelArgs = (s) => {
        const t = s.trim();
        if (!t) return 0;
        let depth = 0, n = 1;
        for (const ch of t) {
          if (ch === '(' || ch === '[' || ch === '{') depth++;
          else if (ch === ')' || ch === ']' || ch === '}') depth--;
          else if (ch === ',' && depth === 0) n++;
        }
        return n;
      };
      const n = topLevelArgs(args);
      const want = ALL_METHODS.get(meth);
      if (!args.includes('...') && want > 0 && n !== want) {
        problems.argCount.push({ at, field: `${meth}（传 ${n}，注解 ${want}）`, text: line.trim() });
      }
    }
    // ③ 枚举成员
    for (const m of code.matchAll(/Enum\.(\w+)\.(\w+)/g)) {
      const [, en, mem] = m;
      const set = ENUM_MEMBERS[en];
      if (set && !set.has(mem)) problems.missEnum.push({ at, field: `Enum.${en}.${mem}`, text: line.trim() });
    }
    // ⑤ game 函数
    for (const m of code.matchAll(/game\.(\w+)\s*\(/g)) {
      const fn = m[1];
      if (!gameFns.has(fn)) problems.missGame.push({ at, field: `game.${fn}`, text: line.trim() });
    }
  });
}

// ── 3. 报告 ──
console.log(`注解：${Object.keys(classes).length} 类（控件 ${CTRL.length}）· 控件字段 ${Object.keys(ALL_FIELDS).length} · 控件方法 ${ALL_METHODS.size}` +
  ` · 枚举 ${Object.keys(ENUM_MEMBERS).length} 类 · game 函数 ${gameFns.size}`);
const roList = Object.entries(ALL_FIELDS).filter(([, v]) => v.ro).map(([k]) => k);
console.log(`只读字段（${roList.length}）：${roList.join(', ')}`);
console.log('');
const total = Object.values(problems).reduce((a, b) => a + b.length, 0);
if (!total) { console.log('✓ 未发现问题'); process.exit(0); }
const show = (title, list) => {
  if (!list.length) return;
  console.log(`【${title}】${list.length} 处`);
  for (const p of list.slice(0, 12)) console.log(`   ${p.at}  ${p.field}   ← ${p.text.slice(0, 84)}`);
};
show('给只读字段赋值', problems.ro);
show('方法不存在（真机会静默失效）', problems.missMethod);
show('枚举成员不存在', problems.missEnum);
show('参数个数不符', problems.argCount);
show('game 函数不存在', problems.missGame);
process.exit(1);
