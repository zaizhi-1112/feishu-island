'use strict';
// Port of Feishu/ServerClock.swift: query windows and startup filtering use the
// Feishu HTTPS Date header, advanced monotonically between calibrations.

function monotonic() { return Number(process.hrtime.bigint() / 1000000n) / 1000; }

async function feishuSample(fetchImpl = fetch) {
  const url = 'https://open.feishu.cn/open-apis/im/v1/messages?danmu_clock_probe=' + require('node:crypto').randomUUID();
  const began = monotonic();
  const localBegan = Date.now();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 3000);
  let response;
  try {
    response = await fetchImpl(url, { method: 'HEAD', cache: 'no-store', headers: { 'Cache-Control': 'no-cache, no-store' }, signal: controller.signal, redirect: 'error' });
  } catch {
    throw new Error('无法读取飞书安全时间，请检查网络。');
  } finally { clearTimeout(timer); }
  const ended = monotonic();
  const rtt = ended - began;
  const header = response.headers.get('date');
  const parsed = header ? Date.parse(header) : NaN;
  if (!(rtt >= 0 && rtt <= 3) || Math.abs((Date.now() - localBegan) / 1000 - rtt) >= 1 || !Number.isFinite(parsed)) {
    throw new Error('飞书没有返回有效时间。');
  }
  return { serverTime: parsed / 1000 + 0.5 + rtt / 2, localTime: Date.now() / 1000, uptime: ended, roundTrip: rtt };
}

class ServerClock {
  constructor(probe = feishuSample) { this.probe = probe; this.sample = null; this.pending = null; }
  async refreshIfNeeded(maxAge = 300) {
    const previous = this.sample;
    if (previous) {
      const elapsed = monotonic() - previous.uptime;
      const wall = Date.now() / 1000 - previous.localTime;
      if (elapsed >= 0 && elapsed < maxAge && Math.abs(wall - elapsed) < 2) return;
    }
    if (!this.pending) this.pending = Promise.resolve().then(() => this.probe()).then(s => { this.sample = s; }).finally(() => { this.pending = null; });
    await this.pending;
  }
  /** Seconds since epoch on the server timebase. */
  now() {
    const s = this.sample;
    if (!s) return Date.now() / 1000;
    return s.serverTime + Math.max(0, monotonic() - s.uptime);
  }
  get offset() { return this.now() - Date.now() / 1000; }
  get calibrated() { return this.sample !== null; }
}

ServerClock.local = (offset = 0) => async () => ({ serverTime: Date.now() / 1000 + offset, localTime: Date.now() / 1000, uptime: monotonic(), roundTrip: 0 });

module.exports = { ServerClock, monotonic, feishuSample };
