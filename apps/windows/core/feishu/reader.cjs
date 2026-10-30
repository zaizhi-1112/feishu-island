'use strict';
// Port of apps/island Feishu/AccountReader.swift.
// The official CLI owns the HTTP calls; this module only schedules read-only GETs,
// verifies unread state, and hands new unread messages to onMessage. Progress,
// dedupe IDs and bodies stay in memory unless the store persists them on request.

const { ServerClock, monotonic } = require('./clock.cjs');
const { createMessage, messageDate } = require('./message.cjs');

class AccountFailure extends Error {}

const sleep = ms => new Promise(r => setTimeout(r, ms));

class Semaphore {
  constructor(n) { this.n = n; this.waiters = []; }
  async acquire() { if (this.n > 0) { this.n--; return; } await new Promise(r => this.waiters.push(r)); }
  release() { const next = this.waiters.shift(); if (next) next(); else this.n++; }
}

class Session {
  constructor(token, ownID, started) {
    this.token = token; this.ownID = ownID; this.started = started;
    this.checkpoints = new Map(); this.seen = new Map(); this.inFlight = new Set(); this.windows = new Map();
    this.catalogCount = 0; this.selectedCount = 0; this.backgroundFailed = false; this.unresolved = new Set();
    this.fastQueue = []; this.fastActive = new Set(); this.fastLastRead = new Map(); this.fastRetryAt = new Map();
  }
}

class AccountReader {
  /**
   * @param {object} o
   * @param {(args:string[])=>Promise<object>} o.run      runs the official CLI and resolves its JSON (rejects on failure)
   * @param {()=>Promise<{openID:string,userName:string}>} o.identity  verified identity for the bound credential
   */
  constructor(o) {
    this.run = o.run; this.identity = o.identity;
    this.pollDelay = o.pollDelay ?? 2; this.pageDelay = o.pageDelay ?? 0.3;
    this.concurrency = Math.max(2, o.concurrency ?? 3); this.catalogInterval = o.catalogInterval ?? 60;
    this.clock = o.clock || new ServerClock(); this.retryDelay = o.retryDelay ?? 5;
    this.slots = new Semaphore(3);
    this.generation = 0; this.enabled = false; this.gray = []; this.hidden = [];
    this.retentionDays = 0; this.archive = null; // {load(openID, days, now) -> snapshot|null}
    this.onMessage = () => {}; this.onAccount = () => {}; this.onStatus = () => {};
    this.onRestore = () => {}; this.onCheckpoint = () => {}; this.onArchiveError = () => {};
  }
  setPollDelay(d) { this.pollDelay = Math.max(0.5, d); }
  setRules(gray, hidden) { this.gray = gray.slice(); this.hidden = hidden.slice(); }
  alive(token) { return this.generation === token; }
  now() { return this.clock.now(); }

  start() {
    if (this.enabled) return;
    this.enabled = true;
    const token = ++this.generation;
    this.onStatus('正在连接飞书账号…');
    (async () => {
      try {
        const user = await this.identity();
        if (!this.alive(token)) return;
        if (!user || typeof user.openID !== 'string' || !user.openID) throw new AccountFailure('账号未授权，请重新连接');
        this.onAccount(user.userName || '已连接账号');
        await this.clock.refreshIfNeeded();
        if (!this.alive(token)) return;
        const now = this.clock.now();
        let snapshot = null;
        if (this.archive) {
          try { snapshot = await this.archive.load(user.openID, this.retentionDays, now); if (snapshot && this.alive(token)) this.onRestore(snapshot); }
          catch { if (this.alive(token)) this.onArchiveError(); }
        }
        const session = new Session(token, user.openID, snapshot && snapshot.startedAt ? snapshot.startedAt : now);
        if (snapshot && snapshot.checkpoints) for (const [k, v] of Object.entries(snapshot.checkpoints)) session.checkpoints.set(k, v);
        this.backfill(session);
        this.cycle(session);
      } catch (error) {
        if (!this.alive(token)) return;
        this.onStatus(`连接失败：${this.reason(error)} · 5 秒后重连`);
        await sleep(this.retryDelay * 1000);
        if (this.alive(token)) { this.enabled = false; this.start(); }
      }
    })();
  }
  stop() {
    this.enabled = false; this.generation++;
    this.onStatus('账号接收已停止');
  }
  reason(error) { return error instanceof AccountFailure ? error.message : (error && error.userMessage) || '本机连接异常'; }

