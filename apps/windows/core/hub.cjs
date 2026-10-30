'use strict';
// 虚实中台: OAuth PKCE client and read-only MCP calls (port of HubHelper/HubBackend.swift),
// card text shaping (Workspace/HubTypes.swift) and the 8-direction shortcut wheel
// preferences (Platform/UnifiedPlatformStore.swift + HubShortcutCatalog.swift).
const crypto = require('node:crypto');

const BUILTINS = [
  ['home', '首页'], ['okr', 'OKR'], ['library', '资料'], ['data', '数据'], ['exceptions', '异常项'], ['apps', '应用'], ['skills', 'Skill'], ['approval', '审批']
].map(([id, title]) => ({ id, title, url: id === 'approval' ? 'https://applink.feishu.cn/client/mini_program/open?appId=cli_9cb844403dbb9108&mode=appCenter' : 'https://virxact.net/' + (id === 'home' ? '' : id) }));

function safeURL(raw) {
  const value = String(raw || '').trim();
  if (!value || value.length > 2048 || /[\u0000-\u001f\u007f]/.test(value)) return null;
  let u; try { u = new URL(value); } catch { return null; }
  if (u.protocol !== 'https:' || !u.hostname || u.username || u.password) return null;
  for (const k of u.searchParams.keys()) if (['token', 'access_token', 'refresh_token', 'password', 'secret', 'api_key', 'authorization', 'code'].includes(k.toLowerCase())) return null;
  return u.href;
}

/** North is zero, clockwise 45° sectors (from LOLPingYourAI). */
function slice(dx, dy, deadZone = 55, outer = Infinity) {
  if (!Number.isFinite(dx) || !Number.isFinite(dy)) return null;
  const r = Math.hypot(dx, dy); if (r < deadZone || r > outer) return null;
  const angle = ((Math.atan2(dy, dx) * 180 / Math.PI + 90 + 22.5 + 360) % 360);
  return Math.floor(angle / 45) % 8;
}

function readable(value, depth = 0) {
  if (depth >= 20) return '内容层级过深，请打开中台查看。';
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  if (value === null || value === undefined) return '—';
  if (Array.isArray(value)) return value.map(v => readable(v, depth + 1)).join('\n');
  if (typeof value === 'object') {
    if (value.auth !== undefined) return '需要本人飞书授权，请打开中台完成。';
    if (value.forbidden !== undefined) return '本人没有此来源的读取权限。';
    if (value.error !== undefined) return '来源读取失败，请打开中台查看详情。';
    if (value.type === 'report') {
      const raw = typeof value.committedAt === 'string' ? value.committedAt : '';
      const d = Date.parse(raw); const stamp = Number.isFinite(d) ? new Date(d).toLocaleString('zh-CN', { dateStyle: 'medium', timeStyle: 'short' }) : raw;
      const items = (Array.isArray(value.items) ? value.items : []).map(i => (i && typeof i.name === 'string' ? i.name : '原汇报项目') + '\n' + (i && typeof i.value === 'string' ? i.value : '—')).join('\n\n');
      return (typeof value.rule === 'string' ? value.rule : '本人汇报') + (stamp ? ' · 提交于 ' + stamp : '') + (items ? '\n\n' + items : '\n暂无填写内容，以原汇报为准。');
    }
    if (typeof value.text === 'string') return value.text;
    if (value.props !== undefined) return readable(value.props, depth + 1);
    const skip = new Set(['type', 'view', 'format', 'limit', 'id', 'recordId', 'record_id', 'userId', 'user_id', 'appToken', 'tableId', 'avatar', 'url']);
    const labels = { text: '内容', title: '标题', name: '名称', value: '数值', items: '条目', columns: '内容', props: '详情', state: '读取状态', cycle: '周期', url: '来源', today: '日期', progress: '进度', label: '名称', rows: '明细', cards: '事项', tag: '状态', owner: '负责人', results: '关键结果', current: '当前', target: '目标', expected: '预期', standing: '状态', submittedAt: '提交时间', submitted_at: '提交时间', fields: '原文项目', period: '周期' };
    return Object.keys(value).sort().filter(k => !skip.has(k)).map(k => `${labels[k] || k}：${readable(value[k], depth + 1)}`).join('\n');
  }
  return '';
}

