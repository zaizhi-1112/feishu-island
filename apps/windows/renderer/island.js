'use strict';
// Top island: collapsed edge → compact capsule → expanded panel with four modules.
const { h, call, time, dateTime, relative, applyTheme, api } = window.ui;
const shell = document.getElementById('shell');
const hot = document.getElementById('hot');
const nav = document.getElementById('nav');
const content = document.getElementById('content');
const measure = document.getElementById('measure');

const MODULES = [['feishu', '消息'], ['agents', 'Agent'], ['todos', '待办'], ['platform', '中台']];
const AGENT_ICONS = { codex: '../assets/img/agent-codex.png', claude: '../assets/img/agent-claude.png', workbuddy: '../assets/img/agent-workbuddy.png', deepseek: '../assets/img/deepseek-icon.ico' };
let S = null;
let mode = 'collapsed', module = 'feishu', feishuTab = 'important';
let hoverTimer = null, leaveTimer = null, revealUntil = 0, peek = null, peekTimer = null, inside = false, ignoring = true;
let editingTodo = null, showCompleted = false, readerPages = [], readerPage = 0, readerID = null, autoTimer = null, autoOn = false, autoLeft = 12;

// ---------- mouse & layout ----------
function setIgnore(v) { if (v !== ignoring) { ignoring = v; api.setIgnoreMouse(v); } }
function activeRect() {
  const r = (mode === 'collapsed' ? hot : shell).getBoundingClientRect();
  const m = mode === 'collapsed' ? 0 : 6;
  return { left: r.left - m, right: r.right + m, top: 0, bottom: r.bottom + m };
}
function within(x, y) { const r = activeRect(); return x >= r.left && x <= r.right && y >= r.top && y <= r.bottom; }
function typing() { const a = document.activeElement; return !!a && content.contains(a) && /^(INPUT|TEXTAREA)$/.test(a.tagName); }
function setMode(next) {
  if (mode === next) return;
  mode = next;
  shell.className = next + (next === 'collapsed' && S && S.island.collapsed === 'hidden' ? ' hiddenStyle' : '') + (next === 'compact' && peek ? ' wide' : '');
  if (next === 'expanded') { render(); if (module === 'agents') call('agents.acknowledge').catch(() => {}); }
  if (next === 'collapsed') { stopAuto(); call('island.blur').catch(() => {}); }
  compactRender();
}
function onEnter() {
  clearTimeout(leaveTimer);
  if (mode !== 'collapsed') return;
  clearTimeout(hoverTimer);
  hoverTimer = setTimeout(() => {
    if (!inside) return;
    setMode(S && S.island.hoverMode === 'peekFirst' ? 'compact' : 'expanded');
  }, 150);
}
function onLeave() {
  clearTimeout(hoverTimer);
  clearTimeout(leaveTimer);
  leaveTimer = setTimeout(() => {
    if (inside || typing() || (S && S.island.keepOpen && mode === 'expanded') || Date.now() < revealUntil) return;
    peek = null; setMode('collapsed');
  }, 320);
}
document.addEventListener('mousemove', e => {
  const now = within(e.clientX, e.clientY);
  setIgnore(!now);
  if (now && !inside) { inside = true; onEnter(); }
  else if (!now && inside) { inside = false; onLeave(); }
});
document.addEventListener('mouseleave', () => { if (inside) { inside = false; setIgnore(true); onLeave(); } });
shell.addEventListener('click', e => {
  if (mode === 'compact') { const target = peek && peek.module; peek = null; if (target) module = target; setMode('expanded'); call('island.focus').catch(() => {}); e.stopPropagation(); }
});
document.addEventListener('keydown', e => { if (e.key === 'Escape' && mode !== 'collapsed' && !typing()) { revealUntil = 0; setMode('collapsed'); } });
function scheduleCollapseCheck(ms) { setTimeout(() => { if (!inside && !typing() && Date.now() >= revealUntil && !(S.island.keepOpen && mode === 'expanded')) { peek = null; setMode('collapsed'); } }, ms + 50); }

