'use strict';
// Todos, completion history, trash, reminders and rest reminders — a port of the
// todo-related parts of Workspace/WorkspaceStore + Todos/UnifiedTodoModel.swift.
// Times are epoch seconds. Data lives in one JSON file under the app data dir.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { EventEmitter } = require('node:events');
const { applyEvents, reminderDates } = require('./schedule.cjs');

const uuid = () => crypto.randomUUID();
const BUILTIN_MATERIALS = [
  { id: 'cat', name: '猫咪走动', durationSeconds: 11, hasAlpha: true, file: 'cat-walk.webm' },
  { id: 'rick', name: '瑞克传送门', durationSeconds: 10, hasAlpha: true, file: 'rick-portal.webm' },
  { id: 'what-a-day', name: 'KUN · What a Day', durationSeconds: 60, hasAlpha: false, file: 'what-a-day.mp4' },
  { id: 'gemini-greeting', name: '杰哥提醒', durationSeconds: 10, hasAlpha: true, file: 'gemini-greeting.webm' }
];

class TodoError extends Error {}

function emptyDisk() {
  return { schema: 1, items: [], trash: [], todoHistory: [], deletedTodoHistoryTasks: [], todoOrder: [], defaultTodoScreen: null, todoCompletionEncouragement: false,
    restReminder: null, screenSchedules: [], removedScreenMaterialIDs: [], feishuSchedule: { enabled: false, events: [], removed: [], account: null, calendarID: null, lastSync: 0, error: '' } };
}

function defaultRest() { return { enabled: false, intervalMinutes: 60, pauseWhenAway: true, sound: false, materialID: 'cat', paused: false, systemPaused: false, remainingSeconds: 3600, fireAt: null }; }
const restValid = p => p.intervalMinutes >= 5 && p.intervalMinutes <= 240 && Number.isFinite(p.remainingSeconds) && p.remainingSeconds >= 0 && p.remainingSeconds <= 86400;
const restRemaining = (p, now) => Math.max(0, p.fireAt !== null && p.fireAt !== undefined ? p.fireAt - now : p.remainingSeconds);
function restRestart(p, now, seconds) { p.remainingSeconds = seconds ?? p.intervalMinutes * 60; p.fireAt = p.enabled && !p.paused && !p.systemPaused ? now + p.remainingSeconds : null; }
function restSetPaused(p, value, now) { p.remainingSeconds = restRemaining(p, now); p.paused = value; p.fireAt = p.enabled && !p.paused && !p.systemPaused ? now + p.remainingSeconds : null; }
function restSetAway(p, away, now) { const next = away && p.pauseWhenAway; if (next === p.systemPaused) return; p.remainingSeconds = restRemaining(p, now); p.systemPaused = next; p.fireAt = p.enabled && !p.paused && !p.systemPaused ? now + p.remainingSeconds : null; }

class TodoStore extends EventEmitter {
  constructor({ file, now, canRemind } = {}) {
    super();
    this.file = file || null; this.now = now || (() => Date.now() / 1000);
    this.canRemind = canRemind || (() => true);
    this.disk = emptyDisk(); this.loadFailed = false; this.error = '';
    if (this.file && fs.existsSync(this.file)) {
      try {
        const parsed = JSON.parse(fs.readFileSync(this.file, 'utf8'));
        if (!parsed || parsed.schema !== 1 || !Array.isArray(parsed.items)) throw new Error('schema');
        this.disk = { ...emptyDisk(), ...parsed, feishuSchedule: { ...emptyDisk().feishuSchedule, ...(parsed.feishuSchedule || {}) } };
      } catch { this.loadFailed = true; this.error = '原待办数据读取失败，请恢复数据后重启；原文件已保留。'; }
    }
    this.away = false;
  }
  mutate(change) {
    if (this.loadFailed) { this.error = '原待办数据未成功读取，暂不能覆盖。'; this.emit('change'); return false; }
    const next = JSON.parse(JSON.stringify(this.disk));
    change(next);
    try {
      if (this.file) {
        fs.mkdirSync(path.dirname(this.file), { recursive: true });
        const temp = this.file + '.tmp';
        fs.writeFileSync(temp, JSON.stringify(next), { mode: 0o600 });
        fs.renameSync(temp, this.file);
      }
    } catch { this.error = '待办暂时未能保存到这台电脑，请检查可用空间。'; this.emit('change'); return false; }
    this.disk = next; this.error = ''; this.emit('change');
    return true;
  }
  get materials() { const removed = new Set(this.disk.removedScreenMaterialIDs || []); return BUILTIN_MATERIALS.filter(m => !removed.has(m.id)); }
  validateStyle(style) {
    if (!style) return;
    if (!Number.isInteger(style.durationSeconds) || style.durationSeconds < 2 || style.durationSeconds > 120 || !this.materials.some(m => m.id === style.materialID)) throw new TodoError('请选择可用的提醒素材，时长为2到120秒。');
  }

