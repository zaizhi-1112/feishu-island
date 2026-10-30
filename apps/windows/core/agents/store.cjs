'use strict';
// Windows AgentStore: preferences, polling, alert tracking and notices.
// Port of Agents/AgentStore.swift + AgentModel.swift (AgentAlertTracker, AgentCompletionBatch).
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { EventEmitter } = require('node:events');
const codex = require('./codex.cjs');
const hooks = require('./hooks.cjs');
const claudeDesktop = require('./claude-desktop-usage.cjs');

const PROFILES = [
  { id: 'codex', name: 'Codex', kind: 'codex', windows: true },
  { id: 'claude', name: 'Claude Code', kind: 'claude', windows: true },
  { id: 'workbuddy', name: 'WorkBuddy', kind: 'workbuddy', windows: false },
  { id: 'deepseek', name: 'DeepSeek Harness', kind: 'deepseek', windows: false }
];
const STATE_LABEL = { working: '正在工作', completed: '本轮已完成', waiting: '等待操作', failed: '任务中断', unknown: '等待状态数据' };

function defaultPreferences() {
  return { revision: 0, enabled: false, quotaDisplayEnabled: false, startAlerts: true, attentionAlerts: true, completionAlerts: true, quotaAlerts: true, monitoredIDs: [], visibleIDs: [], primaryID: 'codex', skinID: 'auto', effectsEnabled: true, completionScreenMaterialID: null, custom: [] };
}

function snapshotState(snapshot, now) {
  const recent = snapshot.sessions.filter(s => s.updatedAt <= now + 60 && now - s.updatedAt < 900);
  if (recent.some(s => s.state === 'working')) return 'working';
  if (recent.some(s => s.state === 'waiting')) return 'waiting';
  if (snapshot.sessions.some(s => (s.state === 'working' || s.state === 'waiting') && now - s.updatedAt >= 900)) return 'unknown';
  const latest = recent.slice().sort((a, b) => b.updatedAt - a.updatedAt)[0];
  return latest ? latest.state : 'unknown';
}

const quotaFresh = (q, now) => Number.isFinite(q.remainingPercent) && q.remainingPercent >= 0 && q.remainingPercent <= 100 && q.updatedAt <= now + 60 && now - q.updatedAt < 900 && (q.resetsAt == null || q.resetsAt > now);

class AlertTracker {
  constructor() { this.prevRunning = new Set(); this.runningInit = false; this.prevAttention = new Map(); this.attentionInit = false; this.prevSessions = new Map(); this.seen = new Map(); this.init = false; this.prevCheck = 0; this.startedAt = 0; this.quotaCycles = new Set(); }
  starts(sessions, now) {
    const key = s => s.id + '/' + (s.startID || 'running');
    const running = sessions.filter(s => s.state === 'working' && now - s.updatedAt < 900 && s.updatedAt <= now + 60);
    const fresh = this.runningInit ? running.filter(s => !this.prevRunning.has(key(s)) && now - s.updatedAt < 60).length : 0;
    this.prevRunning = new Set(running.map(key)); this.runningInit = true;
    return fresh;
  }
  completions(sessions, now) {
    for (const [k, t] of [...this.seen]) if (now - t >= 900) this.seen.delete(k);
    const key = s => s.id + '/' + (s.completionID || String(s.updatedAt));
    let count = 0;
    if (!this.init) { this.startedAt = now; for (const s of sessions) if (s.state === 'completed') this.seen.set(key(s), now); }
    else {
      for (const s of sessions) {
        if (this.seen.has(key(s))) continue;
        if (s.state === 'completed') this.seen.set(key(s), now);
        if (s.state !== 'completed' || now - s.updatedAt >= 60 || s.updatedAt > now + 60) continue;
        const old = this.prevSessions.get(s.id);
        if (!old) { if (s.updatedAt > this.startedAt) count++; continue; }
        if (s.updatedAt <= old.updatedAt) continue;
        if (old.state === 'working' || old.state === 'waiting' || (s.completionID && s.completionID !== old.completionID && s.updatedAt > this.prevCheck)) count++;
      }
    }
    this.prevSessions = new Map(sessions.map(s => [s.id, s])); this.init = true; this.prevCheck = now;
    return count;
  }
  attention(sessions, now) {
    const waiting = sessions.filter(s => s.state === 'waiting' && now - s.updatedAt < 900 && s.updatedAt <= now + 60);
    const fresh = waiting.filter(s => this.prevAttention.get(s.id) !== (s.attentionID || 'waiting') && (this.attentionInit || now - s.updatedAt < 60));
    this.prevAttention = new Map(waiting.map(s => [s.id, s.attentionID || 'waiting'])); this.attentionInit = true;
    return fresh;
  }
  lowQuotas(quotas, profile, now) {
    return quotas.filter(q => {
      if (!quotaFresh(q, now)) return false;
      const cycle = `${profile}/${q.id}/${q.resetsAt != null ? Math.trunc(q.resetsAt) : 'no-reset'}`;
      if (q.remainingPercent >= 20) { if (q.resetsAt == null) this.quotaCycles.delete(cycle); return false; }
      if (this.quotaCycles.has(cycle)) return false;
      this.quotaCycles.add(cycle); return true;
    });
  }
}

