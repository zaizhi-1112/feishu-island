'use strict';
// 一切在岛 Windows — main process.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const { app, BrowserWindow, ipcMain, Tray, Menu, globalShortcut, powerMonitor, shell, nativeImage, safeStorage, clipboard, screen, dialog } = require('electron');

const argv = process.argv.slice(1);
const DEMO = argv.includes('--demo');
const SMOKE = argv.find(a => a.startsWith('--smoke-shot='));

// Data lives in an ASCII directory (mirrors Mac "Application Support/FeishuIsland").
// Development runs outside Windows never share the Mac app's directory.
const explicitData = (argv.find(a => a.startsWith('--data-dir=')) || '').slice('--data-dir='.length);
const DATA = explicitData || (DEMO ? fs.mkdtempSync(path.join(os.tmpdir(), 'feishu-island-win-demo-'))
  : process.platform === 'win32' ? path.join(process.env.APPDATA || app.getPath('appData'), 'FeishuIsland') : path.join(app.getPath('appData'), 'FeishuIsland-Windows-dev'));
fs.mkdirSync(DATA, { recursive: true });
app.setPath('userData', path.join(DATA, 'Electron'));
app.setAppUserModelId('local.zaizhi.feishu-island.windows');

if (!DEMO && !SMOKE && !app.requestSingleInstanceLock()) { app.quit(); return; }

const { Prefs } = require('../core/prefs.cjs');
const { TodoStore } = require('../core/todos.cjs');
const { fetchEvents } = require('../core/schedule.cjs');
const { AgentStore } = require('../core/agents/store.cjs');
const hub = require('../core/hub.cjs');
const updater = require('../core/updater.cjs');
const { runCLI } = require('../core/cli.cjs');
const appearance = require('../core/appearance.cjs');
const M = require('../core/feishu/message.cjs');
const { CompanyConnection, cliEnvironment } = require('./company.cjs');
const { FeishuService } = require('./feishu.cjs');
const W = require('./windows.cjs');

const prefs = new Prefs(path.join(DATA, 'preferences.json'));
const CLI = app.isPackaged ? path.join(process.resourcesPath, 'cli', 'lark-cli.exe') : path.join(__dirname, '..', 'vendor', 'win-x64', 'lark-cli.exe');
const ASSETS = path.join(__dirname, '..', 'assets');
const REMINDER_DIR = app.isPackaged ? path.join(process.resourcesPath, 'app.asar.unpacked', 'assets', 'reminders') : path.join(ASSETS, 'reminders');

const ISLAND_DEFAULTS = { hoverMode: 'immediately', palette: 'dark', textScale: 1, collapsed: 'edge', keepOpen: false, display: 'primary', toggleHotkey: 'Control+Alt+;', activeModule: 'feishu', launchAtLogin: false, dismissReminderWithKey: true, autoCheckUpdates: true };
const islandPrefs = () => ({ ...ISLAND_DEFAULTS, ...(prefs.get('island') || {}) });
const setIslandPrefs = patch => { prefs.set('island', { ...islandPrefs(), ...patch }); broadcast(); };
if (!prefs.has('onboarding')) prefs.set('onboarding', DEMO ? 'done' : 'pending');
const onboardingPending = () => prefs.get('onboarding') === 'pending';

let island = null, danmu = null, settings = null, onboarding = null, wheel = null, reminder = null, tray = null;
let locked = false, lastUpdate = null, updateState = { checking: false, error: '', downloaded: null, progress: 0 };

// ---- services ----
const company = new CompanyConnection({ prefs, preload: W.PRELOAD, uiFile: path.join(W.RENDERER, 'connect.html'), icon: W.ICON });
const feishu = new FeishuService({ prefs, company, dataDir: DATA, cliPath: CLI, demo: DEMO, canPresent: () => !onboardingPending() });
const todos = new TodoStore({ file: path.join(DATA, 'workspace.json'), canRemind: () => !onboardingPending() && !locked });
const agents = new AgentStore({ prefs, statusRoot: path.join(DATA, 'AgentStatus'), locked: () => locked });
const grantFile = path.join(DATA, 'hub-grant.bin');
const hubClient = new hub.HubClient({
  loadGrant: () => { try { return JSON.parse(safeStorage.decryptString(fs.readFileSync(grantFile))); } catch { return null; } },
  saveGrant: g => { if (!safeStorage.isEncryptionAvailable()) throw new Error('系统加密存储不可用，未保存中台授权。'); fs.writeFileSync(grantFile, safeStorage.encryptString(JSON.stringify(g)), { mode: 0o600 }); },
  clearGrant: () => fs.rmSync(grantFile, { force: true })
});
let hubState = { connected: false, name: '', cards: [], applications: [], applicationsError: null, readAt: null, error: '', busy: false };
const wheelPrefs = () => { const w = prefs.get('wheel'); return w && w.version === 1 && Array.isArray(w.slots) && w.slots.length === 8 ? w : hub.defaultWheel(); };

