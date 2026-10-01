// _fakedom.mjs —— 共享的"极简假 DOM"：把网页里的 <script> 丢进 node:vm 真跑一遍
//   给网页原型的微量测试用（tests/vkeypad.mjs、tests/fire-port.mjs）。
//   ★ 关键一条：window 必须**就是全局对象**（浏览器语义）。
//     我第一版把 window 与全局分成两个对象，页面里写裸全局 VKP 就直接 ReferenceError。
import vm from 'node:vm';

function mkEl(tag) {
  const el = {
    tagName: tag, children: [], className: '', textContent: '', _html: '', _ev: {},
    style: { setProperty(k, v) { this[k] = String(v); }, getPropertyValue(k) { return this[k] || ''; } },
    classList: {
      add(c) { if (!el.className.split(' ').includes(c)) el.className = (el.className + ' ' + c).trim(); },
      remove(c) { el.className = el.className.split(' ').filter(x => x !== c).join(' '); },
      contains(c) { return el.className.split(' ').includes(c); },
      toggle(c, on) { const has = el.className.split(' ').includes(c);
                      const want = (on === undefined) ? !has : !!on;
                      want ? el.classList.add(c) : el.classList.remove(c);
                      return want; },
    },
    setAttribute(k, v) { el['attr_' + k] = String(v); },
    getAttribute(k) { return el['attr_' + k]; },
    appendChild(c) { c.parentNode = el; el.children.push(c); return c; },   // ★ 必须设 parentNode，
    //   否则 c.remove() 是空操作（"关掉配料后子件没被移除"就是这么假失败的）
    removeChild(c) { el.children = el.children.filter(x => x !== c); if (c) c.parentNode = null; },
    // ★ remove() 也必须实现：页面里"关掉配料"用的是 toppingEls[i].remove()，
    //   而它外面有 if (el.remove) 守卫 ⇒ 假 DOM 没有 remove() 时**静默跳过**，
    //   表现为"关掉配料后子件还在"（我因此假失败了一次）。
    remove() { if (el.parentNode) el.parentNode.removeChild(el); },
    querySelector(sel) { return doc.querySelector(sel); },
    // ★ 给一个**稳定的**手机尺寸：页面用它算"自动适配"，真浏览器里是真尺寸，
    //   假 DOM 里给固定值 ⇒ 测试可复现（原来没有这个方法，只能靠页面里的 400 兜底）。
    getBoundingClientRect() { return { left: 0, top: 0, width: 360, height: 400, right: 360, bottom: 400 }; },
    // ★ innerHTML 赋值必须**清空子件**（浏览器行为）：页面 rebuild 时靠它清空，
    //   假 DOM 第一版是个普通属性 ⇒ 子件一路累积到 410 个（第 4 次"假 DOM 代际差"）。
    set innerHTML(v) { el._html = String(v); el.children = []; },
    get innerHTML() { return el._html; },
    addEventListener(t, f) { (el._ev[t] = el._ev[t] || []).push(f); },
    removeEventListener() {},
  };
  return el;
}

export function loadPage(html) {
  // 按**页面声明的 id** 建模（不在测试里手写名单，免得页面长大就失同步）
  const declaredIds = [...html.matchAll(/id="([A-Za-z0-9_-]+)"/g)].map(m => m[1]);
  const els = {};
  // ★ 解析标签属性（2026-10-01）：原来只按 id 建空元素，于是 `min="0.3"` 这类**标签属性**
  //   在测试里读不到（getAttribute 返回 undefined）→ 断言"横条范围 0.3~1.5"假失败。
  //   现在把每个 id 所在标签上的 name="value" 都挂到元素上，贴近浏览器行为。
  const tagOf = (id) => {
    const at = html.indexOf('id="' + id + '"');
    if (at < 0) return '';
    const lt = html.lastIndexOf('<', at), gt = html.indexOf('>', at);
    return (lt >= 0 && gt > lt) ? html.slice(lt, gt + 1) : '';
  };
  for (const id of declaredIds) {
    const el = mkEl('div');
    for (const m of tagOf(id).matchAll(/([a-zA-Z-]+)="([^"]*)"/g)) {
      if (m[1] === 'id') continue;
      el.setAttribute(m[1], m[2]);
    }
    els[id] = el;
  }
  // 带 data-* 的元素（页面用 document.querySelectorAll('[data-cell]') 绑按钮）——
  //   假 DOM 按属性名匹配即可，够用且贴近浏览器语义。
  const attrEls = [];
  // ★ 收**全部** data-* 元素，不按名字枚举（2026-10-01 第 5 次"假 DOM 代际差"：
  //   原来只认 data-cell / data-scale，页面加了 data-bg / data-opt 之后测试就"查不到按钮"了。
  //   按名字枚举 = 每加一类控件就要改测试台，这是设计问题，不是偶发 bug。）
  for (const m of html.matchAll(/data-([a-z-]+)="([^"]*)"/g)) {
    const e = mkEl('button');
    e.setAttribute('data-' + m[1], m[2]);
    e.className = 'vk';
    attrEls.push(e);
  }
  const queryAll = (sel) => {
    const m = /^\[data-([a-z-]+)\]$/.exec(String(sel));
    if (m) return attrEls.filter(e => e.getAttribute('data-' + m[1]) !== undefined);
    return [];
  };
  const doc = {
    getElementById: (id) => els[id] || null,
    createElement: mkEl,
    querySelectorAll: queryAll,
    querySelector: (sel) => {                       // 支持 "[data-x]" 与 "[data-x].on"
      const m = /^\[data-([a-z-]+)\](?:\.([a-z-]+))?$/.exec(String(sel));
      if (!m) return null;
      const list = queryAll('[' + 'data-' + m[1] + ']');
      return list.find(e => !m[2] || (e.className || '').split(' ').includes(m[2])) || null;
    },
  };

  const handlers = {};
  const received = [];                       // 记录所有被派发到 window 的事件（供断言）
  class KeyboardEvent {
    constructor(type, init) { Object.assign(this, { type, bubbles: false, cancelable: false, repeat: false }, init); }
  }
  const ctx = {
    document: doc, navigator: {}, KeyboardEvent, console, Date, setInterval, clearInterval, setTimeout,
    addEventListener(t, f) { (handlers[t] = handlers[t] || []).push(f); },
    dispatchEvent(e) { received.push(e); (handlers[e.type] || []).forEach(f => f(e)); return true; },
  };
  ctx.window = ctx;                          // ★ window = 全局（浏览器语义）
  ctx.globalThis = ctx;

  const i = html.indexOf('<script>'), j = html.lastIndexOf('</script>');
  if (i < 0 || j < 0) throw new Error('页面里找不到 <script>');
  vm.createContext(ctx);
  vm.runInContext(html.slice(i + 8, j), ctx, { filename: 'page.html' });
  return { ctx, els, doc, received, declaredIds, attrEls };
}