  async data(args, token) {
    await this.slots.acquire();
    try {
      if (!this.alive(token)) throw new AccountFailure('接收已停止');
      const result = await this.run([...args, '--as', 'user', '--format', 'json']);
      if (!this.alive(token)) throw new AccountFailure('接收已停止');
      if (!result || result.identity !== 'user' || !result.data || typeof result.data !== 'object') throw new AccountFailure('账号身份或接口结构异常');
      return result.data;
    } finally { this.slots.release(); }
  }
  async readStatus(ids, token) {
    return this.data(['api', 'POST', '/open-apis/im/v1/messages/read_status', '--data', JSON.stringify({ message_ids: ids })], token);
  }
  async checkUnread(id) {
    const token = this.generation;
    try {
      const states = await this.readStatus([id], token);
      const item = (Array.isArray(states.items) ? states.items : []).find(i => i.message_id === id);
      return item && typeof item.is_read === 'boolean' ? !item.is_read : null;
    } catch { return null; }
  }
  async chats(token, excludeMuted, full) {
    const rows = []; let cursor = null; const visited = new Set();
    while (this.alive(token)) {
      const args = ['im', '+chat-list', '--types=p2p,group', '--sort', 'active_time', '--page-size', full ? '100' : '12'];
      if (excludeMuted) args.push('--exclude-muted');
      if (cursor) args.push('--page-token', cursor);
      const result = await this.data(args, token);
      if (!Array.isArray(result.chats)) throw new AccountFailure('会话列表结构异常');
      rows.push(...result.chats);
      if (!full || result.has_more !== true) return rows;
      const next = result.page_token;
      if (typeof next !== 'string' || !next || visited.has(next) || visited.size >= 999) throw new AccountFailure('会话列表分页未完整返回');
      visited.add(next); cursor = next;
    }
    throw new AccountFailure('接收已停止');
  }
  catalog(rows, unmuted) {
    const ids = new Set();
    return rows.flatMap(row => {
      const id = row && row.chat_id, kind = row && row.chat_mode;
      if (typeof id !== 'string' || !['p2p', 'group', 'topic'].includes(kind) || ids.has(id)) return [];
      ids.add(id);
      return [{ id, name: typeof row.name === 'string' ? row.name : '飞书会话', kind, muted: !unmuted.has(id) }];
    });
  }
  allowed(chat) {
    const name = chat.name.toLocaleLowerCase();
    const has = list => list.some(k => k && name.includes(k.toLocaleLowerCase()));
    return !has(this.hidden) && (!chat.muted || has(this.gray));
  }