// ---------- events from main ----------
api.onEvent(({ event, payload }) => {
  if (!S || S.onboarding === 'pending') return;
  if (event === 'toggle') {
    if (mode === 'expanded') { revealUntil = 0; setMode('collapsed'); }
    else { setMode('expanded'); call('island.focus').catch(() => {}); revealUntil = Date.now() + 1500; scheduleCollapseCheck(1500); }
  } else if (event === 'reveal') {
    module = MODULES.some(m => m[0] === payload.module) ? payload.module : module;
    revealUntil = Date.now() + (payload.seconds || 5) * 1000;
    if (mode === 'expanded') render(); else setMode('expanded');
    scheduleCollapseCheck((payload.seconds || 5) * 1000);
  } else if (event === 'peek') {
    if (mode === 'expanded') { if (payload.module === module) render(); return; }
    peek = payload; clearTimeout(peekTimer);
    revealUntil = Date.now() + 4000;
    shell.classList.add('wide'); setMode('compact'); compactRender();
    peekTimer = setTimeout(() => { if (peek === payload) { peek = null; compactRender(); } scheduleCollapseCheck(0); }, 4000);
  } else if (event === 'collapse') { revealUntil = 0; peek = null; setMode('collapsed'); }
});

// ---------- compact capsule ----------
function primaryAgent() { return S && S.agents.profiles.find(p => p.id === S.agents.primary && p.mode !== 'off'); }
function compactRender() {
  const glyph = document.getElementById('glyph'), text = document.getElementById('compactText'), count = document.getElementById('compactCount');
  glyph.replaceChildren(); count.textContent = '';
  if (!S) return;
  const agent = peek && peek.agent ? S.agents.profiles.find(p => p.id === peek.agent) : primaryAgent();
  if (agent && AGENT_ICONS[agent.id]) glyph.append(h('img', { src: AGENT_ICONS[agent.id], alt: '' }));
  else glyph.append(h('img', { src: '../assets/icon.png', alt: '' }));
  if (peek) { text.textContent = peek.text; return; }
  if (agent && agent.state === 'working') { text.textContent = `${agent.name} · 正在工作`; return; }
  const q = agent && S.agents.preferences.quotaDisplayEnabled ? agent.quotas.find(x => x.fresh) : null;
  text.textContent = q ? `${agent.name} · ${q.label}剩余${Math.round(q.remainingPercent)}%` : (MODULES.find(m => m[0] === module) || MODULES[0])[1] === '消息' ? '一切在岛' : (MODULES.find(m => m[0] === module) || MODULES[0])[1];
  if (S.feishu.waiting) count.textContent = S.feishu.waiting + '条';
}

// ---------- nav ----------
function modules() { return MODULES.filter(([id]) => id !== 'platform' || S.wheel.showInMainBar); }
function renderNav() {
  if (!modules().some(m => m[0] === module)) module = 'feishu';
  nav.replaceChildren(
    ...modules().map(([id, label]) => h('button.tab' + (module === id ? '.on' : ''), { onclick: () => { module = id; call('island.set', { activeModule: id }).catch(() => {}); if (id === 'agents') call('agents.acknowledge').catch(() => {}); render(); } },
      label, (id === 'feishu' && S.feishu.waiting) || (id === 'agents' && S.agents.profiles.some(p => p.unviewed)) ? h('span.dot') : null)),
    h('span.space'),
    h('button.icon' + (S.island.keepOpen ? '.on' : ''), { title: S.island.keepOpen ? '已锁定展开（点击取消）' : '锁定展开', onclick: () => call('island.set', { keepOpen: !S.island.keepOpen }) }, S.island.keepOpen ? '📌' : '📍'),
    h('button.icon', { title: '设置', onclick: () => call('open.settings', { feishu: 'messages', agents: 'agents', todos: 'todos', platform: 'platform' }[module]) }, '⚙')
  );
}

