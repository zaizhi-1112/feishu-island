'use strict';
// First-run guide: the seven steps of Onboarding/IslandOnboarding.swift.
const { h, call, toast, applyTheme, accelerator, displayAccel, api } = window.ui;
const STEPS = [
  ['展开', '你靠近时，岛怎么回应？', '在左侧的小岛上试试鼠标移入和点击。'],
  ['外观', '选一个舒服的明暗', '点击即预览，之后也能随时换。'],
  ['飞书', '把飞书带到岛上', '一个入口，依次连接消息、日历和虚实中台。'],
  ['弹幕', '消息，要不要从桌面划过？', '岛内照常保留消息，弹幕由你决定。'],
  ['提醒', '到时间，怎样叫你？', '用于新待办和日程；已有提醒保持原样。'],
  ['快捷键', '按一下，打开灵动岛', '点击设置按钮，再按下组合键。'],
  ['Agent', '选择你的 Agent', '先获取本机工具，再选择连接；也可以以后再设置。']
];
const AGENT_ICONS = { codex: '../assets/img/agent-codex.png', claude: '../assets/img/agent-claude.png' };
let S = null, step = 0, reached = 0, recording = false, discovered = null, miniState = 'idle';

const opt = (on, sym, title, sub, onclick) => h('button.opt' + (on ? '.on' : ''), { onclick }, h('span.sym', sym), h('div', h('b', title), sub ? h('small', sub) : null), h('span.tick'));

function preview() {
  const i = S.island;
  const dark = i.palette === 'dark' || (i.palette === 'system' && matchMedia('(prefers-color-scheme: dark)').matches);
  const wrap = h('div', { style: { position: 'absolute', inset: 0 }, class: dark ? '' : 'light' });
  if (step <= 1) {
    const mini = h('div.mini' + (miniState === 'open' ? '.big' : miniState === 'pill' ? '.pill' : ''), h('img', { src: '../assets/icon.png' }), miniState === 'open' ? '消息 · Agent · 待办 · 中台' : '一切在岛');
    mini.addEventListener('mouseenter', () => { miniState = i.hoverMode === 'peekFirst' ? 'pill' : 'open'; render(); });
    mini.addEventListener('mouseleave', () => { miniState = 'idle'; render(); });
    mini.addEventListener('click', () => { miniState = 'open'; render(); });
    wrap.append(h('div.board'), mini, h('div.hint', '↖ 把鼠标移到这座小岛'));
  } else if (step === 2) {
    wrap.append(h('div', { style: { position: 'absolute', inset: 0, display: 'grid', placeItems: 'center' } }, h('div', { style: { textAlign: 'center' } }, h('img', { src: '../assets/img/mascot.png', style: { width: '180px' } }), h('div.small', '只在你授权后接入'))));
  } else if (step === 3) {
    const a = S.feishu.appearance;
    const bg = a.bubble === 'dark' ? 'rgba(20,23,28,.9)' : a.bubble === 'light' ? 'rgba(255,255,255,.94)' : null;
    wrap.append(h('div.board'), S.feishu.danmu.enabled ? h('div.fly' + (bg ? '' : '.outline'), { style: { background: bg || 'transparent', color: a.bubble === 'light' ? '#1a1f26' : '#fff' } }, '项目群 · 小林：资料整理好了，方便时看一下') : h('div', { style: { position: 'absolute', inset: 0, display: 'grid', placeItems: 'center' } }, h('div.small', '新消息，去岛内查看')));
  } else if (step === 4) {
    const style = S.todos.defaultScreen;
    const m = style && S.todos.materials.find(x => x.id === style.materialID);
    wrap.append(h('div.board'), h('div', { style: { position: 'absolute', inset: 0, display: 'grid', placeItems: 'center' } }, m ? h('video', { src: '../assets/reminders/' + m.file, autoplay: true, muted: true, loop: true, playsinline: true }) : h('div.mini.pill', { style: { position: 'static', transform: 'none' } }, '⏰ 写周报')));
  } else if (step === 5) {
    wrap.append(h('div', { style: { position: 'absolute', inset: 0, display: 'grid', placeItems: 'center' } }, h('div', { style: { textAlign: 'center' } }, h('div.keycap', displayAccel(i.toggleHotkey)), h('p.small', '展开与收起，用同一个快捷键'))));
  } else {
    const shown = S.agents.profiles.filter(p => p.mode !== 'off');
    wrap.append(h('div', { style: { position: 'absolute', inset: 0, display: 'grid', placeItems: 'center' } }, h('div', { style: { textAlign: 'center' } },
      shown.length ? h('div.agents-row', shown.map(p => h('div', AGENT_ICONS[p.id] ? h('img', { src: AGENT_ICONS[p.id] }) : h('b', p.name), p.name, p.id === S.agents.primary ? h('span', { style: { color: '#a9b8ff' } }, '主用') : null))) : [h('div', { style: { fontSize: '38px', color: '#a9b8ff' } }, '✦'), h('p.small', '以后再加，也可以')],
      h('p.small', '仅预览位置，不展示你的真实任务'))));
  }
  return wrap;
}

