'use strict';
// Port of Feishu/FeishuStore.swift without UI: inbox, rules, reading queue,
// danmu hand-off, local retention. Persistence goes through an injected Prefs.
const { EventEmitter } = require('node:events');
const M = require('./message.cjs');
const { MessageArchive, accountKey, prune, defaultRetention, validRetention, cleanupSlot } = require('./archive.cjs');
const appearance = require('../appearance.cjs');

class FeishuStore extends EventEmitter {
  /**
   * @param {object} o
   * @param {import('../prefs.cjs').Prefs} o.prefs
   * @param {boolean} [o.live]   real account mode (archive enabled)
   * @param {string} [o.archiveRoot]
   * @param {()=>boolean} [o.canPresent]  false until onboarding completes
   */
  constructor(o) {
    super();
    this.prefs = o.prefs; this.live = !!o.live; this.archiveRoot = o.archiveRoot || null;
    this.canPresent = o.canPresent || (() => true);
    this.now = o.now || (() => Date.now() / 1000);
    const p = this.prefs;
    const savedRules = p.get('feishu.reminderRules'), savedCustom = p.get('feishu.customRules');
    this.rules = { ...M.defaultRules(), ...(savedRules || {}) };
    this.custom = M.normalizeCustom(savedCustom);
    this.rulesReadable = (savedCustom === undefined || M.validationError(this.custom) === null);
    this.enabled = p.get('feishu.enabled', true);
    this.danmu = { enabled: false, paused: false, ...(p.get('feishu.danmu') || {}) };
    this.appearance = appearance.validate(p.get('feishu.danmuAppearance') || {}) || { ...appearance.DEFAULTS };
    this.followed = new Set(p.get('feishu.followed', []));
    const mute = p.get('feishu.mutedUntil', 0);
    this.mutedUntil = mute > this.now() ? mute : null;
    const r = p.get('feishu.retention');
    this.retention = validRetention(r) ? r : defaultRetention();
    this.messages = [];
    this.readingID = null; this.readingQueue = []; this.readingPages = {};
    this.pendingDesktop = new Set();
    this.status = '正在连接飞书…'; this.account = '尚未连接'; this.actionError = null; this.historyError = null;
    this.archive = null; this.snapshot = null; this.historyDirty = false; this.lastSave = 0;
    this.pendingAlert = null; this.pendingCount = 0; this.lastAlert = 0;
    this.suspended = false;
    if (!p.get('feishu.unifiedConversationsV1', false) && this.rulesReadable) {
      const next = M.consolidate(this.custom, this.rules.followedChats ? this.followed : new Set());
      if (M.validationError(next) === null) {
        this.custom = next; this.followed = new Set(); this.rules.followedChats = false;
        p.set('feishu.customRules', next); p.set('feishu.reminderRules', this.rules); p.remove('feishu.followed');
        p.set('feishu.unifiedConversationsV1', true);
      }
    }
    if (!this.enabled) this.status = '接收已停止';
    if (!this.rulesReadable) { this.enabled = false; this.status = '消息规则读取失败，接收已暂停。原设置已保留，请恢复设置后再接收。'; this.actionError = this.status; }
  }
  changed() { this.emit('change'); }
  get isMuted() { return (this.mutedUntil || 0) > this.now(); }
  isImportant(m) { return M.importanceReason(m, this.followed, this.rules, this.custom) !== null; }
  get visibleMessages() { return this.messages.filter(m => !M.blocks(this.custom, m)); }
  get important() { return this.messages.filter(m => this.isImportant(m)); }
  get waitingCount() { return this.important.filter(m => !m.viewed && !m.remindAt).length; }
  get conversationRules() { return [...this.custom.conversations, ...this.custom.people, ...this.custom.groups]; }

  setStatus(s) { this.status = s; this.changed(); }
  setAccount(a) { this.account = a; this.changed(); }