if (DEMO) {
  hubState = { connected: true, name: '演示中台', cards: [{ id: 'page:工作计划:0', title: '工作周报', kind: 'report', text: '本周：完成 Windows 版首轮移植\n下周：真机验收', href: 'https://hub.example.invalid/', sections: [{ title: '工作计划', text: '', children: [{ title: '本周', text: '完成 Windows 版首轮移植', children: [] }, { title: '下周', text: '真机验收', children: [] }] }] }, { id: 'data:社群数据:0', title: '社群数据', kind: 'metric', text: '新增成员：128', href: 'https://hub.example.invalid/data', sections: [{ title: '新增成员', text: '128', children: [] }] }], applications: [{ id: 'a1', name: '社群运营系统', url: 'https://community.example.invalid', frequent: true }], applicationsError: null, readAt: Date.now() / 1000, error: '', busy: false };
  if (!prefs.has('hub.selected')) prefs.set('hub.selected', ['page:工作计划:0', 'data:社群数据:0']);
  const demoAgents = agents.preferences; if (!demoAgents.visibleIDs.length) { demoAgents.enabled = true; demoAgents.visibleIDs = ['codex', 'claude']; demoAgents.monitoredIDs = ['codex', 'claude']; demoAgents.quotaDisplayEnabled = true; }
  agents.snapshots.codex = { sessions: [{ id: 'demo', state: 'working', updatedAt: Date.now() / 1000 }], quotas: [{ id: 'codex/primary', label: '5小时额度', remainingPercent: 72, resetsAt: Date.now() / 1000 + 7200, updatedAt: Date.now() / 1000 }], source: '演示', detail: '演示数据，未读取本机 Codex。' };
  agents.snapshots.claude = { sessions: [{ id: 'demo2', state: 'completed', updatedAt: Date.now() / 1000 - 30 }], quotas: [{ id: 'five_hour', label: '5小时额度', remainingPercent: 46, resetsAt: Date.now() / 1000 + 3600, updatedAt: Date.now() / 1000 }], source: '演示', detail: '演示数据，未读取本机 Claude Code。' };
  if (!todos.disk.items.length) { const a = todos.add('整理本周社群数据'); todos.add('回复合作方邮件'); todos.add('Windows 真机安装测试'); todos.complete(a); }
}

// ---- state broadcast ----
let broadcastTimer = null;
function state() {
  const selected = prefs.get('hub.selected', []);
  const w = wheelPrefs();
  return {
    version: app.getVersion(), build: '110', platform: process.platform, demo: DEMO, packaged: app.isPackaged,
    onboarding: onboardingPending() ? 'pending' : 'done', island: islandPrefs(), locked,
    feishu: feishu.snapshot(), todos: todos.snapshot(), agents: agents.snapshotForUI(),
    hub: { ...hubState, selected, visible: selected.map(id => hubState.cards.find(c => c.id === id)).filter(Boolean) },
    wheel: { ...w, destinations: hub.destinations(w, hubState.cards, hubState.applications), catalog: hub.catalog(hubState.cards, hubState.applications) },
    update: { ...updateState, available: lastUpdate ? { version: lastUpdate.versionText, notes: lastUpdate.notes, prerelease: lastUpdate.prerelease } : null },
    schedule: scheduleStatus
  };
}
function windows() { return [island, danmu, settings, onboarding, wheel, reminder].filter(w => w && !w.isDestroyed()); }
function broadcast() {
  clearTimeout(broadcastTimer);
  broadcastTimer = setTimeout(() => { const s = state(); for (const w of windows()) w.webContents.send('island:state', s); refreshTray(); }, 30);
}
function send(win, event, payload) { if (win && !win.isDestroyed()) win.webContents.send('island:event', { event, payload }); }
for (const emitter of [feishu.store, todos, agents, company]) emitter.on('change', broadcast);

