'use strict';
// Company authorization panel (Feishu/CompanyAuthorizationView.swift). While the company
// login page is visible below, this page shrinks to its header.
const { h, call, api } = window.ui;
const main = document.getElementById('main');

function render(c) {
  main.className = '';
  if (c.pageReady) {
    const calendar = c.purpose === 'calendar';
    main.replaceChildren(
      h('h2', calendar ? '同步飞书日历' : '接收飞书消息'),
      h('div.card',
        h('div.big' + (c.granted ? '.ok' : ''), c.connected || c.granted ? '✓' : '✈'),
        h('h3', c.connected ? '已连接，可以使用了' : c.granted ? '飞书授权已完成' : '确认后，让飞书与小岛连接'),
        h('p', calendar ? '查看未来30天的日程，在岛上提醒你。日程内容继续在飞书管理。' : '读取本人会话与新消息，按你的规则提醒。不发送消息，也不修改已读状态。'),
        h('hr'),
        h('div.feedback', c.feedback),
        c.busy ? [
          h('div.wait', h('span.spin'), '等待你在浏览器里的飞书页面确认…'),
          h('div.buttons', h('button.btn', { onclick: () => call('company.reopen') }, '重新打开飞书授权页')),
          h('div.buttons', h('button.btn', { disabled: c.checking, onclick: () => call('company.check') }, c.checking ? '检查中…' : '检查授权结果'), h('button.btn', { onclick: () => call('company.cancel') }, '取消本次授权'))
        ] : c.connected ? h('div.buttons', h('button.btn.solid.large', { onclick: () => call('company.close') }, '完成'))
          : [h('div.buttons', h('button.btn.solid.large', { disabled: !c.configured, onclick: () => call(c.granted ? 'company.continue' : 'company.begin') }, c.granted ? '重新核对连接' : '连接飞书')),
            h('button.btn.link', { onclick: () => call('company.refresh') }, '重新检查授权状态')]),
      h('div.note', 'ⓘ 你可以随时在设置里暂停同步或接收。'));
  } else if (c.loginError) {
    main.replaceChildren(h('div.center', h('div.big', '!'), h('h3', '暂时无法连接'), h('p.muted', c.loginError), h('button.btn.solid', { onclick: () => call('company.reload') }, '重新打开登录页')));
  } else {
    main.className = 'login';
    main.replaceChildren(h('span', '用飞书登录，随后会自动打开授权页。'));
  }
}
api.onCompany(render);
call('company.snapshot').then(render);
