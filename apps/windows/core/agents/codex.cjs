'use strict';
// Port of Agents/CodexReader.swift: lifecycle metadata from ~/.codex/sessions/*.jsonl.
// Only states and timestamps are retained — never prompts, tool arguments or responses.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawn } = require('node:child_process');

const WAIT_EVENTS = ['request_user_input', 'exec_approval_request', 'apply_patch_approval_request', 'request_permissions', 'elicitation_request'];
const RESUME_EVENTS = ['exec_command_begin', 'patch_apply_begin', 'user_message', 'elicitation_abandoned'];
const SEED_EVENTS = ['task_started', 'task_complete', 'turn_aborted', 'request_user_input', 'exec_approval_request', 'apply_patch_approval_request', 'request_permissions', 'exec_command_begin', 'patch_apply_begin'];

function consume(line, id, cursor) {
  let record; try { record = JSON.parse(line); } catch { return; }
  const payload = record && record.payload; const event = payload && payload.type; const stamp = record && record.timestamp;
  if (!payload || typeof event !== 'string' || typeof stamp !== 'string') return;
  const time = Date.parse(stamp) / 1000; if (!Number.isFinite(time)) return;
  const kind = record.type;
  const s = cursor.session;
  if (kind === 'response_item') {
    const call = typeof payload.call_id === 'string' ? payload.call_id : null;
    const name = String(payload.name || '').split('.').pop();
    if (event === 'function_call' && name === 'request_user_input_async') cursor.pendingAsyncInput = call || stamp;
    else if (event === 'function_call' && name === 'request_user_input' && s && s.state === 'working') Object.assign(s, { state: 'waiting', updatedAt: time, attentionID: call || stamp, attentionReason: 'input' });
    else if (['function_call_output', 'custom_tool_call_output'].includes(event) && call && s && call === s.attentionID) Object.assign(s, { state: 'working', updatedAt: time, attentionID: null, attentionReason: null });
    return;
  }
  if (kind !== 'event_msg') return;
  const turn = typeof payload.turn_id === 'string' ? payload.turn_id : null;
  if (event === 'task_started') { cursor.pendingAsyncInput = null; cursor.turnID = turn; cursor.session = { id, state: 'working', updatedAt: time, startID: turn || stamp }; return; }
  if (cursor.turnID && turn && cursor.turnID !== turn) return;
  if (event === 'task_complete' && cursor.pendingAsyncInput) {
    cursor.session = { id, state: 'waiting', updatedAt: time, attentionID: cursor.pendingAsyncInput, attentionReason: 'input', startID: s && s.startID };
  } else if (['task_complete', 'turn_aborted'].includes(event)) {
    cursor.pendingAsyncInput = null;
    cursor.session = { id, state: event === 'task_complete' ? 'completed' : 'failed', updatedAt: time, completionID: event === 'task_complete' ? (turn || stamp) : null };
  } else if (WAIT_EVENTS.includes(event)) {
    cursor.session = { id, state: 'waiting', updatedAt: time, attentionID: payload.call_id || payload.id || stamp, attentionReason: event === 'request_user_input' ? 'input' : 'approval', startID: s && s.startID };
  } else if (RESUME_EVENTS.includes(event) && s && s.state === 'waiting') {
    Object.assign(s, { state: 'working', updatedAt: time, attentionID: null, attentionReason: null });
  } else if (s && (s.state === 'working' || s.state === 'waiting')) s.updatedAt = time;
}

class CodexReader {
  constructor(root = path.join(os.homedir(), '.codex', 'sessions')) { this.root = root; this.cursors = new Map(); this.files = []; this.lastDiscovery = 0; }
  discover(now) {
    const found = [];
    const walk = dir => {
      let entries; try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
      for (const e of entries) {
        if (e.name.startsWith('.')) continue;
        const p = path.join(dir, e.name);
        if (e.isDirectory()) walk(p);
        else if (e.isFile() && e.name.endsWith('.jsonl')) { try { const m = fs.statSync(p).mtimeMs / 1000; if (now - m < 172800) found.push([p, m]); } catch {} }
      }
    };
    walk(this.root);
    this.files = found.sort((a, b) => b[1] - a[1]).slice(0, 80).map(x => x[0]);
    const keep = new Set(this.files); for (const k of [...this.cursors.keys()]) if (!keep.has(k)) this.cursors.delete(k);
  }
  sessions(now = Date.now() / 1000) {
    if (now - this.lastDiscovery >= 10) { this.lastDiscovery = now; this.discover(now); }
    for (const file of this.files) {
      let fd; try { fd = fs.openSync(file, 'r'); } catch { continue; }
      try {
        const size = fs.fstatSync(fd).size;
        let c = this.cursors.get(file) || { offset: 0, tail: '', session: null, turnID: null, pendingAsyncInput: null };
        if (size < c.offset) c = { offset: 0, tail: '', session: null, turnID: null, pendingAsyncInput: null };
        const id = path.basename(file);
        if (size - c.offset > 4 * 1024 * 1024) {
          if (!c.session) c = this.seed(fd, size, id);
          const start = size - 4 * 1024 * 1024;
          const buf = Buffer.alloc(size - start); fs.readSync(fd, buf, 0, buf.length, start);
          const nl = buf.indexOf(10);
          c.tail = nl >= 0 ? buf.subarray(nl + 1).toString('utf8') : ''; c.offset = size;
        } else if (size > c.offset) {
          const buf = Buffer.alloc(size - c.offset); fs.readSync(fd, buf, 0, buf.length, c.offset);
          c.tail += buf.toString('utf8'); c.offset = size;
        }
        let nl;
        while ((nl = c.tail.indexOf('\n')) >= 0) { const line = c.tail.slice(0, nl); c.tail = c.tail.slice(nl + 1); consume(line, id, c); }
        this.cursors.set(file, c);
      } finally { fs.closeSync(fd); }
    }
    return [...this.cursors.values()].map(c => c.session).filter(Boolean).map(s => ({ ...s }));
  }
  seed(fd, size, id) {
    let end = size, carry = '', examined = 0; const cursor = { offset: 0, tail: '', session: null, turnID: null, pendingAsyncInput: null };
    while (end > 0 && examined < 128 * 1024 * 1024) {
      const start = Math.max(0, end - 1048576);
      const buf = Buffer.alloc(end - start); fs.readSync(fd, buf, 0, buf.length, start); examined += buf.length;
      const chunk = buf.toString('utf8') + carry;
      const lines = chunk.split('\n');
      carry = start > 0 ? lines.shift() : '';
      for (const line of lines.reverse()) {
        if (!line.includes('"event_msg"')) continue;
        let v; try { v = JSON.parse(line); } catch { continue; }
        if (v.type !== 'event_msg' || !v.payload || !SEED_EVENTS.includes(v.payload.type) || !Number.isFinite(Date.parse(v.timestamp))) continue;
        consume(line, id, cursor);
        if (!cursor.session) cursor.session = { id, state: 'working', updatedAt: Date.parse(v.timestamp) / 1000 };
        return cursor;
      }
      end = start;
    }
    return cursor;
  }
}

