'use strict';
document.querySelector('#download').addEventListener('click', () => {
  document.querySelector('#download-feedback').hidden = false;
});
const tabs = [...document.querySelectorAll('[role=tab]')];
const panels = [...document.querySelectorAll('[role=tabpanel]')];
const showcase = document.querySelector('.showcase');
const play = document.querySelector('#play');
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
let current = 0, playing = !reduced.matches, timer;
function schedule() {
  clearTimeout(timer);
  play.textContent = playing ? '暂停' : '播放';
  play.setAttribute('aria-label', playing ? '暂停轮播' : '播放轮播');
  if (playing && !document.hidden && !showcase.matches(':hover') && !showcase.contains(document.activeElement)) timer = setTimeout(() => show(current + 1), 6000);
}
function show(index, focus = false) {
  current = (index + tabs.length) % tabs.length;
  tabs.forEach((tab, i) => {
    tab.setAttribute('aria-selected', String(i === current));
    tab.tabIndex = i === current ? 0 : -1;
    panels[i].hidden = i !== current;
  });
  document.querySelector('#slide-count').textContent = `0${current + 1} / 04`;
  if (focus) tabs[current].focus();
  schedule();
}
tabs.forEach((tab, i) => {
  tab.addEventListener('click', () => show(i));
  tab.addEventListener('keydown', event => {
    const next = {ArrowRight: current + 1, ArrowLeft: current - 1, Home: 0, End: 3}[event.key];
    if (next !== undefined) {event.preventDefault(); show(next, true);}
  });
});
document.querySelector('#previous').addEventListener('click', () => show(current - 1));
document.querySelector('#next').addEventListener('click', () => show(current + 1));
play.addEventListener('click', () => {playing = !playing; schedule();});
['mouseenter', 'mouseleave', 'focusin'].forEach(event => showcase.addEventListener(event, schedule));
showcase.addEventListener('focusout', () => setTimeout(schedule, 0));
document.addEventListener('visibilitychange', schedule);
reduced.addEventListener('change', () => {playing = !reduced.matches; schedule();});
schedule();
