'use strict';
// Windows counterpart of Feishu/CompanyConnection.swift.
// The company gateway owns login inside a private persistent partition; this app
// only calls the same-origin /api/auth/* endpoints from that page, exactly like the
// Mac WKWebView. Access tokens stay in memory; refresh tokens never leave the server.
const { EventEmitter } = require('node:events');
const path = require('node:path');
const { BaseWindow, WebContentsView, shell, session } = require('electron');

const { ORIGIN, CONNECT_URL, PURPOSES, Failure, allowedURL, decodeCredential, cliEnvironment, setOf, sameSet } = require('../core/company.cjs');

class CompanyConnection extends EventEmitter {
  constructor({ prefs, preload, uiFile, icon }) {
    super();
    this.prefs = prefs; this.preload = preload; this.uiFile = uiFile; this.icon = icon;
    this.cached = {}; this.errors = {};
    this.view = null; this.window = null; this.ui = null;
    this.pageReady = false; this.loading = false; this.generation = 0;
    this.state = { purpose: 'receive', configured: false, granted: false, connected: false, busy: false, checking: false, feedback: '正在核对当前账号的授权状态…', loginError: null };
    this.flow = null; this.flowURL = null; this.pollTimer = null; this.attempt = 0;
    this.continueHandlers = {}; // purpose -> async () => void
  }
  partition() { return 'persist:company-' + this.prefs.get('company.store', 'default'); }
  isEnabled(p) { return this.prefs.get(`company.${p}.enabled`, false) === true; }
  setEnabled(p, value) { this.prefs.set(`company.${p}.enabled`, !!value); delete this.cached[p]; if (value) this.ensureView(); }
  publish() { this.emit('change', this.snapshot()); if (this.ui && !this.ui.webContents.isDestroyed()) this.ui.webContents.send('island:company', this.snapshot()); }
  snapshot() {
    const result = { ...this.state, pageReady: this.pageReady, purposes: {} };
    for (const p of Object.keys(PURPOSES)) result.purposes[p] = { enabled: this.isEnabled(p), connected: !!(this.cached[p] && this.cached[p].expires > Date.now()), error: this.errors[p] || '', bound: !!this.prefs.get('company.user') };
    return result;
  }
  setState(patch) { Object.assign(this.state, patch); this.publish(); }