function quotaLabel(minutes) {
  if (typeof minutes !== 'number' || !Number.isFinite(minutes)) return '额度窗口';
  if (minutes === 10080) return '周额度';
  if (minutes >= 60) return `${Math.trunc(minutes / 60)}小时额度`;
  return `${Math.trunc(minutes)}分钟额度`;
}

function parseQuotas(result, now) {
  const buckets = result.rateLimitsByLimitId && typeof result.rateLimitsByLimitId === 'object' ? result.rateLimitsByLimitId : (result.rateLimits ? { codex: result.rateLimits } : {});
  const keys = Object.keys(buckets).sort();
  return keys.flatMap(key => ['primary', 'secondary'].flatMap(slot => {
    const v = buckets[key] || {}; const w = v[slot];
    if (!w || typeof w.usedPercent !== 'number' || !Number.isFinite(w.usedPercent) || w.usedPercent < 0 || w.usedPercent > 100) return [];
    const prefix = keys.length > 1 ? `${v.limitName || key} · ` : '';
    return [{ id: `${key}/${slot}`, label: prefix + quotaLabel(w.windowDurationMins), remainingPercent: 100 - w.usedPercent, resetsAt: typeof w.resetsAt === 'number' ? w.resetsAt : null, updatedAt: now }];
  }));
}

/** Locate codex on Windows (npm global shim or standalone exe) without a shell. */
function codexExecutable(env = process.env) {
  const dirs = String(env.PATH || env.Path || '').split(path.delimiter).filter(Boolean);
  if (env.APPDATA) dirs.push(path.join(env.APPDATA, 'npm'));
  if (env.LOCALAPPDATA) dirs.push(path.join(env.LOCALAPPDATA, 'Programs', 'codex'));
  dirs.push(path.join(os.homedir(), '.local', 'bin'));
  const names = process.platform === 'win32' ? ['codex.exe', 'codex.cmd'] : ['codex'];
  for (const dir of dirs) for (const n of names) { const p = path.join(dir, n); try { if (fs.statSync(p).isFile()) return p; } catch {} }
  return null;
}

/** Only initialize + account/rateLimits/read; never creates a task or model call. */
function readQuotas({ executable = codexExecutable(), timeout = 12000 } = {}) {
  return new Promise((resolve, reject) => {
    if (!executable) { reject(new Error('未找到Codex，请先安装并登录。')); return; }
    const isCmd = /\.cmd$/i.test(executable);
    const child = spawn(isCmd ? (process.env.ComSpec || 'cmd.exe') : executable, isCmd ? ['/d', '/s', '/c', `"${executable}" app-server --listen stdio://`] : ['app-server', '--listen', 'stdio://'], { windowsHide: true, stdio: ['pipe', 'pipe', 'ignore'], windowsVerbatimArguments: isCmd });
    let buffer = '', done = false;
    const finish = (err, value) => { if (done) return; done = true; clearTimeout(timer); try { child.stdin.end(); } catch {} try { child.kill(); } catch {} err ? reject(err) : resolve(value); };
    const send = o => child.stdin.write(JSON.stringify(o) + '\n');
    const timer = setTimeout(() => finish(new Error('Codex额度读取超时，请确认已登录并联网。')), timeout);
    child.on('error', () => finish(new Error('Codex暂时无法启动额度查询。')));
    child.on('close', () => finish(new Error('Codex额度查询已断开。')));
    child.stdout.on('data', chunk => {
      buffer += chunk.toString('utf8');
      if (buffer.length > 1048576) return finish(new Error('Codex返回的数据过大。'));
      let nl;
      while ((nl = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, nl); buffer = buffer.slice(nl + 1);
        let r; try { r = JSON.parse(line); } catch { continue; }
        if (typeof r.id !== 'number') continue;
        if (r.error) return finish(new Error('无法读取Codex额度，请确认使用ChatGPT账号登录。'));
        if (r.id === 1) { send({ method: 'initialized', params: {} }); send({ id: 2, method: 'account/rateLimits/read' }); }
        else if (r.id === 2 && r.result) return finish(null, parseQuotas(r.result, Date.now() / 1000));
      }
    });
    send({ id: 1, method: 'initialize', params: { clientInfo: { name: 'youzi_island', version: '0.5.1' } } });
  });
}

module.exports = { CodexReader, consume, parseQuotas, quotaLabel, codexExecutable, readQuotas };