  async cycle(session) {
    while (this.alive(session.token)) {
      const began = monotonic();
      let retry = 0;
      try {
        await this.clock.refreshIfNeeded();
        const unmuted = await this.chats(session.token, true, false);
        const allowedIDs = new Set(unmuted.map(r => r && r.chat_id).filter(x => typeof x === 'string'));
        const rows = this.gray.length === 0 ? unmuted : await this.chats(session.token, false, false);
        const selected = this.catalog(rows, allowedIDs).filter(c => this.allowed(c));
        const recent = selected.slice(0, 6);
        const recentIDs = new Set(recent.map(c => c.id));
        session.fastQueue = recent.map((c, i) => [c, i]).filter(([c]) => !session.fastActive.has(c.id)).sort((a, b) => {
          const l = session.fastLastRead.get(a[0].id) ?? -Infinity, r = session.fastLastRead.get(b[0].id) ?? -Infinity;
          return l === r ? a[1] - b[1] : l - r;
        }).map(([c]) => c);
        for (const k of [...session.fastLastRead.keys()]) if (!recentIDs.has(k) && !session.fastActive.has(k)) session.fastLastRead.delete(k);
        for (const k of [...session.fastRetryAt.keys()]) if (!recentIDs.has(k) && !session.fastActive.has(k)) session.fastRetryAt.delete(k);
        this.drainFast(session);
        if (!this.alive(session.token)) return;
        const scope = session.catalogCount === 0 ? '会话发现中' : `${session.selectedCount}/${session.catalogCount} 个会话`;
        const failed = session.fastRetryAt.size;
        const suffix = (failed > 0 ? ` · ${failed} 个快查读取失败，将重试` : session.backgroundFailed ? ' · 后台补读重试中' : '') + (session.unresolved.size ? ' · 部分消息待确认未读状态' : '');
        const seconds = monotonic() - began;
        const offset = this.clock.offset;
        const correction = Math.abs(offset) >= 2 ? ` · 时间校准 ${offset >= 0 ? '+' : ''}${offset.toFixed(0)} 秒` : '';
        const state = failed > 0 || session.backgroundFailed ? '接收异常，重试中' : '账号接收中';
        this.onStatus(`${state} · ${scope} · 会话检查 ${seconds.toFixed(1)} 秒${correction}${suffix}`);
      } catch (error) {
        retry = this.retryDelay;
        if (this.alive(session.token)) this.onStatus(`快查暂缓：${this.reason(error)} · 自动重试中`);
      }
      if (!this.alive(session.token)) return;
      const delay = Math.max(Math.max(0.05, this.pollDelay - (monotonic() - began)), retry);
      await sleep(delay * 1000);
    }
  }
  drainFast(session) {
    if (!this.alive(session.token)) return;
    const now = monotonic();
    while (session.fastActive.size < this.concurrency - 1 && session.fastQueue.length) {
      const chat = session.fastQueue.shift();
      if ((session.fastRetryAt.get(chat.id) ?? 0) > now || session.fastActive.has(chat.id)) continue;
      session.fastActive.add(chat.id);
      (async () => {
        let ok = false;
        try { await this.receive(chat, session, true); ok = true; } catch { /* retried below */ }
        session.fastActive.delete(chat.id);
        session.fastLastRead.set(chat.id, monotonic());
        if (ok) session.fastRetryAt.delete(chat.id); else session.fastRetryAt.set(chat.id, monotonic() + this.retryDelay);
        this.drainFast(session);
      })();
    }
  }
  async backfill(session) {
    let list = [], cursor = 0, refreshed = -Infinity;
    while (this.alive(session.token)) {
      try {
        if (monotonic() - refreshed >= this.catalogInterval) {
          const rows = await this.chats(session.token, false, true);
          const ids = new Set((await this.chats(session.token, true, true)).map(r => r && r.chat_id).filter(x => typeof x === 'string'));
          list = this.catalog(rows, ids); refreshed = monotonic();
          session.catalogCount = list.length; session.selectedCount = list.filter(c => this.allowed(c)).length;
        }
        if (list.length) {
          const chat = list[cursor % list.length]; cursor++;
          if (this.allowed(chat)) await this.receive(chat, session);
          else session.checkpoints.set(chat.id, this.clock.now());
        }
        session.backgroundFailed = false;
        await sleep(Math.max(this.pageDelay, list.length ? 0 : 1) * 1000);
      } catch {
        session.backgroundFailed = true;
        for (let i = 0; i < 50; i++) { if (!this.alive(session.token)) return; await sleep(this.retryDelay * 20); }
      }
    }
  }
  async receive(chat, session, fast = false) {
    if (!this.alive(session.token) || !this.allowed(chat)) return;
    const flightKey = chat.id + (fast ? ':fast' : ':background');
    if (session.inFlight.has(flightKey)) return;
    session.inFlight.add(flightKey);
    const checkpoint = session.checkpoints.get(chat.id) ?? session.started;
    const start = Math.max(session.started, checkpoint - 120);
    session.windows.set(flightKey, start);
    try {
      await this.clock.refreshIfNeeded();
      const end = this.clock.now();
      let pageToken = null, pageCount = 0;
      do {
        const params = { container_id_type: 'chat', container_id: chat.id, start_time: String(Math.floor(start)), end_time: String(Math.floor(end)), sort_type: 'ByCreateTimeDesc', page_size: '50', with_sender_name: 'true', only_thread_root_messages: 'false', card_msg_content_type: 'user_card_content' };
        if (pageToken) params.page_token = pageToken;
        const result = await this.data(['api', 'GET', '/open-apis/im/v1/messages', '--params', JSON.stringify(params)], session.token);
        if (!Array.isArray(result.items)) throw new AccountFailure('消息结构异常');
        const retainedFrom = Math.min(...[...session.windows].filter(([k]) => k.startsWith(chat.id + ':')).map(([, v]) => v), start);
        const seen = new Map([...(session.seen.get(chat.id) || new Map())].filter(([, v]) => v >= retainedFrom));
        session.seen.set(chat.id, seen);
        const candidates = result.items.slice().reverse().filter(m => {
          if (!m || typeof m.message_id !== 'string' || seen.has(m.message_id) || m.deleted === true) return false;
          const sender = m.sender && typeof m.sender === 'object' ? m.sender : {};
          if (sender.id === session.ownID) return false;
          const created = messageDate(m.create_time);
          return created !== null && created.getTime() / 1000 >= session.started;
        });
        const ids = candidates.map(m => m.message_id);
        const readStates = new Map();
        if (ids.length) {
          const states = await this.readStatus(ids, session.token);
          if (!Array.isArray(states.items)) throw new AccountFailure('未读状态无法确认，暂停该批消息');
          if (states.items.length < ids.length) session.unresolved.add(chat.id);
          for (const item of states.items) if (item && typeof item.message_id === 'string' && typeof item.is_read === 'boolean') readStates.set(item.message_id, item.is_read);
        }
        for (const m of candidates) {
          const id = m.message_id;
          if (!readStates.has(id)) continue; // Unknown is not read: retry later.
          const created = messageDate(m.create_time);
          if (created && created.getTime() / 1000 < session.started) continue;
          const chatSeen = session.seen.get(chat.id) || new Map();
          const isNew = !chatSeen.has(id);
          if (isNew) { chatSeen.set(id, created ? created.getTime() / 1000 : end); session.seen.set(chat.id, chatSeen); }
          if (!isNew || readStates.get(id)) continue;
          const sender = m.sender && typeof m.sender === 'object' ? m.sender : {};
          const senderOpen = sender.id && typeof sender.id === 'object' ? sender.id.open_id : sender.id;
          if (senderOpen === session.ownID) continue;
          const item = createMessage(m, chat.id, chat.name, chat.kind, session.ownID);
          if (this.alive(session.token) && this.allowed(chat)) this.onMessage(item);
        }
        if (ids.some(id => !readStates.has(id))) throw new AccountFailure('部分消息未读状态待确认，保留进度重试');
        if (result.has_more === true) {
          const next = result.page_token;
          if (typeof next !== 'string' || !next || next === pageToken) throw new AccountFailure('消息分页异常');
          pageToken = next;
        } else pageToken = null;
        pageCount++;
        if (fast && pageCount >= 2 && pageToken) return;
        if (pageCount >= 1000 && pageToken) throw new AccountFailure('消息补读尚未完成');
      } while (pageToken);
      session.unresolved.delete(chat.id);
      const committed = Math.max(session.checkpoints.get(chat.id) ?? session.started, end);
      session.checkpoints.set(chat.id, committed);
      if (this.alive(session.token)) this.onCheckpoint(chat.id, committed);
    } finally {
      session.inFlight.delete(flightKey); session.windows.delete(flightKey);
    }
  }
}

module.exports = { AccountReader, AccountFailure, Semaphore };
