'use strict';
// Small JSON key-value store (the Windows counterpart of a UserDefaults suite).
// Writes are atomic (temp file + rename). Unreadable files are preserved, never overwritten.
const fs = require('node:fs');
const path = require('node:path');

class Prefs {
  constructor(file) {
    this.file = file; this.values = {}; this.readable = true; this.timer = null;
    if (file && fs.existsSync(file)) {
      try {
        const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
        if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) this.values = parsed; else this.readable = false;
      } catch { this.readable = false; }
    }
  }
  static memory(initial = {}) { const p = new Prefs(null); p.values = JSON.parse(JSON.stringify(initial)); return p; }
  has(key) { return Object.prototype.hasOwnProperty.call(this.values, key); }
  get(key, fallback) { return this.has(key) ? JSON.parse(JSON.stringify(this.values[key])) : fallback; }
  set(key, value) {
    if (value === undefined) delete this.values[key]; else this.values[key] = JSON.parse(JSON.stringify(value));
    this.schedule();
  }
  remove(key) { delete this.values[key]; this.schedule(); }
  schedule() {
    if (!this.file || !this.readable) return;
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.flush(), 200);
  }
  flush() {
    clearTimeout(this.timer); this.timer = null;
    if (!this.file || !this.readable) return;
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    const temp = this.file + '.tmp';
    fs.writeFileSync(temp, JSON.stringify(this.values, null, 1), { mode: 0o600 });
    fs.renameSync(temp, this.file);
  }
}

module.exports = { Prefs };
