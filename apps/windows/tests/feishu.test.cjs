'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const M = require('../core/feishu/message.cjs');
const { AccountReader } = require('../core/feishu/reader.cjs');
const { ServerClock } = require('../core/feishu/clock.cjs');
const { FeishuStore } = require('../core/feishu/store.cjs');
const { MessageArchive, accountKey } = require('../core/feishu/archive.cjs');
const { Prefs } = require('../core/prefs.cjs');

const text = (id, body, extra = {}) => ({ message_id: id, msg_type: 'text', create_time: String(Date.now()), body: { content: JSON.stringify({ text: body }) }, sender: { id: 'ou_other', id_type: 'open_id', sender_name: '同事' }, ...extra });

test('text, post, interactive and file bodies become plain text', () => {
  assert.equal(M.messageText(text('a', '<p>你好</p><br>世界')), '你好\n\n世界');
  const post = { message_id: 'p', msg_type: 'post', body: { content: JSON.stringify({ zh_cn: { title: '标题', content: [[{ tag: 'text', text: '第一行 ' }, { tag: 'at', user_id: 'all' }], [{ tag: 'img' }]] } }) } };
  assert.equal(M.messageText(post), '标题\n第一行 @所有人\n[图片]');
  const card = { msg_type: 'interactive', body: { content: JSON.stringify({ i18n_elements: { zh_cn: [{ text: '中文' }], en_us: [{ text: 'English' }] }, header: { title: '审批' } }) } };
  assert.deepEqual(M.messageText(card).split('\n'), ['审批', '中文']);
  assert.equal(M.messageText({ msg_type: 'file', body: { content: JSON.stringify({ file_name: 'a.pdf' }) } }), '[文件] a.pdf');
  assert.equal(M.messageText({ msg_type: 'image', body: { content: '{}' } }), '[图片]');
  assert.equal(M.messageText({ msg_type: 'text', body: { content: 'not json' } }), '[text]');
});

test('mentions resolve, @all is detected from token, structure and post tags', () => {
  const me = M.createMessage(text('m1', '@_user_1 看一下', { mentions: [{ key: '@_user_1', id: { open_id: 'ou_me' }, name: '宰治' }] }), 'oc_1', '群', 'group', 'ou_me');
  assert.equal(me.mentionsMe, true); assert.equal(me.text, '@宰治 看一下');
  const all = M.createMessage(text('m2', '@_all 开会'), 'oc_1', '群', 'group', 'ou_me');
  assert.equal(all.mentionsAll, true); assert.equal(all.text, '@所有人 开会');
  const notAll = M.createMessage(text('m3', 'email@_all.com'), 'oc_1', '群', 'group', 'ou_me');
  assert.equal(notAll.mentionsAll, false);
});

test('importance follows rule precedence: quiet beats defaults, conversation beats person', () => {
  const dm = M.createMessage(text('d', 'hi'), 'oc_p', '小林', 'p2p', 'ou_me');
  assert.equal(M.importanceReason(dm, new Set()), '私聊');
  const custom = M.defaultCustomRules();
  custom.people.push({ target: { id: 'ou_other', name: '同事' }, mode: 'quiet' });
  assert.equal(M.importanceReason(dm, new Set(), M.defaultRules(), custom), null);
  const group = M.createMessage(text('g', '普通'), 'oc_g', '群', 'group', 'ou_me');
  assert.equal(M.importanceReason(group, new Set()), null);
  const c2 = M.defaultCustomRules(); c2.conversations.push({ target: { id: 'oc_g', name: '群' }, mode: 'all' });
  assert.equal(M.importanceReason(group, new Set(), M.defaultRules(), c2), '会话提醒');
  c2.conversations[0].mode = 'mentions';
  assert.equal(M.importanceReason(group, new Set(), M.defaultRules(), c2), null);
});

