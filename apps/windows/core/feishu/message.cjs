'use strict';
// Port of apps/island Feishu/FeishuMessage.swift and AccountReader text helpers.
// Pure data: no network, no Electron, no logging of message bodies.

const ID_PATTERN = /^[A-Za-z0-9_]+$/;

function messageDate(value) {
  let n = null;
  if (typeof value === 'string' && value.trim() !== '' && Number.isFinite(Number(value))) n = Number(value);
  else if (typeof value === 'number' && Number.isFinite(value)) n = value;
  if (n === null) return null;
  return new Date(n > 100_000_000_000 ? n : n * 1000);
}

function plainText(input) {
  if (!/<\/?(?:p|div|span|br|strong|em|b|i|a)(?:\s[^>]*|\s*\/?)>/i.test(input)) return input;
  let value = input.replace(/<(?:br\s*\/?|\/p|\/div)>/gi, '\n');
  value = value.replace(/<\/?(?:p|div|span|strong|em|b|i|a)(?:\s[^>]*)?>/gi, '');
  for (const [entity, decoded] of [['&nbsp;', ' '], ['&lt;', '<'], ['&gt;', '>'], ['&quot;', '"'], ['&#39;', "'"], ['&amp;', '&']]) {
    value = value.split(entity).join(decoded);
  }
  return value.trim();
}

const LABELS = { image: '图片', file: '文件', audio: '语音', media: '视频', video: '视频', sticker: '表情', interactive: '卡片', merge_forward: '合并转发', share_chat: '分享会话', share_user: '分享联系人' };

function messageText(message) {
  const kind = typeof message.msg_type === 'string' ? message.msg_type : '消息';
  const raw = message.body && typeof message.body.content === 'string' ? message.body.content : null;
  let content = null;
  if (raw !== null) { try { content = JSON.parse(raw); } catch { content = null; } }
  if (!content || typeof content !== 'object' || Array.isArray(content)) return `[${kind}]`;
  if (kind === 'text') return plainText(typeof content.text === 'string' ? content.text : '[文字]');
  if (kind === 'post') {
    const localized = (content.zh_cn && typeof content.zh_cn === 'object' ? content.zh_cn : null) || (content.en_us && typeof content.en_us === 'object' ? content.en_us : null) || content;
    const title = typeof localized.title === 'string' ? localized.title : '';
    const rows = Array.isArray(localized.content) ? localized.content : [];
    const lines = rows.map(row => (Array.isArray(row) ? row : []).map(element => {
      if (!element || typeof element !== 'object') return '';
      if (typeof element.text === 'string') return element.text;
      switch (element.tag) {
        case 'at': return element.user_id === 'all' ? '@所有人' : '@' + (typeof element.user_name === 'string' ? element.user_name : '成员');
        case 'img': return '[图片]';
        case 'media': return '[视频]';
        default: return '';
      }
    }).join(''));
    return [title, ...lines].filter(Boolean).join('\n');
  }
  if (kind === 'interactive') {
    const copy = value => {
      if (typeof value === 'string') return [value];
      if (Array.isArray(value)) return value.flatMap(copy);
      if (!value || typeof value !== 'object') return [];
      for (const key of ['i18n_elements', 'i18n_body', 'i18n_content']) {
        const locales = value[key];
        if (locales && typeof locales === 'object' && !Array.isArray(locales)) {
          const sorted = Object.keys(locales).sort();
          const localized = locales.zh_cn ?? locales.en_us ?? (sorted.length ? locales[sorted[0]] : undefined);
          if (localized !== undefined) {
            const rest = { ...value };
            delete rest[key]; delete rest[key.replace('i18n_', '')];
            return [...copy(rest), ...copy(localized)];
          }
        }
      }
      const localized = value.zh_cn ?? value.en_us;
      if (localized !== undefined) return copy(localized);
      const parts = [];
      for (const key of ['header', 'title', 'subtitle', 'text', 'content', 'elements', 'fields', 'columns', 'items', 'body', 'rows']) {
        if (!(key in value)) continue;
        const item = value[key];
        if (typeof item === 'string') { if (item) parts.push(item); }
        else parts.push(...copy(item));
      }
      return parts;
    };
    const parts = copy(content);
    if (parts.length) return plainText(parts.join('\n'));
  }
  const label = LABELS[kind] || kind;
  if (typeof content.file_name === 'string') return `[${label}] ${content.file_name}`;
  return `[${label}]`;
}

