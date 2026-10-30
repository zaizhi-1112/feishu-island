'use strict';
// Full-screen transparent reminder (Workspace/ScreenReminder.swift). Mouse passes through
// for the first 3 seconds; afterwards a click (or a key, when this window has focus) closes it.
const { h, call, api } = window.ui;
const video = document.getElementById('video'), title = document.getElementById('title'), actions = document.getElementById('actions'), hint = document.getElementById('hint');
let started = 0, closeTimer = null, dismissable = false;

function close() { clearTimeout(closeTimer); call(actions.classList.contains('hidden') ? 'reminder.dismiss' : 'reminder.dismiss').catch(() => window.close()); }
api.onEvent(({ event, payload }) => {
  if (event !== 'play') return;
  started = Date.now(); dismissable = false;
  title.textContent = payload.title;
  video.classList.toggle('opaque', !payload.hasAlpha);
  video.src = payload.video; video.muted = payload.rest ? !payload.sound : false; video.loop = false;
  video.play().catch(() => { video.muted = true; video.play().catch(() => {}); });
  actions.replaceChildren();
  if (payload.rest) {
    actions.classList.remove('hidden');
    actions.append(h('button.primary', { onclick: e => { e.stopPropagation(); call('rest.done'); } }, '休息好了'), h('button', { onclick: e => { e.stopPropagation(); call('rest.later'); } }, '10分钟后'));
  } else actions.classList.add('hidden');
  hint.textContent = '';
  setTimeout(() => { dismissable = true; hint.textContent = '点击任意位置关闭'; call('reminder.capture', true).catch(() => {}); }, 3000);
  closeTimer = setTimeout(close, payload.duration * 1000);
  video.onended = () => { if (!payload.rest) setTimeout(close, 600); };
});
document.addEventListener('click', () => { if (dismissable) close(); });
document.addEventListener('keydown', () => { if (dismissable) close(); });
