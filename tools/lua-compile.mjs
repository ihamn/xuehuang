// lua-compile.mjs —— 用 Fengari 把 lua/src 下每个模块**真编译一遍**
//
// 为什么必须有它：中文注释的字节里会出现引号/反斜杠之类的字节，逐字节加载会误报，
// 所以 lua-check.mjs 只做词法检查。而**真正的语法错误**（比如把 `in ipairs` 写成 `of ipairs`）
// 只有编译才知道 —— 这个工具就是干这个的：把非 ASCII 字节替换掉再编译，既避开误报又能抓真错。
// 它已经抓到过一次真错（order.lua 里的 `for ... of`），所以别再省这一步。
//   node tools/lua-compile.mjs
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const SIM = 'D:/miliastra-beyond-simulator/client/lua-runtime/node_modules/fengari/src/fengari.js';
if (!fs.existsSync(SIM)) { console.log('跳过：没找到 fengari'); process.exit(0); }
const fengari = (await import(pathToFileURL(SIM).href)).default;

const dirs = [path.join(ROOT, 'lua', 'src'), path.join(ROOT, 'lua', 'test')];
let bad = 0, n = 0;
for (const dir of dirs) {
  if (!fs.existsSync(dir)) continue;
  for (const name of fs.readdirSync(dir).filter(x => x.endsWith('.lua'))) {
    n++;
    const src = fs.readFileSync(path.join(dir, name), 'utf8').replace(/[^\x00-\x7F]/g, ' ');
    const L = fengari.lauxlib.luaL_newstate();
    fengari.lualib.luaL_openlibs(L);
    const st = fengari.lauxlib.luaL_loadbuffer(L, Buffer.from(src, 'latin1'), null, name);
    if (st !== fengari.lua.LUA_OK) {
      try { fengari.lauxlib.luaL_tolstring(L, -1); } catch {}
      console.log(`  ✗ ${path.basename(dir)}/${name}: ${fengari.lua.lua_tojsstring(L, -1) || '?'}`);
      bad++;
    } else {
      console.log(`  ✓ ${path.basename(dir)}/${name}`);
    }
    fengari.lua.lua_close(L);
  }
}
console.log(bad ? `\n✗ ${bad}/${n} 个文件编译失败` : `\n✓ ${n} 个 Lua 文件全部编译通过`);
process.exit(bad ? 1 : 0);
