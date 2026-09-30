// _fakedom.mjs —— 共享的"极简假 DOM"：把网页里的 <script> 丢进 node:vm 真跑一遍
//   给网页原型的微量测试用（tests/vkeypad.mjs、tests/fire-port.mjs）。
//   ★ 关键一条：window 必须**就是全局对象**（浏览器语义）。
//     我第一版把 window 与全局分成两个对象，页面里写裸全局 VKP 就直接 ReferenceError。
import vm from 'node:vm';

function mkEl(tag) {
  const el = {
    tagName: tag, children: [], className: '', textContent: '', innerHTML: '', _ev: {},
    style: { setProperty(k, v) { this[k] = String(v); }, getPropertyValue(k) { return this[k] || ''; } },
    classList: {
      add(c) { if (!el.className.split(' ').includes(c)) el.className = (el.className + ' ' + c).trim(); },
      remove(c) { el.className = el.className.split(' ').filter(x => x !== c).join(' '); },
      contains(c) { return el.className.split(' ').includes(c); },
    },
    setAttribute(k, v) { el['attr_' + k] = String(v); },
    getAttribute(k) { return el['attr_' + k]; },
    appendChild(c) { el.children.push(c); return c; },
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
  for (const m of html.matchAll(/data-(cell|scale)="([^"]+)"/g)) {
    const e = mkEl('button');
    e.setAttribute('data-' + m[1], m[2]);
    e.className = 'vk';
    attrEls.push(e);
  }
  const queryAll = (sel) => {
    const m = /^\[data-([a-z]+)\]$/.exec(String(sel));
    if (m) return attrEls.filter(e => e.getAttribute('data-' + m[1]) !== undefined);
    return [];
  };
  const doc = { getElementById: (id) => els[id] || null, createElement: mkEl, querySelectorAll: queryAll };

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