test('legacy blocked targets consolidate into quiet rules and validation rejects bad ids', () => {
  const legacy = { ...M.defaultCustomRules(), blockedGroups: [{ id: 'oc_x', name: '吵闹群' }], groups: [{ target: { id: 'oc_y', name: '项目' }, mode: 'all' }] };
  const next = M.consolidate(legacy, new Set(['oc_z']));
  assert.deepEqual(next.conversations.map(r => [r.target.id, r.mode]), [['oc_x', 'quiet'], ['oc_y', 'all'], ['oc_z', 'all']]);
  assert.equal(M.validationError(next), null);
  next.people.push({ target: { id: 'oc_wrong', name: 'x' }, mode: 'all' });
  assert.notEqual(M.validationError(next), null);
});

test('display text strips markdown and Feishu tags, keeps fenced code', () => {
  assert.equal(M.displayText('**粗体** [链接](https://x) <font color=red>红</font>'), '粗体 链接 红');
  assert.equal(M.displayText('```\n**x**\n```'), '```\n**x**\n```');
  assert.equal(M.displayText('# 标题\n* 项'), '标题\n• 项');
  const m = M.createMessage(text('x', '你好'), 'oc_1', '项目群', 'group', '');
  assert.equal(M.danmuText(m), '项目群 · 同事：你好');
  assert.equal(M.chatURL(m), 'https://applink.feishu.cn/client/chat/open?openChatId=oc_1');
});

// ---- synthetic CLI for the reader ----
function fakeCLI({ chats, messages, read = () => false, failRead = false }) {
  const calls = [];
  const run = async args => {
    calls.push(args);
    if (args[0] === 'im' && args[1] === '+chat-list') {
      const muted = args.includes('--exclude-muted');
      return { ok: true, identity: 'user', data: { chats: chats.filter(c => !muted || !c.muted).map(c => ({ chat_id: c.id, name: c.name, chat_mode: c.kind })), has_more: false } };
    }
    if (args[0] === 'api' && args[1] === 'GET') {
      const params = JSON.parse(args[args.indexOf('--params') + 1]);
      return { ok: true, identity: 'user', data: { items: (messages[params.container_id] || []).slice().reverse(), has_more: false } };
    }
    if (args[0] === 'api' && args[1] === 'POST') {
      if (failRead) throw new Error('fail');
      const ids = JSON.parse(args[args.indexOf('--data') + 1]).message_ids;
      return { ok: true, identity: 'user', data: { items: ids.map(id => ({ message_id: id, is_read: read(id) })) } };
    }
    throw new Error('unexpected ' + args.join(' '));
  };
  return { run, calls };
}
const fastReader = (cli, extra = {}) => new AccountReader({ run: cli.run, identity: async () => ({ openID: 'ou_me', userName: '本人' }), pollDelay: 0.05, pageDelay: 0.01, catalogInterval: 0.2, retryDelay: 0.05, clock: new ServerClock(ServerClock.local()), ...extra });
const waitFor = async (fn, ms = 3000) => { const end = Date.now() + ms; while (!fn()) { if (Date.now() > end) throw new Error('timeout'); await new Promise(r => setTimeout(r, 10)); } };

test('reader delivers unread messages once, skips read, own, muted and pre-start messages', async () => {
  const now = Date.now();
  const messages = {
    oc_a: [text('new1', '一', { create_time: String(now + 1000) }), text('read1', '已读', { create_time: String(now + 1000) }), text('mine', '我发的', { create_time: String(now + 1000), sender: { id: 'ou_me', sender_name: '本人' } }), text('old', '旧', { create_time: String(now - 600000) })],
    oc_muted: [text('m1', '免打扰', { create_time: String(now + 1000) })],
    oc_gray: [text('g1', '灰色放行', { create_time: String(now + 1000) })]
  };
  const cli = fakeCLI({ chats: [{ id: 'oc_a', name: '项目', kind: 'group' }, { id: 'oc_muted', name: '闲聊', kind: 'group', muted: true }, { id: 'oc_gray', name: '重要通知', kind: 'group', muted: true }], messages, read: id => id === 'read1' });
  const reader = fastReader(cli);
  reader.setRules(['通知'], []);
  const got = [];
  reader.onMessage = m => got.push(m.id);
  reader.start();
  await waitFor(() => got.includes('new1') && got.includes('g1'));
  await new Promise(r => setTimeout(r, 300));
  reader.stop();
  assert.deepEqual(got.sort(), ['g1', 'new1']);
});

