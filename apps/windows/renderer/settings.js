'use strict';
// Settings window: the six sections of Settings/UnifiedSettingsWindow.swift.
const { h, call, toast, dateTime, time, relative, applyTheme, accelerator, displayAccel, api } = window.ui;
const SECTIONS = [
  ['messages', '飞书消息', '✈', '接收关心的消息，用喜欢的方式提醒。'],
  ['agents', 'Agent状态', '✦', '关注正在运行的 Agent，按需查看状态与额度。'],
  ['todos', '待办', '☑', '管理待办，回看已完成的记录。完成记录长期保存在本机。'],
  ['platform', '中台', '▦', '把常用入口放进信号轮盘，抬手打开。'],
  ['rest', '休息提醒', '☕', '到时间，提醒自己起身活动一下。'],
  ['appearance', '外观与交互', '✎', '主题、悬浮交互与显示屏。']
];
const AGENT_ICONS = { codex: '../assets/img/agent-codex.png', claude: '../assets/img/agent-claude.png', workbuddy: '../assets/img/agent-workbuddy.png', deepseek: '../assets/img/deepseek-icon.ico' };
let S = null, section = (location.hash || '#messages').slice(1);
const local = { query: '', results: null, searching: false, editing: null, historyOpen: false, trashOpen: false, recording: null, customName: '', customURL: '', discovered: null, slotEdit: null };

