import fs from 'node:fs';
let c = fs.readFileSync('lua/src/input.lua', 'utf8');

// 整体重写 IN.CAND（英文助记 → 可用键）
const s = c.indexOf('IN.CAND = {');
const e = c.indexOf('IN.KEYMAP = {}');
if (s < 0 || e < 0) { console.log('定位失败', s, e); process.exit(1); }

const block = `IN.CAND = {
  -- 工位：{ 理想键(英文首字母), 实际可用键… }
  --   Shake(S 不可用) → Y     Fire(F 不可用) → H
  --   Chemistry(C 不可用) → K  Brew(B 不可用) → P      Pack → 空格
  shake = { 'Y', 'H', 'S', 'Z' },   -- 捣锤 Shake：S 不在 → Y（主）
  fire  = { 'H', 'F', 'G', 'Y' },   -- 火系 Fire：F 不在 → H（主，也是原版键）
  chem  = { 'K', 'C', 'V', 'J' },   -- 化学 Chemistry：C 不在 → K（主）
  brew  = { 'P', 'B', 'O', 'I' },   -- 萃茶 Brew：B 不在 → P（主，也是原版键）
  pack  = { 'SPACE' },              -- 打包 Pack：空格（原版一致）
  -- 调试（不显示在界面上）
  auto   = { ',', '.' },
  ticket = { '.', '/' },
}
`;
c = c.slice(0, s) + block + c.slice(e);
fs.writeFileSync('lua/src/input.lua', c);
console.log('IN.CAND 已按英文助记重写');
