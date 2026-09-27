import fs from 'node:fs';
let v = fs.readFileSync('lua/src/view.lua', 'utf8');

// ① hold 类：文案改成直白指引"按住不放"（点一下只加一帧，玩家会误以为要点 30 次）
v = v.replace(`          prog = string.format('   按住 %.1f/%.1f 秒', nx.done or 0, full)`,
              `          prog = string.format('   按住不放 ↦ %.1f/%.1f 秒', nx.done or 0, full)`);
// ② mash 类：写明"连按"
v = v.replace(`          prog = string.format('   连按 %d/%d', nx.done or 0, nx.taps or 1)`,
              `          prog = string.format('   连按 ↦ %d/%d 下', nx.done or 0, nx.taps or 1)`);
// ③ 无活：文案缩短（避免被 clip 截断）
v = v.replace(`          setText(slot.step, string.format('本工位无活（按 %s 无效）', kname))`,
              `          setText(slot.step, '本工位无活')`);
fs.writeFileSync('lua/src/view.lua', v);
console.log('文案已改为直白指引');
