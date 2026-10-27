'use strict';
const download = document.querySelector('#download');
download.addEventListener('click', () => {
  document.querySelector('#download-feedback').hidden = false;
});
const tabs = [...document.querySelectorAll('[role=tab]')];
const panels = [...document.querySelectorAll('[role=tabpanel]')];
const showcase = document.querySelector('.showcase');
const desktop = document.querySelector('#demo-desktop');
const play = document.querySelector('#play');
const caption = document.querySelector('#demo-caption');
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const captions = [
  '消息来了，移入灵动岛直接阅读。',
  'Agent 完成工作，抬眼就能知道。',
  '到点提醒，做完的事留在历史里。',
  '工作计划和常用中台入口，随手打开。'
];
let current = 0;
let playing = !reduced.matches;
let visible = true;
let sequence = 0;
let timers = [];
function clearTimers() {
  timers.forEach(clearTimeout);
  timers = [];
  sequence += 1;
}
function later(delay, action) {
  const expected = sequence;
  timers.push(setTimeout(() => { if (sequence === expected) action(); }, delay));
}
function updateControls() {
  play.hidden = reduced.matches;
  play.dataset.paused = String(!playing);
  play.querySelector('span').textContent = playing ? '暂停' : '播放';
  play.setAttribute('aria-label', playing ? '暂停演示' : '播放演示');
  desktop.dataset.running = String(playing);
}
function select(index, focus = false) {
  current = (index + tabs.length) % tabs.length;
  desktop.dataset.current = String(current);
  desktop.dataset.detail = 'start';
  tabs.forEach((tab, i) => {
    tab.setAttribute('aria-selected', String(i === current));
    tab.tabIndex = i === current ? 0 : -1;
    panels[i].hidden = i !== current;
  });
  caption.textContent = captions[current];
  if (focus) tabs[current].focus();
}
function renderCycle({ intro = false, automatic = true } = {}) {
  clearTimers();
  updateControls();
  desktop.dataset.phase = intro && !reduced.matches ? 'closed' : 'open';
  desktop.dataset.detail = 'start';
  if (reduced.matches) {
    desktop.dataset.phase = 'open';
    desktop.dataset.detail = 'done';
    return;
  }
  if (intro) {
    caption.textContent = '移入展开，信息就在屏幕顶部。';
    later(1200, () => { desktop.dataset.phase = 'open'; caption.textContent = captions[current]; });
  }
  later(intro ? 1900 : 700, () => { desktop.dataset.detail = 'progress'; });
  later(intro ? 4300 : 3100, () => { desktop.dataset.detail = 'done'; });
  if (automatic && playing && visible && !document.hidden) {
    later(intro ? 7000 : 6000, () => {
      desktop.dataset.phase = 'closed';
      later(650, () => { select(current + 1); renderCycle(); });
    });
  }
}
function pause() {
  playing = false;
  clearTimers();
  desktop.dataset.phase = 'open';
  caption.textContent = captions[current];
  updateControls();
}
tabs.forEach((tab, i) => {
  tab.addEventListener('click', () => { pause(); select(i); renderCycle({ automatic: false }); });
  tab.addEventListener('keydown', event => {
    const next = { ArrowRight: current + 1, ArrowLeft: current - 1, Home: 0, End: tabs.length - 1 }[event.key];
    if (next !== undefined) {
      event.preventDefault(); pause(); select(next, true); renderCycle({ automatic: false });
    }
  });
});
play.addEventListener('click', () => {
  if (playing) pause();
  else { playing = true; renderCycle(); }
});
document.querySelector('#replay').addEventListener('click', () => {
  playing = !reduced.matches; select(0); renderCycle({ intro: true });
});
showcase.addEventListener('focusin', event => {
  // A keyboard reader gets a stable panel. The play controls can explicitly resume.
  if (event.target.matches('[role=tab]')) pause();
});
document.addEventListener('visibilitychange', () => {
  if (document.hidden) clearTimers();
  else if (playing && visible) renderCycle();
});
const observer = new IntersectionObserver(entries => {
  visible = entries[0].isIntersecting;
  if (!visible) clearTimers();
  else if (playing && !document.hidden) renderCycle({ intro: desktop.dataset.phase === 'closed' });
}, { threshold: .15 });
observer.observe(showcase);
reduced.addEventListener('change', () => {
  playing = !reduced.matches; renderCycle();
});
select(0);
renderCycle({ intro: true });