  // ---- hidden company page ----
  ensureView() {
    if (this.view && !this.view.webContents.isDestroyed()) return;
    const ses = session.fromPartition(this.partition());
    ses.setPermissionRequestHandler((_wc, _perm, cb) => cb(false));
    this.view = new WebContentsView({ webPreferences: { session: ses, sandbox: true, contextIsolation: true, nodeIntegration: false, javascript: true } });
    const wc = this.view.webContents;
    wc.setWindowOpenHandler(({ url }) => {
      try { const u = new URL(url); if (u.protocol === 'https:' && u.hostname === 'accounts.feishu.cn' && !u.username) shell.openExternal(url); } catch {}
      return { action: 'deny' };
    });
    wc.on('will-navigate', (event, url) => { try { const u = new URL(url); if (u.protocol !== 'https:' || u.username || u.password) event.preventDefault(); } catch { event.preventDefault(); } });
    wc.on('did-start-navigation', (_e, _url, inPlace, isMain) => {
      if (!isMain || inPlace) return;
      this.loading = true; this.pageReady = false; this.cached = {}; this.generation++;
      this.setState({ loginError: null, connected: false });
    });
    wc.on('did-finish-load', () => {
      this.loading = false;
      const url = wc.getURL();
      this.pageReady = allowedURL(url) && new URL(url).pathname === '/connect.html';
      this.layout();
      if (this.pageReady && this.window) this.refreshStatus();
      this.publish();
      this.emit('pageReady');
    });
    wc.on('did-fail-load', (_e, code, _d, _u, isMain) => {
      if (!isMain || code === -3) return;
      this.loading = false; this.pageReady = false;
      this.setState({ loginError: '连接页面暂时打不开，请检查网络后重试。' });
      this.layout();
    });
    wc.on('render-process-gone', () => { this.view = null; this.pageReady = false; this.cached = {}; this.publish(); });
    this.loading = true;
    wc.loadURL(CONNECT_URL, { extraHeaders: 'pragma: no-cache\n' });
  }
  async pageCall(code, args) {
    this.ensureView();
    if (this.loading) await new Promise((resolve, reject) => { const t = setTimeout(() => reject(new Failure('公司登录未就绪，请打开连接页完成登录。')), 20000); this.once('pageReady', () => { clearTimeout(t); resolve(); }); });
    const wc = this.view.webContents;
    if (!allowedURL(wc.getURL()) || new URL(wc.getURL()).pathname !== '/connect.html') throw new Failure('请先完成公司账号登录。');
    const epoch = this.generation;
    const script = `(async (args) => { ${code} })(${JSON.stringify(args)})`;
    const result = await wc.executeJavaScript(script, true);
    if (epoch !== this.generation || !allowedURL(wc.getURL())) throw new Failure('登录状态已变化，请重新检查授权。');
    if (!result || typeof result !== 'object') throw new Failure('授权服务返回不完整，请重试。');
    return result;
  }
  async request(route, payload) {
    if (!['status', 'start', 'poll', 'cancel'].includes(route)) throw new Failure('unknown route');
    const code = `
      if (location.origin !== '${ORIGIN}' || location.pathname !== '/connect.html') throw new Error('origin');
      const controller = new AbortController(); const timer = setTimeout(() => controller.abort(), 16000);
      try {
        const payload = args.payload;
        const response = await fetch('/api/auth/' + args.route, {method: payload ? 'POST' : 'GET', credentials: 'same-origin', cache: 'no-store', redirect: 'error', headers: payload ? {'Content-Type': 'application/json', 'X-Island-Auth': '1'} : {}, body: payload ? JSON.stringify(payload) : undefined, signal: controller.signal});
        if (!response.ok) return {authorizationFailure: response.status};
        return await response.json();
      } finally { clearTimeout(timer); }`;
    const response = await this.pageCall(code, { route, payload: payload || null });
    if (typeof response.authorizationFailure === 'number') {
      const s = response.authorizationFailure;
      if (route === 'cancel' && s === 404) return { cancelled: true };
      if (route === 'poll' && (s === 404 || s === 410)) { const e = new Failure('expired'); e.kind = 'expired'; throw e; }
      if (s === 401) { this.pageReady = false; this.setState({ connected: false, loginError: null }); this.layout(); const e = new Failure('公司登录已过期，请重新登录后继续。'); e.kind = 'login'; throw e; }
      if (s === 403) { const e = new Failure('forbidden'); e.kind = 'forbidden'; throw e; }
      const e = new Failure('unavailable'); e.kind = 'unavailable'; throw e;
    }
    return response;
  }