// ---------- feishu ----------
function emptyPresentation(f, showAll) {
  if (f.connecting) return ['⟳', '等待你完成飞书授权', '在授权窗口确认后，电脑会自动核对连接。'];
  if (!f.enabled) return ['❚❚', '接收已停止', '点右上角齿轮，在“飞书消息”中开启接收。'];
  if (/^(账号接收中|演示模式)/.test(f.status)) return showAll ? ['☐', '等待新的消息', '按你的规则筛选，继续遵守免打扰。'] : ['✓', '暂时没有重要消息', '按你的规则筛选，继续遵守免打扰。'];
  const failed = ['失败', '异常', '过期', '未登录', '无法', '错误', '暂缓', '请先连接'].some(k => f.status.includes(k));
  return [failed ? '!' : '⟳', failed ? '连接需要检查' : '正在连接飞书', f.status || '正在核对连接，请稍候。'];
}
function paginate(text, width = 346, limit = 168) {
  measure.style.width = width + 'px';
  const chars = [...text]; const pages = []; let i = 0;
  while (i < chars.length) {
    let lo = 1, hi = chars.length - i;
    while (lo < hi) { const mid = Math.ceil((lo + hi) / 2); measure.textContent = chars.slice(i, i + mid).join(''); if (measure.scrollHeight <= limit) lo = mid; else hi = mid - 1; }
    pages.push(chars.slice(i, i + lo).join('')); i += lo;
  }
  return pages.length ? pages : [''];
}
function stopAuto() { clearInterval(autoTimer); autoTimer = null; autoOn = false; }
const readingDuration = n => Math.max(12, Math.min(45, 4 + n / 4));
function renderReader(f, m) {
  if (readerID !== m.id) { readerID = m.id; readerPages = paginate(m.text); readerPage = Math.min(f.readingPage || 0, readerPages.length - 1); stopAuto(); }
  const go = d => { readerPage = Math.min(Math.max(0, readerPage + d), readerPages.length - 1); autoOn = false; stopAuto(); call('feishu.rememberPage', m.id, readerPage).catch(() => {}); render(); };
  return h('div.reader',
    h('button.back', { onclick: () => { readerID = null; stopAuto(); call('feishu.closeReader'); } }, '‹ 消息列表'),
    h('div.src', h('b', m.source), h('span.when', time(m.created))),
    m.source !== m.sender ? h('div.faint', { style: { fontSize: 'calc(10px * var(--scale))' } }, m.sender) : null,
    h('div.page.card', readerPages[readerPage]),
    h('div.pager',
      h('button.ibtn', { disabled: readerPage === 0, onclick: () => go(-1) }, '上一页'),
      h('span.n', `${readerPage + 1} / ${readerPages.length}`),
      h('button.ibtn', { disabled: readerPage + 1 >= readerPages.length, onclick: () => go(1) }, '下一页'),
      h('span', { style: { flex: 1 } }),
      h('button.ibtn', { onclick: () => {
        if (autoOn) { stopAuto(); render(); return; }
        autoOn = true; autoLeft = readingDuration([...readerPages[readerPage]].length);
        autoTimer = setInterval(() => { autoLeft--; if (autoLeft <= 0) { if (readerPage + 1 < readerPages.length) { readerPage++; autoLeft = readingDuration([...readerPages[readerPage]].length); call('feishu.rememberPage', m.id, readerPage).catch(() => {}); render(); } else { stopAuto(); render(); } } }, 1000);
        render();
      } }, autoOn ? '暂停' : '自动')),
    h('div.btnrow',
      h('button.ibtn', { onclick: () => { call('feishu.remindLater', m.id).then(() => call('feishu.finishReading')); readerID = null; } }, '稍后提醒'),
      h('button.ibtn', { disabled: !m.canOpen, onclick: () => call('feishu.open', m.id) }, '打开会话'),
      h('span', { style: { flex: 1 } }),
      h('button.ibtn.pro', { onclick: () => { readerID = null; stopAuto(); call('feishu.finishReading'); } }, f.readingQueue > 1 ? '读完 · 下一条' : '读完'))
  );
}
function renderFeishu() {
  const f = S.feishu;
  const reading = f.readingID && f.messages.find(m => m.id === f.readingID);
  if (reading) return [renderReader(f, reading)];
  readerID = null;
  const showAll = feishuTab === 'recent';
  const list = showAll ? f.messages : f.messages.filter(m => m.reason);
  const head = h('div.head', h('div.subtabs',
    h('button' + (!showAll ? '.on' : ''), { onclick: () => { feishuTab = 'important'; render(); } }, '重要', h('span.n', String(f.waiting))),
    h('button' + (showAll ? '.on' : ''), { onclick: () => { feishuTab = 'recent'; render(); } }, '最近')));
  let body;
  if (!list.length) {
    const [sym, t, d] = emptyPresentation(f, showAll);
    body = h('div.empty', h('div.sym', sym), h('div.t', t), h('div.d', d),
      !f.connected && !f.demo ? h('button.ibtn.pro', { onclick: () => call('feishu.connect') }, '连接飞书') : null,
      f.actionError ? h('div.status.warn', f.actionError) : null);
  } else {
    body = h('div.scroll', list.map(m => h('button.row.card' + (!m.viewed ? '.hi' : ''), { onclick: () => call('feishu.openReader', m.id) },
      h('div.avatar' + (!m.viewed ? '.unread' : ''), [...m.source][0] || '飞'),
      h('div.grow',
        h('div.line', h('span.name', m.source), h('span.when', time(m.created))),
        h('div.body', m.text),
        h('div.chips', m.reason ? h('span.chip', m.reason) : null, m.remindAt ? h('span.chip.plain', '⏰ 稍后提醒已设') : null)))),
      !/^(账号接收中|演示模式)/.test(f.status) ? h('div.status' + (/失败|异常|暂缓/.test(f.status) ? '.warn' : ''), f.status) : null,
      f.actionError ? h('div.status.warn', f.actionError) : null);
  }
  const foot = h('div.foot',
    h('button' + (f.muted ? '.on' : ''), { onclick: () => call('feishu.toggleMute') }, f.muted ? '🔕 恢复提醒' : '🔔 静音1小时'),
    h('span', { style: { flex: 1 } }),
    h('span.faint', f.account));
  return [head, body, foot];
}