// ---- feishu → island / danmu ----
feishu.store.on('openReader', () => send(island, 'reveal', { module: 'feishu', seconds: 5 }));
feishu.store.on('alert', count => send(island, 'peek', { module: 'feishu', text: `${count}条重要消息 · 点击查看` }));
feishu.store.on('danmu', message => showDanmu({ id: message.id, text: M.danmuText(message), created: message.created, canOpen: !!M.chatURL(message) }));
feishu.store.on('clearDanmu', () => send(danmu, 'clear'));
feishu.store.on('danmuOptions', () => send(danmu, 'appearance', appearance.resolve(feishu.store.appearance)));
feishu.store.on('retain', ids => send(danmu, 'retain', [...ids]));
function showDanmu(item) {
  if (!feishu.store.danmu.enabled || locked) return;
  if (!danmu || danmu.isDestroyed()) {
    danmu = W.createDanmu();
    danmu.webContents.once('did-finish-load', () => { send(danmu, 'appearance', appearance.resolve(feishu.store.appearance)); send(danmu, 'paused', feishu.store.danmu.paused); send(danmu, 'enqueue', item); danmu.showInactive(); });
    danmu.on('closed', () => { danmu = null; });
    return;
  }
  if (!danmu.isVisible()) danmu.showInactive();
  send(danmu, 'enqueue', item);
}

// ---- todos & agents → island / reminder ----
todos.on('notify', n => send(island, 'peek', { module: 'todos', text: n.title }));
todos.on('screen', request => presentReminder(request));
todos.on('encourage', title => send(island, 'peek', { module: 'todos', text: '✓ 完成了 · ' + title }));
agents.on('notice', n => send(island, 'peek', { module: 'agents', text: n.message, agent: n.profileID }));
agents.on('screen', request => presentReminder(request));

let reminderQueue = [];
function presentReminder(request) {
  if (locked || onboardingPending()) return;
  const material = todos.materials.find(m => m.id === request.style.materialID) || todos.materials[0];
  if (!material) { send(island, 'peek', { module: 'todos', text: request.title }); return; }
  const file = path.join(REMINDER_DIR, material.file);
  if (!fs.existsSync(file)) { send(island, 'peek', { module: 'todos', text: request.title + '（提醒素材暂不可用）' }); return; }
  const payload = { title: request.title, video: 'file:///' + file.replace(/\\/g, '/').replace(/^\//, ''), hasAlpha: material.hasAlpha, duration: Math.min(120, Math.max(request.style.durationSeconds || 15, Math.ceil(material.durationSeconds) + 1)), rest: !!request.rest, sound: !!request.sound };
  if (reminder && !reminder.isDestroyed()) { reminderQueue = [payload]; return; }
  reminder = W.createReminder();
  reminder.webContents.once('did-finish-load', () => { send(reminder, 'play', payload); reminder.showInactive(); });
  reminder.on('closed', () => { reminder = null; const next = reminderQueue.shift(); if (next) setTimeout(() => presentReminder({ title: next.title, style: { materialID: material.id, durationSeconds: next.duration }, rest: next.rest }), 300); });
}

// ---- calendar sync (company "calendar" purpose) ----
let scheduleStatus = '', scheduleSyncing = false;
async function calendarRequest(method, p, params) {
  const credential = await company.credential('calendar');
  const args = ['api', method, '/open-apis/calendar/v4/' + p, '--as', 'user', '--format', 'json'];
  if (params && Object.keys(params).length) args.push('--params', JSON.stringify(params));
  if (method === 'POST') args.push('--data', '{}');
  const result = await runCLI({ executable: CLI, args, env: cliEnvironment(credential, process.env, path.join(DATA, 'CompanyCLI')), cwd: DATA });
  if (!result || result.ok !== true || result.identity !== 'user' || !result.data) throw new Error('日历返回身份或内容无效。');
  return result.data;
}
async function syncSchedule() {
  if (DEMO || scheduleSyncing || !todos.disk.feishuSchedule.enabled || locked) return;
  scheduleSyncing = true; scheduleStatus = '正在检查未来30天的日程…'; broadcast();
  try {
    const credential = await company.credential('calendar');
    const key = credential.appID + ':' + credential.openID;
    if (todos.disk.feishuSchedule.account && todos.disk.feishuSchedule.account !== key) throw new Error('日历账号已变化，请重新连接。');
    const now = Date.now() / 1000;
    const { calendarID, events } = await fetchEvents(calendarRequest, now, now + 30 * 86400);
    todos.replaceScheduleEvents(key, calendarID, events);
    scheduleStatus = `已同步${events.length}个日程 · ${new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })}`;
  } catch (error) { scheduleStatus = '同步未完成，提醒暂时暂停：' + (error.message || '请稍后重试'); }
  finally { scheduleSyncing = false; broadcast(); }
}
company.continueHandlers.calendar = async () => {
  const credential = await company.prepare('calendar');
  company.activate(credential, 'calendar');
  todos.setSchedule({ enabled: true, account: credential.appID + ':' + credential.openID });
  await syncSchedule();
};

// ---- hub ----
let oauthServer = null;
async function connectHub() {
  if (DEMO) return;
  if (oauthServer) oauthServer.close();
  oauthServer = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1');
    if (url.pathname !== '/oauth/virxact/callback') { res.writeHead(404); res.end(); return; }
    let ok = true, message = '授权完成，可以关闭这个页面，回到一切在岛。';
    try { await hubClient.finish(url.searchParams); } catch (error) { ok = false; message = error.message; }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(`<!doctype html><meta charset="utf-8"><title>一切在岛</title><body style="font:16px system-ui;padding:48px;color:#202a30">${ok ? '✓ ' : ''}${message.replace(/[<>&]/g, '')}</body>`);
    oauthServer.close(); oauthServer = null;
    if (ok) { prefs.set('hub.selected', []); await refreshHub(); if (!prefs.get('hub.selected', []).length) prefs.set('hub.selected', hubState.cards.filter(c => c.kind === 'report').map(c => c.id)); broadcast(); }
    else { hubState.error = message; broadcast(); }
  });
  await new Promise(r => oauthServer.listen(0, '127.0.0.1', r));
  const callback = `http://127.0.0.1:${oauthServer.address().port}/oauth/virxact/callback`;
  try { await shell.openExternal(await hubClient.begin(callback)); }
  catch (error) { hubState.error = error.message; broadcast(); }
  setTimeout(() => { if (oauthServer) { oauthServer.close(); oauthServer = null; } }, 600000);
}
async function refreshHub() {
  if (DEMO) return;
  if (!hubClient.connected()) { hubState = { ...hubState, connected: false, cards: [], applications: [], error: '' }; broadcast(); return; }
  hubState.busy = true; broadcast();
  try { const s = await hubClient.snapshot(); hubState = { ...s, applications: s.applications || [], error: '', busy: false }; }
  catch (error) { hubState = { ...hubState, connected: hubClient.connected(), error: error.message, busy: false }; }
  broadcast();
}

