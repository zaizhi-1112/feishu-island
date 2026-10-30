'use strict';
// Claude Code status hooks on Windows (counterpart of AgentHookProtocol.swift and
// AgentStatusConnection.swift). Installing edits ~/.claude/settings.json only after the
// user clicks “连接”; existing hooks and the original status line are preserved and backed up.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const EVENTS = ['UserPromptSubmit', 'PreToolUse', 'PermissionRequest', 'PostToolUse', 'PostToolUseFailure', 'Notification', 'Elicitation', 'ElicitationResult', 'Stop', 'StopFailure', 'SessionEnd'];
const REQUIRED = ['UserPromptSubmit', 'PreToolUse', 'PermissionRequest', 'PostToolUse', 'Stop'];
const STATES = ['working', 'waiting', 'completed', 'failed'];

const hookCommand = (script, mode) => `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${script}" ${mode} claude`;

function writeAtomic(file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = file + '.' + crypto.randomUUID() + '.tmp';
  fs.writeFileSync(temp, text, { mode: 0o600 });
  fs.renameSync(temp, file);
}

/** Copy the PowerShell hook with a UTF-8 BOM so Windows PowerShell 5.1 reads Chinese labels correctly. */
function deployScript(sourcePS1, statusRoot) {
  const target = path.join(statusRoot, 'agent-hook.ps1');
  const body = fs.readFileSync(sourcePS1, 'utf8').replace(/^\uFEFF/, '');
  writeAtomic(target, '\uFEFF' + body);
  return target;
}

function install({ home, statusRoot, script }) {
  const dir = path.join(home, '.claude');
  const settings = path.join(dir, 'settings.json');
  fs.mkdirSync(dir, { recursive: true });
  let original = null, object = {};
  if (fs.existsSync(settings)) {
    if (!fs.lstatSync(settings).isFile()) throw new Error('Claude Code 设置文件不是普通文件，未修改。');
    original = fs.readFileSync(settings, 'utf8');
    if (original.length >= 4194304) throw new Error('Claude Code 设置文件过大，未修改。');
    const parsed = JSON.parse(original.replace(/^\uFEFF/, '') || '{}');
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('Claude Code 设置文件格式无法识别，未修改。');
    object = parsed;
  }
  if (object.hooks !== undefined && (typeof object.hooks !== 'object' || Array.isArray(object.hooks))) throw new Error('Claude Code 的 hooks 格式无法识别，未修改。');
  const hooks = object.hooks || {};
  const record = hookCommand(script, 'record');
  for (const event of EVENTS) {
    if (hooks[event] !== undefined && !Array.isArray(hooks[event])) throw new Error('Claude Code 的 hooks 格式无法识别，未修改。');
    let entries = (hooks[event] || []).flatMap(entry => {
      if (!entry || !Array.isArray(entry.hooks)) return [entry];
      const kept = entry.hooks.filter(h => !(h && typeof h.command === 'string' && h.command.includes('agent-hook.ps1')));
      return kept.length ? [{ ...entry, hooks: kept }] : [];
    });
    const entry = { hooks: [{ type: 'command', command: record, timeout: 5 }] };
    if (['PreToolUse', 'PostToolUse', 'PostToolUseFailure'].includes(event)) entry.matcher = '.*';
    if (event === 'Notification') entry.matcher = 'permission_prompt|elicitation_dialog|agent_needs_input|elicitation_complete|elicitation_response';
    entries.push(entry); hooks[event] = entries;
  }
  const own = hookCommand(script, 'statusline');
  const statusLine = object.statusLine && typeof object.statusLine === 'object' ? { ...object.statusLine } : {};
  if (statusLine.command !== own) {
    const previous = typeof statusLine.command === 'string' && !statusLine.command.includes('agent-hook.ps1') ? statusLine.command : '';
    writeAtomic(path.join(statusRoot, 'claude-statusline-forward.json'), JSON.stringify({ command: previous }));
    object.statusLine = { ...statusLine, type: 'command', command: own };
  }
  object.hooks = hooks;
  const result = JSON.stringify(object, null, 2);
  if (result !== original) {
    if (original !== null) writeAtomic(path.join(statusRoot, 'config-backups', 'claude-' + crypto.randomUUID() + '.json'), original);
    const now = fs.existsSync(settings) ? fs.readFileSync(settings, 'utf8') : null;
    if (now !== original) throw new Error('Claude Code 设置刚被修改，为避免覆盖已停止。请稍后重试。');
    writeAtomic(settings, result);
  }
  return true;
}

