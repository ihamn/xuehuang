// cup-player.mjs —— 工序播放器（杯子原型页里的「⑦ 工序播放器」）的微量测试
//
//   node tests/cup-player.mjs
//
// 验三件事：
//   ① **玩家按一下，杯子里必须看得见变化**（液体增加 / 出现干冰 / 增加配料）——
//      这正是用户提的问题；没变化的步必须是显式标注的"器具步"。
//   ② 连按步（mash）要**在次数里均分**涨液面，且**没按满不许触发**（否则"次数"这个玩法就没了）。
//   ③ 网页里的 VIS 表与 lua/src/recipes.lua 的 vis 字段**不漂移**（两边是同一份数据的两次抄写）。
import fs from 'node:fs';
import path from 'node:path';
import { loadPage } from './_fakedom.mjs';
import { parseRecipes } from './_recipe-vis.mjs';

const ROOT = path.resolve(import.meta.dirname, '..');
const html = fs.readFileSync(path.join(ROOT, 'preview', '杯子-原型.html'), 'utf8');
const env = loadPage(html);
const C = env.ctx.CUP;

let bad = 0;
const chk = (ok, msg) => { console.log(`  ${ok ? '✓' : '✗'} ${msg}`); if (!ok) bad++; };

console.log('杯子工序播放器 · 微量测试');
chk(!!C && !!C.VIS && !!C.playHit, '页面暴露了播放器 API');
chk(C.PRODUCTS.length === 6, `播放器有 ${C.PRODUCTS.length} 个产品`);

/* ───────── ① 逐步走一遍：干冰干柠檬水（6 步 / 16 次操作）───────── */
//   ★ 顺序是用户 2026-10-01 改定的：**先压缩、后加水**。
//     所以这里顺带断言"压缩时杯子还是空的"—— 这就是那条改动的核心。
C.playLoad('dryice');
{
  const ct = () => C.content();
  chk(ct().fill === 0 && ct().toppings.lemon === 0 && !ct().states.dryice, '起始：空杯、无配料、无干冰');

  C.playHit();                                     // 1 双手握住杯子（hold）
  chk(ct().fill === 0 && !ct().states.dryice, '①双手握住 → 只晃杯子，杯子还是空的');

  C.playHit();                                     // 2 压缩 1/6
  chk(ct().states.bubble === false, '②压缩 1/6：**没按满，不触发气泡**');
  chk(ct().fill === 0, `②压缩时杯里**还没有水**（液面 ${(ct().fill * 100).toFixed(0)}%）—— 压的是空气，这就是改顺序的理由`);
  for (let i = 0; i < 5; i++) C.playHit();
  chk(ct().states.bubble === true, '②压缩 6/6 按满 → **出现气泡**');

  for (let i = 0; i < 6; i++) C.playHit();         // 3 继续压缩 6/6
  chk(ct().states.dryice === true, '③继续压缩按满 → **出现干冰（白雾+结霜）**');
  chk(ct().fill === 0, '③此时仍是空杯（干冰躺在杯底）');

  C.playHit();                                     // 4 放入干柠檬片
  chk(ct().toppings.lemon === 1, '④放入干柠檬片 → 杯里**出现柠檬片**');

  C.playHit();                                     // 5 加水至七分满
  chk(Math.abs(ct().fill - 0.70) < 1e-9, `⑤加水至七分满 → 液面涨到 ${(ct().fill * 100).toFixed(0)}%`);
  chk(ct().states.fogburst === true, '⑤**干冰遇水 → 白雾爆发**（这一步的演出）');

  C.playHit();                                     // 6 封杯出餐
  chk(ct().lid === true, '⑥封杯出餐 → **盖上盖子**');
  chk(C.play().done === true, '走完 6 步后标记完成');
}