  // ---- lists ----
  get pending() {
    const ranks = new Map(); (this.disk.todoOrder || []).forEach((id, i) => { if (!ranks.has(id)) ranks.set(id, i); });
    return this.disk.items.map((item, offset) => ({ item, offset })).filter(({ item }) => !item.archivedAt && item.state !== 'done').sort((a, b) => {
      const l = ranks.has(a.item.id) ? ranks.get(a.item.id) : -1, r = ranks.has(b.item.id) ? ranks.get(b.item.id) : -1;
      if (l !== r) return l - r;
      return a.item.created === b.item.created ? b.offset - a.offset : b.item.created - a.item.created;
    }).map(x => x.item);
  }
  get completed() { return this.disk.items.filter(i => !i.archivedAt && i.state === 'done').sort((a, b) => (b.completedAt || 0) - (a.completedAt || 0)); }
  get archived() { return this.disk.items.filter(i => i.archivedAt).sort((a, b) => (b.completedAt || b.archivedAt || 0) - (a.completedAt || a.archivedAt || 0)); }
  get history() { return (this.disk.todoHistory || []).slice().sort((a, b) => (b.completedAt || 0) - (a.completedAt || 0)); }

  // ---- edits ----
  add(title, details = '') {
    title = String(title || '').trim();
    if (!title || [...title].length > 160 || Buffer.byteLength(details) > 200000 || this.disk.items.filter(i => !i.archivedAt).length >= 500) throw new TodoError('请填写160字以内的待办名称；当前列表最多500项，已归档历史不限期保留。');
    const now = this.now(), due = now + 20 * 60;
    const item = { id: uuid(), title, input: details || title, service: 'todo', state: 'todo', created: now, deadline: null, due, reminded: false, todoReminder: { pendingDates: [due], repeatMinutes: null, repeatUntil: null }, screenReminder: this.disk.defaultTodoScreen || null, completionReminder: null, completedAt: null, archivedAt: null, completedCollapsed: null };
    if (!this.mutate(d => { d.items.push(item); d.todoOrder = [item.id, ...(d.todoOrder || []).filter(x => x !== item.id)]; })) throw new TodoError(this.error);
    return item.id;
  }
  update(id, { title, details, deadline, dates, repeatMinutes = null, repeatUntil = null, style, completionStyle, preserveSchedule = false }) {
    const item = this.disk.items.find(i => i.id === id);
    if (!item || item.archivedAt || item.state === 'done') throw new TodoError('只能为未完成待办设置提醒。');
    const now = this.now();
    if (!preserveSchedule) {
      const list = dates || [];
      const ok = list.length <= 48 && list.every(d => d > now && d - now <= 366 * 86400) && (repeatMinutes === null || (repeatMinutes >= 1 && repeatMinutes <= 10080 && list.length > 0))
        && (repeatUntil === null || (repeatUntil > now && repeatUntil - now <= 366 * 86400 && (!list.length || Math.min(...list) <= repeatUntil)));
      if (!ok) throw new TodoError('提醒时间须在未来一年内，最多48个时间；循环间隔为1到10080分钟。');
    }
    if (style) this.validateStyle(style);
    if (completionStyle) this.validateStyle(completionStyle);
    const cleaned = title === undefined ? undefined : String(title).trim();
    if (cleaned !== undefined && (!cleaned || [...cleaned].length > 160)) throw new TodoError('任务名称须为1到160字，说明最多200KB。');
    if (details !== undefined && Buffer.byteLength(details) > 200000) throw new TodoError('任务名称须为1到160字，说明最多200KB。');
    const sorted = [...new Set(dates || [])].sort((a, b) => a - b);
    return this.mutate(d => {
      const t = d.items.find(i => i.id === id); if (!t) return;
      if (deadline !== undefined) t.deadline = deadline;
      if (!preserveSchedule) { t.due = sorted[0] ?? null; t.reminded = false; t.todoReminder = sorted.length ? { pendingDates: sorted, repeatMinutes, repeatUntil } : null; }
      if (style !== undefined) t.screenReminder = style;
      if (completionStyle !== undefined) t.completionReminder = completionStyle;
      if (cleaned !== undefined) t.title = cleaned;
      if (details !== undefined) t.input = details || (cleaned ?? t.title);
    });
  }
  move(id, offset) {
    const ids = this.pending.map(i => i.id); const from = ids.indexOf(id);
    if (from < 0 || from + offset < 0 || from + offset >= ids.length) return false;
    [ids[from], ids[from + offset]] = [ids[from + offset], ids[from]];
    return this.mutate(d => { d.todoOrder = ids; });
  }
  moveBefore(id, target) {
    const ids = this.pending.map(i => i.id); const from = ids.indexOf(id);
    if (id === target || from < 0 || !ids.includes(target)) return false;
    ids.splice(from, 1); ids.splice(ids.indexOf(target), 0, id);
    return this.mutate(d => { d.todoOrder = ids; });
  }
  complete(id) {
    const item = this.disk.items.find(i => i.id === id);
    if (!item || item.state === 'done' || item.archivedAt) return false;
    const now = this.now();
    const saved = this.mutate(d => {
      const t = d.items.find(i => i.id === id);
      t.state = 'done'; t.completedAt = now; t.completedCollapsed = false; t.due = null; t.reminded = true; t.todoReminder = null;
      d.todoHistory = [...(d.todoHistory || []), { id: uuid(), taskID: id, title: item.title, content: item.input, completedAt: now, deadline: item.deadline, project: null, source: 'human' }];
    });
    if (saved && this.canRemind()) {
      if (item.completionReminder) this.emit('screen', { style: item.completionReminder, title: '完成了 · ' + item.title });
      else if (this.disk.todoCompletionEncouragement) this.emit('encourage', item.title);
    }
    return saved;
  }
  reopen(id) {
    const item = this.disk.items.find(i => i.id === id);
    if (!item || item.state !== 'done') return false;
    return this.mutate(d => { const t = d.items.find(i => i.id === id); Object.assign(t, { state: 'todo', completedAt: null, completedCollapsed: false, archivedAt: null, due: null, reminded: false, todoReminder: null }); });
  }
  remove(id) {
    const item = this.disk.items.find(i => i.id === id); if (!item) return false;
    return this.mutate(d => { d.items = d.items.filter(i => i.id !== id); d.trash = [item, ...(d.trash || []).filter(i => i.id !== id)].slice(0, 200); });
  }
  restore(id) {
    const item = (this.disk.trash || []).find(i => i.id === id);
    if (!item || this.disk.items.some(i => i.id === id) || this.disk.items.filter(i => !i.archivedAt).length >= 500) { this.error = '待办已恢复或列表已满。'; this.emit('change'); return false; }
    return this.mutate(d => { d.trash = d.trash.filter(i => i.id !== id); d.items.unshift(item); });
  }
  purgeTrash(id) { return this.mutate(d => { d.trash = (d.trash || []).filter(i => i.id !== id); }); }
  archiveCompleted() {
    const now = this.now(); const ids = new Set(this.completed.map(i => i.id));
    if (!ids.size) return false;
    return this.mutate(d => { for (const t of d.items) if (ids.has(t.id)) { t.archivedAt = now; t.due = null; } });
  }
  setCollapsed(id, collapsed) { return this.mutate(d => { const t = d.items.find(i => i.id === id && i.state === 'done' && !i.archivedAt); if (t) t.completedCollapsed = collapsed; }); }
  deleteHistory(id) {
    const event = (this.disk.todoHistory || []).find(e => e.id === id); if (!event) return true;
    return this.mutate(d => {
      d.todoHistory = d.todoHistory.filter(e => e.id !== id);
      d.deletedTodoHistoryTasks = [...new Set([...(d.deletedTodoHistoryTasks || []), event.taskID])];
      if (!d.todoHistory.some(e => e.taskID === event.taskID)) d.items = d.items.filter(i => !(i.id === event.taskID && i.archivedAt && i.state === 'done'));
    });
  }
  snooze(id, minutes) {
    const now = this.now();
    return this.mutate(d => { const t = d.items.find(i => i.id === id); if (t && t.state !== 'done') { t.due = now + minutes * 60; t.reminded = false; t.todoReminder = { pendingDates: [t.due], repeatMinutes: null, repeatUntil: null }; } });
  }
  setDefaultScreen(style) { if (style) this.validateStyle(style); return this.mutate(d => { d.defaultTodoScreen = style; }); }
  setEncouragement(on) { return this.mutate(d => { d.todoCompletionEncouragement = !!on; }); }
  historyText(events) {
    const fmt = t => { const d = new Date(t * 1000); const p = n => String(n).padStart(2, '0'); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`; };
    if (!events.length) return '这段时间没有完成记录。';
    return events.map(e => { const lines = [e.title, '已完成 · ' + (e.completedAt ? fmt(e.completedAt) : '完成时间未记录')]; if (e.content && e.content !== e.title) lines.push(e.content); return lines.join('\n'); }).join('\n\n');
  }
  /** ISO week (Monday–Sunday) containing now, local time. */
  weekRange(now = this.now()) {
    const d = new Date(now * 1000); const day = (d.getDay() + 6) % 7;
    const start = new Date(d.getFullYear(), d.getMonth(), d.getDate() - day);
    return [start.getTime() / 1000, start.getTime() / 1000 + 7 * 86400];
  }
  weekHistory() { const [a, b] = this.weekRange(); return this.history.filter(e => e.completedAt && e.completedAt >= a && e.completedAt < b); }

  // ---- rest reminder ----
  get rest() { return { ...defaultRest(), ...(this.disk.restReminder || {}) }; }
  changeRest(change) {
    const plan = this.rest; change(plan);
    if (!restValid(plan) || (this.materials.length && !this.materials.some(m => m.id === plan.materialID))) { this.error = '提醒间隔应为5到240分钟，并选择可用素材。'; this.emit('change'); return false; }
    return this.mutate(d => { d.restReminder = plan; });
  }
  setRestEnabled(on) { const now = this.now(); return this.changeRest(p => { p.enabled = on; p.paused = false; p.systemPaused = false; restRestart(p, now); }); }
  setRestInterval(minutes) { const now = this.now(); return this.changeRest(p => { p.intervalMinutes = minutes; restRestart(p, now); }); }
  setRestPaused(value) { const now = this.now(); return this.changeRest(p => restSetPaused(p, value, now)); }
  postponeRest() { const now = this.now(); return this.changeRest(p => restRestart(p, now, 600)); }
  restartRest() { const now = this.now(); return this.changeRest(p => restRestart(p, now)); }

  // ---- reminder clock (WorkspaceStore.tickReminders) ----
  setAway(away) { this.away = away; }
  tick() {
    if (!this.canRemind()) return;
    const now = this.now();
    const plan = this.rest;
    if (plan.enabled) {
      const before = JSON.stringify(plan); restSetAway(plan, this.away, now);
      if (JSON.stringify(plan) !== before) this.mutate(d => { d.restReminder = plan; });
      if (!this.away && !plan.paused && !plan.systemPaused && plan.fireAt && plan.fireAt <= now) {
        restRestart(plan, now);
        if (this.mutate(d => { d.restReminder = plan; })) this.emit('screen', { style: { materialID: plan.materialID, durationSeconds: 15 }, title: '站起来，活动一下', rest: true, sound: plan.sound });
      }
    }
    if (this.away) return;
    const due = this.disk.items.filter(i => !i.archivedAt && i.state !== 'done' && !i.reminded && i.due && i.due <= now);
    const fs_ = this.disk.feishuSchedule;
    const events = fs_.enabled ? (fs_.events || []).filter(e => e.status === 'confirmed' && e.end > now && !(fs_.removed || []).includes(e.id) && reminderDates(e).some(d => d <= now && !e.consumed.includes(d))) : [];
    if (!due.length && !events.length) return;
    const ids = new Set(due.map(i => i.id)), eventIDs = new Set(events.map(e => e.id));
    if (!this.mutate(d => {
      for (const t of d.items) {
        if (!ids.has(t.id)) continue;
        t.reminded = true;
        if (t.todoReminder) {
          const p = t.todoReminder; p.pendingDates = p.pendingDates.filter(x => x > now);
          let next = p.pendingDates.length ? Math.min(...p.pendingDates) : null;
          if (p.repeatMinutes >= 1 && p.repeatMinutes <= 10080) {
            const repeated = now + p.repeatMinutes * 60;
            if (p.repeatUntil === null || p.repeatUntil === undefined || repeated <= p.repeatUntil) next = next === null ? repeated : Math.min(next, repeated);
          }
          if (next !== null) { t.due = next; t.reminded = false; }
        }
      }
      for (const e of d.feishuSchedule.events) if (eventIDs.has(e.id)) e.consumed = [...new Set([...e.consumed, ...reminderDates(e).filter(x => x <= now)])].sort((a, b) => a - b);
    })) return;
    const titles = [...due.map(i => i.title), ...events.map(e => '日程 · ' + e.title)];
    const light = [...due.filter(i => !i.screenReminder).map(i => i.title), ...events.filter(() => !this.disk.defaultTodoScreen).map(e => '日程 · ' + e.title)];
    if (light.length) this.emit('notify', { title: light.length > 1 ? `${light[0]} · 还有${light.length - 1}项提醒` : light[0], todoID: due[0] && due[0].id });
    const screens = [...due.filter(i => i.screenReminder).map(i => [i.title, i.screenReminder]), ...(this.disk.defaultTodoScreen ? events.map(e => ['日程 · ' + e.title, this.disk.defaultTodoScreen]) : [])];
    if (screens.length) this.emit('screen', { style: screens[0][1], title: screens.length > 1 ? `${screens[0][0]} · 还有${screens.length - 1}项提醒` : screens[0][0] });
    return titles;
  }

  // ---- Feishu schedule (read-only calendar events) ----
  setSchedule(patch) { return this.mutate(d => { Object.assign(d.feishuSchedule, patch); }); }
  replaceScheduleEvents(account, calendarID, events) {
    const now = this.now();
    return this.mutate(d => {
      d.feishuSchedule.account = account; d.feishuSchedule.calendarID = calendarID; d.feishuSchedule.lastSync = now; d.feishuSchedule.error = '';
      d.feishuSchedule.events = applyEvents(d.feishuSchedule.events || [], events, now);
    });
  }
  setEventOffsets(id, offsets) {
    const now = this.now();
    const clean = [...new Set(offsets.filter(o => Number.isInteger(o) && o >= 0 && o <= 43200))].sort((a, b) => b - a).slice(0, 12);
    return this.mutate(d => { const e = d.feishuSchedule.events.find(x => x.id === id); if (!e) return; e.offsets = clean; e.consumed = [...new Set([...e.consumed, ...reminderDates(e).filter(x => x <= now)])].sort((a, b) => a - b); });
  }
  removeScheduleEvent(id) { return this.mutate(d => { d.feishuSchedule.removed = [...new Set([...(d.feishuSchedule.removed || []), id])]; }); }

  snapshot() {
    const view = i => ({ id: i.id, title: i.title, details: i.input !== i.title ? i.input : '', created: i.created, deadline: i.deadline, due: i.due, completedAt: i.completedAt, reminder: i.todoReminder, screenReminder: i.screenReminder, completionReminder: i.completionReminder, collapsed: i.completedCollapsed === true, archivedAt: i.archivedAt });
    const s = this.disk.feishuSchedule;
    return {
      error: this.error, loadFailed: this.loadFailed,
      pending: this.pending.map(view), completed: this.completed.map(view), archived: this.archived.slice(0, 200).map(view),
      trash: (this.disk.trash || []).slice(0, 50).map(view), history: this.history.slice(0, 300), weekCount: this.weekHistory().length,
      defaultScreen: this.disk.defaultTodoScreen, encouragement: !!this.disk.todoCompletionEncouragement,
      rest: { ...this.rest, remaining: restRemaining(this.rest, this.now()) }, materials: this.materials,
      schedule: { enabled: s.enabled, account: s.account, lastSync: s.lastSync, error: s.error, events: (s.events || []).filter(e => !s.removed.includes(e.id)).slice(0, 100) }
    };
  }
}

module.exports = { TodoStore, TodoError, BUILTIN_MATERIALS, defaultRest };