// ---- windows ----
function ensureIsland() {
  if (onboardingPending()) { if (island && !island.isDestroyed()) island.hide(); return; }
  if (!island || island.isDestroyed()) {
    island = W.createIsland(islandPrefs().display);
    island.webContents.once('did-finish-load', () => { island.webContents.send('island:state', state()); island.showInactive(); if (SMOKE) smoke(); });
    island.on('closed', () => { island = null; });
  } else if (!island.isVisible()) island.showInactive();
}
function openSettings(section) {
  if (onboardingPending()) { openOnboarding(); return; }
  if (settings && !settings.isDestroyed()) { send(settings, 'section', section); settings.show(); settings.focus(); return; }
  settings = W.createSettings(section);
  settings.on('closed', () => { settings = null; });
}
function openOnboarding() {
  if (onboarding && !onboarding.isDestroyed()) { onboarding.show(); onboarding.focus(); return; }
  onboarding = W.createOnboarding();
  onboarding.on('closed', () => { onboarding = null; });
}
function openWheel() {
  if (onboardingPending() || locked) return;
  if (wheel && !wheel.isDestroyed()) { wheel.close(); return; }
  wheel = W.createWheel();
  wheel.webContents.once('did-finish-load', () => { wheel.webContents.send('island:state', state()); wheel.show(); wheel.focus(); });
  wheel.on('blur', () => { if (wheel && !wheel.isDestroyed()) wheel.close(); });
  wheel.on('closed', () => { wheel = null; });
}
function completeOnboarding() {
  prefs.set('onboarding', 'done'); prefs.flush();
  if (onboarding && !onboarding.isDestroyed()) onboarding.close();
  ensureIsland(); registerShortcuts(); feishu.startIfAllowed(); broadcast();
  setTimeout(() => send(island, 'reveal', { module: islandPrefs().activeModule, seconds: 4 }), 600);
}

// ---- shortcuts ----
function registerShortcuts() {
  globalShortcut.unregisterAll();
  const results = {};
  if (onboardingPending()) return results;
  const toggle = islandPrefs().toggleHotkey, ring = wheelPrefs().hotkey;
  try { results.toggle = toggle ? globalShortcut.register(toggle, () => send(island, 'toggle')) : true; } catch { results.toggle = false; }
  try { results.wheel = ring ? globalShortcut.register(ring, openWheel) : true; } catch { results.wheel = false; }
  return results;
}