function choices() {
  const i = S.island, f = S.feishu;
  switch (step) {
    case 0: return [opt(i.hoverMode === 'immediately', '⇕', '完整展开', '鼠标移入，就能查看和操作。', () => call('island.set', { hoverMode: 'immediately' })), opt(i.hoverMode === 'peekFirst', '⬭', '先露出胶囊', '轻轻露出，点一下再完整展开。', () => call('island.set', { hoverMode: 'peekFirst' }))];
    case 1: return [opt(i.palette === 'dark', '☾', '深色', '让注意力留在岛上。', () => call('island.set', { palette: 'dark' })), opt(i.palette === 'light', '☀', '浅色', '轻盈、明亮。', () => call('island.set', { palette: 'light' })), h('button.btn.link', { onclick: () => call('island.set', { palette: 'system' }).then(() => toast('已跟随系统')) }, '跟随 Windows 的外观')];
    case 2: {
      const rows = [['飞书消息', f.connected], ['飞书日历', S.todos.schedule.enabled], ['虚实中台', S.hub.connected]];
      const nextTarget = !f.connected ? 'feishu.connect' : !S.todos.schedule.enabled ? 'schedule.connect' : !S.hub.connected ? 'hub.connect' : null;
      return [S.demo ? h('div.small', '演示模式不会连接真实账号。') : h('button.btn.solid', { style: { alignSelf: 'flex-start', padding: '11px 24px', fontSize: '15px' }, disabled: !nextTarget, onclick: () => call(nextTarget) }, nextTarget ? (f.connected ? '继续连接下一项' : '连接飞书') : '已全部连接'),
        ...rows.map(([t, ok]) => h('div.conn', t, ok ? h('span.ok', '✓ 已连接') : h('span.no', '未连接'))),
        h('div.small', '按授权窗口提示确认。每项连接成功后才会显示勾选。'),
        f.hint ? h('div.small', f.hint) : null,
        h('div.small', '也可以先跳过，稍后在设置里连接。')];
    }
    case 3: {
      const a = f.appearance;
      return [opt(!f.danmu.enabled, '⬭', '只在岛内看', '桌面保持安静。', () => call('feishu.updateDanmu', { ...f.danmu, enabled: false })),
        opt(f.danmu.enabled, '💬', '也显示桌面弹幕', '消息完整飘过，长文字在同一条弹幕中滚动。', () => call('feishu.updateDanmu', { enabled: true, paused: false })),
        f.danmu.enabled ? h('div', { style: { display: 'flex', gap: '8px' } }, [['none', '文字'], ['dark', '深色气泡'], ['light', '浅色气泡']].map(([v, l]) => h('button.btn' + (a.bubble === v ? '.primary' : ''), { onclick: () => call('feishu.updateAppearance', { ...a, bubble: v, background: null, foreground: null }) }, l))) : null];
    }
    case 4: {
      const style = S.todos.defaultScreen;
      return [opt(!style, '⬭', '岛内轻提醒', '在屏幕顶部提示。', () => call('todos.setDefaultScreen', null)),
        ...S.todos.materials.map(m => opt(style && style.materialID === m.id, m.id === 'cat' ? '🐈' : '▶', m.name, '', () => call('todos.setDefaultScreen', { materialID: m.id, durationSeconds: 15 }))),
        h('div.small', '屏幕动效出现 3 秒后，点击任意位置即可关闭。')];
    }
    case 5: {
      const b = h('button.btn' + (recording ? '.primary' : ''), { style: { alignSelf: 'flex-start', padding: '12px 22px', fontSize: '15px' }, onclick: () => { recording = !recording; render(); } }, recording ? '请按下组合键…（Esc 取消）' : '自定义快捷键 · ' + displayAccel(S.island.toggleHotkey));
      return [b, h('div.small', '建议包含 Ctrl 或 Alt，避免与输入冲突。中台信号轮盘默认 Ctrl + Alt + Space，可在设置里更换。')];
    }
    default: return [h('button.btn.solid', { style: { alignSelf: 'flex-start', padding: '11px 24px', fontSize: '15px' }, onclick: () => call('agents.discover').then(r => { discovered = r; render(); }) }, discovered ? '重新获取本机 Agent' : '一键获取本机 Agent'),
      h('div.small', '找到工具后，点击“连接”才开始读取状态。也可以先不连接。'),
      discovered ? (discovered.length ? discovered.map(id => { const p = S.agents.profiles.find(x => x.id === id); return h('div.conn', AGENT_ICONS[id] ? h('img', { src: AGENT_ICONS[id], style: { width: '24px' } }) : null, p.name, p.mode !== 'off' ? h('span.ok', '已连接') : h('button.btn', { style: { marginLeft: 'auto' }, onclick: () => call('agents.connect', id) }, '连接')); }) : h('div.small', '未找到支持的工具，可稍后在设置中添加。')) : null];
  }
}