function uninstall({ home, statusRoot }) {
  const settings = path.join(home, '.claude', 'settings.json');
  if (!fs.existsSync(settings)) return true;
  const original = fs.readFileSync(settings, 'utf8');
  const object = JSON.parse(original.replace(/^\uFEFF/, '') || '{}');
  const hooks = object.hooks && typeof object.hooks === 'object' ? object.hooks : {};
  for (const event of Object.keys(hooks)) {
    if (!Array.isArray(hooks[event])) continue;
    hooks[event] = hooks[event].flatMap(entry => {
      if (!entry || !Array.isArray(entry.hooks)) return [entry];
      const kept = entry.hooks.filter(h => !(h && typeof h.command === 'string' && h.command.includes('agent-hook.ps1')));
      return kept.length ? [{ ...entry, hooks: kept }] : [];
    });
    if (!hooks[event].length) delete hooks[event];
  }
  if (object.statusLine && typeof object.statusLine.command === 'string' && object.statusLine.command.includes('agent-hook.ps1')) {
    let previous = '';
    try { previous = JSON.parse(fs.readFileSync(path.join(statusRoot, 'claude-statusline-forward.json'), 'utf8')).command || ''; } catch {}
    if (previous) object.statusLine = { ...object.statusLine, command: previous }; else delete object.statusLine;
  }
  const result = JSON.stringify(object, null, 2);
  if (result !== original) { writeAtomic(path.join(statusRoot, 'config-backups', 'claude-' + crypto.randomUUID() + '.json'), original); writeAtomic(settings, result); }
  return true;
}

function isConfigured(home) {
  try {
    const object = JSON.parse(fs.readFileSync(path.join(home, '.claude', 'settings.json'), 'utf8').replace(/^\uFEFF/, ''));
    const hooks = object.hooks || {};
    if (!(object.statusLine && typeof object.statusLine.command === 'string' && object.statusLine.command.includes('agent-hook.ps1'))) return false;
    return REQUIRED.every(e => (hooks[e] || []).some(entry => (entry.hooks || []).some(h => typeof h.command === 'string' && h.command.includes('agent-hook.ps1') && h.command.endsWith(' record claude'))));
  } catch { return false; }
}

function savePolicy(statusRoot, enabled, visibleIDs) { writeAtomic(path.join(statusRoot, 'policy.json'), JSON.stringify({ enabled, visibleIDs })); }

function readRecords(statusRoot, now) {
  const folder = path.join(statusRoot, 'claude');
  let names; try { names = fs.readdirSync(folder); } catch { return []; }
  return names.filter(n => /^[0-9a-f]{64}\.json$/.test(n)).map(n => {
    const file = path.join(folder, n);
    try {
      const st = fs.lstatSync(file); if (!st.isFile() || st.size > 2048) return null;
      const r = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
      if (r.id !== n.slice(0, 64) || !STATES.includes(r.state) || !Number.isFinite(r.updatedAt) || r.updatedAt > now + 60 || now - r.updatedAt >= 86400) return null;
      return { id: r.id, state: r.state, updatedAt: r.updatedAt, completionID: r.completionID || null, startID: r.startID || null, attentionID: r.attentionID || null, attentionReason: r.attentionReason || null, mtime: st.mtimeMs };
    } catch { return null; }
  }).filter(Boolean).sort((a, b) => b.mtime - a.mtime).slice(0, 200).map(({ mtime, ...r }) => r);
}

function readQuota(statusRoot) {
  try {
    const file = path.join(statusRoot, 'claude-quota.json');
    if (fs.statSync(file).size > 8192) return [];
    const q = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '')).quotas;
    return Array.isArray(q) ? q.filter(x => x && typeof x.id === 'string' && Number.isFinite(x.remainingPercent) && x.remainingPercent >= 0 && x.remainingPercent <= 100).slice(0, 2) : [];
  } catch { return []; }
}

module.exports = { install, uninstall, isConfigured, savePolicy, readRecords, readQuota, deployScript, hookCommand, EVENTS };