  // ---- credentials ----
  async fetchAccess(purpose) {
    const p = PURPOSES[purpose];
    const code = `
      if (location.origin !== '${ORIGIN}') throw new Error('origin');
      const controller = new AbortController(); const timer = setTimeout(() => controller.abort(), 16000);
      try { const r = await fetch('/api/auth/access', {method:'POST', credentials:'same-origin', cache:'no-store', redirect:'error', headers:{'Content-Type':'application/json','X-Island-Auth':'1'}, body: JSON.stringify({purpose: args.purpose}), signal: controller.signal});
        if (!r.ok) { let j; try { j = await r.json(); } catch { j = {}; } return {failure: r.status, scopeMismatch: typeof j.error === 'string' && j.error.startsWith('飞书返回权限与本次用途不一致')}; }
        return await r.json();
      } finally { clearTimeout(timer); }`;
    const json = await this.pageCall(code, { purpose: p.serviceKey });
    if (typeof json.failure === 'number') {
      throw new Failure(json.scopeMismatch ? '授权服务返回了超出当前用途的权限，电脑已拒绝连接。请维护者修复服务端权限收窄，无需反复登录。'
        : json.failure === 401 ? '公司登录或飞书授权已失效，请打开连接页重新连接。'
          : json.failure === 403 ? '授权服务拒绝电脑连接（403），请维护者检查访问权限。' : '公司连接暂时不可用，请稍后重试。');
    }
    return decodeCredential(json, purpose);
  }
  validateBound(c, purpose) {
    const user = this.prefs.get('company.user'), open = this.prefs.get(`company.${purpose}.openID`);
    if (user && user !== c.userID) throw new Failure('公司账号已切换，已停止连接。请先停用连接，再明确更换账号。');
    if (open && open !== c.openID) throw new Failure('飞书账号已切换，已停止连接。请先停用连接，再明确更换账号。');
  }
  /** Credential for a running consumer; refreshed from the company page when near expiry. */
  async credential(purpose) {
    if (!this.isEnabled(purpose)) throw new Failure('尚未启用此项公司连接。');
    const hit = this.cached[purpose];
    if (hit && hit.expires > Date.now() + 120000) return hit;
    if (!this.inflight) this.inflight = {};
    if (!this.inflight[purpose]) {
      this.inflight[purpose] = (async () => {
        try {
          const c = await withTimeout(this.fetchAccess(purpose), 25000, '公司连接超时，请打开连接页检查登录。');
          this.validateBound(c, purpose);
          if (!this.prefs.get('company.user') || !this.prefs.get(`company.${purpose}.openID`)) throw new Failure('公司连接未完成启用，请从设置页确认。');
          this.cached[purpose] = c; delete this.errors[purpose]; this.publish();
          return c;
        } catch (error) {
          delete this.cached[purpose]; this.errors[purpose] = error instanceof Failure ? error.message : '公司连接暂不可用。'; this.publish();
          throw error;
        } finally { delete this.inflight[purpose]; }
      })();
    }
    return this.inflight[purpose];
  }
  /** Explicit activation after the user finished authorization in the window. */
  async prepare(purpose) {
    const c = await withTimeout(this.fetchAccess(purpose), 25000, '公司登录未就绪，请打开连接页完成登录。');
    this.validateBound(c, purpose);
    return c;
  }
  activate(c, purpose) {
    const p = PURPOSES[purpose];
    if (c.appID !== p.appID || !sameSet(setOf(c.scope), setOf(p.scopes)) || c.expires <= Date.now() + 30000) throw new Failure('公司连接已过期或用途不符，请重新核对。');
    this.validateBound(c, purpose);
    this.prefs.set('company.user', c.userID); this.prefs.set(`company.${purpose}.openID`, c.openID); this.prefs.set(`company.${purpose}.enabled`, true);
    this.cached[purpose] = c; delete this.errors[purpose];
    if (this.state.purpose === purpose) this.setState({ granted: true, connected: true, feedback: '已核实本人授权，电脑连接已完成。消息是否接收以设置中的开关为准。' });
    else this.publish();
  }
  reset() {
    for (const p of Object.keys(PURPOSES)) this.prefs.set(`company.${p}.enabled`, false);
    this.cancelAuthorization();
    this.cached = {}; this.errors = {}; this.generation++;
    this.prefs.remove('company.user');
    for (const p of Object.keys(PURPOSES)) this.prefs.remove(`company.${p}.openID`);
    const old = this.partition();
    this.prefs.set('company.store', require('node:crypto').randomUUID());
    session.fromPartition(old).clearStorageData().catch(() => {});
    if (this.view) { this.view.webContents.close(); this.view = null; }
    this.pageReady = false;
    this.setState({ granted: false, connected: false, configured: false, feedback: '连接已重置，请登录自己的账号后继续。' });
  }