// ---------- agents ----------
function quotaRows(p) {
  return p.quotas.slice(0, 3).map(q => [
    h('span', q.label), h('span.faint', q.fresh ? `剩余 ${q.remainingPercent.toFixed(0)}%${q.resetsAt ? ' · ' + relative(q.resetsAt - Date.now() / 1000) + '后重置' : ''}` : '等待更新'),
    h('div.bar', h('i' + (q.remainingPercent < 20 ? '.low' : ''), { style: { width: Math.max(2, q.remainingPercent) + '%' } }))]).flat();
}
function renderAgents() {
  const a = S.agents;
  const shown = a.profiles.filter(p => p.mode === 'show');
  const notice = a.notice ? h('div.notice', h('span.light-dot.' + (a.notice.attention === 'running' ? 'working' : a.notice.attention ? 'waiting' : 'completed')), a.notice.message) : null;
  if (!shown.length) return [notice, h('div.empty', h('div.sym', '✦'), h('div.t', '还没有显示在岛上的 Agent'), h('div.d', '在设置的 Agent 状态里连接 Codex 或 Claude Code，状态会显示在这里。'), h('button.ibtn.pro', { onclick: () => call('open.settings', 'agents') }, '去连接'))];
  return [notice, h('div.scroll', shown.map(p => h('div.agent.card' + (p.id === a.primary ? '.hi' : ''),
    h('div.top', AGENT_ICONS[p.id] ? h('img', { src: AGENT_ICONS[p.id], alt: '' }) : h('div.ph', [...p.name][0]),
      h('div.grow', h('div.name', p.name), h('div.st', h('span.light-dot.' + p.state), p.stateLabel, p.running > 1 ? ` · ${p.running}个任务` : '')),
      p.launchURL ? h('button.ibtn', { onclick: () => call('agents.open', p.id) }, '打开') : null),
    p.quotas.length ? h('div.quota', quotaRows(p)) : h('div.faint', { style: { fontSize: 'calc(10.5px * var(--scale))' } }, p.detail || '')))) ];
}

