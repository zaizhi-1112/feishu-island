'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { CodexReader, parseQuotas } = require('../core/agents/codex.cjs');
const hooks = require('../core/agents/hooks.cjs');
const { AgentStore, AlertTracker } = require('../core/agents/store.cjs');
const { Prefs } = require('../core/prefs.cjs');

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'island-agents-'));
const line = (type, payload, t) => JSON.stringify({ type, timestamp: new Date(t * 1000).toISOString(), payload }) + '\n';

test('codex lifecycle: started → waiting approval → working → completed, no content kept', () => {
  const root = tmp(); const dir = path.join(root, '2026', '10', '30'); fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, 'rollout-a.jsonl'); const now = Date.now() / 1000;
  fs.writeFileSync(file, line('event_msg', { type: 'task_started', turn_id: 't1' }, now - 5) + line('event_msg', { type: 'exec_approval_request', call_id: 'c1', command: 'secret' }, now - 4));
  const reader = new CodexReader(root);
  let [s] = reader.sessions(now);
  assert.equal(s.state, 'waiting'); assert.equal(s.attentionReason, 'approval'); assert.equal(JSON.stringify(s).includes('secret'), false);
  fs.appendFileSync(file, line('event_msg', { type: 'exec_command_begin' }, now - 3));
  [s] = reader.sessions(now); assert.equal(s.state, 'working');
  fs.appendFileSync(file, line('event_msg', { type: 'task_complete', turn_id: 't1' }, now - 1));
  [s] = reader.sessions(now); assert.equal(s.state, 'completed'); assert.equal(s.completionID, 't1');
});

test('codex quotas map windows to labels and remaining percent', () => {
  const q = parseQuotas({ rateLimits: { primary: { usedPercent: 30, windowDurationMins: 300, resetsAt: 2e9 }, secondary: { usedPercent: 90, windowDurationMins: 10080 } } }, 1);
  assert.deepEqual(q.map(x => [x.label, x.remainingPercent]), [['5小时额度', 70], ['周额度', 10]]);
});

test('alert tracker: completion counted once, not on first observation; attention per new request', () => {
  const t = new AlertTracker(); const now = 1000;
  assert.equal(t.completions([{ id: 'a', state: 'completed', updatedAt: now - 1, completionID: 'x' }], now), 0);
  assert.equal(t.completions([{ id: 'a', state: 'working', updatedAt: now + 1 }], now + 2), 0);
  assert.equal(t.completions([{ id: 'a', state: 'completed', updatedAt: now + 3, completionID: 'y' }], now + 4), 1);
  assert.equal(t.completions([{ id: 'a', state: 'completed', updatedAt: now + 3, completionID: 'y' }], now + 5), 0);
  assert.equal(t.attention([{ id: 'a', state: 'waiting', updatedAt: now, attentionID: 'q1' }], now).length, 1);
  assert.equal(t.attention([{ id: 'a', state: 'waiting', updatedAt: now, attentionID: 'q1' }], now + 1).length, 0);
  assert.equal(t.attention([{ id: 'a', state: 'waiting', updatedAt: now, attentionID: 'q2' }], now + 2).length, 1);
});

test('claude hook install preserves user hooks and status line, uninstall restores them', () => {
  const home = tmp(), status = path.join(home, 'status');
  fs.mkdirSync(path.join(home, '.claude'));
  const settings = path.join(home, '.claude', 'settings.json');
  const original = { model: 'opus', hooks: { Stop: [{ hooks: [{ type: 'command', command: 'echo mine' }] }] }, statusLine: { type: 'command', command: 'my-status' } };
  fs.writeFileSync(settings, JSON.stringify(original));
  const script = hooks.deployScript(path.join(__dirname, '../assets/agent-hook.ps1'), status);
  assert.equal(fs.readFileSync(script)[0], 0xef, 'UTF-8 BOM for Windows PowerShell 5.1');
  hooks.install({ home, statusRoot: status, script });
  const after = JSON.parse(fs.readFileSync(settings, 'utf8'));
  assert.equal(after.model, 'opus');
  assert.ok(after.hooks.Stop.some(e => e.hooks.some(h => h.command === 'echo mine')));
  assert.ok(after.statusLine.command.includes('agent-hook.ps1'));
  assert.equal(hooks.isConfigured(home), true);
  hooks.install({ home, statusRoot: status, script });
  assert.equal(JSON.parse(fs.readFileSync(settings, 'utf8')).hooks.Stop.length, 2, 'idempotent');
  hooks.uninstall({ home, statusRoot: status });
  const restored = JSON.parse(fs.readFileSync(settings, 'utf8'));
  assert.deepEqual(restored.hooks, original.hooks); assert.equal(restored.statusLine.command, 'my-status');
  assert.ok(fs.readdirSync(path.join(status, 'config-backups')).length >= 2);
});

test('claude hook install refuses malformed settings without touching the file', () => {
  const home = tmp(); fs.mkdirSync(path.join(home, '.claude'));
  const settings = path.join(home, '.claude', 'settings.json'); fs.writeFileSync(settings, '{"hooks": []}');
  assert.throws(() => hooks.install({ home, statusRoot: path.join(home, 's'), script: 'x.ps1' }));
  assert.equal(fs.readFileSync(settings, 'utf8'), '{"hooks": []}');
});

test('agent store: new users start empty, show mode caps at three, Windows-unsupported tools refuse', async () => {
  const home = tmp(); let now = 2000;
  const store = new AgentStore({ prefs: Prefs.memory(), statusRoot: path.join(home, 's'), home, env: {}, now: () => now, readQuotas: async () => [] });
  assert.deepEqual(store.preferences.visibleIDs, []);
  assert.ok(store.setMode('workbuddy', 'show').error);
  store.setMode('codex', 'show'); store.setMode('claude', 'show');
  assert.equal(store.addCustom('Kimi', 'https://www.kimi.com'), null);
  const kimi = store.preferences.custom[0].id;
  store.setMode(kimi, 'show');
  store.addCustom('豆包', '');
  assert.equal(store.setMode(store.preferences.custom[1].id, 'show').needsReplace, true);
  assert.equal(store.addCustom('x', 'http://a.com'), '入口请填不含账号、参数或令牌的 HTTPS 地址；也可以留空。');
  const notices = []; store.on('notice', n => notices.push(n.message));
  store.ingest({ codex: { sessions: [{ id: 's', state: 'working', updatedAt: now - 120 }], quotas: [] } }, now);
  now += 5; store.ingest({ codex: { sessions: [{ id: 's', state: 'working', updatedAt: now, startID: 'n' }], quotas: [] } }, now);
  assert.deepEqual(notices, ['Codex · 正在运行']);
  store.finishNotice(store.notice.id);
});

test('hook records are read only when well-formed and recent', () => {
  const status = tmp(); const folder = path.join(status, 'claude'); fs.mkdirSync(folder);
  const id = 'a'.repeat(64); const now = 5000;
  fs.writeFileSync(path.join(folder, id + '.json'), JSON.stringify({ id, state: 'working', updatedAt: now - 1 }));
  fs.writeFileSync(path.join(folder, 'b'.repeat(64) + '.json'), JSON.stringify({ id: 'wrong', state: 'working', updatedAt: now }));
  assert.deepEqual(hooks.readRecords(status, now).map(r => r.id), [id]);
});