class CompletionBatch {
  constructor() { this.pending = 0; this.first = null; }
  ingest(count, now) {
    if (count > 0) { if (this.pending === 0) this.first = now; this.pending += count; }
    if (this.pending <= 0 || now - (this.first ?? now) < 2) return 0;
    const r = this.pending; this.pending = 0; this.first = null; return r;
  }
}

function noticeText(n) {
  if (n.quotaMessage) return n.quotaMessage;
  const status = n.attention === 'quota' ? '额度不足' : n.attention ? (n.attention === 'running' ? '正在运行' : n.attention === 'input' ? '等你输入' : '等你确认') : n.stillWorking ? '正在运行' : '本轮工作已结束';
  return n.name + ' · ' + status;
}

class AgentStore extends EventEmitter {
  constructor({ prefs, statusRoot, home = os.homedir(), env = process.env, now, codexReader, locked, readQuotas } = {}) {
    super();
    this.prefs = prefs; this.statusRoot = statusRoot; this.home = home; this.env = env;
    this.now = now || (() => Date.now() / 1000);
    this.locked = locked || (() => false);
    this.codexReader = codexReader || new codex.CodexReader(path.join(home, '.codex', 'sessions'));
    this.readQuotas = readQuotas || (() => codex.readQuotas({ executable: codex.codexExecutable(env) }));
    this.preferences = { ...defaultPreferences(), ...(prefs.get('agents.preferences') || {}) };
    this.snapshots = {}; this.trackers = {}; this.batches = {}; this.quotaTracker = new AlertTracker();
    for (const c of prefs.get('agents.notifiedQuotaCycles', [])) this.quotaTracker.quotaCycles.add(c);
    this.notice = null; this.pending = []; this.noticeTimer = null; this.lastQuota = 0; this.polling = false; this.unviewed = new Set();
  }
  profiles() { return [...PROFILES, ...(this.preferences.custom || []).map(c => ({ id: c.id, name: c.name, kind: 'custom', windows: true, launchURL: c.launchURL }))]; }
  isMonitoring(id) { return this.preferences.enabled && this.preferences.monitoredIDs.includes(id); }
  get primary() { return this.profiles().find(p => p.id === this.preferences.primaryID) || PROFILES[0]; }
  save() { this.preferences.revision++; this.prefs.set('agents.preferences', this.preferences); this.syncPolicy(); this.emit('change'); }
  syncPolicy() { try { hooks.savePolicy(this.statusRoot, this.preferences.enabled && this.isMonitoring('claude'), this.preferences.visibleIDs.filter(id => this.isMonitoring(id))); } catch {} }

