'use strict';
// Windows update check against the public GitHub Releases of zaizhi-1112/feishu-island.
// Never installs silently: the user clicks to download, the SHA-256 is verified when the
// release publishes SHA256SUMS, and the installer only runs after a second explicit click.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const REPO = 'zaizhi-1112/feishu-island';
const ASSET = /^FeishuIsland-Setup-(\d+)\.(\d+)\.(\d+)-x64\.exe$/;

function compare(a, b) { for (let i = 0; i < 3; i++) { if (a[i] !== b[i]) return a[i] - b[i]; } return 0; }
const parse = v => String(v).split('.').map(n => parseInt(n, 10) || 0).concat([0, 0, 0]).slice(0, 3);

/** Picks the newest non-draft release that carries a Windows installer newer than current. */
function pickUpdate(releases, current, { includePrerelease = false } = {}) {
  let best = null;
  for (const r of Array.isArray(releases) ? releases : []) {
    if (!r || r.draft || (r.prerelease && !includePrerelease)) continue;
    for (const a of Array.isArray(r.assets) ? r.assets : []) {
      const m = a && typeof a.name === 'string' ? ASSET.exec(a.name) : null;
      if (!m || typeof a.browser_download_url !== 'string' || !a.browser_download_url.startsWith('https://github.com/')) continue;
      const version = [Number(m[1]), Number(m[2]), Number(m[3])];
      if (compare(version, parse(current)) <= 0) continue;
      if (!best || compare(version, best.version) > 0) {
        const sums = (r.assets || []).find(x => x && x.name === 'SHA256SUMS');
        best = { version, versionText: version.join('.'), name: a.name, url: a.browser_download_url, size: a.size, sumsURL: sums ? sums.browser_download_url : null, notes: typeof r.body === 'string' ? r.body.slice(0, 4000) : '', page: r.html_url, prerelease: !!r.prerelease };
      }
    }
  }
  return best;
}

async function check(current, { fetchImpl = fetch, includePrerelease = false } = {}) {
  const r = await fetchImpl(`https://api.github.com/repos/${REPO}/releases?per_page=20`, { headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'FeishuIsland-Windows' }, redirect: 'follow' });
  if (!r.ok) throw new Error(r.status === 403 ? 'GitHub 暂时限制了查询次数，请稍后再检查。' : `暂时无法检查更新（${r.status}）。`);
  return pickUpdate(await r.json(), current, { includePrerelease });
}

async function download(update, dir, { fetchImpl = fetch, onProgress = () => {} } = {}) {
  fs.mkdirSync(dir, { recursive: true });
  let expected = null;
  if (update.sumsURL) {
    const s = await fetchImpl(update.sumsURL, { redirect: 'follow' });
    if (s.ok) { const line = (await s.text()).split('\n').find(l => l.trim().endsWith(update.name)); if (line && /^[0-9a-f]{64}\s/.test(line)) expected = line.slice(0, 64); }
  }
  const r = await fetchImpl(update.url, { redirect: 'follow' });
  if (!r.ok || !r.body) throw new Error('下载失败，请稍后重试。');
  const total = Number(r.headers.get('content-length')) || update.size || 0;
  const file = path.join(dir, update.name), temp = file + '.part';
  const hash = crypto.createHash('sha256'); const out = fs.createWriteStream(temp);
  let received = 0;
  for await (const chunk of r.body) { hash.update(chunk); received += chunk.length; out.write(chunk); onProgress(total ? received / total : 0); }
  await new Promise((res, rej) => out.end(err => err ? rej(err) : res()));
  const actual = hash.digest('hex');
  if (expected && actual !== expected) { fs.rmSync(temp, { force: true }); throw new Error('安装包校验未通过，已删除。请稍后重试。'); }
  fs.renameSync(temp, file);
  return { file, sha256: actual, verified: !!expected };
}

module.exports = { pickUpdate, check, download, compare, parse, ASSET };