  // ---- authorization window ----
  open(purpose = 'receive') {
    if (this.state.busy && this.state.purpose !== purpose) { this.window && this.window.focus(); return; }
    if (this.state.purpose !== purpose) this.setState({ purpose, configured: false, granted: false, connected: false, feedback: '正在核对这项用途的授权状态…' });
    this.connectAfterStatus = !this.state.busy;
    this.ensureView();
    if (!this.window) {
      this.window = new BaseWindow({ width: 540, height: 640, minWidth: 480, minHeight: 540, title: '连接飞书 · 一切在岛', icon: this.icon, autoHideMenuBar: true, show: false });
      this.ui = new WebContentsView({ webPreferences: { preload: this.preload, sandbox: true, contextIsolation: true, nodeIntegration: false } });
      this.ui.webContents.loadFile(this.uiFile, { hash: 'connect' });
      this.ui.webContents.once('did-finish-load', () => this.publish());
      this.window.contentView.addChildView(this.ui);
      this.window.on('resize', () => this.layout());
      this.window.on('closed', () => {
        this.window = null; this.ui = null; this.connectAfterStatus = false;
        if (this.view && !this.view.webContents.isDestroyed()) { try { this.view.setVisible(false); } catch {} }
        this.cancelAuthorization();
        this.emit('windowClosed', this.state.purpose);
      });
      this.window.once('ready-to-show', () => this.window && this.window.show());
      setTimeout(() => this.window && !this.window.isVisible() && this.window.show(), 300);
    }
    this.layout(); this.window.show(); this.window.focus();
    if (this.pageReady) this.refreshStatus();
  }
  layout() {
    if (!this.window) return;
    const { width, height } = this.window.getContentBounds();
    const loginVisible = !this.pageReady && !this.state.loginError && this.view;
    const header = 128;
    this.ui.setBounds({ x: 0, y: 0, width, height: loginVisible ? header : height });
    if (this.view) {
      if (loginVisible) {
        if (!this.window.contentView.children.includes(this.view)) this.window.contentView.addChildView(this.view);
        this.view.setVisible(true);
        this.view.setBounds({ x: 0, y: header, width, height: Math.max(0, height - header) });
      } else if (this.window.contentView.children.includes(this.view)) {
        this.view.setVisible(false);
      }
    }
    if (this.ui) this.ui.webContents.send('island:company', this.snapshot());
  }
  async refreshStatus() {
    if (!this.pageReady) return;
    const purpose = this.state.purpose, epoch = this.generation;
    try {
      const response = await this.request('status');
      if (epoch !== this.generation || purpose !== this.state.purpose) return;
      const st = response[PURPOSES[purpose].serviceKey];
      if (!st || typeof st !== 'object') { this.setState({ configured: false, feedback: '日历连接服务正在升级，请稍后重试。无需创建应用或填写配置。' }); return; }
      const configured = st.configured === true, granted = st.authorized === true;
      const connected = granted && !!(this.cached[purpose] && this.cached[purpose].expires > Date.now());
      const patch = { configured, granted, connected };
      if (!this.state.busy) patch.feedback = !configured ? '这项连接暂不可用，请联系应用维护者。' : connected ? '已核实本人授权，电脑连接已完成。' : granted ? '飞书授权已保存。点下方按钮核对电脑连接，成功后会显示连接结果。' : '点击下方按钮，在飞书核对自己的账号并确认。完成后这里会自动更新。';
      this.setState(patch);
      if (this.connectAfterStatus && configured && !this.state.busy) {
        this.connectAfterStatus = false;
        if (granted) this.continueConnection(); else this.beginAuthorization();
      }
    } catch (error) {
      if (epoch !== this.generation || purpose !== this.state.purpose) return;
      this.setState({ configured: false, feedback: error.kind === 'login' ? '公司登录已过期，请重新登录后继续。' : error.kind === 'forbidden' ? '授权服务拒绝访问（403）。请联系应用维护者核对账号访问权限。' : '暂时无法核对授权状态，请稍后重新检查。' });
    }
  }
  async beginAuthorization() {
    if (!this.pageReady || !this.state.configured || this.state.busy) return;
    const purpose = this.state.purpose, attempt = ++this.attempt;
    this.setState({ busy: true, granted: false, connected: false, feedback: '正在准备飞书授权页…' });
    try {
      const started = await this.request('start', { purpose: PURPOSES[purpose].serviceKey });
      if (attempt !== this.attempt) { if (typeof started.flow === 'string') this.request('cancel', { flow: started.flow }).catch(() => {}); return; }
      let url;
      try { url = new URL(started.url); } catch { url = null; }
      if (typeof started.flow !== 'string' || !started.flow || !url || url.protocol !== 'https:' || url.hostname !== 'accounts.feishu.cn' || url.port || url.username || url.password) throw new Failure('飞书授权信息不完整，请重试。');
      this.flow = started.flow; this.flowURL = url.href;
      this.setState({ feedback: '请在浏览器里的飞书页面确认。授权完成后无需复制任何内容。' });
      this.reopenAuthorization();
      let interval = Math.max(5, Math.min(60, Number(started.interval) || 5));
      const deadline = Date.now() + 600000;
      const flow = this.flow;
      while (attempt === this.attempt && this.flow === flow && Date.now() < deadline) {
        await new Promise(r => { this.pollTimer = setTimeout(r, interval * 1000); });
        if (attempt !== this.attempt || this.flow !== flow) return;
        const result = await this.request('poll', { flow });
        if (attempt !== this.attempt || this.flow !== flow) return;
        if (result.state === 'authorized') {
          this.flow = null; this.flowURL = null; this.setState({ busy: false });
          await this.refreshStatus();
          this.setState({ feedback: this.state.connected ? '已完成飞书授权和电脑连接。' : '飞书授权已完成。电脑正在核对连接，请稍候。' });
          if (this.state.granted && !this.state.connected) this.continueConnection();
          if (this.window) this.window.focus();
          return;
        }
        interval = Math.max(5, Math.min(60, Number(result.interval) || interval));
      }
      if (attempt === this.attempt) this.setState({ feedback: '本次授权已超时。可以取消后重新开始。' });
    } catch (error) {
      if (attempt !== this.attempt) return;
      if (error.kind === 'expired') { this.flow = null; this.flowURL = null; this.setState({ busy: false, feedback: '本次授权已过期，请重新开始。' }); return; }
      this.setState({ feedback: '授权尚未完成，可能已取消、过期或网络中断。可以重新检查，或取消后重试。' });
    }
    if (attempt === this.attempt) this.setState({ busy: this.flow !== null });
  }
  reopenAuthorization() { if (this.flowURL) shell.openExternal(this.flowURL).catch(() => this.setState({ feedback: '未能打开浏览器，可点“重新打开飞书授权页”再试。' })); }
  async checkProgress() {
    const flow = this.flow; if (!flow || this.state.checking) return;
    this.setState({ checking: true });
    try {
      const result = await this.request('poll', { flow });
      if (this.flow !== flow) return;
      if (result.state === 'authorized') {
        clearTimeout(this.pollTimer); this.attempt++; this.flow = null; this.flowURL = null; this.setState({ busy: false });
        await this.refreshStatus();
        if (this.state.granted && !this.state.connected) this.continueConnection();
      } else this.setState({ feedback: '仍在等待飞书确认。完成后会自动核对，也可以稍后再检查。' });
    } catch (error) {
      if (this.flow !== flow) return;
      if (error.kind === 'expired') { clearTimeout(this.pollTimer); this.attempt++; this.flow = null; this.flowURL = null; this.setState({ busy: false, feedback: '本次授权已过期，请重新开始。' }); }
      else this.setState({ feedback: '暂未取得授权结果。请检查网络，稍后重新检查或取消。' });
    } finally { this.setState({ checking: false }); }
  }
  cancelAuthorization() {
    const attempt = ++this.attempt; clearTimeout(this.pollTimer);
    const flow = this.flow;
    if (!flow) { if (this.state.busy) this.setState({ busy: false }); return; }
    this.request('cancel', { flow }).then(async () => {
      if (attempt !== this.attempt || this.flow !== flow) return;
      this.flow = null; this.flowURL = null; this.setState({ busy: false });
      await this.refreshStatus();
      this.setState({ feedback: '本次授权已取消，已有授权不会被撤销。' });
    }).catch(() => { if (attempt === this.attempt && this.flow === flow) this.setState({ feedback: '暂时无法取消，请重新检查连接后再试。' }); });
  }
  continueConnection() {
    const handler = this.continueHandlers[this.state.purpose];
    if (!handler) { this.setState({ feedback: '这项连接组件尚未就绪，请稍后重新核对连接。' }); return; }
    this.setState({ feedback: '飞书授权已完成，正在核对电脑连接…' });
    Promise.resolve(handler()).then(() => this.refreshStatus()).catch(error => this.setState({ connected: false, feedback: error.message || '连接未完成，请重试。' }));
  }
  reportFailure(message) { this.setState({ connected: false, feedback: message }); }
  reloadLogin() {
    this.pageReady = false; this.setState({ loginError: null });
    this.ensureView(); this.view.webContents.loadURL(CONNECT_URL);
    this.layout();
  }
  close() { if (this.window) this.window.close(); }
}

function withTimeout(promise, ms, message) {
  let t; return Promise.race([promise, new Promise((_, reject) => { t = setTimeout(() => reject(new Failure(message)), ms); })]).finally(() => clearTimeout(t));
}

module.exports = { CompanyConnection, Failure, PURPOSES, cliEnvironment };
