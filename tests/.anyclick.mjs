import fs from 'node:fs';
let x = fs.readFileSync('lua/src/xuehuang.lua', 'utf8');

const i = x.indexOf('  -- ★★ 鼠标左键：菜单点「开门营业」开局；结算/总分页点任意处继续');
const j = x.indexOf('  -- ④ 画面');
if (i < 0 || j < 0) { console.log('定位失败'); process.exit(1); }

const block = `  -- ★★ 鼠标左键（菜单 / 结算页）
  --   设计决定：**菜单里点任何地方都开门**。
  --   为什么不做"精确点按钮"：千星的光标坐标（GetCursorUIPos）与控件坐标
  --   （anchoredPosition，原点是父控件中心）**换算口径没有稳定结论** ——
  --   我实测过 H/2±ay 两种约定都不能稳定命中，而菜单页上本来**只有那一个主按钮**，
  --   所以"点屏幕任意处 = 开门营业"在体验上等价，且不会因为坐标偏差而点不动。
  do
    local I = require('input')
    if I.clicked then
      I.clearClick()
      if scene == 'menu' then
        local m = IN.MODES[menuMode]
        if MODE_READY[m] == false then
          tip(string.format('「%s」还在施工中，请先按 1 选「速通」', tostring(m)), 3)
        else
          say('鼠标点击 → 开门营业（模式 %s）', tostring(m))
          startGame()
        end
      elseif scene == 'play' and G.s and (G.s.settling or G.s.ended) then
        -- 结算页：点任意处 = 继续（和确认键同一条路）
        if G.s.ended then enterMenu() else G.nextDay() end
      end
    end
  end

`;
x = x.slice(0, i) + block + x.slice(j);
fs.writeFileSync('lua/src/xuehuang.lua', x);
console.log('菜单点击改成"点任意处开门"');