const META = new Set(['id', 'key', 'href', 'url', 'view', 'type', 'kind', 'kindLabel', 'live', 'editedAt', 'updatedAt', 'createdAt', 'created_at', 'createdBy', 'ownerAvatar', 'avatar', 'ownerId', 'recordId', 'record_id', 'userId', 'user_id', 'appToken', 'tableId', 'format', 'limit', 'committedAt', 'submittedAt', 'submitted_at', 'color', 'icon', 'source', 'schema', 'version']);
const SECTION_LABELS = { name: '名称', title: '标题', label: '名称', contract: '签约方式', level: '等级', platforms: '平台', followers: '粉丝', tags: '标签', status: '状态', state: '状态', count: '数量', total: '合计', value: '数值', current: '当前', target: '目标', expected: '预期', progress: '进度', owner: '负责人', date: '日期', start: '开始', end: '结束', period: '周期', cycle: '周期', standing: '状态', results: '关键结果', description: '说明', summary: '摘要', content: '内容', text: '内容', unit: '单位', rule: '项目', due: '截止时间', trend: '趋势' };
const CONTAINERS = new Set(['props', 'items', 'rows', 'entries', 'cards', 'data', 'fields', 'columns', 'list', 'records']);
const PRIORITY = ['contract', 'level', 'tags', 'status', 'state', 'value', 'current', 'target', 'progress', 'followers', 'platforms'];
const clean = t => t.replace(/https?:\/\/[^\s<>]+/g, '').trim();

function sections(value, depth = 0) {
  if (depth >= 20) return [{ title: '', text: '内容层级过深，请在中台查看完整内容。', children: [] }];
  if (Array.isArray(value)) return value.flatMap(v => sections(v, depth + 1));
  if (typeof value === 'string') { const c = clean(value); return c ? [{ title: '', text: c, children: [] }] : []; }
  if (typeof value === 'number') return [{ title: '', text: String(value), children: [] }];
  if (!value || typeof value !== 'object') return [];
  if (value.auth !== undefined) return [{ title: '', text: '请在中台完成本人授权。', children: [] }];
  if (value.forbidden !== undefined) return [{ title: '', text: '你没有此来源的读取权限。', children: [] }];
  if (value.error !== undefined) return [{ title: '', text: '来源读取失败，请稍后刷新。', children: [] }];
  const nameKey = ['name', 'title', 'label'].find(k => typeof value[k] === 'string');
  const title = nameKey ? clean(value[nameKey]) : '';
  const children = [];
  const keys = Object.keys(value).sort((a, b) => { const x = PRIORITY.indexOf(a), y = PRIORITY.indexOf(b); const xi = x < 0 ? 999 : x, yi = y < 0 ? 999 : y; return xi === yi ? (a < b ? -1 : a > b ? 1 : 0) : xi - yi; });
  for (const key of keys) {
    const lk = key.toLowerCase();
    if (key === nameKey || META.has(key) || lk.endsWith('token') || lk.endsWith('avatar') || lk.endsWith('url') || lk.endsWith('id')) continue;
    const parts = sections(value[key], depth + 1);
    if (!parts.length) continue;
    if (CONTAINERS.has(key)) { children.push(...parts); continue; }
    const label = SECTION_LABELS[key] || (/[^\x00-\x7f]/.test(key) ? key : '补充信息');
    if (parts.length === 1 && !parts[0].title && !parts[0].children.length) {
      let text = parts[0].text;
      if (key === 'followers' && Number(text) >= 10000) text = (Number(text) / 10000).toFixed(1).replace(/\.0$/, '') + ' 万';
      children.push({ title: label, text, children: [] });
    } else children.push({ title: label, text: '', children: parts });
  }
  return title ? [{ title, text: '', children }] : children;
}