  // ---- history ----
  bindArchive(namespace, openID) {
    if (!this.live || !this.archiveRoot) return null;
    return new MessageArchive(this.archiveRoot, accountKey(namespace, openID));
  }
  restore(archive, snapshot) {
    const same = this.archive && this.archive.key === archive.key && this.retention.days === 0;
    this.archive = archive; this.snapshot = snapshot;
    if (!same) {
      this.messages = snapshot.messages.slice().sort((a, b) => Date.parse(b.created) - Date.parse(a.created));
      this.pendingDesktop = new Set(snapshot.pending);
    }
    this.historyDirty = true; this.historyError = null;
    this.restoreDesktopQueue(); this.changed();
  }
  checkpoint(chat, at) { if (this.snapshot) { this.snapshot.checkpoints[chat] = at; this.historyDirty = true; } }
  saveHistory(force = false) {
    const now = this.now();
    if (!this.live || !this.historyDirty || !(force || now - this.lastSave >= 5) || !this.archive || !this.snapshot) return;
    const s = this.snapshot;
    s.messages = this.retention.days > 0 ? this.messages : [];
    s.pending = this.retention.days > 0 ? [...this.pendingDesktop] : [];
    if (this.retention.days === 0) { s.checkpoints = {}; s.startedAt = now; }
    try { this.archive.save(s); this.historyDirty = false; this.lastSave = now; this.historyError = null; }
    catch { this.historyError = '消息暂时未能保存到这台电脑，请检查可用空间。'; }
  }
  pruneHistory(now) {
    if (!this.snapshot) return;
    const s = this.snapshot; s.messages = this.messages; s.pending = [...this.pendingDesktop];
    if (this.retention.days > 0) {
      prune(s, this.retention.days, now);
      this.messages = s.messages; this.pendingDesktop = new Set(s.pending);
      this.readingQueue = this.readingQueue.filter(id => this.messages.some(m => m.id === id));
      if (this.readingID && !this.messages.some(m => m.id === this.readingID)) this.closeReader();
      this.emit('retain', new Set(this.messages.map(m => m.id)));
    } else s.lastCleanup = now;
    this.historyDirty = true;
    if (this.live && this.archive) {
      try { MessageArchive.expireAll(this.archiveRoot, this.retention.days, now); }
      catch { this.historyError = '部分过期历史暂时未能清理，将在下次启动重试。'; }
    }
  }
  updateRetention(value) {
    if (!validRetention(value) || (value.days === this.retention.days && value.cleanupMinute === this.retention.cleanupMinute)) return;
    this.retention = value; this.prefs.set('feishu.retention', value);
    this.emit('retentionDays', value.days);
    this.pruneHistory(this.now()); this.saveHistory(true); this.changed();
  }