// ---- tray ----
function refreshTray() {
  if (!tray) return;
  const s = feishu.store;
  tray.setToolTip(`一切在岛 · ${s.enabled ? (s.waitingCount ? s.waitingCount + '条待看' : '接收中') : '已暂停接收'}`);
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: onboardingPending() ? '继续首次设置' : '打开设置', click: () => openSettings('messages') },
    { label: '展开灵动岛', enabled: !onboardingPending(), click: () => send(island, 'reveal', { module: islandPrefs().activeModule, seconds: 6 }) },
    { type: 'separator' },
    { label: s.enabled ? '暂停接收飞书消息' : '继续接收飞书消息', enabled: s.rulesReadable, click: () => s.setEnabled(!s.enabled) },
    { label: s.isMuted ? '取消静音' : '静音 1 小时', click: () => s.toggleMute() },
    { type: 'separator' },
    { label: '退出一切在岛', click: () => app.quit() }
  ]));
}

// ---- IPC ----
const ok = v => ({ ok: true, value: v === undefined ? null : v });
const fail = e => ({ ok: false, error: (e && e.message) || String(e) });
const handlers = {
  'state': () => state(),
  'island.set': patch => { const allowed = ['hoverMode', 'palette', 'textScale', 'collapsed', 'keepOpen', 'display', 'activeModule', 'dismissReminderWithKey', 'autoCheckUpdates']; const clean = {}; for (const k of allowed) if (k in patch) clean[k] = patch[k]; setIslandPrefs(clean); if ('display' in clean) W.placeIsland(island, clean.display); },
  'island.setHotkey': value => { const previous = islandPrefs().toggleHotkey; setIslandPrefs({ toggleHotkey: value }); const r = registerShortcuts(); if (!r.toggle) { setIslandPrefs({ toggleHotkey: previous }); registerShortcuts(); throw new Error('这个快捷键未能注册，可能已被其他应用占用，已保留原设置。'); } },
  'island.launchAtLogin': on => { if (process.platform === 'win32' && app.isPackaged) app.setLoginItemSettings({ openAtLogin: !!on }); setIslandPrefs({ launchAtLogin: !!on }); },
  'island.focus': () => { if (island && !island.isDestroyed()) island.focus(); },
  'island.blur': () => { if (island && !island.isDestroyed()) island.blur(); },
  'open.settings': section => openSettings(section),
  'open.onboarding': () => { prefs.set('onboarding', 'pending'); if (island && !island.isDestroyed()) island.hide(); globalShortcut.unregisterAll(); openOnboarding(); broadcast(); },
  'onboarding.complete': () => completeOnboarding(),
  'onboarding.later': () => { if (onboarding && !onboarding.isDestroyed()) onboarding.close(); },
  'open.url': url => { const safe = hub.safeURL(url); if (!safe) throw new Error('地址无效。'); return shell.openExternal(safe); },
  // feishu
  'feishu.connect': () => feishu.openConnection(),
  'feishu.setEnabled': on => feishu.store.setEnabled(!!on),
  'feishu.toggleMute': () => feishu.store.toggleMute(),
  'feishu.updateRules': (rules, custom) => { if (!feishu.store.updateSettings(rules, custom)) throw new Error(feishu.store.actionError || '规则未保存。'); },
  'feishu.setConversation': (target, mode) => { if (!feishu.store.setConversation(target, mode || null)) throw new Error(feishu.store.actionError || '规则未保存。'); },
  'feishu.directory': q => feishu.directory(q || ''),
  'feishu.updateDanmu': v => feishu.store.updateDanmu(v),
  'feishu.updateAppearance': v => { if (!feishu.store.updateAppearance(v)) throw new Error('外观设置无效：文字与背景需要足够的对比度。'); },
  'feishu.updateRetention': v => feishu.store.updateRetention(v),
  'feishu.openReader': id => feishu.store.openReader(id),
  'feishu.closeReader': () => feishu.store.closeReader(),
  'feishu.finishReading': () => feishu.store.finishReading(),
  'feishu.rememberPage': (id, page) => feishu.store.rememberPage(id, page),
  'feishu.remindLater': id => feishu.store.remindLater(id),
  'feishu.markViewed': id => feishu.store.markViewed(id),
  'feishu.open': id => { const m = feishu.store.messages.find(x => x.id === id); const url = m && M.chatURL(m); if (!url) throw new Error('缺少有效会话地址'); feishu.store.markViewed(id); return shell.openExternal(url); },
  'feishu.reconnect': () => feishu.reconnect(),
  'feishu.switchAccount': async () => { const r = await dialog.showMessageBox({ type: 'question', buttons: ['更换账号', '取消'], defaultId: 1, cancelId: 1, title: '一切在岛', message: '更换连接的飞书账号？', detail: '当前接收和日历同步会暂停。已有待办、完成记录会保留。' }); if (r.response === 0) { todos.setSchedule({ enabled: false, account: null }); feishu.switchAccount(); } },
  'feishu.preview': () => feishu.store.playSynthetic('这是一条透明试播的弹幕，不会打开真实会话。'),
  'danmu.finished': id => feishu.store.danmuFinished(id),
  'danmu.open': id => handlers['feishu.open'](id),
  'danmu.checkUnread': id => feishu.checkUnread(id),
  'danmu.preview': () => showDanmu({ id: 'preview-' + Date.now(), text: '弹幕示例：这是一条预览，点击文字可以停留，移开继续前进。', created: new Date().toISOString(), canOpen: false, demo: true }),
  // company window
  'company.begin': () => company.beginAuthorization(),
  'company.check': () => company.checkProgress(),
  'company.cancel': () => company.cancelAuthorization(),
  'company.reopen': () => company.reopenAuthorization(),
  'company.continue': () => company.continueConnection(),
  'company.refresh': () => company.refreshStatus(),
  'company.reload': () => company.reloadLogin(),
  'company.close': () => company.close(),
  'company.snapshot': () => company.snapshot(),
  // todos
  'todos.add': (title, details) => todos.add(title, details),
  'todos.update': (id, patch) => todos.update(id, patch),
  'todos.complete': id => todos.complete(id),
  'todos.reopen': id => todos.reopen(id),
  'todos.remove': id => todos.remove(id),
  'todos.restore': id => todos.restore(id),
  'todos.purgeTrash': id => todos.purgeTrash(id),
  'todos.move': (id, offset) => todos.move(id, offset),
  'todos.moveBefore': (id, target) => todos.moveBefore(id, target),
  'todos.archiveCompleted': () => todos.archiveCompleted(),
  'todos.setCollapsed': (id, c) => todos.setCollapsed(id, c),
  'todos.deleteHistory': id => todos.deleteHistory(id),
  'todos.snooze': (id, minutes) => todos.snooze(id, minutes),
  'todos.setDefaultScreen': style => todos.setDefaultScreen(style),
  'todos.setEncouragement': on => todos.setEncouragement(on),
  'todos.copyWeek': () => { clipboard.writeText(todos.historyText(todos.weekHistory())); return todos.weekHistory().length; },
  'todos.previewReminder': style => presentReminder({ style: style || { materialID: 'cat', durationSeconds: 15 }, title: '这是提醒效果预览' }),
  'schedule.connect': () => { if (DEMO) throw new Error('演示模式不会连接真实日历。'); if (todos.disk.feishuSchedule.enabled && company.isEnabled('calendar')) return syncSchedule(); company.open('calendar'); },
  'schedule.disable': () => todos.setSchedule({ enabled: false }),
  'schedule.sync': () => syncSchedule(),
  'schedule.remove': id => todos.removeScheduleEvent(id),
  'schedule.offsets': (id, offsets) => todos.setEventOffsets(id, offsets),
  'schedule.open': id => { const e = (todos.disk.feishuSchedule.events || []).find(x => x.id === id); if (e && e.appLink) return shell.openExternal(e.appLink); },
  // rest
  'rest.enable': on => todos.setRestEnabled(!!on),
  'rest.interval': m => todos.setRestInterval(Number(m)),
  'rest.pause': v => todos.setRestPaused(!!v),
  'rest.material': id => todos.changeRest(p => { p.materialID = id; }),
  'rest.sound': on => todos.changeRest(p => { p.sound = !!on; }),
  'rest.pauseWhenAway': on => todos.changeRest(p => { p.pauseWhenAway = !!on; }),
  'rest.done': () => { todos.restartRest(); if (reminder && !reminder.isDestroyed()) reminder.close(); },
  'rest.later': () => { todos.postponeRest(); if (reminder && !reminder.isDestroyed()) reminder.close(); },
  'reminder.dismiss': () => { if (reminder && !reminder.isDestroyed()) reminder.close(); },
  'reminder.capture': on => { if (reminder && !reminder.isDestroyed()) reminder.setIgnoreMouseEvents(!on, { forward: true }); },
  // agents
  'agents.discover': () => DEMO ? ['codex', 'claude'] : agents.discover(),
  'agents.connect': id => { const r = agents.connect(id); if (r.error) throw new Error(r.error); return r; },
  'agents.setMode': (id, mode, replace) => { const r = agents.setMode(id, mode, replace); if (r.error) throw new Error(r.error); return r; },
  'agents.primary': id => agents.selectPrimary(id),
  'agents.update': patch => agents.update(patch),
  'agents.addCustom': (name, url) => { const e = agents.addCustom(name, url); if (e) throw new Error(e); },
  'agents.removeCustom': id => agents.removeCustom(id),
  'agents.installClaude': () => DEMO ? null : agents.installClaudeHook(path.join(ASSETS, 'agent-hook.ps1')),
  'agents.uninstallClaude': () => agents.uninstallClaudeHook(),
  'agents.refresh': () => { if (DEMO) return; agents.lastQuota = 0; agents.refreshQuotas(); return agents.poll(); },
  'agents.open': id => { const p = agents.profiles().find(x => x.id === id); if (p && p.launchURL) return shell.openExternal(p.launchURL); throw new Error('这个工具没有设置入口地址。'); },
  'agents.acknowledge': () => agents.acknowledge(),
  'agents.finishNotice': id => agents.finishNotice(id),
  // hub & wheel
  'hub.connect': () => connectHub(),
  'hub.disconnect': () => { hubClient.disconnect(); prefs.set('hub.selected', []); hubState = { connected: false, name: '', cards: [], applications: [], applicationsError: null, readAt: null, error: '', busy: false }; broadcast(); },
  'hub.refresh': () => refreshHub(),
  'hub.toggleCard': id => { const s = prefs.get('hub.selected', []); prefs.set('hub.selected', s.includes(id) ? s.filter(x => x !== id) : [...s, id]); broadcast(); },
  'hub.moveCard': (id, dir) => { const s = prefs.get('hub.selected', []); const i = s.indexOf(id), j = i + dir; if (i >= 0 && j >= 0 && j < s.length) { [s[i], s[j]] = [s[j], s[i]]; prefs.set('hub.selected', s); broadcast(); } },
  'wheel.setSlot': (i, slot) => { const w = wheelPrefs(); if (!(i >= 0 && i < 8) || !hub.validSlot(slot)) throw new Error('名称最多40字；自定义入口请填写不含凭据的 HTTPS 地址。'); w.slots[i] = slot; prefs.set('wheel', w); broadcast(); },
  'wheel.swap': (a, b) => { const w = wheelPrefs(); if (!(a >= 0 && a < 8 && b >= 0 && b < 8)) return; for (const i of [a, b]) if (w.slots[i].source === 'automatic') w.slots[i] = { ...w.slots[i], source: 'builtin', cardID: hub.BUILTINS[i].id }; [w.slots[a], w.slots[b]] = [w.slots[b], w.slots[a]]; prefs.set('wheel', w); broadcast(); },
  'wheel.set': patch => { const w = wheelPrefs(); for (const k of ['showInMainBar', 'soundEnabled']) if (k in patch) w[k] = !!patch[k]; prefs.set('wheel', w); broadcast(); },
  'wheel.setHotkey': value => { const w = wheelPrefs(); const previous = w.hotkey; w.hotkey = value; prefs.set('wheel', w); const r = registerShortcuts(); if (!r.wheel) { w.hotkey = previous; prefs.set('wheel', w); registerShortcuts(); throw new Error('这个快捷键未能注册，可能已被其他应用占用，已保留原设置。'); } broadcast(); },
  'wheel.open': index => { const d = hub.destinations(wheelPrefs(), hubState.cards, hubState.applications)[index]; if (wheel && !wheel.isDestroyed()) wheel.close(); if (!d) return; if (d.settings) openSettings('appearance'); else if (d.url) shell.openExternal(d.url); },
  'wheel.close': () => { if (wheel && !wheel.isDestroyed()) wheel.close(); },
  // updates
  'update.check': async () => { updateState = { ...updateState, checking: true, error: '' }; broadcast(); try { lastUpdate = await updater.check(app.getVersion()); updateState.error = lastUpdate ? '' : '已是最新版本。'; } catch (e) { updateState.error = e.message; } finally { updateState.checking = false; broadcast(); } },
  'update.download': async () => { if (!lastUpdate) return; updateState = { ...updateState, progress: 0, error: '' }; try { const r = await updater.download(lastUpdate, path.join(DATA, 'Updates'), { onProgress: p => { updateState.progress = p; broadcast(); } }); updateState.downloaded = r; } catch (e) { updateState.error = e.message; } broadcast(); },
  'update.install': async () => { if (!updateState.downloaded) return; const err = await shell.openPath(updateState.downloaded.file); if (err) throw new Error('无法启动安装包：' + err); setTimeout(() => app.quit(), 800); }
};
ipcMain.handle('island:invoke', async (event, method, args) => {
  const fn = handlers[method];
  if (!fn) return fail(new Error('unknown method ' + method));
  try { return ok(await fn(...(Array.isArray(args) ? args : []))); } catch (e) { return fail(e); }
});
ipcMain.on('island:ignore-mouse', (event, ignore) => {
  const win = BrowserWindow.fromWebContents(event.sender);
  if (win && !win.isDestroyed()) win.setIgnoreMouseEvents(!!ignore, { forward: true });
});