const ALL_TOKEN = /(?<![A-Za-z0-9_@])@_all(?![A-Za-z0-9_])/g;

function hasAllTag(value) {
  if (Array.isArray(value)) return value.some(hasAllTag);
  if (!value || typeof value !== 'object') return false;
  if (value.tag === 'at' && value.user_id === 'all') return true;
  return Object.values(value).some(hasAllTag);
}

function createMessage(raw, chatID, chatName, chatKind, ownID) {
  const sender = raw.sender && typeof raw.sender === 'object' ? raw.sender : {};
  const senderType = typeof sender.id_type === 'string' ? sender.id_type : 'open_id';
  let senderID = '';
  if (sender.id && typeof sender.id === 'object') senderID = typeof sender.id.open_id === 'string' ? sender.id.open_id : '';
  else if (senderType === 'open_id' && typeof sender.id === 'string') senderID = sender.id;
  const senderName = typeof sender.sender_name === 'string' ? sender.sender_name : (chatKind === 'p2p' ? chatName : '群成员');
  const created = messageDate(raw.create_time) || new Date();
  const mentions = Array.isArray(raw.mentions) ? raw.mentions.filter(m => m && typeof m === 'object') : [];
  const mentionsMe = !!ownID && mentions.some(m => {
    if (m.id && typeof m.id === 'object') return m.id.open_id === ownID;
    return m.id === ownID && (m.id_type || 'open_id') === 'open_id';
  });
  let body = messageText(raw);
  const structuredAll = mentions.some(m => (m.id && typeof m.id === 'object') ? ['open_id', 'user_id', 'union_id'].some(k => m.id[k] === 'all') : m.id === 'all');
  let postContent = null;
  if (raw.msg_type === 'post' && raw.body && typeof raw.body.content === 'string') { try { postContent = JSON.parse(raw.body.content); } catch { postContent = null; } }
  const mentionsAll = structuredAll || (postContent !== null && hasAllTag(postContent)) || new RegExp(ALL_TOKEN.source).test(body);
  body = body.replace(ALL_TOKEN, '@所有人');
  for (const m of mentions) {
    if (typeof m.key === 'string' && m.key && typeof m.name === 'string') body = body.split(m.key).join('@' + m.name);
  }
  return {
    id: typeof raw.message_id === 'string' ? raw.message_id : cryptoRandomID(),
    chatID, chatName, chatKind, senderName, senderID,
    text: body,
    created: created.toISOString(),
    mentionsMe, mentionsAll,
    viewed: false, remindAt: null, reminded: false
  };
}

function cryptoRandomID() { return 'local_' + require('node:crypto').randomUUID(); }

// ---- Reminder rules (FeishuReminderRules / FeishuCustomRules) ----

function defaultRules() { return { mentionsMe: true, mentionsAll: true, directMessages: true, followedChats: true }; }
function defaultCustomRules() { return { conversations: [], people: [], groups: [], blockedPeople: [], blockedGroups: [] }; }

function normalizeCustom(input) {
  const base = defaultCustomRules();
  if (!input || typeof input !== 'object') return base;
  for (const key of Object.keys(base)) if (Array.isArray(input[key])) base[key] = input[key];
  return base;
}

function consolidate(custom, followed) {
  const next = normalizeCustom(JSON.parse(JSON.stringify(custom)));
  for (const target of next.blockedPeople) {
    next.people = next.people.filter(r => r.target.id !== target.id);
    next.people.push({ target, mode: 'quiet' });
  }
  for (const target of next.blockedGroups) {
    next.groups = next.groups.filter(r => r.target.id !== target.id);
    next.conversations = next.conversations.filter(r => r.target.id !== target.id);
    next.conversations.push({ target, mode: 'quiet' });
  }
  next.blockedPeople = []; next.blockedGroups = [];
  for (const item of next.groups) if (!next.conversations.some(r => r.target.id === item.target.id)) next.conversations.push(item);
  next.groups = [];
  for (const id of [...followed].sort()) {
    if (!next.conversations.some(r => r.target.id === id) && id.startsWith('oc_')) {
      next.conversations.push({ target: { id, name: '原会话提醒', detail: '刷新会话列表后显示名称' }, mode: 'all' });
    }
  }
  return next;
}

function blocks(custom, message) {
  return custom.blockedGroups.some(t => t.id === message.chatID) || (!!message.senderID && custom.blockedPeople.some(t => t.id === message.senderID));
}

