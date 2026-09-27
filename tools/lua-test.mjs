// lua-test.mjs —— 把 lua/src 下的多个模块合成一份，在真机同款运行时里跑逻辑测试
//
// 两个用途：
//   ① 打包：`node tools/lua-test.mjs --bundle dist/xuehuang.lua` → 生成单文件（真机上传用）
//   ② 测试：`node tools/lua-test.mjs lua/test/logic_test.lua` → 合成 + 挂载 + 打印结果
//
// 为什么需要合成：真机的 require 是**按映射路径**加载的，但"单文件上传"更稳（少一层映射就没法出错）。
// 所以：本地按 require 开发 → 打成一个文件 → 上传那个文件。
// 合成时给每个模块套一层函数，构造一个最小 require（带缓存，和真机语义一致）。
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const SRC = path.join(ROOT, 'lua', 'src');
const SIM = 'D:/miliastra-beyond-simulator/client/lua-runtime/node_modules/fengari/src/fengari.js';
const argOf = (n, d) => { const h = process.argv.find(a => a.startsWith('--' + n + '=')); return h ? h.slice(n.length + 3) : d; };

// ── 收集模块（按文件名，不含目录前缀；子目录用 "目录/文件名"）──
// 不进包的模块（自检脚本 / 纯开发用）
const BUNDLE_SKIP = new Set(['hello']);
function collect(dir, prefix) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) out.push(...collect(path.join(dir, e.name), prefix ? prefix + '/' + e.name : e.name));
    else if (e.name.endsWith('.lua')) {
      const name = e.name.replace(/\.lua$/, '');
      if (BUNDLE_SKIP.has(name)) continue;
      out.push({ name, key: prefix ? prefix + '/' + name : name, src: fs.readFileSync(path.join(dir, e.name), 'utf8') });
    }
  }
  return out;
}

/**
 * 只清洗**注释和字符串字面量之外**的非 ASCII 字节。
 *
 * ★ 为什么这么做（这是个我自己造成的严重 bug）：
 *   真机的 Lua 逐字节读源码，非 ASCII 字节会让整份脚本**加载失败**，
 *   所以合成时要处理。但我一开始"把所有非 ASCII 换成空格"，于是
 *   `'雪皇的后厨'` 变成了 `'      '` —— 脚本能跑、控件都建出来、日志全正常，
 *   只有**屏幕上一个字都没有**。这个症状极难定位（逻辑/控件/属性全对）。
 *   正确做法：
 *     · 注释里的非 ASCII → 换成空格（注释内容无关紧要）
 *     · 字符串字面量里的非 ASCII → **转成 Lua 十进制转义** `\229\164\169`
 *       （Lua 5.3 的十进制转义正好表示一个字节，拼起来就是原来的 UTF-8 → 中文照常显示）
 */
