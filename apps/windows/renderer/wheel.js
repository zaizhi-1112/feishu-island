'use strict';
// 8-direction shortcut wheel (Platform/HubPingWheel.swift). North is slot 0, clockwise.
const { h, call, api } = window.ui;
const wheel = document.getElementById('wheel'), label = document.getElementById('label');
const ICONS = ['⌂', '◎', '▤', '▥', '⚠', '▦', '✦', '✓'];
let S = null, active = null, slots = [];
const CX = 190, CY = 190, R = 118;

function slice(dx, dy) {
  const r = Math.hypot(dx, dy); if (r < 45 || r > 200) return null;
  return Math.floor(((Math.atan2(dy, dx) * 180 / Math.PI + 90 + 22.5 + 360) % 360) / 45) % 8;
}
function render() {
  wheel.querySelectorAll('.slot').forEach(e => e.remove());
  slots = S.wheel.destinations.map((d, i) => {
    const a = (i * 45 - 90) * Math.PI / 180;
    const el = h('div.slot' + (d.available ? '' : '.off'), { style: { left: (170 + Math.cos(a) * R) + 'px', top: (170 + Math.sin(a) * R) + 'px' } },
      h('div.ic', d.icon ? h('img', { src: d.icon, alt: '' }) : (d.settings ? '⚙' : ICONS[i])), h('span', d.title));
    wheel.append(el); return el;
  });
  label.textContent = '移向方向后点击打开 · Esc 取消';
}
function highlight(i) {
  active = i;
  slots.forEach((el, k) => el.classList.toggle('on', k === i && S.wheel.destinations[k].available));
}
document.addEventListener('mousemove', e => highlight(slice(e.clientX - CX, e.clientY - CY)));
document.addEventListener('click', () => {
  if (active === null || !S.wheel.destinations[active].available) { call('wheel.close'); return; }
  if (S.wheel.soundEnabled) { const a = new Audio('../assets/ping.wav'); a.volume = .25; a.play().catch(() => {}); }
  call('wheel.open', active);
});
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') call('wheel.close');
  const keys = { ArrowUp: 0, ArrowRight: 2, ArrowDown: 4, ArrowLeft: 6 };
  if (e.key in keys) highlight(keys[e.key]);
  if (e.key === 'Enter' && active !== null) document.dispatchEvent(new MouseEvent('click'));
});
api.onState(s => { S = s; window.ui.applyTheme(s.island); render(); });
call('state').then(s => { if (!S) { S = s; render(); } });