  // ---- receiving ----
  receive(message) {
    if (!this.enabled || M.blocks(this.custom, message) || this.messages.some(m => m.id === message.id)) return;
    this.messages.push(message);
    this.messages.sort((a, b) => Date.parse(b.created) - Date.parse(a.created));
    this.historyDirty = true;
    if (this.isImportant(message) && this.canPresent() && !this.isMuted && !this.suspended) {
      if (this.danmu.enabled && message.text.trim()) { this.pendingDesktop.add(message.id); this.emit('danmu', message); }
      this.readingQueue = this.readingQueue.filter(id => this.messages.some(m => m.id === id));
      this.readingQueue.push(message.id);
      if (!this.readingID) { this.readingID = this.readingQueue[0]; this.emit('openReader', this.readingID); }
    }
    this.changed();
  }
  danmuFinished(id) { if (this.pendingDesktop.delete(id)) this.historyDirty = true; }
  restoreDesktopQueue() {
    if (!this.enabled || !this.danmu.enabled || this.isMuted || this.suspended) return;
    for (const m of this.messages.slice().reverse()) {
      if (!this.pendingDesktop.has(m.id)) continue;
      if (!this.isImportant(m)) { this.pendingDesktop.delete(m.id); this.historyDirty = true; continue; }
      this.emit('danmu', m);
    }
  }
  markViewed(id) { const m = this.messages.find(x => x.id === id); if (m) { m.viewed = true; this.historyDirty = true; this.changed(); } }
  openReader(id) {
    if (!this.visibleMessages.some(m => m.id === id)) return;
    if (!this.readingQueue.includes(id)) this.readingQueue.unshift(id);
    this.readingID = id; this.markViewed(id); this.changed();
  }
  closeReader() { this.readingID = null; this.readingQueue = []; this.changed(); }
  finishReading() {
    if (!this.readingID) return;
    const id = this.readingID; this.markViewed(id);
    this.readingQueue = this.readingQueue.filter(x => x !== id && this.visibleMessages.some(m => m.id === x));
    this.readingID = this.readingQueue[0] || null;
    if (!this.readingID) this.emit('closeReader');
    this.changed();
  }
  rememberPage(id, page) {
    if (!this.messages.some(m => m.id === id)) return;
    for (const k of Object.keys(this.readingPages)) if (!this.messages.some(m => m.id === k)) delete this.readingPages[k];
    this.readingPages[id] = Math.max(0, page | 0);
  }
  remindLater(id) {
    const m = this.messages.find(x => x.id === id); if (!m) return;
    m.remindAt = this.now() + 600; m.viewed = true; this.historyDirty = true; this.changed();
  }
  toggleMute() {
    this.mutedUntil = this.isMuted ? null : this.now() + 3600;
    this.prefs.set('feishu.mutedUntil', this.mutedUntil || 0);
    this.cancelAlert(); this.emit('clearDanmu'); this.closeReader(); this.changed();
  }
  setEnabled(value) {
    if (!this.rulesReadable) { this.actionError = '原消息规则无法读取，已保留设置并暂停接收。'; this.changed(); return; }
    if (this.enabled === value) return;
    this.enabled = value; this.prefs.set('feishu.enabled', value);
    this.cancelAlert();
    if (!value) { this.emit('clearDanmu'); this.closeReader(); }
    this.emit('receiving', value); this.changed();
  }
  updateSettings(rules, custom = this.custom) {
    if (!this.rulesReadable) { this.actionError = '原消息规则无法读取，未覆盖设置。'; return false; }
    const next = M.normalizeCustom(custom);
    if (M.validationError(next) !== null) { this.actionError = M.validationError(next); this.changed(); return false; }
    this.rules = { ...M.defaultRules(), ...rules }; this.custom = next;
    this.prefs.set('feishu.customRules', next); this.prefs.set('feishu.reminderRules', this.rules);
    this.cancelAlert(); this.emit('clearDanmu'); this.closeReader(); this.changed();
    return true;
  }
  setConversation(target, mode) {
    const next = JSON.parse(JSON.stringify(this.custom));
    if (target.id.startsWith('ou_')) {
      next.people = next.people.filter(r => r.target.id !== target.id);
      if (mode) next.people.push({ target, mode });
    } else {
      next.conversations = next.conversations.filter(r => r.target.id !== target.id);
      next.groups = next.groups.filter(r => r.target.id !== target.id);
      if (mode) next.conversations.push({ target, mode });
    }
    return this.updateSettings(this.rules, next);
  }
  updateDanmu(value) {
    const next = { enabled: !!value.enabled, paused: !!value.paused };
    if (next.enabled === this.danmu.enabled && next.paused === this.danmu.paused) return;
    this.danmu = next; this.prefs.set('feishu.danmu', next);
    if (!next.enabled) this.emit('clearDanmu');
    this.emit('danmuOptions', next); this.changed();
  }
  updateAppearance(input) {
    const value = appearance.validate(input);
    if (!value) return false;
    this.appearance = value; this.prefs.set('feishu.danmuAppearance', value);
    this.emit('danmuOptions', this.danmu); this.changed(); return true;
  }
  suspend(value) { this.suspended = value; if (value) this.emit('clearDanmu'); this.changed(); }
  resetAccount() {
    this.saveHistory(true); this.archive = null; this.snapshot = null; this.pendingDesktop.clear();
    this.messages = []; this.cancelAlert(); this.closeReader(); this.readingPages = {};
    this.emit('clearDanmu'); this.changed();
  }