function decodeApplications(value) {
  const top = Array.isArray(value.top) ? value.top : [], all = Array.isArray(value.all) ? value.all : [];
  const favorites = new Set(top.map(r => r && r.key).filter(x => typeof x === 'string'));
  const seen = new Set();
  return [...top, ...all].flatMap(r => {
    if (!r || typeof r.key !== 'string' || !r.key || r.key.length > 512 || typeof r.name !== 'string' || !r.name || r.name.length > 100 || typeof r.url !== 'string' || r.url.length > 2048) return [];
    if (!safeURL(r.url) || seen.has(r.key)) return [];
    seen.add(r.key); return [{ id: r.key, name: r.name, url: r.url, frequent: favorites.has(r.key) }];
  });
}

const isWorkPlan = card => ['工作周报', '周报', '工作计划', '下周工作计划', '本周工作计划'].some(t => card.title.includes(t));
const cardTitle = card => isWorkPlan(card) ? '工作计划' : card.title;

const b64url = buf => buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

class HubClient {
  /** @param {{loadGrant:()=>object|null, saveGrant:(g:object)=>void, clearGrant:()=>void, fetch?:typeof fetch}} o */
  constructor(o) { this.o = o; this.fetch = o.fetch || fetch; this.pending = null; this.session = null; this.rpcID = 0; this.epoch = 0; }
  async http(url, { json, form, bearer, extra = {} } = {}) {
    const u = new URL(url); if (u.protocol !== 'https:' || u.hostname !== 'virxact.net') throw new Error('中台地址不合法。');
    const headers = { Accept: 'application/json, text/event-stream', ...extra };
    let body;
    if (json) { body = JSON.stringify(json); headers['Content-Type'] = 'application/json'; }
    if (form) { body = Object.keys(form).sort().map(k => k + '=' + encodeURIComponent(form[k])).join('&'); headers['Content-Type'] = 'application/x-www-form-urlencoded'; }
    if (bearer) headers.Authorization = 'Bearer ' + bearer;
    const controller = new AbortController(); const t = setTimeout(() => controller.abort(), 30000);
    let r; try { r = await this.fetch(url, { method: 'POST', headers, body, redirect: 'error', signal: controller.signal, credentials: 'omit' }); }
    catch { throw new Error('中台暂时连不上，请检查网络后重试。'); } finally { clearTimeout(t); }
    const text = await r.text();
    if (text.length >= 4_000_000) throw new Error('中台响应超出范围。');
    if (!r.ok) throw new Error(r.status === 401 ? '中台授权已失效，请重新连接。' : `中台暂时无法读取（${r.status}），请稍后重试。`);
    return { text, headers: r.headers };
  }
  async begin(callback) {
    const c = new URL(callback);
    if (c.protocol !== 'http:' || c.hostname !== '127.0.0.1' || c.pathname !== '/oauth/virxact/callback') throw new Error('授权回调地址无效。');
    const { text } = await this.http('https://virxact.net/oauth/register', { json: { client_name: '一切在岛 Windows · 本机个人卡片', redirect_uris: [callback], grant_types: ['authorization_code', 'refresh_token'], response_types: ['code'], token_endpoint_auth_method: 'none' } });
    const client = JSON.parse(text).client_id; if (typeof client !== 'string') throw new Error('中台未返回客户端编号。');
    const state = b64url(crypto.randomBytes(32)), verifier = b64url(crypto.randomBytes(32));
    const challenge = b64url(crypto.createHash('sha256').update(verifier).digest());
    this.pending = { state, verifier, client, callback, date: Date.now() };
    const url = new URL('https://virxact.net/oauth/authorize');
    for (const [k, v] of Object.entries({ client_id: client, redirect_uri: callback, response_type: 'code', scope: 'hub', state, code_challenge: challenge, code_challenge_method: 'S256', resource: 'https://virxact.net/mcp' })) url.searchParams.set(k, v);
    return url.href;
  }
  async finish(params) {
    const p = this.pending, generation = this.epoch;
    if (!p || Date.now() - p.date >= 600000) throw new Error('授权请求已过期，请重新连接。');
    const state = params.get('state') || '';
    if (state.length !== p.state.length || !crypto.timingSafeEqual(Buffer.from(state), Buffer.from(p.state))) throw new Error('授权校验未通过。');
    this.pending = null;
    const code = params.get('code'); if (!code) throw new Error('未完成中台授权。');
    const { text } = await this.http('https://virxact.net/oauth/token', { form: { grant_type: 'authorization_code', client_id: p.client, code, redirect_uri: p.callback, code_verifier: p.verifier, resource: 'https://virxact.net/mcp' } });
    if (generation !== this.epoch) throw new Error('连接已断开，授权未保存。');
    this.o.saveGrant(this.decode(text, p.client, null)); this.session = null; this.epoch++;
  }
  decode(text, client, previous) {
    const v = JSON.parse(text); if (typeof v.access_token !== 'string' || !v.access_token) throw new Error('个人授权未成功。');
    return { clientID: client, access: v.access_token, refresh: typeof v.refresh_token === 'string' ? v.refresh_token : previous, expires: Date.now() + (Number.isInteger(v.expires_in) ? v.expires_in : 3600) * 1000 };
  }
  disconnect() { this.o.clearGrant(); this.pending = null; this.session = null; this.epoch++; }
  connected() { return !!this.o.loadGrant(); }
  async access() {
    const generation = this.epoch;
    let grant = this.o.loadGrant();
    if (!grant) throw new Error('请先连接本人虚实中台，读取你的飞书首页与数据。');
    if (grant.expires - Date.now() < 60000) {
      if (!grant.refresh) throw new Error('中台授权已过期，请重新连接。');
      const { text } = await this.http('https://virxact.net/oauth/token', { form: { grant_type: 'refresh_token', client_id: grant.clientID, refresh_token: grant.refresh } });
      if (generation !== this.epoch) throw new Error('连接已断开。');
      grant = this.decode(text, grant.clientID, grant.refresh); this.o.saveGrant(grant);
    }
    return grant.access;
  }
  async rpc(method, params, token, notification = false) {
    const id = ++this.rpcID;
    const object = { jsonrpc: '2.0', method, params }; if (!notification) object.id = id;
    const extra = { 'MCP-Protocol-Version': '2025-03-26' }; if (this.session) extra['Mcp-Session-Id'] = this.session;
    const { text, headers } = await this.http('https://virxact.net/mcp', { json: object, bearer: token, extra });
    const sid = headers.get('mcp-session-id'); if (sid) this.session = sid;
    if (notification) return {};
    let v;
    if ((headers.get('content-type') || '').includes('text/event-stream')) {
      const found = text.split('\n').filter(l => l.startsWith('data:')).map(l => { try { return JSON.parse(l.slice(5).trim()); } catch { return null; } }).filter(x => x && x.id === id);
      v = found[found.length - 1]; if (!v) throw new Error('中台未返回请求结果。');
    } else v = JSON.parse(text);
    if (!v || v.error || !v.result) throw new Error('中台请求未成功，请重新连接后重试。');
    return v.result;
  }
  async tool(name, args, token) {
    if (!['get_page', 'get_spec', 'list_home_applications'].includes(name)) throw new Error('本机仅允许读取个人卡片和应用入口。');
    const result = await this.rpc('tools/call', { name, arguments: args }, token);
    const text = result.isError ? null : (Array.isArray(result.content) ? (result.content.find(c => c && c.type === 'text') || {}).text : null);
    let value; try { value = JSON.parse(text); } catch { value = null; }
    if (!value || typeof value !== 'object') throw new Error('中台数据未读到，请在飞书检查本人权限。');
    return value;
  }
  async initialize(token) {
    if (this.session) return;
    await this.rpc('initialize', { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 'feishu-island', version: '0.7.0' } }, token);
    await this.rpc('notifications/initialized', {}, token, true);
  }
  async snapshot() {
    const generation = this.epoch;
    const token = await this.access(); await this.initialize(token);
    const snap = { connected: true, name: '', cards: [], applications: null, applicationsError: null, readAt: null };
    for (const kind of ['page', 'data']) {
      const page = await this.tool('get_page', { scope: 'me', kind, includeData: true }, token);
      snap.name = typeof page.name === 'string' ? page.name : '本人中台';
      (Array.isArray(page.data) ? page.data : []).forEach((entry, index) => {
        const title = entry && typeof entry.title === 'string' ? entry.title : '个人卡片';
        const result = entry && entry.result && typeof entry.result === 'object' ? entry.result : entry;
        snap.cards.push({ id: `${kind}:${title}:${index}`, title, kind: result && typeof result.type === 'string' ? result.type : '', text: readable(result), href: typeof page.view === 'string' ? page.view : null, sections: sections(result) });
      });
    }
    try {
      const apps = await this.tool('list_home_applications', {}, token);
      if (apps.auth !== undefined || apps.error !== undefined || apps.forbidden !== undefined) throw new Error();
      snap.applications = decodeApplications(apps);
    } catch { snap.applicationsError = '常用应用暂未读到，请刷新重试。'; }
    if (generation !== this.epoch) throw new Error('连接已改变，请重新刷新。');
    snap.readAt = Date.now() / 1000; return snap;
  }
}