// ---------- todos ----------
function reminderSummary(t) {
  if (t.deadline) return '完成期限 · ' + dateTime(t.deadline);
  if (t.due) return '⏰ ' + dateTime(t.due) + (t.reminder && t.reminder.repeatMinutes ? ` · 每${t.reminder.repeatMinutes}分钟` : '');
  return '';
}
function todoRow(t, done) {
  if (editingTodo === t.id) {
    const title = h('input', { value: t.title, maxlength: 160 }), details = h('textarea', { rows: 3, placeholder: '补充说明（可选）' }); details.value = t.details;
    const save = () => call('todos.update', t.id, { title: title.value, details: details.value, preserveSchedule: true }).then(() => { editingTodo = null; render(); });
    setTimeout(() => title.focus(), 0);
    return h('div.todo.card.edit', h('div.grow', title, details, h('div.btnrow', h('button.ibtn.pro', { onclick: save }, '保存'), h('button.ibtn', { onclick: () => { editingTodo = null; render(); } }, '取消'), h('button.ibtn', { onclick: () => call('open.settings', 'todos') }, '提醒设置…'))));
  }
  return h('div.todo.card' + (done ? '.done' : ''),
    h('button.check' + (done ? '.done' : ''), { title: done ? '重新打开' : '完成', onclick: () => call(done ? 'todos.reopen' : 'todos.complete', t.id) }, '✓'),
    h('div.grow', h('div.t', t.title), done ? h('div.meta', t.completedAt ? '完成于 ' + dateTime(t.completedAt) : '旧记录 · 完成时间未记录') : reminderSummary(t) ? h('div.meta', reminderSummary(t)) : null),
    !done ? h('div.acts',
      h('button', { title: '上移', onclick: () => call('todos.move', t.id, -1) }, '↑'),
      h('button', { title: '下移', onclick: () => call('todos.move', t.id, 1) }, '↓'),
      h('button', { onclick: () => { editingTodo = t.id; render(); } }, '编辑'),
      h('button', { onclick: () => call('todos.remove', t.id).then(() => window.ui.toast('已删除，可在设置的“最近删除”中恢复')) }, '删除')) : null);
}
function renderTodos() {
  const t = S.todos;
  const input = h('input', { placeholder: '添加待办，回车保存', maxlength: 160, onkeydown: e => { if (e.key === 'Enter' && input.value.trim()) { const v = input.value; input.value = ''; call('todos.add', v).then(() => window.ui.toast('已添加，20分钟后提醒')); } } });
  const head = h('div.head', h('span.title', '待办'), h('span.faint', { style: { fontSize: 'calc(11px * var(--scale))' } }, `${t.pending.length}项待完成`));
  const events = t.schedule.enabled ? t.schedule.events.filter(e => e.end > Date.now() / 1000).slice(0, 5) : [];
  return [head, h('div.add', input, h('button.ibtn.pro', { onclick: () => { if (input.value.trim()) { const v = input.value; input.value = ''; call('todos.add', v); } } }, '＋')),
    h('div.scroll',
      t.pending.length ? t.pending.map(x => todoRow(x, false)) : h('div.faint', { style: { padding: '18px 4px', textAlign: 'center', fontSize: 'calc(12px * var(--scale))' } }, '暂无待办事项'),
      events.length ? [h('div.section-label', '飞书日程'), events.map(e => h('div.todo.card', h('span', '📅'), h('div.grow', h('div.t', e.title), h('div.meta', e.allDay ? dateTime(e.start).replace(/\d\d:\d\d$/, '全天') : `${dateTime(e.start)} — ${time(e.end)}`)), e.appLink ? h('div.acts', h('button', { onclick: () => call('schedule.open', e.id) }, '打开')) : null))] : null,
      h('div.section-label', h('button', { onclick: () => { showCompleted = !showCompleted; render(); } }, `${showCompleted ? '▾' : '▸'} 已完成 ${t.completed.length}`), h('span', { style: { flex: 1 } }), t.completed.length ? h('button', { onclick: () => call('todos.archiveCompleted') }, '全部归档') : null),
      showCompleted ? (t.completed.length ? t.completed.map(x => todoRow(x, true)) : h('div.faint', { style: { fontSize: 'calc(11px * var(--scale))', padding: '4px' } }, '完成的事项会显示在这里。')) : null,
      t.error ? h('div.status.warn', t.error) : null)];
}

