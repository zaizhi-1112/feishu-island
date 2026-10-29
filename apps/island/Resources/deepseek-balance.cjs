'use strict';

// Runs with Harness's own Electron/Node runtime and YAML parser. Only the
// existing Platform grant and its read-only wallet endpoint are used.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const ORIGIN = 'https://platform.deepseek.com';
const ENDPOINT = ORIGIN + '/api/v0/users/get_user_summary';
const KEY = 'deepseek-account-platform/default';
class BalanceError extends Error {
  constructor(code) { super(code); this.code = code; }
}
function grantFromDocument(document) {
  if (document?.version !== 1) throw new BalanceError('storage');
  const record = document.records?.[KEY];
  if (!record) throw new BalanceError('login');
  const grant = record.payload;
  if (record.kind !== 'grant' || grant?.version !== 1 || grant.issuer !== ORIGIN ||
      typeof grant.token !== 'string' || !/^[\x21-\x7e]{1,8192}$/.test(grant.token)) throw new BalanceError('storage');
  return { token: grant.token, fingerprint: crypto.createHash('sha256').update(grant.token).digest('hex') };
}
function loadGrant() {
  const location = path.join(os.homedir(), '.dsh', '.credentials.yaml');
  let fd;
  try {
    fd = fs.openSync(location, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
    const info = fs.fstatSync(fd);
    if (!info.isFile() || info.size > 1048576 || (info.mode & 0o077) !== 0 || info.uid !== process.getuid()) throw new BalanceError('storage');
    const yamlPath = path.resolve(path.dirname(process.execPath), '../Resources/app.asar/dsh/node_modules/yaml');
    const { parseDocument } = require(yamlPath);
    const parsed = parseDocument(fs.readFileSync(fd, 'utf8'), { uniqueKeys: true, prettyErrors: false });
    if (parsed.errors.length) throw new BalanceError('storage');
    return grantFromDocument(parsed.toJS({ maxAliasCount: 20 }));
  } catch (error) {
    if (error instanceof BalanceError) throw error;
    throw new BalanceError(error?.code === 'ENOENT' ? 'login' : 'storage');
  } finally { if (fd !== undefined) fs.closeSync(fd); }
}
function parseWallets(payload, now = Date.now() / 1000) {
  if (payload?.code === 40003) throw new BalanceError('login');
  if (payload?.code !== 0 || payload?.data?.biz_code !== 0) throw new BalanceError('protocol');
  const summary = payload.data.biz_data;
  if (!Array.isArray(summary?.normal_wallets) || !Array.isArray(summary?.bonus_wallets) ||
      summary.normal_wallets.length === 0 || summary.normal_wallets.length > 2 || summary.bonus_wallets.length > 2) throw new BalanceError('protocol');
  const metrics = [];
  for (const [key, wallets, label] of [['balance', summary.normal_wallets, '账户余额'], ['bonus', summary.bonus_wallets, '赠送余额']]) {
    const currencies = new Set();
    for (const wallet of wallets) {
      if (!['CNY', 'USD'].includes(wallet?.currency) || currencies.has(wallet.currency) ||
          typeof wallet.balance !== 'string' || wallet.balance.length > 64 ||
          !/^-?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$/i.test(wallet.balance)) throw new BalanceError('protocol');
      currencies.add(wallet.currency);
      const value = Number(wallet.balance);
      if (!Number.isFinite(value) || Math.abs(value) > 1e12) throw new BalanceError('protocol');
      // Keep valid zero balances; omit an empty bonus row, never invent a total.
      if (key === 'bonus' && value === 0) continue;
      metrics.push({ id: key + '-' + wallet.currency, label, value,
        unit: wallet.currency === 'CNY' ? '元' : '美元', updatedAt: now });
    }
  }
  return metrics;
}
async function readBalance({ readGrant = loadGrant, fetcher = fetch } = {}) {
  const grant = readGrant();
  let response;
  try {
    response = await fetcher(ENDPOINT, { method: 'GET', headers: { 'x-dsh-auth-token': grant.token },
      redirect: 'error', signal: AbortSignal.timeout(10000) });
  } catch { throw new BalanceError('network'); }
  if (response.status === 401 || response.status === 403) throw new BalanceError('login');
  if (!response.ok || !response.body) throw new BalanceError('network');
  let size = 0; const chunks = [];
  for await (const chunk of response.body) {
    size += chunk.length;
    if (size > 65536) throw new BalanceError('protocol');
    chunks.push(chunk);
  }
  let payload;
  try { payload = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw new BalanceError('protocol'); }
  const metrics = parseWallets(payload);
  if (readGrant().fingerprint !== grant.fingerprint) throw new BalanceError('changed');
  return { ok: true, metrics };
}
function safeFailure(error) {
  return { ok: false, error: error instanceof BalanceError ? error.code : 'network' };
}
module.exports = { grantFromDocument, parseWallets, readBalance, safeFailure, BalanceError, ENDPOINT };
if (require.main === module) {
  readBalance().then(value => process.stdout.write(JSON.stringify(value)),
    error => process.stdout.write(JSON.stringify(safeFailure(error))));
}
