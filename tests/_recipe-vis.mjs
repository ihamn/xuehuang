// _recipe-vis.mjs —— 从 lua/src/recipes.lua 里解析出每个产品每一步的 vis
//
// 为什么抽成共享模块：这个解析器前后被写过 4 次，每次都在同一类地方翻车——
//   ① 要求 `', '` 恰好一个空格 → 对齐用的两个空格让整步消失
//   ② 按"第几个连按步"当步号 → 报错的位置全是错的
//   ③ `onDone = { add = 'apple' }` 被拍平成顶层 add → 假漂移
//   ④ **懒匹配到第一个 `},`** → 而 `onDone = {...}, quip = ...` 里那个 `},`
//      是内层表的收尾 ⇒ 它后面的字段（quip）被静默截掉
// 现在只有这一份，并且 tests/recipe-parser.mjs 会体检它（步数、字段数、自检）。
//
// 解析策略：**按行分组**，不用懒正则跨表匹配。
//   一步 = 从 `{ st = ` 开头那行起，到第一行"去掉空白后以 `},` 结尾"为止。

const FIELD_RE = {
  fill: [/fill = ([\d.]+)/, parseFloat],
  add: [/add = '(\w+)'/],
  state: [/state = '(\w+)'/],
  mix: [/mix = '(\w+)'/],
  rim: [/rim = '(\w+)'/],
  pulse: [/pulse = '(\w+)'/],
  tool: [/tool = '(\w+)'/],
  quip: [/quip = '([^']*)'/],
};

function parseVis(text) {
  const vis = {};
  const onDoneM = text.match(/onDone = \{([^}]*)\}/);
  const top = text.replace(/onDone = \{[^}]*\}/, '');   // 摘出去，免得内层字段被当顶层
  for (const k of Object.keys(FIELD_RE)) {
    const m = top.match(FIELD_RE[k][0]);
    if (m) vis[k] = FIELD_RE[k][1] ? FIELD_RE[k][1](m[1]) : m[1];
  }
  if (onDoneM) {
    const od = {};
    const a = onDoneM[1].match(/add = '(\w+)'/); if (a) od.add = a[1];
    const s = onDoneM[1].match(/state = '(\w+)'/); if (s) od.state = s[1];
    vis.onDone = od;
  }
  const colS = top.match(/color = '(\w+)'/);
  const colT = top.match(/color = \{ (\d+), (\d+), (\d+) \}/);
  if (colS) vis.color = colS[1];
  else if (colT) vis.color = [Number(colT[1]), Number(colT[2]), Number(colT[3])];
  if (/lid = true/.test(top)) vis.lid = true;
  return vis;
}

export function parseRecipes(luaSrc) {
  const out = {};
  const marks = [...luaSrc.matchAll(/id = '([a-z]+)', name = '([^']+)'/g)]
    .map(m => ({ id: m[1], name: m[2], at: m.index }));
  marks.forEach((mk, i) => {
    const seg = luaSrc.slice(mk.at, i + 1 < marks.length ? marks[i + 1].at : luaSrc.length);
    const si = seg.indexOf('steps = {');
    if (si < 0) { out[mk.id] = { name: mk.name, steps: [] }; return; }
    const lines = seg.slice(si).split('\n');
    const steps = [];
    let cur = null;
    for (const line of lines) {
      if (/^\s*\{ st = /.test(line)) cur = line;
      else if (cur) cur += '\n' + line;
      if (cur && /(^|\s)\},?\s*$/.test(line.trim() === '},' ? '},' : line) && /^\s*\},?\s*$/.test(line)) {
        // 一步结束：该行（去掉空白）就是 `},`
        //  （多行步的最后一行是 `vis = { ... } },`，也以 `},` 结尾）
      }
      if (cur && /^\s*.*\},\s*$/.test(line) && /^\s*\{ st = /.test(cur)) {
        steps.push(cur); cur = null;
      }
    }
    out[mk.id] = {
      name: mk.name,
      steps: steps.map(s => {
        // ★ 必须带边界：`/t = '...'/` 会匹配到 `st = 'shake'` 里的 `t = `（我踩了）
        const t = (s.match(/(?:^|[\s,{])t = '([^']*)'/) || [])[1];
        const kind = (s.match(/kind = '([a-z]+)'/) || [])[1];
        const taps = Number((s.match(/taps = (\d+)/) || [])[1]) || undefined;
        const press = (s.match(/press = '(\w+)'/) || [])[1];
        return { t, kind, taps, press, vis: parseVis(s), raw: s };
      }),
    };
  });
  return out;
}