// ---- smoke screenshot (development verification only) ----
const call_ = (m, ...a) => handlers[m](...a);
async function smoke() {
  const out = SMOKE.slice('--smoke-shot='.length);
  fs.mkdirSync(out, { recursive: true });
  const shots = [];
  const capture = async (win, name) => { await new Promise(r => setTimeout(r, 900)); const img = await win.webContents.capturePage(); fs.writeFileSync(path.join(out, name + '.png'), img.toPNG()); shots.push(name); };
  try {
    send(island, 'reveal', { module: 'feishu', seconds: 60 }); await capture(island, 'island-feishu'); call_('feishu.closeReader'); await capture(island, 'island-feishu-list');
    for (const m of ['agents', 'todos', 'platform']) { send(island, 'reveal', { module: m, seconds: 60 }); await capture(island, 'island-' + m); }
    send(island, 'collapse'); await capture(island, 'island-collapsed');
    openSettings('messages'); await new Promise(r => settings.webContents.once('did-finish-load', r));
    for (const s of ['messages', 'agents', 'todos', 'platform', 'rest', 'appearance']) { send(settings, 'section', s); await capture(settings, 'settings-' + s); }
    openOnboarding(); await new Promise(r => onboarding.webContents.once('did-finish-load', r));
    for (let i = 0; i < 7; i++) { send(onboarding, 'step', i); await capture(onboarding, 'onboarding-' + (i + 1)); }
    feishu.store.updateDanmu({ enabled: true, paused: false });
    showDanmu({ id: 'smoke', text: '项目群 · 小林：Windows 版弹幕试播', created: new Date().toISOString(), canOpen: false });
    await new Promise(r => setTimeout(r, 1500)); if (danmu) await capture(danmu, 'danmu');
    openWheel(); await new Promise(r => setTimeout(r, 400)); if (wheel) await capture(wheel, 'wheel');
    if (wheel) wheel.close();
    presentReminder({ style: { materialID: 'cat', durationSeconds: 6 }, title: '提醒预览 · 写周报' }); await new Promise(r => setTimeout(r, 2200)); if (reminder) await capture(reminder, 'reminder');
  } catch (error) { fs.writeFileSync(path.join(out, 'error.txt'), String(error && error.stack || error)); }
  fs.writeFileSync(path.join(out, 'done.json'), JSON.stringify({ shots }));
  app.exit(0);
}

