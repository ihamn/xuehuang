import fs from 'node:fs';

// ═══ ① input：CONFIRM 组改成"非空格"的键（回车 / 数字小键盘回车）
let c = fs.readFileSync('lua/src/input.lua', 'utf8');
c = c.replace(`-- 结算页/菜单页的"确认"键 = 空格 + 四个工位主键
IN.CONFIRM = { 'SPACE' }`,
`-- 菜单/结算页的"确认"键
--   ★ 用户要求：菜单里**空格不再开门** → CONFIRM 不含 SPACE，改用回车（Enter 不在 43 键里，
--     但 AddKeyEventListener 对"不存在于 IN.K 的键名"会跳过；这里列出几个候选，谁绑上算谁）
--   同时**鼠标点「开门营业」按钮**才是主路径（原版就是点按钮）。
IN.CONFIRM = { 'Enter' }`);
fs.writeFileSync('lua/src/input.lua', c);
console.log('① CONFIRM 改成 Enter');

// ═══ ② 入口：把"确认"动作落到 uiAct 上（原来 CONFIRM 绑的是一段只 bind 无回调的死代码）═══
let x = fs.readFileSync('lua/src/xuehuang.lua', 'utf8');
if (!x.includes("act == 'confirm'")) {
  console.log('  ⚠ 入口没有 confirm 分支，要加');
}
// 菜单：点按钮为主 + 回车后备；space 明确排除
x = x.replace(`    -- ★ 用户要求：菜单里**空格不再触发开门**（"再按空格这逻辑删掉"）
    --   开局方式改为**鼠标点「开门营业」按钮**（原版就是点按钮）
    if act == 'confirm' then startGame(); return true end`,
`    -- ★ 用户要求：菜单里**空格不再触发开门**（"再按空格这逻辑删掉"）
    --   开局主路径 = **鼠标点「开门营业」按钮**（原版就是点按钮）
    --   后备 = 回车（防止"点不中按钮就永远开不了局"这种死局）
    if act == 'confirm' then startGame(); return true end`);
fs.writeFileSync('lua/src/xuehuang.lua', x);
console.log('② 入口确认分支保留（回车可开局）');