// ---- shortcut wheel preferences ----
const SOURCES = ['automatic', 'builtin', 'application', 'settings', 'card', 'custom', 'empty'];
function defaultWheel() { return { version: 1, showInMainBar: true, soundEnabled: false, slots: Array.from({ length: 8 }, () => ({ source: 'automatic', cardID: '', title: '', address: '', icon: null })), hotkey: 'Control+Alt+Space' }; }
function validSlot(s) {
  return s && SOURCES.includes(s.source) && typeof s.cardID === 'string' && s.cardID.length <= 512 && typeof s.title === 'string' && [...s.title].length <= 40
    && typeof s.address === 'string' && (s.source !== 'custom' || (safeURL(s.address) && s.title.trim())) && (s.icon === null || s.icon === undefined || (typeof s.icon === 'string' && s.icon.startsWith('data:image/png;base64,') && s.icon.length < 400000));
}
function destinations(wheel, cards, apps) {
  return wheel.slots.map((s, id) => {
    let d;
    switch (s.source) {
      case 'automatic': d = { title: BUILTINS[id].title, url: BUILTINS[id].url }; break;
      case 'builtin': { const b = BUILTINS.find(x => x.id === s.cardID); d = b ? { title: b.title, url: b.url } : { title: '入口暂不可用', url: null }; break; }
      case 'application': { const a = (apps || []).find(x => x.id === s.cardID); d = a ? { title: a.name, url: safeURL(a.url) } : { title: '应用暂不可用', url: null }; break; }
      case 'settings': d = { title: '灵动岛设置', url: null, settings: true }; break;
      case 'card': { const c = (cards || []).find(x => x.id === s.cardID); d = c ? { title: cardTitle(c), url: c.href ? safeURL(c.href) : null } : { title: '卡片暂不可用', url: null }; break; }
      case 'custom': d = { title: s.title, url: safeURL(s.address) }; break;
      default: d = { title: '空位', url: null };
    }
    return { id, ...d, icon: s.icon || null, available: !!(d.url || d.settings) };
  });
}
function catalog(cards, apps) {
  return [
    ...BUILTINS.map(b => ({ id: 'builtin:' + b.id, title: b.title, group: '中台入口', slot: { source: 'builtin', cardID: b.id, title: '', address: '', icon: null } })),
    { id: 'settings', title: '灵动岛设置', group: '本机', slot: { source: 'settings', cardID: '', title: '', address: '', icon: null } },
    ...(apps || []).filter(a => safeURL(a.url)).map(a => ({ id: 'app:' + a.id, title: a.name, group: a.frequent ? '常用应用' : '全部应用', slot: { source: 'application', cardID: a.id, title: '', address: '', icon: null } })),
    ...(cards || []).filter(c => c.href && safeURL(c.href)).map(c => ({ id: 'card:' + c.id, title: cardTitle(c), group: '我的卡片', slot: { source: 'card', cardID: c.id, title: '', address: '', icon: null } }))
  ];
}

module.exports = { HubClient, BUILTINS, safeURL, slice, readable, sections, decodeApplications, cardTitle, defaultWheel, validSlot, destinations, catalog };
