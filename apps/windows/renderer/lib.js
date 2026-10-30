'use strict';
// Shared helpers for every page. No framework, no remote code.
(function () {
  const api = window.island;
  /** h('div.cls#id', {attrs/on*}, children...) */
  function h(tag, props, ...children) {
    const m = /^([a-z0-9]+)?((?:[.#][\w-]+)*)$/i.exec(tag) || [];
    const el = document.createElement(m[1] || 'div');
    for (const part of (m[2] || '').match(/[.#][\w-]+/g) || []) part[0] === '.' ? el.classList.add(part.slice(1)) : (el.id = part.slice(1));
    if (props && (typeof props !== 'object' || props instanceof Node || Array.isArray(props))) { children.unshift(props); props = null; }
    for (const [k, v] of Object.entries(props || {})) {
      if (v === undefined || v === null || v === false) continue;
      if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2).toLowerCase(), v);
      else if (k === 'class') el.className += ' ' + v;
      else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
      else if (k === 'dataset') Object.assign(el.dataset, v);
      else if (k in el && typeof v !== 'string') el[k] = v;
      else el.setAttribute(k, v === true ? '' : v);
    }
    for (const c of children.flat(Infinity)) if (c !== null && c !== undefined && c !== false) el.append(c instanceof Node ? c : document.createTextNode(String(c)));
    return el;
  }
  async function call(method, ...args) {
    const r = await api.invoke(method, ...args);
    if (!r || !r.ok) { const message = (r && r.error) || '操作未完成'; toast(message, true); throw new Error(message); }
    return r.value;
  }
  let toastTimer;
  function toast(text, error) {
    let el = document.getElementById('toast');
    if (!el) { el = h('div#toast'); document.body.append(el); }
    el.textContent = text; el.className = error ? 'show error' : 'show';
    clearTimeout(toastTimer); toastTimer = setTimeout(() => { el.className = ''; }, 3200);
  }
  const pad = n => String(n).padStart(2, '0');
  function time(t) { const d = typeof t === 'number' ? new Date(t * 1000) : new Date(t); return `${pad(d.getHours())}:${pad(d.getMinutes())}`; }
  function dateTime(t) {
    const d = typeof t === 'number' ? new Date(t * 1000) : new Date(t); const now = new Date();
    const same = d.toDateString() === now.toDateString();
    const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).toDateString() === d.toDateString();
    return (same ? '今天 ' : tomorrow ? '明天 ' : `${d.getMonth() + 1}月${d.getDate()}日 `) + time(t);
  }
  function relative(seconds) {
    const s = Math.max(0, Math.round(seconds));
    if (s < 60) return '不到1分钟';
    if (s < 3600) return `${Math.round(s / 60)}分钟`;
    if (s < 86400) { const m = Math.round(s / 60), hh = Math.floor(m / 60), mm = m % 60; return mm ? `${hh}小时${mm}分` : `${hh}小时`; }
    return `${Math.floor(s / 86400)}天`;
  }
  function applyTheme(island) {
    const dark = island.palette === 'dark' || (island.palette === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches);
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    document.documentElement.style.setProperty('--scale', String(island.textScale || 1));
  }
  /** Converts a KeyboardEvent into an Electron accelerator, or null for bare modifiers. */
  function accelerator(e) {
    const key = e.key;
    if (['Control', 'Shift', 'Alt', 'Meta'].includes(key)) return null;
    const mods = [];
    if (e.ctrlKey) mods.push('Control'); if (e.altKey) mods.push('Alt'); if (e.shiftKey) mods.push('Shift'); if (e.metaKey) mods.push('Super');
    const map = { ' ': 'Space', ArrowUp: 'Up', ArrowDown: 'Down', ArrowLeft: 'Left', ArrowRight: 'Right', Escape: null, '+': 'Plus' };
    let k = key in map ? map[key] : key.length === 1 ? key.toUpperCase() : key;
    if (k === null) return null;
    if (/^F\d{1,2}$/.test(k)) return [...mods, k].join('+');
    if (!mods.length || (mods.length === 1 && mods[0] === 'Shift')) return null;
    return [...mods, k].join('+');
  }
  const displayAccel = a => !a ? '未设置' : a.replace(/Control/g, 'Ctrl').replace(/Super/g, 'Win').split('+').join(' + ');
  window.ui = { h, call, toast, time, dateTime, relative, applyTheme, accelerator, displayAccel, api };
})();