  // ---- timers & alerts ----
  tick() {
    const now = this.now();
    if (this.retention.days > 0 && this.snapshot && this.snapshot.lastCleanup < cleanupSlot(this.retention, now)) this.pruneHistory(now);
    this.saveHistory();
    this.restoreDesktopQueue();
    if (this.mutedUntil && this.mutedUntil <= now) { this.mutedUntil = null; this.prefs.remove('feishu.mutedUntil'); if (this.waitingCount > 0) this.queueAlert(); this.changed(); }
    for (const m of this.messages) {
      if (m.remindAt && m.remindAt <= now) {
        m.remindAt = null; m.viewed = false; m.reminded = true; this.historyDirty = true;
        if (this.enabled && !M.blocks(this.custom, m)) this.queueAlert();
        this.changed();
      }
    }
  }
  cancelAlert() { clearTimeout(this.pendingAlert); this.pendingAlert = null; this.pendingCount = 0; }
  queueAlert() {
    if (!this.enabled || this.isMuted || this.suspended || !this.canPresent()) return;
    this.pendingCount++;
    if (this.pendingAlert) return;
    const wait = Math.max(1, 12 - (this.now() - this.lastAlert));
    this.pendingAlert = setTimeout(() => {
      this.pendingAlert = null;
      if (!this.enabled || this.isMuted || this.suspended || !this.canPresent()) { this.pendingCount = 0; return; }
      const count = this.pendingCount; this.pendingCount = 0; this.lastAlert = this.now();
      this.emit('alert', count);
    }, wait * 1000);
  }

  // ---- presentation ----
  snapshotForUI() {
    return {
      status: this.status, account: this.account, enabled: this.enabled, muted: this.isMuted, mutedUntil: this.mutedUntil,
      actionError: this.actionError, historyError: this.historyError, rulesReadable: this.rulesReadable,
      rules: this.rules, custom: this.custom, retention: this.retention, danmu: this.danmu, appearance: this.appearance,
      waiting: this.waitingCount, readingID: this.readingID, readingQueue: this.readingQueue.length,
      readingPage: this.readingID ? (this.readingPages[this.readingID] || 0) : 0,
      messages: this.visibleMessages.slice(0, 200).map(m => ({
        id: m.id, source: M.source(m), sender: m.senderName, chatKind: m.chatKind, text: M.displayText(m.text), created: m.created,
        viewed: m.viewed, remindAt: m.remindAt, reason: M.importanceReason(m, this.followed, this.rules, this.custom), canOpen: M.chatURL(m) !== null
      }))
    };
  }
  loadDemo() {
    this.status = '演示模式 · 未连接网络'; this.account = '示例账号';
    const items = [[1, 'group', '@_user_1 这版方案我看过了，请帮忙确认最终时间。', true], [2, 'p2p', '资料已经整理好了，方便时看一下。', false], [3, 'group', '今天的会议纪要已更新。', false]];
    for (const [i, kind, content, mentioned] of items) {
      const text = i === 1 ? Array(20).fill(content).join('\n') : content;
      this.receive(M.createMessage({ message_id: 'demo' + i, create_time: String(Date.now() - i * 60000), msg_type: 'text', sender: { sender_name: i === 2 ? '小林' : '项目同事' }, body: { content: JSON.stringify({ text }) }, mentions: mentioned ? [{ id: 'demo_me', name: '佑哥', key: '@_user_1' }] : [] },
        'oc_demo_chat_' + i, i === 2 ? '小林' : '项目讨论群', kind, 'demo_me'));
    }
  }
  playSynthetic(text = '透明试播') {
    const m = M.createMessage({ message_id: 'demo_' + require('node:crypto').randomUUID(), sender: { id: 'ou_demo', sender_name: '合成示例' }, msg_type: 'text', body: { content: JSON.stringify({ text }) } }, 'oc_demo', '演示', 'p2p', '');
    this.receive(m);
  }
}

module.exports = { FeishuStore };