function stripNonAscii(src) {
  let out = '';
  let i = 0;
  const n = src.length;
  const isNL = c => c === '\n' || c === '\r';
  while (i < n) {
    const c = src[i];
    // 行注释
    if (c === '-' && src[i + 1] === '-') {
      const nl = src.indexOf('\n', i);
      out += src.slice(i, nl < 0 ? n : nl);
      i = nl < 0 ? n : nl;
      continue;
    }
    // 长字符串 [[ ... ]]（可能含中文；不能转义，只能删）
    if (c === '[') {
      const m = /^\[(=*)\[/.exec(src.slice(i));
      if (m) {
        const close = ']' + m[1] + ']';
        const end = src.indexOf(close, i);
        const stop = end < 0 ? n : end + close.length;
        out += src.slice(i, stop).replace(/[^\x00-\x7F]/g, ' ');
        i = stop;
        continue;
      }
    }
    // 普通字符串：保留内容，非 ASCII 转成十进制转义
    if (c === '"' || c === "'") {
      const q = c;
      out += q;
      i++;
      while (i < n) {
        const d = src[i];
        if (d === '\\') { out += src.slice(i, i + 2); i += 2; continue; }
        if (d === q) { out += q; i++; break; }
        if (isNL(d)) { out += d; i++; continue; }   // 不该发生，保底
        const cp = src.codePointAt(i);
        if (cp > 127) {
          // UTF-8 逐字节转义（Lua 5.3：\ddd 表示一个字节）
          const bytes = Buffer.from(String.fromCodePoint(cp), 'utf8');
          out += [...bytes].map(b => '\\' + b).join('');
          i += String.fromCodePoint(cp).length;
          continue;
        }
        out += d;
        i++;
      }
      continue;
    }
    // 其它位置（代码、空白）：非 ASCII 一律换成空格
    const cp = src.codePointAt(i);
    if (cp > 127) { out += ' '; i += String.fromCodePoint(cp).length; continue; }
    out += c;
    i++;
  }
  return out;
}

/**
 * 把 lua/src 下的模块**铺平**成一段代码（不是"模块包装 + require 表"）。
 *
 * ★ 为什么必须铺平：真机/模拟器按固定名字在**本段代码的环境**里找生命周期函数。
 *   我原来用 `__mods[name] = function() … end` + 一张 require 表，结果
 *   OnInit/OnStart 能找到、**OnUpdate 永远不被调用**（画面完全不动，极难定位）。
 *   改成铺平之后，每个模块的代码都在同一层作用域里、`function OnUpdate()` 就是普通全局函数，
 *   和能正常跑的 hello.lua 完全同一种形态。
 *
 * 做法（保持"每个模块一个独立作用域"的语义）：
 *   模块 A 的代码包一层 `local function __m_A() … end`，内部 `require('x')` 改写为 `__m_x()`，
 *   结果缓存进 `__c_x`。入口模块的代码**不加包装、直接铺在最外层**，保证生命周期是全局函数。
 */
function bundle(entryName) {
  const all = collect(SRC, '');
  const entry = entryName ? all.find(m => m.key === entryName) : null;
  if (entryName && !entry) throw new Error('入口模块不存在：' + entryName);

  // 模块名 → 合法的 Lua 标识符（目录用 _ 代替）
  const idOf = m => '__m_' + m.key.replace(/[^A-Za-z0-9_]/g, '_');
  const cacheOf = m => '__c_' + m.key.replace(/[^A-Za-z0-9_]/g, '_');
  const funcOf = key => '__m_' + key.replace(/[^A-Za-z0-9_]/g, '_');
  const known = new Set(all.map(m => m.key));
  // 把 require('x') 改写成对**取用函数**的调用（__m_x()，内部查缓存）。
  //   ⚠️ 只改写"我们自己的模块"；别的名字（真机上的平台模块）保持原样，否则会调不存在的函数。
  const rewrite = src => src.replace(/require\s*\(\s*(['"])([^'"]+)\1\s*\)/g,
    (whole, q, name) => (known.has(name) ? funcOf(name) + '()' : whole));

  const parts = [];
  parts.push('-- ==== 自动合成（铺平形态），请勿手改 ====');
  parts.push('-- 源：lua/src/*.lua　　生成：node tools/lua-test.mjs --entry=' + (entryName || '') + ' --out=<文件>');
  parts.push('-- 每个模块一个独立作用域 + 结果缓存；入口源码铺在同一层（生命周期函数必须是全局）');
  // ★ 外层 do…end：模块的取用函数都声明在这一层，入口代码同处一层才能看到它们。
  parts.push('do');

  const others = all.filter(m => m !== entry);
  // ★ 先把所有"取用函数"**前置声明**：模块之间会互相 require（recipes→config 等），
  //   而 Lua 的 `local function` 在定义前不可见 → 会报 `attempt to call a nil value (global '__m_recipes')`。
  for (const m of others) parts.push(`local ${cacheOf(m)}, ${idOf(m)}`);
  for (const m of others) {
    // ★ 缓存赋值必须在函数体内（接住模块的返回值）；写在函数外就成了"先调用再赋值"，
    //   模块间互相 require 时会拿到 nil（`attempt to call a table value (upvalue '__c_config')`，我踩过）。
    parts.push(`${idOf(m)} = function()`);
    parts.push('  if ' + cacheOf(m) + ' ~= nil then return ' + cacheOf(m) + ' end');
    parts.push('  ' + cacheOf(m) + ' = (function()');
    parts.push(rewrite(stripNonAscii(m.src)));
    parts.push('  end)()');
    parts.push('  if ' + cacheOf(m) + ' == nil then ' + cacheOf(m) + ' = true end');
    parts.push('  return ' + cacheOf(m));
    parts.push('end');
  }
  if (entry) {
    parts.push('-- ── 入口源码（与本层同级：能看见上面的缓存；生命周期函数在这里定义 = 真正的全局）──');
    parts.push(rewrite(stripNonAscii(entry.src)));
  }
  parts.push('end');
  return { code: parts.join('\n'), mods: all };
}

/** 在模拟器里跑一段 Lua，返回日志 */
async function runLua(code, label) {
  if (!fs.existsSync(SIM)) return { skipped: true, logs: [] };
  const fengari = (await import(pathToFileURL(SIM).href)).default;
  const { createRuntime } = await import(pathToFileURL('D:/miliastra-beyond-simulator/client/lua-runtime/src/index.js').href);
  const rt = createRuntime({ canvasWidth: 1280, canvasHeight: 720 });
  const root = rt.addRoot({ name: 'Canvas', kind: 'container' });
  rt.registerTemplate(1, { kind: 'image' });
  rt.registerTemplate(2, { kind: 'textbox' });
  rt.registerTemplate(3, { kind: 'cursor' });
  rt.registerTemplate(4, { kind: 'container' });
  const wrapped = `
function OnInit() script:EnableUpdate(true) end
local __err = nil
function OnStart()
  local ok, e = pcall(function()
${code.split('\n').map(l => '    ' + l).join('\n')}
  end)
  if not ok then __err = tostring(e); print('TEST-ERROR ' .. __err) end
end
function OnUpdate(dt) end
return { OnInit = OnInit, OnStart = OnStart, OnUpdate = OnUpdate }`;
  rt.mountScript({ path: 'main', source: wrapped, control: root, params: {} });
  for (let i = 0; i < 5; i++) rt.step(1 / 30);
  const logs = (rt.logs || []).map(l => `[${l.level}] ${l.text}`);
  rt.destroy();
  return { skipped: false, logs };
}

// 取 --bundle 的值：支持 `--bundle=x` 与 `--bundle x` 两种写法
// 合成单文件：
//   --bundle out/x.lua                 只打包模块（当库）
//   --entry=xuehuang --out=out/x.lua   以 xuehuang 为入口打成**可挂载的单文件**（推荐给真机）
let bundleOut = null;
let entryName = null;
{
  for (let i = 2; i < process.argv.length; i++) {
    const a = process.argv[i];
    if (a === '--bundle') bundleOut = process.argv[i + 1] || null;
    else if (a.startsWith('--bundle=')) bundleOut = a.slice('--bundle='.length);
    else if (a.startsWith('--entry=')) entryName = a.slice('--entry='.length);
    else if (a === '--entry') entryName = process.argv[i + 1] || null;
    else if (a.startsWith('--out=')) bundleOut = a.slice('--out='.length);
    else if (a === '--out') bundleOut = process.argv[i + 1] || null;
  }
}
if (bundleOut) {
  const { code, mods } = bundle(entryName);
  const out = path.resolve(ROOT, bundleOut);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, code);
  console.log(`已合成：${path.relative(ROOT, out)}  ${Buffer.byteLength(code)} 字节  ${mods.length} 个模块` +
    (entryName ? `  入口=${entryName}（可直接挂到客户端控件上）` : '（纯库，无入口）'));
  process.exit(0);
}

  // 测试文件 = 第一个非 flag、且**不是 --bundle/--xxx 的取值**的参数
  //   （第一版直接用"第一个非 flag 参数"，结果 --bundle out/x.lua 里的 out/x.lua 被当成测试文件）
  const flagValues = new Set();
  for (let i = 2; i < process.argv.length; i++) {
    const a = process.argv[i];
    if (a.startsWith('--') && !a.includes('=')) flagValues.add(process.argv[i + 1]);
  }
  const testFile = process.argv.slice(2).find(a => !a.startsWith('--') && !flagValues.has(a));
  if (testFile) {
  const tf = path.resolve(ROOT, testFile);
  // ★ 真机的 Lua 是**逐字节**读源码的：中文/emoji 的字节序列会让它报
  //   "unexpected symbol near '<\239>'"。所以测试运行前把非 ASCII 换掉（行号不变），
  //   中文字符串会变成 ### —— 测试里的中文只用于打印，不影响断言。
  const testSrc = fs.readFileSync(tf, 'utf8').replace(/[^\x00-\x7F]/g, ' ');
  // 测试文件自己也当成一个模块挂进合成体（这样它能 require 我们的模块）
  const { code } = (() => {
    const mods = collect(SRC, '');
    const parts = [];
    parts.push('local __mods, __cache = {}, {}');
    parts.push('local function __require(name)');
    parts.push('  name = tostring(name):gsub("%.lua$", ""):gsub("\\\\", "/")');
    parts.push('  if __cache[name] ~= nil then return __cache[name] end');
    parts.push('  local f = __mods[name]');
    parts.push('  if not f then error("module not found: " .. name) end');
    parts.push('  local v = f()');
    parts.push('  if v == nil then v = true end');
    parts.push('  __cache[name] = v');
    parts.push('  return v');
    parts.push('end');
    for (const m of mods) parts.push(`__mods[${JSON.stringify(m.key)}] = function()\n${stripNonAscii(m.src)}\nend`);
    // ★ 关键：把注入的 __require 暴露成**全局 require**，测试文件里就能照常写 require('config')。
    //   （第一版忘了这步，测试里调的是真机的 require，于是报 "failed to load script 'config'"）
    parts.push('_G.require = __require');
    parts.push(testSrc);
    return { code: parts.join('\n') };
  })();
  const r = await runLua(code, path.basename(tf));
  if (r.skipped) { console.log('跳过：没找到模拟器'); process.exit(0); }
  let fail = 0;
  for (const l of r.logs) {
    console.log('  ' + l);
    if (l.includes('TEST-ERROR') || l.includes('✗')) fail++;
  }
  console.log(fail ? `\n✗ ${fail} 处问题` : '\n✓ 逻辑测试通过');
  process.exit(fail ? 1 : 0);
}

console.log('用法：');
console.log('  node tools/lua-test.mjs --bundle dist/xuehuang.lua        # 合成单文件');
console.log('  node tools/lua-test.mjs lua/test/logic_test.lua          # 跑逻辑测试');
