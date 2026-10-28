const { test } = require('node:test');
const assert = require('node:assert/strict');
const { grantFromDocument, parseWallets, readBalance, safeFailure, ENDPOINT } = require('../Resources/deepseek-balance.cjs');
const token = 'synthetic-grant';
const document = () => ({ version: 1, records: { 'deepseek-account-platform/default': {
  kind: 'grant', payload: { version: 1, issuer: 'https://platform.deepseek.com', token }
} } });
const grant = () => grantFromDocument(document());
const payload = (balance = '42.38', bonus = '5.25') => ({ code: 0, data: { biz_code: 0, biz_data: {
  normal_wallets: [{ currency: 'CNY', balance }], bonus_wallets: [{ currency: 'CNY', balance: bonus }]
} } });
test('only the existing Harness Platform grant is admitted', () => {
  assert.equal(grant().token, token);
  const value = document(); value.records['deepseek-account-platform/default'].payload.issuer = 'https://example.com';
  assert.throws(() => grantFromDocument(value));
  assert.throws(() => grantFromDocument({ version: 1, refs: { DEEPSEEK_API_KEY: 'synthetic' } }));
  assert.throws(() => grantFromDocument({ version: 2 }));
});
test('ordinary and gifted balances stay separate, with currency and timestamp', () => {
  const metrics = parseWallets(payload(), 1700000000);
  assert.deepEqual(metrics.map(x => [x.label, x.value, x.unit]), [['账户余额', 42.38, '元'], ['赠送余额', 5.25, '元']]);
  assert.equal(metrics[0].updatedAt, 1700000000);
});
test('a real zero or negative wallet is preserved; empty bonus is omitted', () => {
  assert.equal(parseWallets(payload('0', '0'))[0].value, 0);
  assert.equal(parseWallets(payload('0', '0')).length, 1);
  assert.equal(parseWallets(payload('-0.25', '0'))[0].value, -0.25);
});
test('missing, duplicate, non-finite, or unrecognised balances never become zero', () => {
  for (const balance of ['', 'NaN', 'Infinity', '1e999', 'no balance']) assert.throws(() => parseWallets(payload(balance)));
  assert.throws(() => parseWallets({ code: 0, data: { biz_code: 0, biz_data: {} } }));
  const value = payload(); value.data.biz_data.normal_wallets.push({ currency: 'CNY', balance: '1' });
  assert.throws(() => parseWallets(value));
  const unknown = payload(); unknown.data.biz_data.normal_wallets[0].currency = 'XXX';
  assert.throws(() => parseWallets(unknown));
});
test('USD has a distinct display unit', () => {
  const value = payload(); value.data.biz_data.normal_wallets[0].currency = 'USD';
  assert.equal(parseWallets(value)[0].unit, '美元');
});
test('only the fixed GET endpoint receives the in-memory grant, redirects refused', async () => {
  const result = await readBalance({ readGrant: grant, fetcher: async (url, options) => {
    assert.equal(url, ENDPOINT); assert.equal(new URL(url).host, 'platform.deepseek.com');
    assert.equal(options.method, 'GET'); assert.equal(options.redirect, 'error');
    assert.equal(options.headers['x-dsh-auth-token'], token); assert.equal(options.body, undefined);
    return Response.json(payload());
  } });
  assert.equal(result.ok, true); assert.equal(result.metrics[0].value, 42.38);
  assert.ok(!JSON.stringify(result).includes(token));
});
test('logout or grant switch during a request discards the previous balance', async () => {
  let reads = 0;
  await assert.rejects(readBalance({ readGrant: () => ({ token, fingerprint: String(++reads) }), fetcher: async () => Response.json(payload()) }), /changed/);
});
test('HTTP and business authentication failures become login state', async () => {
  for (const status of [401, 403]) await assert.rejects(readBalance({ readGrant: grant, fetcher: async () => new Response('', { status }) }), /login/);
  assert.throws(() => parseWallets({ code: 40003 }), /login/);
  assert.throws(() => parseWallets({ code: 0, data: { biz_code: 1 } }), /protocol/);
});
test('oversized or malformed server replies are rejected', async () => {
  for (const text of ['invalid', 'x'.repeat(65537)]) await assert.rejects(readBalance({ readGrant: grant, fetcher: async () => new Response(text) }), /protocol/);
});
test('network failures never expose raw errors, headers or credentials', async () => {
  let error;
  try { await readBalance({ readGrant: grant, fetcher: async () => { throw new Error('secret: ' + token); } }); } catch (e) { error = e; }
  assert.deepEqual(safeFailure(error), { ok: false, error: 'network' });
  assert.ok(!JSON.stringify(safeFailure(new Error(token))).includes(token));
});
