'use strict';
// Port of Feishu/MessageArchive.swift: user-requested local history, one file per
// account hash inside the private app data directory. Times are epoch seconds.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const RETENTION_CHOICES = [0, 1, 3, 7, 14, 30];
function defaultRetention() { return { days: 7, cleanupMinute: 3 * 60 }; }
function validRetention(r) { return !!r && RETENTION_CHOICES.includes(r.days) && Number.isInteger(r.cleanupMinute) && r.cleanupMinute >= 0 && r.cleanupMinute < 1440; }
/** Most recent scheduled cleanup instant (epoch seconds) at or before now, local time. */
function cleanupSlot(retention, now) {
  const d = new Date(now * 1000);
  const today = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const candidate = new Date(today.getTime() + retention.cleanupMinute * 60000);
  return (candidate.getTime() <= d.getTime() ? candidate : new Date(candidate.getTime() - 86400000)).getTime() / 1000;
}

function accountKey(namespace, openID) {
  return crypto.createHash('sha256').update(namespace + '\u0000' + openID).digest('hex');
}

function emptySnapshot(key, startedAt) { return { schema: 1, accountKey: key, startedAt, messages: [], pending: [], checkpoints: {}, lastCleanup: 0 }; }

function prune(snapshot, days, now) {
  const cutoff = now - days * 86400;
  snapshot.messages = snapshot.messages.filter(m => Date.parse(m.created) / 1000 >= cutoff);
  const ids = new Set(snapshot.messages.map(m => m.id));
  snapshot.pending = snapshot.pending.filter(id => ids.has(id));
  for (const k of Object.keys(snapshot.checkpoints)) snapshot.checkpoints[k] = Math.max(snapshot.checkpoints[k], cutoff);
  snapshot.startedAt = Math.max(snapshot.startedAt, cutoff);
  snapshot.lastCleanup = now;
  return snapshot;
}

class MessageArchive {
  constructor(root, key) {
    if (!/^[0-9a-f]{64}$/.test(key)) throw new Error('invalid archive key');
    this.root = root; this.key = key; this.file = path.join(root, key + '.json');
  }
  load(days, now) {
    if (days <= 0 || !fs.existsSync(this.file)) return emptySnapshot(this.key, now - (days > 0 ? 86400 : 0));
    const st = fs.lstatSync(this.file);
    if (!st.isFile() || st.size > 100_000_000) throw new Error('corrupt');
    const snapshot = JSON.parse(fs.readFileSync(this.file, 'utf8'));
    if (snapshot.schema !== 1 || snapshot.accountKey !== this.key || !Array.isArray(snapshot.messages) || !Array.isArray(snapshot.pending)
      || typeof snapshot.checkpoints !== 'object' || typeof snapshot.startedAt !== 'number') throw new Error('corrupt');
    return prune(snapshot, days, now);
  }
  save(snapshot) {
    if (snapshot.accountKey !== this.key) throw new Error('wrong account');
    fs.mkdirSync(this.root, { recursive: true, mode: 0o700 });
    if (fs.existsSync(this.file) && !fs.lstatSync(this.file).isFile()) throw new Error('not a file');
    const temp = this.file + '.' + process.pid + '.tmp';
    fs.writeFileSync(temp, JSON.stringify(snapshot), { mode: 0o600 });
    fs.renameSync(temp, this.file);
  }
  static expireAll(root, days, now) {
    if (!fs.existsSync(root)) return;
    if (!fs.lstatSync(root).isDirectory()) throw new Error('not a directory');
    for (const name of fs.readdirSync(root)) {
      const m = /^([0-9a-f]{64})\.json$/.exec(name);
      if (!m) continue;
      const archive = new MessageArchive(root, m[1]);
      archive.save(archive.load(days, now));
    }
  }
}

module.exports = { MessageArchive, accountKey, prune, emptySnapshot, defaultRetention, validRetention, cleanupSlot, RETENTION_CHOICES };