  setMode(id, mode, replace) {
    const p = this.preferences; const profile = this.profiles().find(x => x.id === id);
    if (!profile) return { error: '未知工具。' };
    if (!profile.windows && mode !== 'off') return { error: `${profile.name} 的 Windows 版接入尚未支持。` };
    if (mode === 'show' && !p.visibleIDs.includes(id) && p.visibleIDs.length >= 3 && !replace) return { needsReplace: true };
    let ids = p.visibleIDs.filter(x => x !== id);
    if (replace) ids = ids.map(x => x === replace ? id : x); else if (mode === 'show') ids.push(id);
    let monitored = p.monitoredIDs.filter(x => x !== id);
    if (mode !== 'off') { monitored.push(id); p.enabled = true; }
    p.monitoredIDs = monitored; p.visibleIDs = ids.slice(0, 3);
    if (!p.visibleIDs.includes(p.primaryID) && p.visibleIDs.length) p.primaryID = p.visibleIDs[0];
    if (mode !== 'off') p.quotaDisplayEnabled = true;
    this.save(); return {};
  }
  connect(id) { return this.setMode(id, this.preferences.visibleIDs.length < 3 ? 'show' : 'alerts'); }
  selectPrimary(id) { if (this.profiles().some(p => p.id === id)) { this.preferences.primaryID = id; this.save(); } }
  update(patch) {
    const allowed = ['startAlerts', 'attentionAlerts', 'completionAlerts', 'quotaAlerts', 'quotaDisplayEnabled', 'skinID', 'effectsEnabled', 'completionScreenMaterialID', 'enabled'];
    for (const k of Object.keys(patch)) if (allowed.includes(k)) this.preferences[k] = patch[k];
    this.save();
  }
  addCustom(name, url) {
    name = String(name || '').trim(); url = String(url || '').trim();
    const custom = this.preferences.custom || [];
    if (custom.length >= 12) return '最多添加12个 Agent。';
    if (!name || name.length > 40 || /[\u0000-\u001f]/.test(name)) return '名称请填写1–40个字。';
    if (url) { try { const u = new URL(url); if (u.protocol !== 'https:' || !u.hostname || u.username || u.password || u.search || u.hash) throw 0; } catch { return '入口请填不含账号、参数或令牌的 HTTPS 地址；也可以留空。'; } }
    if (this.profiles().some(p => p.name.toLowerCase() === name.toLowerCase())) return '这个 Agent 已在列表中。';
    custom.push({ id: 'custom-' + require('node:crypto').randomUUID(), name, launchURL: url });
    this.preferences.custom = custom; this.save(); return null;
  }
  removeCustom(id) {
    const p = this.preferences; p.custom = (p.custom || []).filter(c => c.id !== id);
    p.visibleIDs = p.visibleIDs.filter(x => x !== id); p.monitoredIDs = p.monitoredIDs.filter(x => x !== id); this.save();
  }
  discover() {
    const found = [];
    if (codex.codexExecutable(this.env) || fs.existsSync(path.join(this.home, '.codex'))) found.push('codex');
    if (fs.existsSync(path.join(this.home, '.claude')) || (this.env.APPDATA && fs.existsSync(path.join(this.env.APPDATA, 'Claude')))) found.push('claude');
    return found;
  }
  claudeHookConfigured() { return hooks.isConfigured(this.home); }
  installClaudeHook(scriptSource) {
    const script = hooks.deployScript(scriptSource, this.statusRoot);
    hooks.install({ home: this.home, statusRoot: this.statusRoot, script });
    this.syncPolicy(); this.emit('change');
  }
  uninstallClaudeHook() { hooks.uninstall({ home: this.home, statusRoot: this.statusRoot }); this.emit('change'); }

