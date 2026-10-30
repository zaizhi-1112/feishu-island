'use strict';
// Desktop danmu: port of Danmu/Overlay.swift + MultilineMotion.swift.
// Each message is one moving panel; long text scrolls inside it while the whole
// panel is on screen. Click pauses (shows 打开会话), moving the mouse away resumes.
const { h, api } = window.ui;
const stage = document.getElementById('stage');
let look = { fontSize: 28, corner: 12, speed: 100, background: null, foreground: '#ffffff', border: null, outline: true };
let paused = false, queue = [], flying = [], checking = null, verified = null, retryAt = 0, last = performance.now();
const LANES = 4, TOP = 64, GAP = 48;

function rowHeight() { return Math.ceil(look.fontSize * 1.32) * 4 + 4 + 56; }
function laneCount() { return Math.min(LANES, Math.max(1, Math.floor((innerHeight - 120) / rowHeight()))); }

api.onEvent(({ event, payload }) => {
  if (event === 'appearance') { look = payload; for (const f of flying) style(f.el); }
  else if (event === 'paused') paused = !!payload;
  else if (event === 'enqueue') { if (!queue.some(q => q.id === payload.id) && !flying.some(f => f.item.id === payload.id)) queue.push(payload); }
  else if (event === 'clear') { queue = []; checking = null; verified = null; for (const f of flying) f.el.remove(); flying = []; }
  else if (event === 'retain') { const keep = new Set(payload); queue = queue.filter(q => q.demo || keep.has(q.id)); }
});

function style(el) {
  el.style.fontSize = look.fontSize + 'px';
  el.style.borderRadius = look.corner + 'px';
  el.style.color = look.foreground || '#fff';
  el.style.background = look.background || 'transparent';
  el.style.border = look.border ? `1px solid ${look.border}` : '0';
  el.classList.toggle('outline', !look.background);
}

function launch(item, lane) {
  const width = Math.min(620, Math.max(280, innerWidth * 0.48));
  const el = h('div.dm', h('div.vp', h('div.tx', item.demo ? [h('span.demo', '[演示]'), item.text] : item.text)), h('span.hint', '点击停留'), item.canOpen ? h('button.open', { onclick: e => { e.stopPropagation(); window.ui.call('danmu.open', item.id).catch(() => {}); } }, '打开会话') : null);
  style(el);
  el.style.maxWidth = width + 'px';
  stage.append(el);
  const tx = el.querySelector('.tx'), vp = el.querySelector('.vp');
  const lineH = Math.ceil(look.fontSize * 1.32);
  const textH = tx.scrollHeight;
  const single = textH <= lineH * 1.2 && !item.text.includes('\n');
  el.classList.toggle('single', single);
  vp.style.height = Math.min(textH, lineH * 4) + 'px';
  const rect = el.getBoundingClientRect();
  const panelW = Math.min(width, Math.max(180, rect.width));
  el.style.width = panelW + 'px';
  const top = TOP + lane * rowHeight();
  const chars = [...item.text].length;
  const readingSeconds = Math.max(1, chars / 8);
  const speed = Math.min(look.speed || 100, Math.max(1, innerWidth - panelW) / readingSeconds);
  const f = { item, el, tx, vp, lane, x: innerWidth, w: panelW, speed, paused: false, overflow: Math.max(0, textH - lineH * 4) };
  el.style.transform = `translate(${innerWidth}px, ${top}px)`;
  el.addEventListener('click', () => { f.paused = true; el.classList.add('paused'); el.querySelector('.hint').textContent = '移开继续'; });
  el.addEventListener('mouseleave', () => { f.paused = false; el.classList.remove('paused'); el.querySelector('.hint').textContent = '点击停留'; });
  flying.push(f);
}

function frame(now) {
  const dt = Math.min(0.1, (now - last) / 1000); last = now;
  if (!paused) {
    for (const lane of new Set(flying.map(f => f.lane))) {
      let leading = null;
      for (const f of flying.filter(x => x.lane === lane).sort((a, b) => a.x - b.x)) {
        let x = f.x - (f.paused ? 0 : f.speed * dt);
        if (leading) x = Math.max(x, leading.x + leading.w + GAP);
        f.x = x; leading = f;
        const top = TOP + f.lane * rowHeight();
        f.el.style.transform = `translate(${Math.round(x * devicePixelRatio) / devicePixelRatio}px, ${top}px)`;
        if (f.overflow) {
          const travel = Math.max(1, innerWidth - f.w);
          const fraction = Math.min(1, Math.max(0, (travel - x) / travel));
          f.tx.style.transform = `translateY(${-f.overflow * fraction}px)`;
        }
      }
    }
    for (const f of flying.filter(f => f.x + f.w < 0)) { f.el.remove(); if (!f.item.demo) window.ui.call('danmu.finished', f.item.id).catch(() => {}); }
    flying = flying.filter(f => f.x + f.w >= 0);
    next(now);
  }
  requestAnimationFrame(frame);
}

function next(now) {
  if (!queue.length) return;
  const lanes = laneCount();
  const lane = [...Array(lanes).keys()].find(c => !flying.some(f => f.lane === c && f.x + f.w > innerWidth - 60));
  if (lane === undefined) return;
  const item = queue[0];
  if (!item.demo && verified !== item.id) {
    if (checking || now < retryAt) return;
    checking = item.id;
    window.ui.api.invoke('danmu.checkUnread', item.id).then(r => {
      const unread = r && r.ok ? r.value : null;
      if (checking !== item.id) return;
      checking = null;
      if (queue[0] !== item) return;
      if (unread === true) verified = item.id;
      else if (unread === false) { queue.shift(); window.ui.call('danmu.finished', item.id).catch(() => {}); }
      else { queue.push(queue.shift()); retryAt = performance.now() + 1000; }
    });
    return;
  }
  queue.shift(); verified = null; retryAt = 0;
  launch(item, lane);
}

// Only the danmu panels take the mouse; everything else passes through to the desktop.
let ignoring = true;
document.addEventListener('mousemove', e => {
  const over = !!(e.target && e.target.closest && e.target.closest('.dm'));
  if (over === ignoring) { ignoring = !over; api.setIgnoreMouse(!over); }
});
requestAnimationFrame(frame);