test('unknown unread state is retried, never delivered as unread', async () => {
  const now = Date.now();
  const cli = fakeCLI({ chats: [{ id: 'oc_a', name: '项目', kind: 'p2p' }], messages: { oc_a: [text('x', 'x', { create_time: String(now + 1000) })] }, failRead: true });
  const reader = fastReader(cli);
  const got = []; const statuses = [];
  reader.onMessage = m => got.push(m.id); reader.onStatus = s => statuses.push(s);
  reader.start();
  await waitFor(() => statuses.some(s => s.includes('快查读取失败') || s.includes('接收异常')));
  reader.stop();
  assert.deepEqual(got, []);
});

test('hidden keyword blocks even unmuted chats; stop halts delivery', async () => {
  const now = Date.now();
  const cli = fakeCLI({ chats: [{ id: 'oc_h', name: '广告群', kind: 'group' }], messages: { oc_h: [text('h', '广告', { create_time: String(now + 1000) })] } });
  const reader = fastReader(cli); reader.setRules([], ['广告']);
  const got = []; reader.onMessage = m => got.push(m.id);
  reader.start(); await new Promise(r => setTimeout(r, 300)); reader.stop();
  assert.deepEqual(got, []);
});

test('store routes important messages to reader queue and danmu, respects mute and onboarding', () => {
  const prefs = Prefs.memory();
  let present = false;
  const store = new FeishuStore({ prefs, canPresent: () => present });
  store.updateDanmu({ enabled: true });
  const danmu = []; store.on('danmu', m => danmu.push(m.id));
  const dm = M.createMessage(text('d1', '私聊'), 'oc_p', '小林', 'p2p', 'ou_me');
  store.receive(dm);
  assert.equal(store.readingID, null, 'onboarding blocks presentation');
  present = true;
  store.receive(M.createMessage(text('d2', '私聊2'), 'oc_p', '小林', 'p2p', 'ou_me'));
  assert.equal(store.readingID, 'd2'); assert.deepEqual(danmu, ['d2']);
  store.toggleMute();
  store.receive(M.createMessage(text('d3', '私聊3'), 'oc_p', '小林', 'p2p', 'ou_me'));
  assert.deepEqual(danmu, ['d2']);
  assert.equal(store.messages.length, 3);
});

test('remind later re-queues after ten minutes', () => {
  let now = 1000;
  const store = new FeishuStore({ prefs: Prefs.memory(), now: () => now });
  store.receive(M.createMessage(text('r1', 'x'), 'oc_p', '小林', 'p2p', 'ou_me'));
  store.remindLater('r1');
  assert.equal(store.waitingCount, 0);
  now += 601; store.tick();
  const m = store.messages[0];
  assert.equal(m.reminded, true); assert.equal(m.viewed, false); store.cancelAlert();
});

test('archive is per account, prunes by retention and survives reload', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'island-archive-'));
  try {
    const key = accountKey('cli_app', 'ou_me');
    const archive = new MessageArchive(root, key);
    const now = Date.now() / 1000;
    const s = archive.load(7, now);
    s.messages = [{ id: 'keep', created: new Date().toISOString() }, { id: 'drop', created: new Date((now - 8 * 86400) * 1000).toISOString() }];
    s.pending = ['keep', 'drop'];
    archive.save(s);
    const again = archive.load(7, now);
    assert.deepEqual(again.messages.map(m => m.id), ['keep']);
    assert.deepEqual(again.pending, ['keep']);
    assert.throws(() => new MessageArchive(root, '../x'));
    MessageArchive.expireAll(root, 0, now);
    assert.deepEqual(archive.load(7, now).messages, []);
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});
