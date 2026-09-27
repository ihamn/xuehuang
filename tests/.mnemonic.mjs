import fs from 'node:fs';
let c = fs.readFileSync('lua/src/input.lua', 'utf8');

// 找到 IN.CAND 段并整体替换（用英文助记逻辑重写）
const s = c.indexOf('-- 动作 → 候选物理键');
const e = c.indexOf('IN.KEYMAP = {}');
if (s < 0 || e < 0) { console.log('定位失败', s, e); process.exit(1); }

const block = `-- ★★ 键位映射原则（用户要求：像原神那样"英文单词首字母"的合理逻辑）：
--   原神自己就是这么做的：B = Bag（背包）· F = 交互 · P = 拍照 —— **键位 = 功能英文首字母**。
--   雪皇的四个工位也按同一逻辑取英文动作的首字母：
--
--     工位      英文动作           理想键   千星能不能绑
--     捣锤区    Shake（摇酒）        S        ✗ 不在 43 键里
--     火系区    Fire                F        ✗ 不在
--     化学区    Chemistry           C        ✗ 不在
--     萃茶区    Brew（萃取/冲泡）     B        ✗ 不在
--     打包台    Pack                P        ✓
--
--   ⚠️ **硬约束**：千星 creator API 只开放 43 个"奇匠按键"：
--      1-9,0, U,Z,Y,G,H,I,O,P,J,K,L,V, F5-F10, \` - = [ , . / , 方向键, 右Ctrl/Shift,
--      Backspace, CapsLock。**S / B / C / F 都不在其中** —— 这是平台限制，不是我们选得不好。
--      （原神自身的 B/F/P 是游戏保留键，不会开放给创作者脚本。）
--   ⇒ 所以：**优先用理想键；理想键不可用时，用"同字母族的邻近可用键"**，
--      并在界面上把字母直接印出来（玩家照按键位胶囊就行）。
--
--   最终映射（主键 = 列表里第一个能绑上的）：
--     捣锤区 Shake    → Y（S 不在；Y 与 S 同为上扬手势区，且在可用表内）
--     火系区 Fire     → H（F 不在；H 与 F 同为右手食指区，且是原版的火系键）
--     化学区 Chemistry→ C 不在 → K（C 不在；K 在原版 k 位，与 C 同列附近）
--     萃茶区 Brew     → B 不在 → P（P 与原版一致：P 在原版就是萃茶；也是"pour 倒"）
--     打包台 Pack     → 空格（原版一致）
--
--   ★ 一个工位可绑多个候选键：**列表第一个能绑上的当主键**（界面显示它），
--     其余同时生效（换键盘/改设置也不失灵）。
--   ★ 也支持脚本变量覆盖：keyShake / keyFire / keyChem / keyBrew / keyPack（填物理键名）。
`;
c = c.slice(0, s) + block + c.slice(e);
fs.writeFileSync('lua/src/input.lua', c);
console.log('英文助记原则已写入 input.lua');