  // ---- polling ----
  async poll() {
    if (this.locked()) { this.handleLock(); return; }
    const p = this.preferences;
    if (!(p.enabled || p.quotaDisplayEnabled) || this.polling) return;
    this.polling = true;
    try {
      const now = this.now();
      if (now - this.lastQuota >= 180) this.refreshQuotas();
      if (!p.enabled) return;
      const received = {};
      if (this.isMonitoring('claude')) received.claude = this.claudeSnapshot(now);
      if (this.isMonitoring('codex')) {
        const old = this.snapshots.codex || { sessions: [], quotas: [], source: 'Codex本机事件＋官方额度接口', detail: '仅监测这台电脑保存的Codex任务。' };
        let sessions = [];
        try { sessions = this.codexReader.sessions(now); } catch {}
        received.codex = { ...old, sessions };
      }
      this.ingest(received, now);
    } finally { this.polling = false; }
  }
  claudeSnapshot(now) {
    const snapshot = { sessions: hooks.readRecords(this.statusRoot, now), quotas: [], source: 'Claude Code本机状态与额度', detail: this.claudeHookConfigured() ? '等待 Claude Code 更新额度；新回复后自动同步。' : '尚未连接 Claude Code 状态提醒，请在设置中点击连接。' };
    const quotas = hooks.readQuota(this.statusRoot);
    if (quotas.length) { snapshot.quotas = quotas; snapshot.detail = quotas.some(q => quotaFresh(q, now)) ? '已同步 Claude Code 额度；新回复后自动更新。' : '上次 Claude Code 额度；等待客户端新回复后更新。'; }
    if (this.env.APPDATA) {
      try {
        const desktop = claudeDesktop.read(path.join(this.env.APPDATA, 'Claude'), now);
        for (const q of desktop) {
          const label = q.label; const i = snapshot.quotas.findIndex(x => x.label === label);
          if (i < 0) snapshot.quotas.push(q); else if (q.updatedAt >= snapshot.quotas[i].updatedAt) snapshot.quotas[i] = q;
        }
        if (desktop.length) { snapshot.source = 'Claude 桌面端额度'; snapshot.detail = '已读取客户端额度与重置时间；每分钟同步客户端已有记录。'; }
      } catch {}
    }
    return snapshot;
  }
  async refreshQuotas() {
    const p = this.preferences; const now = this.now();
    if (now - this.lastQuota < 5) return;
    this.lastQuota = now;
    const codexEnabled = (p.quotaDisplayEnabled && p.primaryID === 'codex') || this.isMonitoring('codex');
    if (!codexEnabled) return;
    const snapshot = this.snapshots.codex || { sessions: [], quotas: [], source: 'Codex本机事件＋官方额度接口', detail: '' };
    try { const quotas = await this.readQuotas(); snapshot.quotas = quotas; snapshot.detail = quotas.length ? '已读取官方额度；每3分钟自动刷新。' : '此账号未返回额度窗口。'; }
    catch (error) { snapshot.detail = error.message; }
    this.snapshots.codex = snapshot; this.checkQuotaAlerts(); this.emit('change');
  }
  ingest(values, now) {
    if (this.locked() || !this.preferences.enabled) return;
    for (const [id, v] of Object.entries(values)) if (this.isMonitoring(id)) this.snapshots[id] = v;
    for (const profile of this.profiles()) {
      if (!this.isMonitoring(profile.id) || !values[profile.id]) continue;
      const tracker = this.trackers[profile.id] || (this.trackers[profile.id] = new AlertTracker());
      const sessions = this.snapshots[profile.id].sessions || [];
      const started = tracker.starts(sessions, now), count = tracker.completions(sessions, now), attention = tracker.attention(sessions, now);
      if (started > 0 && this.preferences.startAlerts) this.present(profile, started, true, 'running');
      if (this.preferences.completionAlerts) {
        const batch = this.batches[profile.id] || (this.batches[profile.id] = new CompletionBatch());
        const settled = batch.ingest(count, now);
        if (settled > 0) this.present(profile, settled, false, null);
      }
      if (attention.length && this.preferences.attentionAlerts) this.present(profile, attention.length, false, attention[0].attentionReason || 'approval');
    }
    this.checkQuotaAlerts();
    this.emit('change');
  }
  checkQuotaAlerts() {
    const now = this.now();
    if (this.locked() || !this.preferences.enabled || !this.preferences.quotaAlerts) return;
    for (const profile of this.profiles().filter(p => this.isMonitoring(p.id) && p.kind !== 'claude')) {
      const low = this.quotaTracker.lowQuotas((this.snapshots[profile.id] || {}).quotas || [], profile.id, now);
      const q = low.sort((a, b) => a.remainingPercent - b.remainingPercent)[0];
      if (q) this.enqueue({ profileID: profile.id, name: profile.name, count: 0, stillWorking: false, attention: 'quota', quotaMessage: `${profile.name} · ${q.label}剩余${q.remainingPercent.toFixed(1)}%` });
    }
    this.prefs.set('agents.notifiedQuotaCycles', [...this.quotaTracker.quotaCycles].slice(-200));
  }
  present(profile, count, stillWorking, attention) {
    if (this.locked() || !this.isMonitoring(profile.id)) return;
    if (attention !== 'running') this.unviewed.add(profile.id);
    this.enqueue({ profileID: profile.id, name: profile.name, count, stillWorking, attention });
  }
  enqueue(n) {
    n.id = require('node:crypto').randomUUID(); n.message = noticeText(n); n.isQuota = n.attention === 'quota';
    if (this.preferences.completionScreenMaterialID && !this.locked()) { this.emit('screen', { style: { materialID: this.preferences.completionScreenMaterialID, durationSeconds: 15 }, title: n.message }); return; }
    if (this.notice && (this.notice.profileID !== n.profileID || this.notice.isQuota !== n.isQuota)) {
      const i = this.pending.findIndex(x => x.profileID === n.profileID && x.isQuota === n.isQuota);
      if (i >= 0) this.pending[i] = n; else this.pending.push(n);
    } else this.show(n);
  }
  allows(n) { const p = this.preferences; return this.isMonitoring(n.profileID) && (n.isQuota ? p.quotaAlerts : n.attention === 'running' ? p.startAlerts : n.attention ? p.attentionAlerts : p.completionAlerts); }
  show(n) {
    clearTimeout(this.noticeTimer); this.notice = n; this.emit('notice', n); this.emit('change');
    this.noticeTimer = setTimeout(() => this.finishNotice(n.id), 6000);
  }
  finishNotice(id) {
    if (!this.notice || this.notice.id !== id) return;
    clearTimeout(this.noticeTimer); this.notice = null;
    if (this.locked()) { this.pending = []; this.emit('change'); return; }
    this.pending = this.pending.filter(n => this.allows(n));
    if (this.pending.length) this.show(this.pending.shift()); else this.emit('change');
  }
  acknowledge() { if (this.unviewed.size) { this.unviewed.clear(); this.emit('change'); } }
  handleLock() { clearTimeout(this.noticeTimer); this.notice = null; this.pending = []; this.emit('change'); }