// ---------- platform ----------
function sectionNode(s) {
  if (s.children && s.children.length) return h('div.grp', s.title ? h('div.gt', s.title) : null, s.text ? h('div', s.text) : null, s.children.map(sectionNode));
  return h('div', s.title ? [h('span.k', s.title + '：'), s.text] : s.text);
}
function renderPlatform() {
  const hb = S.hub;
  if (!hb.connected) return [h('div.empty', h('div.sym', '▦'), h('div.t', '连接本人虚实中台'), h('div.d', '读取你的中台首页卡片与常用应用，只读，不修改任何数据。'), S.demo ? null : h('button.ibtn.pro', { onclick: () => call('hub.connect') }, '连接中台'), hb.error ? h('div.status.warn', hb.error) : null)];
  const head = h('div.head', h('span.title', hb.name || '本人中台'), h('span', { style: { flex: 1 } }), h('button.ibtn', { onclick: () => call('open.url', 'https://hub.example.invalid/') }, '打开中台'));
  const cards = hb.visible.length ? hb.visible.map(c => h('div.hubcard.card', h('h4', c.title === '工作周报' ? '工作计划' : c.title, c.href ? h('button.ibtn', { style: { marginLeft: 'auto', padding: '3px 8px' }, onclick: () => call('open.url', c.href) }, '查看') : null),
    h('div.sec', (c.sections && c.sections.length ? c.sections : [{ title: '', text: c.text, children: [] }]).map(sectionNode))))
    : h('div.empty', h('div.t', '还没有选择首页卡片'), h('div.d', '在设置的“中台”里选择要显示在岛上的卡片。'), h('button.ibtn.pro', { onclick: () => call('open.settings', 'platform') }, '选择卡片'));
  return [head, h('div.scroll', cards, hb.error ? h('div.status.warn', hb.error) : null)];
}

// ---------- render ----------
function render() {
  if (!S) return;
  renderNav();
  if (typing()) return;
  const parts = module === 'feishu' ? renderFeishu() : module === 'agents' ? renderAgents() : module === 'todos' ? renderTodos() : renderPlatform();
  const scroller = content.querySelector('.scroll'); const top = scroller ? scroller.scrollTop : 0;
  content.replaceChildren(...parts.filter(Boolean));
  const next = content.querySelector('.scroll'); if (next) next.scrollTop = top;
  fitReader();
}
// Pages are cut to the real text box, so a long message never shows a half line.
let fitted = '';
function fitReader() {
  const page = content.querySelector('.reader .page');
  if (!page || !readerID) return;
  const w = page.clientWidth - 24, hgt = page.clientHeight - 24;
  const key = readerID + ':' + w + ':' + hgt;
  if (key === fitted || w <= 0 || hgt <= 0) return;
  fitted = key;
  const m = S.feishu.messages.find(x => x.id === readerID); if (!m) return;
  readerPages = paginate(m.text, w, hgt);
  readerPage = Math.min(readerPage, readerPages.length - 1);
  render();
}
api.onState(s => {
  const first = !S; S = s; applyTheme(s.island);
  if (first) module = s.island.activeModule || 'feishu';
  shell.classList.toggle('hiddenStyle', mode === 'collapsed' && s.island.collapsed === 'hidden');
  hot.style.height = s.island.collapsed === 'hidden' ? '5px' : '14px';
  compactRender();
  if (mode === 'expanded') render();
});
document.addEventListener('focusout', () => setTimeout(() => { if (!typing() && mode === 'expanded') render(); }, 0));
call('state').then(s => { if (!S) { S = s; applyTheme(s.island); module = s.island.activeModule || 'feishu'; compactRender(); } });