// ---- lifecycle ----
app.on('second-instance', () => { if (onboardingPending()) openOnboarding(); else openSettings(); });
app.on('window-all-closed', () => { /* stays in tray */ });
app.whenReady().then(() => {
  const trayIcon = nativeImage.createFromPath(path.join(ASSETS, 'tray.png'));
  tray = new Tray(trayIcon.isEmpty() ? nativeImage.createFromPath(W.ICON).resize({ width: 16, height: 16 }) : trayIcon);
  tray.on('click', () => onboardingPending() ? openOnboarding() : send(island, 'reveal', { module: islandPrefs().activeModule, seconds: 6 }));
  refreshTray();
  powerMonitor.on('lock-screen', () => { locked = true; feishu.store.suspend(true); todos.setAway(true); agents.handleLock(); if (reminder && !reminder.isDestroyed()) reminder.close(); broadcast(); });
  powerMonitor.on('unlock-screen', () => { locked = false; feishu.store.suspend(false); todos.setAway(false); broadcast(); });
  powerMonitor.on('suspend', () => { todos.setAway(true); });
  powerMonitor.on('resume', () => { if (!locked) todos.setAway(false); syncSchedule(); });
  screen.on('display-metrics-changed', () => W.placeIsland(island, islandPrefs().display));
  screen.on('display-added', () => W.placeIsland(island, islandPrefs().display));
  screen.on('display-removed', () => W.placeIsland(island, islandPrefs().display));
  if (onboardingPending() && !SMOKE) openOnboarding(); else ensureIsland();
  registerShortcuts();
  feishu.start();
  setInterval(() => { todos.tick(); if (!DEMO) agents.poll(); }, 5000);
  setInterval(() => { syncSchedule(); }, 60000);
  setInterval(() => { if (hubClient.connected()) refreshHub(); }, 15 * 60000);
  setTimeout(() => { syncSchedule(); refreshHub(); }, 3000);
  if (!DEMO && islandPrefs().autoCheckUpdates && app.isPackaged) setTimeout(() => handlers['update.check'](), 20000);
});
app.on('will-quit', () => { globalShortcut.unregisterAll(); feishu.shutdown(); prefs.flush(); });