  snapshotForUI() {
    const now = this.now();
    const profiles = this.profiles().map(p => {
      const s = this.snapshots[p.id] || { sessions: [], quotas: [], source: '', detail: p.windows ? '尚未收到Agent的数据。' : 'Windows 版暂不支持读取这个工具。' };
      const state = snapshotState({ sessions: s.sessions || [] }, now);
      return {
        id: p.id, name: p.name, kind: p.kind, windows: p.windows, launchURL: p.launchURL || '',
        mode: this.preferences.visibleIDs.includes(p.id) ? 'show' : this.isMonitoring(p.id) ? 'alerts' : 'off',
        state, stateLabel: STATE_LABEL[state], detail: s.detail, source: s.source,
        running: (s.sessions || []).filter(x => x.state === 'working' && now - x.updatedAt < 900).length,
        quotas: (s.quotas || []).map(q => ({ ...q, fresh: quotaFresh(q, now) })),
        unviewed: this.unviewed.has(p.id)
      };
    });
    return { preferences: this.preferences, profiles, primary: this.primary.id, notice: this.notice ? { id: this.notice.id, message: this.notice.message, profileID: this.notice.profileID, attention: this.notice.attention || null } : null, claudeHook: this.claudeHookConfigured() };
  }
}

module.exports = { AgentStore, AlertTracker, CompletionBatch, snapshotState, quotaFresh, PROFILES, defaultPreferences, noticeText };