function validationError(custom) {
  const buckets = [[custom.conversations.map(r => r.target), 'oc_'], [custom.people.map(r => r.target), 'ou_'], [custom.groups.map(r => r.target), 'oc_'], [custom.blockedPeople, 'ou_'], [custom.blockedGroups, 'oc_']];
  if (buckets.reduce((n, [t]) => n + t.length, 0) > 500) return '最多保存500项会话提醒设置。';
  for (const [targets, prefix] of buckets) {
    if (new Set(targets.map(t => t && t.id)).size !== targets.length) return '同一对象存在重复规则。';
    for (const t of targets) {
      if (!t || typeof t.id !== 'string' || !t.id.startsWith(prefix) || t.id.length <= prefix.length || t.id.length > 128 || !ID_PATTERN.test(t.id)
        || typeof t.name !== 'string' || !t.name.trim() || [...t.name].length > 120 || (t.detail !== undefined && (typeof t.detail !== 'string' || [...t.detail].length > 200))) {
        return '联系人或群聊信息不完整，请重新从飞书选择。';
      }
    }
  }
  return null;
}

function importanceReason(message, followed, rules = defaultRules(), custom = defaultCustomRules()) {
  if (blocks(custom, message)) return null;
  if (message.reminded || message.remindAt) return '稍后';
  const person = message.senderID ? custom.people.find(r => r.target.id === message.senderID) : undefined;
  const group = custom.groups.find(r => r.target.id === message.chatID);
  const conversation = custom.conversations.find(r => r.target.id === message.chatID);
  if ([person, conversation, group].some(r => r && r.mode === 'quiet')) return null;
  const selected = conversation || person || group;
  if (selected) {
    switch (selected.mode) {
      case 'all': return conversation ? '会话提醒' : person ? '联系人' : '群规则';
      case 'mentions': return message.mentionsMe ? '@我' : message.mentionsAll ? '@所有人' : null;
      default: return null;
    }
  }
  if (message.mentionsMe && rules.mentionsMe) return '@我';
  if (message.mentionsAll && rules.mentionsAll) return '@所有人';
  if (message.chatKind === 'p2p' && rules.directMessages) return '私聊';
  if (followed.has(message.chatID) && rules.followedChats) return '关注';
  return null;
}

function chatURL(message) {
  if (!message.chatID.startsWith('oc_') || !ID_PATTERN.test(message.chatID)) return null;
  return 'https://applink.feishu.cn/client/chat/open?openChatId=' + encodeURIComponent(message.chatID);
}

function source(message) { return message.chatKind === 'p2p' ? message.senderName : message.chatName; }

// Feishu presentation tags and inline markdown are stripped for display only.
function displayText(text) {
  let inCode = false;
  return text.split('\n').map(line => {
    if (line.trim().startsWith('```')) { inCode = !inCode; return line; }
    if (inCode) return line;
    let readable = line.replace(/(`+)[^`]*?\1|<\/?(?:font|text_tag)(?:\s+[^<>]*?)?\s*>|<br\s*\/?>/gi, token => {
      if (token.startsWith('`')) return token.replace(/^`+|`+$/g, '');
      return /^<br/i.test(token) ? '\n' : '';
    });
    readable = readable.replace(/^(\s{0,3})\*\s+/, '$1• ').replace(/^\s{0,3}#{1,6}\s+/, '');
    readable = readable
      .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
      .replace(/(\*\*|__)(?=\S)(.+?)(?<=\S)\1/g, '$2')
      .replace(/~~(?=\S)(.+?)(?<=\S)~~/g, '$1')
      .replace(/(^|[^\w*])\*(?=\S)([^*]+?)(?<=\S)\*(?!\w)/g, '$1$2');
    return readable;
  }).join('\n');
}

function danmuText(message) {
  const chat = message.chatName.trim();
  const sender = message.senderName.trim();
  const label = message.chatKind === 'p2p' || chat === sender || !chat ? sender : (!sender ? chat : `${chat} · ${sender}`);
  const body = displayText(message.text);
  return label ? `${label}：${body}` : body;
}

module.exports = {
  messageDate, plainText, messageText, createMessage,
  defaultRules, defaultCustomRules, normalizeCustom, consolidate, blocks, validationError, importanceReason,
  chatURL, source, displayText, danmuText
};
