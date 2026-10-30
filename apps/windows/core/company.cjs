'use strict';
// Pure parts of the company connection (see main/company.cjs). No Electron.
const ORIGIN = 'https://island.example.invalid';
const CONNECT_URL = ORIGIN + '/connect.html';
const PURPOSES = {
  receive: { serviceKey: 'receive', appID: 'cli_aa217b534af89cdc', scopes: 'auth:user.id:read im:chat:read im:chat.user_setting:read im:message.group_msg:get_as_user im:message.p2p_msg:get_as_user im:message:readonly offline_access' },
  calendar: { serviceKey: 'schedule', appID: 'cli_aa217b534af89cdc', scopes: 'auth:user.id:read calendar:calendar:read calendar:calendar.event:read offline_access' }
};
const setOf = s => new Set(s.split(/\s+/).filter(Boolean));
const sameSet = (a, b) => a.size === b.size && [...a].every(x => b.has(x));

class Failure extends Error {}

function allowedURL(raw) {
  try { const u = new URL(raw); return u.protocol === 'https:' && u.hostname === 'island.example.invalid' && (u.port === '' || u.port === '443') && !u.username && !u.password; }
  catch { return false; }
}

function decodeCredential(j, purpose, now = Date.now()) {
  const p = PURPOSES[purpose];
  if (!j || typeof j !== 'object' || j.appId !== p.appID || typeof j.access !== 'string' || !j.access || j.access.length >= 16384 || !/^[\x21-\x7e]+$/.test(j.access)
    || typeof j.scope !== 'string' || typeof j.userId !== 'string' || !j.userId || j.userId.length >= 200
    || typeof j.openId !== 'string' || !j.openId.startsWith('ou_') || j.openId.length >= 200
    || typeof j.expires !== 'number' || !Number.isFinite(j.expires) || j.expires <= now + 30000 || j.expires >= now + 172800000) {
    throw new Failure('公司连接返回不完整，请重新打开连接页。');
  }
  if (!sameSet(setOf(j.scope), setOf(p.scopes))) throw new Failure('公司连接权限范围不符，未用于本机。');
  return { appID: j.appId, access: j.access, scope: j.scope, userID: j.userId, openID: j.openId, userName: String(typeof j.userName === 'string' ? j.userName : '已连接账号').slice(0, 120), expires: j.expires };
}

const CLI_AUTH_KEYS = ['LARKSUITE_CLI_APP_ID', 'LARKSUITE_CLI_APP_SECRET', 'LARKSUITE_CLI_USER_ACCESS_TOKEN', 'LARKSUITE_CLI_TENANT_ACCESS_TOKEN', 'LARKSUITE_CLI_TENANT_ACCESS_TOKEN_SOURCE', 'LARKSUITE_CLI_PROFILE', 'LARKSUITE_CLI_DEFAULT_AS', 'LARKSUITE_CLI_STRICT_MODE', 'LARKSUITE_CLI_BRAND', 'LARKSUITE_CLI_AUTH_PROXY', 'LARKSUITE_CLI_PROXY_KEY'];
/** Official lark-cli 1.0.96 token-only environment; no profile or secret is written. */
function cliEnvironment(credential, original, configDir) {
  const env = { ...original };
  for (const k of CLI_AUTH_KEYS) delete env[k];
  Object.assign(env, {
    LARKSUITE_CLI_APP_ID: credential.appID, LARKSUITE_CLI_USER_ACCESS_TOKEN: credential.access,
    LARKSUITE_CLI_BRAND: 'feishu', LARKSUITE_CLI_DEFAULT_AS: 'user', LARKSUITE_CLI_STRICT_MODE: 'user',
    LARKSUITE_CLI_CONFIG_DIR: configDir, LARKSUITE_CLI_NO_UPDATE_NOTIFIER: '1', LARKSUITE_CLI_NO_SKILLS_NOTIFIER: '1'
  });
  return env;
}


module.exports = { ORIGIN, CONNECT_URL, PURPOSES, Failure, allowedURL, decodeCredential, cliEnvironment, setOf, sameSet };
