'use strict';
// Glue between the company connection, the official CLI reader and FeishuStore.
const path = require('node:path');
const { AccountReader } = require('../core/feishu/reader.cjs');
const { FeishuStore } = require('../core/feishu/store.cjs');
const { MessageArchive, accountKey } = require('../core/feishu/archive.cjs');
const { runCLI } = require('../core/cli.cjs');
const { cliEnvironment, PURPOSES } = require('../core/company.cjs');

class FeishuService {
  constructor({ prefs, company, dataDir, cliPath, demo, canPresent }) {
    this.prefs = prefs; this.company = company; this.dataDir = dataDir; this.cliPath = cliPath; this.demo = demo;
    this.archiveRoot = path.join(dataDir, 'MessageHistory');
    this.store = new FeishuStore({ prefs, live: !demo, archiveRoot: this.archiveRoot, canPresent });
    this.connecting = false; this.hint = null;
    this.reader = this.makeReader();
    this.store.on('receiving', on => { if (on) this.startIfAllowed(); else this.reader.stop(); });
    this.store.on('retentionDays', d => { this.reader.retentionDays = d; });
    company.continueHandlers.receive = () => this.completeConnection();
    company.on('windowClosed', purpose => { if (purpose === 'receive' && this.connecting) { this.connecting = false; this.hint = '连接已暂停。'; this.store.changed(); } });
    this.timer = setInterval(() => this.store.tick(), 5000);
  }
  makeReader() {
    const configDir = path.join(this.dataDir, 'CompanyCLI');
    const reader = new AccountReader({
      run: async args => {
        const credential = await this.company.credential('receive');
        return runCLI({ executable: this.cliPath, args, env: cliEnvironment(credential, process.env, configDir), cwd: this.dataDir });
      },
      identity: async () => {
        const c = await this.company.credential('receive');
        return { openID: c.openID, userName: c.userName };
      }
    });
    reader.retentionDays = this.store.retention.days;
    reader.archive = {
      load: async (openID, days, now) => {
        const archive = new MessageArchive(this.archiveRoot, accountKey(PURPOSES.receive.appID, openID));
        MessageArchive.expireAll(this.archiveRoot, days, now);
        const snapshot = archive.load(days, now);
        this.store.restore(archive, snapshot);
        return snapshot;
      }
    };
    reader.onMessage = m => this.store.receive(m);
    reader.onAccount = a => this.store.setAccount(a);
    reader.onCheckpoint = (chat, at) => this.store.checkpoint(chat, at);
    reader.onArchiveError = () => { this.store.historyError = '本机历史暂时无法读取，原文件已保留；新消息仍会接收。'; this.store.changed(); };
    reader.onStatus = status => {
      this.store.setStatus(status);
      if (status.startsWith('账号接收中')) this.offeredRecovery = false;
      if (this.store.enabled && !this.connecting && !this.offeredRecovery && ['公司登录或飞书授权已失效', '公司登录未就绪', '公司登录已过期'].some(s => status.includes(s))) {
        this.offeredRecovery = true;
        this.hint = '登录已过期，请在连接窗口重新授权；完成后会自动恢复接收。';
        this.company.open('receive');
      }
    };
    return reader;
  }
  get canResume() { return this.company.isEnabled('receive') && !!this.prefs.get('company.receive.openID'); }
  start() {
    if (this.demo) { this.store.loadDemo(); return; }
    this.startIfAllowed();
  }
  startIfAllowed() {
    if (this.demo || !this.store.enabled || !this.store.rulesReadable) return;
    if (!this.canResume) { this.reader.stop(); this.store.setStatus('请先连接飞书，已有提醒规则已保留。'); return; }
    this.reader.start();
  }
  reconnect() { this.store.saveHistory(true); this.reader.stop(); this.store.emit('clearDanmu'); this.startIfAllowed(); }
  checkUnread(id) { return this.demo ? Promise.resolve(true) : this.store.enabled ? this.reader.checkUnread(id) : Promise.resolve(false); }
  openConnection() { if (!this.demo) this.company.open('receive'); }
  async completeConnection() {
    if (this.demo) throw new Error('演示模式不会连接真实账号。');
    if (!this.store.rulesReadable) throw new Error('消息规则无法读取，请先在设置中检查规则。');
    if (this.connecting) return;
    this.connecting = true; this.hint = '正在核对飞书账号…'; this.store.changed();
    try {
      const credential = await this.company.prepare('receive');
      this.company.activate(credential, 'receive');
      this.store.setAccount(credential.userName);
      this.store.setEnabled(true);
      this.reconnect();
      this.hint = '已连接飞书，正在接收新消息。';
    } catch (error) {
      this.hint = error.message || '连接未完成，请重试。';
      throw error;
    } finally { this.connecting = false; this.store.changed(); }
  }
  switchAccount() {
    this.reader.stop(); this.store.setEnabled(false);
    this.company.reset();
    this.store.resetAccount();
    this.store.updateSettings(require('../core/feishu/message.cjs').defaultRules(), require('../core/feishu/message.cjs').defaultCustomRules());
    this.store.setAccount('尚未连接'); this.store.setStatus('请先连接飞书，已有提醒规则已保留。');
    this.company.open('receive');
  }
  /** Recent chats for the rules picker; names only, read with the same receive scope. */
  async directory(query = '') {
    if (this.demo) return [{ id: 'oc_demo_chat_1', name: '项目讨论群', detail: '群聊' }, { id: 'oc_demo_chat_2', name: '小林', detail: '私聊' }];
    const credential = await this.company.credential('receive');
    const env = cliEnvironment(credential, process.env, path.join(this.dataDir, 'CompanyCLI'));
    const args = ['im', '+chat-list', '--types=p2p,group', '--sort', 'active_time', '--page-size', '50', '--as', 'user', '--format', 'json'];
    const result = await runCLI({ executable: this.cliPath, args, env, cwd: this.dataDir });
    const chats = result && result.data && Array.isArray(result.data.chats) ? result.data.chats : [];
    const q = query.trim().toLocaleLowerCase();
    return chats.filter(c => c && typeof c.chat_id === 'string' && /^oc_[A-Za-z0-9_]+$/.test(c.chat_id))
      .map(c => ({ id: c.chat_id, name: String(c.name || '飞书会话').slice(0, 120), detail: c.chat_mode === 'p2p' ? '私聊' : '群聊' }))
      .filter(c => !q || c.name.toLocaleLowerCase().includes(q));
  }
  snapshot() {
    return { ...this.store.snapshotForUI(), connecting: this.connecting, hint: this.hint, connected: this.canResume, demo: this.demo, company: this.company.snapshot() };
  }
  shutdown() { clearInterval(this.timer); this.store.saveHistory(true); this.reader.stop(); }
}

module.exports = { FeishuService };