document.addEventListener('keydown', e => {
  if (!recording) return;
  e.preventDefault();
  if (e.key === 'Escape') { recording = false; render(); return; }
  const acc = accelerator(e); if (!acc) return;
  recording = false;
  call('island.setHotkey', acc).then(() => toast('快捷键已更新：' + displayAccel(acc))).finally(render);
});

function render() {
  if (!S) return;
  applyTheme(S.island);
  document.getElementById('steps').replaceChildren(...STEPS.map(([name], i) => h('li' + (i === step ? '.on' : i < reached ? '.done' : ''), { style: { cursor: i <= reached ? 'pointer' : 'default' }, onclick: () => { if (i <= reached) { step = i; render(); } } }, h('span.n', String(i + 1)), name)));
  document.getElementById('title').textContent = STEPS[step][1];
  document.getElementById('detail').textContent = STEPS[step][2];
  document.getElementById('preview').replaceChildren(preview());
  document.getElementById('choices').replaceChildren(...choices().flat().filter(Boolean));
  document.getElementById('prev').classList.toggle('hidden', step === 0);
  document.getElementById('next').textContent = step === STEPS.length - 1 ? '开始使用' : '下一步';
  document.getElementById('later').textContent = step === 0 ? '以后再设置' : '退出，稍后继续';
}
document.getElementById('prev').addEventListener('click', () => { step = Math.max(0, step - 1); render(); });
document.getElementById('next').addEventListener('click', () => {
  if (step === STEPS.length - 1) { call('onboarding.complete'); return; }
  step++; reached = Math.max(reached, step); render();
});
document.getElementById('later').addEventListener('click', () => call('onboarding.later'));
api.onState(s => { S = s; render(); });
api.onEvent(({ event, payload }) => { if (event === 'step') { step = payload; reached = Math.max(reached, step); render(); } });
call('state').then(s => { if (!S) { S = s; render(); } });