// ---------- tiny components ----------
const card = (title, desc, ...children) => h('div.card', title ? h('h3', title) : null, desc ? h('p.desc', desc) : null, ...children);
const toggle = (on, onchange, disabled) => h('button.switch' + (on ? '.on' : ''), { disabled, onclick: () => onchange(!on), role: 'switch', 'aria-checked': String(!!on) });
const row = (label, small, control) => h('div.row', h('div.label', h('b', label), small ? h('small', small) : null), control);
const seg = (value, options, onchange) => h('div.seg', options.map(([v, l]) => h('button' + (v === value ? '.on' : ''), { onclick: () => onchange(v) }, l)));
const choice = (on, sym, title, sub, onclick) => h('button.choice' + (on ? '.on' : ''), { onclick }, h('span.sym', sym), h('b', title), sub ? h('small', sub) : null);
const btn = (label, onclick, cls = '') => h('button.btn' + cls, { onclick }, label);
const select = (value, options, onchange) => { const s = h('select', { onchange: () => onchange(s.value) }, options.map(([v, l]) => h('option', { value: v, selected: v === value }, l))); return s; };
const toLocalInput = t => { const d = new Date(t * 1000); const p = n => String(n).padStart(2, '0'); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`; };
const fromLocalInput = v => v ? new Date(v).getTime() / 1000 : null;
function hotkeyRecorder(id, value, method) {
  const recording = local.recording === id;
  const b = h('button.btn.hotkey' + (recording ? '.rec' : ''), { onclick: () => { local.recording = recording ? null : id; render(); } }, recording ? '请按下组合键…' : displayAccel(value));
  if (recording) {
    const onKey = e => {
      e.preventDefault(); e.stopPropagation();
      if (e.key === 'Escape') { local.recording = null; document.removeEventListener('keydown', onKey, true); render(); return; }
      const acc = accelerator(e); if (!acc) return;
      document.removeEventListener('keydown', onKey, true); local.recording = null;
      call(method, acc).then(() => toast('快捷键已更新：' + displayAccel(acc))).finally(render);
    };
    document.addEventListener('keydown', onKey, true);
  }
  return b;
}

// ---------- 飞书消息 ----------
function messages() {
  const f = S.feishu, c = f.company;
  const connected = f.connected;
  const statusDot = !connected ? '' : f.enabled && /^账号接收中/.test(f.status) ? '.on' : '.warn';
  const out = [];
  out.push(card(null, null,
    h('div.row', h('div.label', h('b', { style: { fontSize: '16px' } }, '连接自己的飞书'), h('small', '在岛上查看你的新消息')), h('span.muted', '接收新消息'), toggle(f.enabled, v => call('feishu.setEnabled', v), !f.rulesReadable)),
    h('div.row', h('div.status-line.label', h('span.dot' + statusDot), h('div', h('b', connected ? (f.account || '已连接') : f.demo ? '演示模式' : '尚未连接飞书'), h('small', connected ? f.status : f.demo ? '演示模式不会连接真实账号。' : '连接后，在岛上接收与你有关的新消息。'))),
      f.demo ? null : connected ? h('div.inline', btn('重新连接', () => call('feishu.reconnect')), btn('更换账号', () => call('feishu.switchAccount'))) : btn(f.connecting ? '连接中…' : '连接飞书', () => call('feishu.connect'), '.primary')),
    f.hint ? h('div.notice.info', f.hint) : null,
    f.historyError ? h('div.notice', f.historyError) : null,
    f.actionError ? h('div.notice', f.actionError) : null));
  out.push(h('div.section-title', '哪些消息提醒我', h('span.right', '默认规则')));
  if (!f.enabled) out.push(h('div.notice', '当前已停止接收新消息，下面的规则会在恢复接收后生效。'));
  const setRule = (k, v) => call('feishu.updateRules', { ...f.rules, [k]: v }, f.custom);
  out.push(card(null, null,
    row('私聊消息', null, toggle(f.rules.directMessages, v => setRule('directMessages', v))),
    row('群聊中有人 @我', null, toggle(f.rules.mentionsMe, v => setRule('mentionsMe', v))),
    row('群聊中有人 @所有人', '普通群消息仍可在岛内查看。需要每条提醒的群，在下面单独设置。', toggle(f.rules.mentionsAll, v => setRule('mentionsAll', v)))));
  const rules = [...f.custom.conversations, ...f.custom.people];
  const modeOptions = [['all', '全部提醒'], ['mentions', '仅@我'], ['quiet', '不提醒']];
  const search = h('input.field', { placeholder: '搜索联系人或群聊', value: local.query, oninput: e => { local.query = e.target.value; }, onkeydown: e => { if (e.key === 'Enter') runSearch(); } });
  const runSearch = () => { local.searching = true; render(); call('feishu.directory', local.query).then(r => { local.results = r; }).catch(() => { local.results = []; }).finally(() => { local.searching = false; render(); }); };
  out.push(card('单独设置某个人或群', '已单独设置的会话优先展示，其余会话使用上方默认规则。',
    h('div.inline', search, btn(local.searching ? '搜索中…' : '搜索', runSearch)),
    !connected && !f.demo ? h('p.desc', { style: { marginTop: '12px' } }, '连接飞书后，会自动显示你的最近联系人和群聊。') : null,
    local.results ? h('div.list', { style: { marginTop: '12px' } }, local.results.length ? local.results.map(r => {
      const existing = rules.find(x => x.target.id === r.id);
      return h('div.item', h('div.grow', h('b', r.name), h('small', r.detail)), select(existing ? existing.mode : '', [['', '使用默认规则'], ...modeOptions], v => call('feishu.setConversation', { id: r.id, name: r.name, detail: r.detail }, v || null)));
    }) : h('p.desc', '没有找到匹配的会话。')) : null,
    rules.length ? [h('div.section-title', { style: { fontSize: '14px', margin: '18px 0 8px' } }, `已单独设置 · ${rules.length}`), h('div.list', rules.map(r => h('div.item', h('div.grow', h('b', r.target.name), h('small', r.target.detail || (r.target.id.startsWith('ou_') ? '联系人' : '会话'))),
      select(r.mode, modeOptions, v => call('feishu.setConversation', r.target, v)), btn('移除', () => call('feishu.setConversation', r.target, null), '.danger'))))] : null));
  // danmu
  const a = f.appearance, d = f.danmu;
  const setLook = patch => call('feishu.updateAppearance', { ...a, ...patch });
  const look = (() => { const bubble = a.bubble; const bg = bubble === 'dark' ? (a.background || 'rgba(20,23,28,.9)') : bubble === 'light' ? (a.background || 'rgba(255,255,255,.94)') : bubble === 'custom' ? a.background : null; const fg = a.foreground || (bubble === 'light' ? '#1a1f26' : '#ffffff'); return { bg: bubble !== 'none' && a.backgroundEnabled ? bg : null, fg, border: bubble !== 'none' && a.borderEnabled ? a.border : null }; })();
  const sample = h('div.dm' + (look.bg ? '' : '.outline'), { style: { background: look.bg || 'transparent', color: look.fg, fontSize: Math.round(a.fontSize * 0.7) + 'px', borderRadius: a.corner + 'px', border: look.border ? '1px solid ' + look.border : '0' } }, '项目群 · 小林：资料整理好了，方便时看一下');
  out.push(h('div.section-title', '桌面弹幕'));
  out.push(card(null, '岛内照常保留消息；打开后，重要消息也会从桌面飘过。长消息在同一条弹幕中滚动，点击停留，移开继续。',
    row('显示桌面弹幕', null, toggle(d.enabled, v => call('feishu.updateDanmu', { ...d, enabled: v }))),
    d.enabled ? row('暂停播放', '暂停后新消息仍在岛内保留。', toggle(d.paused, v => call('feishu.updateDanmu', { ...d, paused: v }))) : null,
    h('div.preview', sample),
    row('样式', null, seg(a.bubble, [['none', '文字'], ['dark', '深色气泡'], ['light', '浅色气泡'], ['custom', '自定义']], v => setLook({ bubble: v, background: v === 'custom' ? (a.background || '#1f2a30') : null, foreground: v === 'custom' ? (a.foreground || '#ffffff') : null }))),
    a.bubble === 'custom' ? row('颜色', '文字与背景需要足够对比度（4.5:1）。', h('div.inline', h('span.muted', '文字'), h('input', { type: 'color', value: a.foreground || '#ffffff', onchange: e => setLook({ foreground: e.target.value }) }), h('span.muted', '背景'), h('input', { type: 'color', value: a.background || '#1f2a30', onchange: e => setLook({ background: e.target.value }) }), h('span.muted', '边线'), h('input', { type: 'color', value: a.border || '#ffffff', onchange: e => setLook({ border: e.target.value }) }))) : null,
    a.bubble !== 'none' ? row('背景与边线', null, h('div.inline', h('span.muted', '背景'), toggle(a.backgroundEnabled, v => setLook({ backgroundEnabled: v })), h('span.muted', '边线'), toggle(a.borderEnabled, v => setLook({ borderEnabled: v })))) : null,
    row('字号', `${a.fontSize} 像素`, h('input', { type: 'range', min: 22, max: 44, step: 1, value: a.fontSize, onchange: e => setLook({ fontSize: Number(e.target.value) }) })),
    row('速度', `每秒 ${a.speed} 像素`, h('input', { type: 'range', min: 40, max: 240, step: 10, value: a.speed, onchange: e => setLook({ speed: Number(e.target.value) }) })),
    row('圆角', `${a.corner} 像素`, h('input', { type: 'range', min: 0, max: 24, step: 1, value: a.corner, onchange: e => setLook({ corner: Number(e.target.value) }) })),
    row('试播', '在桌面播放一条示例弹幕，不会打开真实会话。', btn('试播一条', () => call('danmu.preview'), '.primary'))));
  // retention
  const r = f.retention;
  const hh = String(Math.floor(r.cleanupMinute / 60)).padStart(2, '0'), mm = String(r.cleanupMinute % 60).padStart(2, '0');
  out.push(h('div.section-title', '消息保留'));
  out.push(card(null, '消息只保存在这台电脑上，按账号分开存放；不上传，不写入日志。',
    row('保留时长', r.days === 0 ? '仅保留本次使用，关闭后清空。' : `保留最近 ${r.days} 天。`, seg(r.days, [[0, '仅本次'], [1, '1天'], [3, '3天'], [7, '7天'], [14, '14天'], [30, '30天']], v => call('feishu.updateRetention', { ...r, days: v }))),
    r.days > 0 ? row('每天清理时间', null, h('input', { type: 'time', value: `${hh}:${mm}`, onchange: e => { const [x, y] = e.target.value.split(':').map(Number); call('feishu.updateRetention', { ...r, cleanupMinute: x * 60 + y }); } })) : null));
  return out;
}

// ---------- Agent ----------
function agents() {
  const a = S.agents, p = a.preferences;
  const out = [];
  out.push(card('获取本机 Agent', '找到工具后，点击“连接”才开始读取状态。也可以先不连接。',
    h('div.inline', btn(local.discovered ? '重新获取本机 Agent' : '一键获取本机 Agent', () => call('agents.discover').then(r => { local.discovered = r; render(); }), '.solid')),
    local.discovered ? h('div.list', { style: { marginTop: '14px' } }, local.discovered.length ? local.discovered.map(id => {
      const prof = a.profiles.find(x => x.id === id);
      return h('div.item', AGENT_ICONS[id] ? h('img', { src: AGENT_ICONS[id], style: { width: '26px', height: '26px' } }) : null, h('div.grow', h('b', prof.name)),
        prof.mode !== 'off' ? h('small.muted', prof.mode === 'show' ? '已在岛上显示' : '监测已开启 · 未在岛上显示') : btn('连接', () => call('agents.connect', id)));
    }) : h('p.desc', '未找到支持的工具。Codex 需要已安装命令行；Claude Code 需要已使用过（存在 .claude 目录）。')) : null));
  const order = [...a.profiles.filter(x => x.mode === 'show'), ...a.profiles.filter(x => x.mode !== 'show')];
  out.push(h('div.card', h('h3', '我的工具', h('span.right', btn('接入Agent', () => { local.adding = !local.adding; render(); }, '.solid'))),
    h('p.desc', '选择工具的使用方式，修改后立即生效。岛上最多显示三个。'),
    local.adding ? h('div.item', { style: { marginBottom: '14px' } }, h('div.grow.inline', h('input.field', { placeholder: '名称，如 Kimi', value: local.customName, oninput: e => { local.customName = e.target.value; } }), h('input.field', { placeholder: '入口地址（HTTPS，可留空）', value: local.customURL, oninput: e => { local.customURL = e.target.value; } })),
      btn('添加', () => call('agents.addCustom', local.customName, local.customURL).then(() => { local.customName = ''; local.customURL = ''; local.adding = false; toast('已添加；自定义 Agent 只提供快捷入口，不读取状态。'); render(); }), '.primary')) : null,
    h('div.grid2', order.map(prof => {
      const q = prof.quotas.find(x => x.fresh) || prof.quotas[0];
      return h('div.agent.' + prof.id,
        h('div.top', AGENT_ICONS[prof.id] ? h('img', { src: AGENT_ICONS[prof.id] }) : h('div.ph', [...prof.name][0]), h('div', { style: { flex: 1 } }, h('b', prof.name), h('small', h('span.light-dot.' + prof.state), prof.windows ? prof.stateLabel : 'Windows 版暂不支持')),
          prof.windows && prof.kind !== 'custom' ? h('button.btn', { title: '刷新', onclick: () => call('agents.refresh') }, '↻') : null),
        prof.kind !== 'custom' ? h('div.quotaBox', q ? [h('div.big', `${Math.round(q.remainingPercent)}%`), h('small', `${q.label}剩余${q.resetsAt ? ' · ' + relative(q.resetsAt - Date.now() / 1000) + '后重置' : ''}${q.fresh ? '' : ' · 等待更新'}`),
          prof.quotas.slice(1, 3).map(x => h('div.qrow', h('span', x.label), h('span.muted', `${Math.round(x.remainingPercent)}%`), h('div.bar', h('i' + (x.remainingPercent < 20 ? '.low' : ''), { style: { width: x.remainingPercent + '%' } }))))]
          : [h('div.big', '额度未知'), h('small', prof.windows ? '此来源尚未提供额度数据' : '这个工具在 Windows 上的读取方式尚未确认')]) : h('div.foot', prof.launchURL || '没有设置入口地址'),
        prof.windows ? h('div.modes', [['show', '▭', '岛上显示'], ['alerts', '🔔', '仅提醒'], ['off', '⊖', '不使用']].map(([m, i, l]) => h('button' + (prof.mode === m ? '.on' : ''), { onclick: () => call('agents.setMode', prof.id, m).then(r => { if (r && r.needsReplace) { const first = a.profiles.find(x => x.mode === 'show' && x.id !== prof.id); if (first && confirm(`岛上最多显示三个。用 ${prof.name} 替换 ${first.name}？`)) call('agents.setMode', prof.id, m, first.id); } }) }, h('span', i), l))) : null,
        prof.id === 'claude' && prof.mode !== 'off' ? h('div.inline', a.claudeHook ? [h('span.muted', '✓ 已写入 Claude Code 状态提醒'), btn('移除', () => call('agents.uninstallClaude'))] : [h('span.muted', '需要在 Claude Code 设置里加入状态提醒（保留你原有的设置并备份）'), btn('连接', () => call('agents.installClaude').then(() => toast('已连接 Claude Code，新开的会话生效')), '.primary')]) : null,
        prof.kind === 'custom' ? h('div.inline', prof.launchURL ? btn('打开', () => call('agents.open', prof.id)) : null, btn('移除', () => call('agents.removeCustom', prof.id), '.danger')) : null,
        h('div.foot', prof.windows ? (prof.id === p.primaryID ? '主用工具 · ' : '') + (prof.detail || '') : 'Mac 版通过本机专用通道读取；Windows 版接口未确认前不连接。'),
        prof.windows && prof.mode === 'show' && prof.id !== p.primaryID ? btn('设为主用（显示在胶囊）', () => call('agents.primary', prof.id), '.link') : null);
    }))));
  const materials = S.todos.materials;
  out.push(card('提醒', 'Agent 状态变化时在岛上提示 6 秒。',
    row('开始运行时提醒', null, toggle(p.startAlerts, v => call('agents.update', { startAlerts: v }))),
    row('等你确认或输入时提醒', null, toggle(p.attentionAlerts, v => call('agents.update', { attentionAlerts: v }))),
    row('本轮完成时提醒', null, toggle(p.completionAlerts, v => call('agents.update', { completionAlerts: v }))),
    row('额度低于 20% 时提醒', null, toggle(p.quotaAlerts, v => call('agents.update', { quotaAlerts: v }))),
    row('在胶囊显示主用工具额度', null, toggle(p.quotaDisplayEnabled, v => call('agents.update', { quotaDisplayEnabled: v }))),
    row('提醒方式', '选择屏幕动效后，Agent 提醒改为全屏动画。', select(p.completionScreenMaterialID || '', [['', '灵动岛提示'], ...materials.map(m => [m.id, '屏幕动效 · ' + m.name])], v => call('agents.update', { completionScreenMaterialID: v || null })))));
  return out;
}

// ---------- 待办 ----------
function todoEditor(t) {
  const e = local.editing;
  const title = h('input.field', { value: e.title, oninput: ev => { e.title = ev.target.value; } });
  const details = h('textarea.field', { rows: 3, oninput: ev => { e.details = ev.target.value; } }); details.value = e.details;
  const materials = S.todos.materials;
  return h('div.item', { style: { flexDirection: 'column', alignItems: 'stretch' } },
    h('div.edit-grid',
      h('label', '名称'), title,
      h('label', '说明'), details,
      h('label', '完成期限'), h('div.inline', h('input', { type: 'datetime-local', value: e.deadline ? toLocalInput(e.deadline) : '', onchange: ev => { e.deadline = fromLocalInput(ev.target.value); } }), e.deadline ? btn('清除', () => { e.deadline = null; render(); }, '.link') : null),
      h('label', '提醒时间'), h('div.dates', e.dates.map((d, i) => h('span.inline', h('input', { type: 'datetime-local', value: toLocalInput(d), onchange: ev => { e.dates[i] = fromLocalInput(ev.target.value); e.changed = true; } }), btn('×', () => { e.dates.splice(i, 1); e.changed = true; render(); }, '.link'))), e.dates.length < 48 ? btn('＋ 添加', () => { e.dates.push(Math.ceil(Date.now() / 60000) * 60 + 1800); e.changed = true; render(); }) : null),
      h('label', '循环'), h('div.inline', select(String(e.repeat || ''), [['', '不循环'], ['30', '每30分钟'], ['60', '每小时'], ['1440', '每天'], ['10080', '每周']], v => { e.repeat = v ? Number(v) : null; e.changed = true; render(); }), e.repeat ? [h('span.muted', '截止'), h('input', { type: 'datetime-local', value: e.until ? toLocalInput(e.until) : '', onchange: ev => { e.until = fromLocalInput(ev.target.value); e.changed = true; } })] : null),
      h('label', '到时提醒'), select(e.style ? e.style.materialID : '', [['', '灵动岛提醒'], ...materials.map(m => [m.id, '屏幕动效 · ' + m.name])], v => { e.style = v ? { materialID: v, durationSeconds: 15 } : null; }),
      h('label', '完成效果'), select(e.completion ? e.completion.materialID : '', [['', '标记完成'], ...materials.map(m => [m.id, '屏幕动效 · ' + m.name])], v => { e.completion = v ? { materialID: v, durationSeconds: 15 } : null; })),
    h('div.inline', { style: { marginTop: '12px' } },
      btn('保存', () => call('todos.update', t.id, { title: e.title, details: e.details, deadline: e.deadline, dates: e.dates.filter(Boolean), repeatMinutes: e.repeat || null, repeatUntil: e.repeat ? e.until : null, style: e.style, completionStyle: e.completion, preserveSchedule: !e.changed }).then(() => { local.editing = null; toast('已保存'); render(); }), '.solid'),
      btn('取消', () => { local.editing = null; render(); })));
}
function todos() {
  const t = S.todos, out = [];
  const materials = t.materials;
  out.push(card('提醒方式', '待办和飞书日程到时间后，怎样提醒你。',
    h('div.choices', choice(!t.defaultScreen, '⬭', '灵动岛提醒', '在屏幕顶部轻轻提醒', () => call('todos.setDefaultScreen', null)),
      choice(!!t.defaultScreen, '✧', '屏幕动效', '用一段动效提醒你', () => call('todos.setDefaultScreen', { materialID: (materials[0] || {}).id || 'cat', durationSeconds: 15 }))),
    t.defaultScreen ? row('动效素材', null, select(t.defaultScreen.materialID, materials.map(m => [m.id, m.name]), v => call('todos.setDefaultScreen', { ...t.defaultScreen, materialID: v }))) : null,
    h('div.row', h('div.label', h('small', '新待办使用默认效果，已有待办可单独调整。')), btn('体验提醒', () => t.defaultScreen ? call('todos.previewReminder', t.defaultScreen) : toast('灵动岛提醒会在顶部展开，并停留 4 秒。')))));
  out.push(card('完成时', null,
    h('div.choices', choice(!t.encouragement, '✓', '标记完成', '保留完整文字，方便回看', () => call('todos.setEncouragement', false)), choice(t.encouragement, '✔', '对勾鼓励', '完成一件，给自己一个肯定', () => call('todos.setEncouragement', true)))));
  // schedule
  const s = t.schedule;
  out.push(card('飞书日程', '只读取本人主日历未来30天的日程，在岛上提醒你。删除只在本机隐藏，不改动飞书。',
    row(s.enabled ? '已连接飞书日历' : '尚未连接飞书日历', S.schedule || (s.lastSync ? '上次同步 ' + dateTime(s.lastSync) : null),
      S.demo ? h('span.muted', '演示模式') : s.enabled ? h('div.inline', btn('立即同步', () => call('schedule.sync')), btn('停用', () => call('schedule.disable'))) : btn('连接日历', () => call('schedule.connect'), '.primary')),
    s.enabled && s.events.length ? h('div.list', s.events.slice(0, 30).map(e => h('div.item', h('div.grow', h('b', e.title), h('small', (e.allDay ? new Date(e.start * 1000).toLocaleDateString('zh-CN') + ' · 全天' : dateTime(e.start) + ' — ' + time(e.end)))),
      select(String((e.offsets || [])[0] ?? ''), [['', '不提醒'], ['0', '开始时'], ['15', '提前15分钟'], ['60', '提前1小时'], ['1440', '提前1天']], v => call('schedule.offsets', e.id, v === '' ? [] : (v === '1440' ? [1440, 15] : [Number(v)]))),
      btn('移除', () => call('schedule.remove', e.id), '.danger')))) : null));
  // todos
  out.push(h('div.section-title', `待办 · ${t.pending.length}`, h('span.right', '在岛上也可以直接添加、完成和排序')));
  const input = h('input.field', { placeholder: '添加待办，回车保存', maxlength: 160, onkeydown: e => { if (e.key === 'Enter' && input.value.trim()) call('todos.add', input.value).then(() => { input.value = ''; }); } });
  out.push(h('div.card', h('div.inline', input, btn('添加', () => input.value.trim() && call('todos.add', input.value).then(() => { input.value = ''; }), '.primary')),
    h('div.list', { style: { marginTop: '14px' } }, t.pending.map((x, i) => local.editing && local.editing.id === x.id ? todoEditor(x) : h('div.item',
      h('button.btn', { title: '完成', onclick: () => call('todos.complete', x.id) }, '○'),
      h('div.grow', h('b', x.title), h('small', [x.deadline ? '期限 ' + dateTime(x.deadline) : null, x.due ? '提醒 ' + dateTime(x.due) : '未设提醒', x.reminder && x.reminder.repeatMinutes ? `每${x.reminder.repeatMinutes}分钟` : null, x.screenReminder ? '屏幕动效' : null].filter(Boolean).join(' · '))),
      btn('↑', () => call('todos.move', x.id, -1)), btn('↓', () => call('todos.move', x.id, 1)),
      btn('编辑', () => { local.editing = { id: x.id, title: x.title, details: x.details, deadline: x.deadline, dates: x.reminder ? x.reminder.pendingDates.slice() : (x.due ? [x.due] : []), repeat: x.reminder ? x.reminder.repeatMinutes : null, until: x.reminder ? x.reminder.repeatUntil : null, style: x.screenReminder, completion: x.completionReminder, changed: false }; render(); }),
      btn('删除', () => call('todos.remove', x.id), '.danger'))), !t.pending.length ? h('p.desc', '暂无待办事项。') : null),
    t.error ? h('div.notice', { style: { marginTop: '12px' } }, t.error) : null));
  // history
  out.push(h('div.card', h('h3', h('button.collapse-head', { onclick: () => { local.historyOpen = !local.historyOpen; render(); } }, local.historyOpen ? '▾' : '▸', ` 完成记录 · ${t.history.length}`), h('span.right', btn('复制本周记录', () => call('todos.copyWeek').then(n => toast(`已复制本周 ${n} 条完成记录（周一至周日）`)), '.link'))),
    local.historyOpen ? h('div.list', t.history.map(e => h('div.item', h('div.grow', h('b', e.title), h('small', e.completedAt ? '完成于 ' + dateTime(e.completedAt) : '完成时间未记录')), btn('删除记录', () => confirm('只删除这条完成记录，不影响其他待办。确定？') && call('todos.deleteHistory', e.id), '.danger')))) : null,
    h('h3', { style: { marginTop: '18px' } }, h('button.collapse-head', { onclick: () => { local.trashOpen = !local.trashOpen; render(); } }, local.trashOpen ? '▾' : '▸', ` 最近删除 · ${t.trash.length}`)),
    local.trashOpen ? h('div.list', t.trash.map(x => h('div.item', h('div.grow', h('b', x.title)), btn('恢复', () => call('todos.restore', x.id), '.primary'), btn('彻底删除', () => confirm('彻底删除后无法恢复。确定？') && call('todos.purgeTrash', x.id), '.danger')))) : null));
  return out;
}

// ---------- 中台 ----------
function platform() {
  const hb = S.hub, w = S.wheel, out = [];
  out.push(card('连接本人虚实中台', '只读读取你的中台首页卡片与常用应用。授权保存在本机，用 Windows 系统加密保护。',
    row(hb.connected ? (hb.name || '已连接中台') : '尚未连接', hb.readAt ? '上次读取 ' + dateTime(hb.readAt) : (hb.error || null),
      S.demo ? h('span.muted', '演示数据') : hb.connected ? h('div.inline', btn(hb.busy ? '刷新中…' : '刷新', () => call('hub.refresh')), btn('断开', () => confirm('断开后需要重新授权才能读取中台。确定？') && call('hub.disconnect'), '.danger')) : btn('连接中台', () => call('hub.connect').then(() => toast('已在浏览器打开中台授权页')), '.primary')),
    hb.error && hb.connected ? h('div.notice', hb.error) : null));
  if (hb.connected) {
    out.push(card('岛上显示的卡片', '勾选后按顺序显示在岛的“中台”页。',
      h('div.list', hb.cards.map(c => { const i = hb.selected.indexOf(c.id); return h('div.item', toggle(i >= 0, () => call('hub.toggleCard', c.id)), h('div.grow', h('b', c.title), h('div.sec-text', c.text)), i >= 0 ? [btn('↑', () => call('hub.moveCard', c.id, -1)), btn('↓', () => call('hub.moveCard', c.id, 1))] : null); })),
      !hb.cards.length ? h('p.desc', '中台暂未返回卡片。') : null));
  }
  const groups = {};
  for (const c of w.catalog) (groups[c.group] = groups[c.group] || []).push(c);
  const DIRS = ['上', '右上', '右', '右下', '下', '左下', '左', '左上'];
  out.push(card('信号轮盘', '按下快捷键，轮盘出现在鼠标位置；移向一个方向后点击打开。',
    row('快捷键', 'Windows 版支持组合键。Esc 取消。', hotkeyRecorder('wheel', w.hotkey, 'wheel.setHotkey')),
    row('在岛上显示“中台”页', null, toggle(w.showInMainBar, v => call('wheel.set', { showInMainBar: v }))),
    row('打开时播放提示音', null, toggle(w.soundEnabled, v => call('wheel.set', { soundEnabled: v }))),
    h('div.slots', { style: { marginTop: '12px' } }, w.slots.map((slot, i) => {
      const d = w.destinations[i];
      const value = slot.source === 'automatic' ? 'auto' : slot.source === 'custom' ? 'custom' : slot.source === 'empty' ? 'empty' : slot.source === 'settings' ? 'settings' : (slot.source === 'builtin' ? 'builtin:' : slot.source === 'application' ? 'app:' : 'card:') + slot.cardID;
      const sel = h('select', { onchange: () => {
        const v = sel.value;
        if (v === 'custom') { local.slotEdit = { i, title: slot.title || '', address: slot.address || '', icon: slot.icon || null }; render(); return; }
        const next = v === 'auto' ? { source: 'automatic', cardID: '', title: '', address: '', icon: slot.icon || null } : v === 'empty' ? { source: 'empty', cardID: '', title: '', address: '', icon: null } : { ...w.catalog.find(c => c.id === v).slot, icon: slot.icon || null };
        call('wheel.setSlot', i, next);
      } }, h('option', { value: 'auto', selected: value === 'auto' }, '默认 · ' + ['首页', 'OKR', '资料', '数据', '异常项', '应用', 'Skill', '审批'][i]),
        Object.entries(groups).map(([g, items]) => h('optgroup', { label: g }, items.map(c => h('option', { value: c.id, selected: c.id === value }, c.title)))),
        h('option', { value: 'custom', selected: value === 'custom' }, '自定义网址…'), h('option', { value: 'empty', selected: value === 'empty' }, '空位'));
      return h('div.slot', h('div.dir', { title: DIRS[i] }, slot.icon ? h('img', { src: slot.icon }) : DIRS[i]), h('div', { style: { flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: '4px' } }, sel, h('small.muted', d.available ? d.title : d.title + '（暂不可用）')),
        btn('图标', () => { const inp = h('input', { type: 'file', accept: 'image/png,image/jpeg,image/webp', onchange: () => iconFile(inp.files[0], i, slot) }); inp.click(); }),
        i > 0 ? btn('⇄', () => call('wheel.swap', i, i - 1)) : null);
    })),
    local.slotEdit ? h('div.item', { style: { marginTop: '12px' } }, h('div.grow.inline', h('span.muted', `自定义 · ${DIRS[local.slotEdit.i]}`), h('input.field', { placeholder: '名称（最多40字）', value: local.slotEdit.title, oninput: e => { local.slotEdit.title = e.target.value; } }), h('input.field', { placeholder: 'https://…', value: local.slotEdit.address, oninput: e => { local.slotEdit.address = e.target.value; } })),
      btn('保存', () => call('wheel.setSlot', local.slotEdit.i, { source: 'custom', cardID: '', title: local.slotEdit.title.trim(), address: local.slotEdit.address.trim(), icon: local.slotEdit.icon }).then(() => { local.slotEdit = null; render(); }), '.primary'), btn('取消', () => { local.slotEdit = null; render(); })) : null));
  return out;
}
function iconFile(file, i, slot) {
  if (!file) return;
  const img = new Image(); const url = URL.createObjectURL(file);
  img.onload = () => { const c = document.createElement('canvas'); c.width = c.height = 96; const x = c.getContext('2d'); const s = Math.min(img.width, img.height); x.drawImage(img, (img.width - s) / 2, (img.height - s) / 2, s, s, 0, 0, 96, 96); URL.revokeObjectURL(url); call('wheel.setSlot', i, { ...slot, icon: c.toDataURL('image/png') }).then(() => toast('图标已保存在本机')); };
  img.onerror = () => toast('图片无法读取', true);
  img.src = url;
}

// ---------- 休息提醒 ----------
function rest() {
  const r = S.todos.rest, materials = S.todos.materials;
  return [card(null, null,
    row('开启休息提醒', r.enabled ? (r.paused ? '已暂停' : r.systemPaused ? '离开电脑时已自动暂停' : `下次提醒：${relative(r.remaining)}后`) : null, toggle(r.enabled, v => call('rest.enable', v))),
    r.enabled ? row('间隔', `${r.intervalMinutes} 分钟`, h('input', { type: 'range', min: 5, max: 240, step: 5, value: r.intervalMinutes, onchange: e => call('rest.interval', Number(e.target.value)) })) : null,
    r.enabled ? row('暂时暂停', null, toggle(r.paused, v => call('rest.pause', v))) : null,
    row('离开电脑时暂停计时', '锁屏或睡眠期间不计时，回来后继续。', toggle(r.pauseWhenAway, v => call('rest.pauseWhenAway', v))),
    row('提醒动效', null, select(r.materialID, materials.map(m => [m.id, m.name]), v => call('rest.material', v))),
    row('播放声音', null, toggle(r.sound, v => call('rest.sound', v))),
    row('体验一下', '播放一次休息提醒，3秒后可以点击关闭。', btn('体验', () => call('todos.previewReminder', { materialID: r.materialID, durationSeconds: 15 }), '.primary')))];
}

// ---------- 外观与交互 ----------
function appearancePage() {
  const i = S.island, u = S.update, out = [];
  out.push(card('悬浮交互', null,
    h('div.choices', choice(i.hoverMode === 'immediately', '⇕', '完整展开', '鼠标移入，就能查看和操作。', () => call('island.set', { hoverMode: 'immediately' })), choice(i.hoverMode === 'peekFirst', '⬭', '先露出胶囊', '轻轻露出，点一下再完整展开。', () => call('island.set', { hoverMode: 'peekFirst' }))),
    row('收起时', null, seg(i.collapsed, [['edge', '露出黑边'], ['hidden', '完全隐藏']], v => call('island.set', { collapsed: v }))),
    row('展开与收起快捷键', null, hotkeyRecorder('toggle', i.toggleHotkey, 'island.setHotkey'))));
  out.push(card('主题', null,
    row('明暗', null, seg(i.palette, [['dark', '深色'], ['light', '浅色'], ['system', '跟随 Windows']], v => call('island.set', { palette: v }))),
    row('岛内字号', `${Math.round(i.textScale * 100)}%`, h('input', { type: 'range', min: 0.9, max: 1.3, step: 0.05, value: i.textScale, onchange: e => call('island.set', { textScale: Number(e.target.value) }) }))));
  out.push(card('灵动岛显示在哪里', null,
    row('显示屏', null, seg(i.display, [['primary', '主显示器'], ['cursor', '鼠标所在显示器']], v => call('island.set', { display: v })))));
  out.push(card('启动与更新', null,
    row('开机时启动一切在岛', S.packaged ? null : '安装版生效。', toggle(i.launchAtLogin, v => call('island.launchAtLogin', v))),
    row('发现新版时提醒', null, toggle(i.autoCheckUpdates, v => call('island.set', { autoCheckUpdates: v }))),
    row(`版本 ${S.version} · ${S.build}`, u.available ? `发现新版本 ${u.available.version}` + (u.downloaded ? ' · 已下载' + (u.downloaded.verified ? '并校验' : '') : u.progress ? ` · 下载中 ${Math.round(u.progress * 100)}%` : '') : (u.error || 'Windows 版 · 未签名测试包'),
      h('div.inline', u.available ? (u.downloaded ? btn('安装并重启', () => call('update.install'), '.solid') : btn('下载更新', () => call('update.download'), '.primary')) : null, btn(u.checking ? '检查中…' : '检查更新', () => call('update.check'))))));
  return out;
}

// ---------- shell ----------
function render() {
  if (!S) return;
  applyTheme(S.island);
  const [, title, , subtitle] = SECTIONS.find(s => s[0] === section) || SECTIONS[0];
  document.getElementById('title').textContent = title;
  document.getElementById('subtitle').textContent = subtitle;
  document.getElementById('sections').replaceChildren(...SECTIONS.map(([id, label, icon]) => h('button' + (id === section ? '.on' : ''), { onclick: () => { section = id; local.results = null; render(); document.getElementById('page').scrollTop = 0; } }, h('span.ic', icon), label)));
  const page = document.getElementById('page');
  const active = document.activeElement;
  if (active && page.contains(active) && /^(INPUT|TEXTAREA)$/.test(active.tagName) && active.type !== 'range') return;
  const top = page.scrollTop;
  const builder = { messages, agents, todos, platform, rest, appearance: appearancePage }[section] || messages;
  page.replaceChildren(...builder().flat().filter(Boolean));
  page.scrollTop = top;
}
document.getElementById('replay').addEventListener('click', () => call('open.onboarding'));
api.onState(s => { S = s; render(); });
api.onEvent(({ event, payload }) => { if (event === 'section' && payload) { section = payload; render(); } });
document.addEventListener('focusout', () => setTimeout(render, 0));
call('state').then(s => { if (!S) { S = s; render(); } });