/* ───────── ② 连按步：液面在次数里**均分**涨上去 ───────── */
C.playLoad('bromine');
C.playHit();                                       // 1 取 10ml 原液
chk(Math.abs(C.content().fill - 0.15) < 1e-9, '①取原液 → 液面 15%');
{
  const seen = [];
  for (let i = 0; i < 5; i++) { C.playHit(); seen.push(C.content().fill); }
  const mono = seen.every((v, i) => i === 0 || v >= seen[i - 1] - 1e-9);
  chk(mono, `②加满空杯（mash5）：液面逐步上涨 ${seen.map(v => (v * 100).toFixed(0) + '%').join(' → ')}`);
  chk(seen[0] > 0.15 && seen[0] < 1.0, '②第 1 下就跳满是不对的（必须**逐步**涨，玩家才看到"在涨"）');
  chk(Math.abs(seen[4] - 1.0) < 1e-9, '②按满 5 下 → 满杯 100%');
}

/* ───────── ③ 每一步都必须有可见变化（或显式标注为器具步）───────── */
{
  let noEffect = 0, toolSteps = 0, total = 0;
  C.PRODUCTS.forEach(p => {
    C.steps(p.id).forEach((st, i) => {
      total++;
      const v = st.vis || {};
      const keys = Object.keys(v).filter(k => k !== 'tool');
      if (keys.length === 0) { if (v.tool) toolSteps++; else { noEffect++; console.log(`      ✗ [${p.name}] 第 ${i + 1} 步没有任何视觉字段：${st.t}`); } }
    });
  });
  chk(noEffect === 0, `全部 ${total} 步都有可见变化（无变化的必须标 tool）`);
  // 4 个 = 咖啡前三步（作用于咖啡机）+ 甜筒的「掏出枪筒」（作用于枪筒，杯子/甜筒本体不动）
  chk(toolSteps === 4, `器具步 ${toolSteps} 个（咖啡 3 + 枪筒 1）—— 这类杯子不动，必须另有提示，否则就是"按了没反应"`);
}

/* ───────── ④ 与 recipes.lua 不漂移 ───────── */
{
  // ★ 用 **共享解析器**（tests/_recipe-vis.mjs），不再各写一份 —— 见该文件头的 4 次踩坑记录
  const luaVis = parseRecipes(fs.readFileSync(path.join(ROOT, 'lua', 'src', 'recipes.lua'), 'utf8'));
  const pageVis = {};
  C.PRODUCTS.forEach(p => { pageVis[p.id] = C.steps(p.id).map(s => ({ t: s.t, kind: s.kind, taps: s.taps ? String(s.taps) : undefined, vis: JSON.parse(JSON.stringify(s.vis)) })); });

  let drift = 0;
  C.PRODUCTS.forEach(p => {
    const a = (luaVis[p.id] || {}).steps, b = pageVis[p.id];   // 共享解析器返回 { name, steps }
    if (!a) { console.log(`      ✗ lua 里没有产品 ${p.id}`); drift++; return; }
    if (a.length !== b.length) { console.log(`      ✗ [${p.id}] 步数不一致：lua ${a.length} / 网页 ${b.length}`); drift++; return; }
    a.forEach((sa, i) => {
      const sb = b[i];
      const ka = JSON.stringify(Object.keys(sa.vis).sort()), kb = JSON.stringify(Object.keys(sb.vis).sort());
      const canon = (o) => JSON.stringify(Object.keys(o).sort().map(k => [k, o[k]]));
      const saTaps = sa.taps === undefined ? undefined : String(sa.taps), sbTaps = sb.taps === undefined ? undefined : String(sb.taps);
      if (sa.t !== sb.t || sa.kind !== sb.kind || saTaps !== sbTaps || ka !== kb || canon(sa.vis) !== canon(sb.vis)) {
        drift++;
        console.log(`      ✗ [${p.id}] 第 ${i + 1} 步不一致`);
        console.log(`         lua : ${JSON.stringify(sa)}`);
        console.log(`         网页: ${JSON.stringify(sb)}`);
      }
    });
  });
  chk(drift === 0, `网页 VIS 与 lua/src/recipes.lua 的 vis **逐步一致**（${Object.keys(luaVis).length} 个产品）`);
}

console.log(bad ? `\n微量测试：${bad} 项失败` : '\n微量测试：全部通过 ✓');
process.exit(bad ? 1 : 0);
