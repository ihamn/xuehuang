import fs from 'node:fs';
let x = fs.readFileSync('lua/src/xuehuang.lua', 'utf8');
// 菜单就绪日志：还在说"按空格开门营业"（早就改了）
x = x.replace("say('已就绪 BUILD=%s —— 菜单（选模式后按空格开门营业）', BUILD)",
              "say('已就绪 BUILD=%s —— 菜单（选模式后点屏幕开门）', BUILD)");
x = x.replace("tip(string.format('BUILD=%s  菜单：按 1 选模式 → 空格开门营业', BUILD), 6)",
              "tip(string.format('BUILD=%s  菜单：点屏幕开门（或按退格）', BUILD), 6)");
fs.writeFileSync('lua/src/xuehuang.lua', x);
console.log('菜单提示已改（不再说"空格"）');
