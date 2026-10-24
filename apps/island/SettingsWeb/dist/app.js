'use strict';
const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const systemAppearance = window.matchMedia('(prefers-color-scheme: dark)');
let appearance = 'system';
try { const stored = localStorage.getItem('island.appearance'); if (['light','dark','system'].includes(stored)) appearance = stored; } catch {}
function renderAppearance() {
  document.documentElement.dataset.theme = appearance === 'system' ? (systemAppearance.matches ? 'dark' : 'light') : appearance;
  $$('[data-theme-mode]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.themeMode === appearance)));
}
$$('[data-theme-mode]').forEach(button => button.addEventListener('click', () => {
  appearance = button.dataset.themeMode;
  try { localStorage.setItem('island.appearance', appearance); } catch {}
  renderAppearance();
}));
systemAppearance.addEventListener('change', renderAppearance);
renderAppearance();
try { const cachedSkin = localStorage.getItem('island.skin'); if (['codex','claude','workbuddy'].includes(cachedSkin)) document.documentElement.dataset.skin = cachedSkin; } catch {}
const keys = ['mentionsMe', 'mentionsAll', 'directMessages', 'followedChats'];
let saved = null, draft = null, connected = false, saving = false, previewType = 'mentionsAll', activeTab = 'defaults';
const targetValue = (target) => ({id:target.id, name:target.name, detail:target.detail || ''});
const customValue = (custom = {}) => ({
  people:(custom.people || []).map(rule => ({target:targetValue(rule.target), mode:rule.mode})),
  groups:(custom.groups || []).map(rule => ({target:targetValue(rule.target), mode:rule.mode})),
  blockedPeople:(custom.blockedPeople || []).map(targetValue),
  blockedGroups:(custom.blockedGroups || []).map(targetValue)
});
const values = (state) => ({ enabled: state.enabled, rules:Object.fromEntries(keys.map(key => [key,state.rules[key]])), customRules:customValue(state.customRules) });
const dirty = () => saved && draft && JSON.stringify(values(saved)) !== JSON.stringify(draft);
const text = (id, content) => { $(id).textContent = content; };
function setStatus(message, error = false) { text('#save-status', message); $('#save-status').classList.toggle('error', error); }
function render() {
  if (!draft) return;
  $$('[data-setting]').forEach(button => {
    const key = button.dataset.setting;
    button.setAttribute('aria-checked', String(key === 'enabled' ? draft.enabled : draft.rules[key]));
    button.disabled = saving || !connected;
  });
  $('#save').disabled = !connected || saving || !dirty();
  $('#reset').disabled = !connected || saving;
  text('#rules-count', `${keys.filter(key => draft.rules[key]).length}类消息`);
  renderPreview();
  renderCustom();
}
function renderPreview() {
  const examples = {
    mentionsAll: ['项目讨论群', '@所有人', '@所有人 明天的会议时间已更新。', '群内@所有人的新消息'],
    mentionsMe: ['项目讨论群', '@我', '@你 方便时确认一下这版方案。', '群内直接提到你的新消息'],
    directMessages: ['小林', '私聊', '资料已经整理好了，方便时看一下。', '一对一发给你的新消息']
  };
  const example = examples[previewType];
  const show = draft?.enabled && draft.rules[previewType];
  $('#preview-message').hidden = !show; $('#preview-quiet').hidden = show;
  text('#preview-count', show ? '1条' : '安静');
  const label = document.createElement('span'); label.textContent = example[0] + ' ';
  const badge = document.createElement('em'); badge.textContent = example[1]; label.append(badge);
  const body = document.createElement('p'); body.textContent = example[2];
  $('#preview-message').replaceChildren(label, body);
  text('#preview-caption', `示例：${example[3]}`);
  text('#preview-quiet', draft?.enabled ? '这类消息不弹出提醒' : '已停止接收消息');
  $$('[data-preview]').forEach(button => button.classList.toggle('active', button.dataset.preview === previewType));
}
function renderLive(state) {
  text('#account', state.account); text('#version', state.version);
  text('#receive-state', state.enabled ? '接收中' : '已停止');
  text('#mute-state', state.isMuted ? `静音至${new Date(state.mutedUntil * 1000).toLocaleTimeString('zh-CN', {hour:'2-digit', minute:'2-digit', hour12:false})}` : '正常提醒');
  text('#follow-count', `${state.followedCount}个`); text('#reader-status', state.status);
  $('#reader-dot').classList.toggle('off', !state.enabled || !state.status.startsWith('账号接收中'));
  text('#local-state', '已连接本机'); $('#local-dot').classList.remove('off');
  $('#connection-error').hidden = true;
}
async function request(method = 'GET', payload, path = '/api/settings') {
  const response = await fetch(path, { method, cache:'no-store', headers: payload ? {'Content-Type':'application/json', 'X-Island-Settings':'1'} : {}, body: payload ? JSON.stringify(payload) : undefined, signal: AbortSignal.timeout(path.startsWith('/api/directory') ? 12000 : 5000) });
  const body = await response.json();
  if (!response.ok) { const error = new Error(body.error || '请求未成功'); error.status = response.status; throw error; }
  return body;
}
async function load(manual = false) {
  if (saving) return;
  try {
    const state = await request(); connected = true; renderLive(state);
    if (!saved || !dirty()) { saved = state; draft = values(state); setStatus('已与柚子岛同步'); }
    else if (state.revision !== saved.revision) { setStatus('设置在其他位置已变更，请重新连接以载入最新设置。', true); $('#connection-error').hidden = false; text('#connection-error-message', '设置在其他位置已变更，重新连接可载入最新设置。'); }
    if (manual) { saved = state; draft = values(state); setStatus('已重新载入最新设置'); }
    render();
  } catch {
    connected = false; $('#connection-error').hidden = false; text('#connection-error-message', '无法连接柚子岛。请先打开应用，再重新连接。');
    text('#local-state', '等待柚子岛连接'); $('#local-dot').classList.add('off');
    setStatus('尚未保存；请打开柚子岛后重新连接。', true); render();
  }
}
$$('[data-setting]').forEach(button => button.addEventListener('click', () => {
  const key = button.dataset.setting;
  if (key === 'enabled') draft.enabled = !draft.enabled; else draft.rules[key] = !draft.rules[key];
  setStatus(dirty() ? '有未保存的修改' : '已与柚子岛同步'); render();
}));
$('#reset').addEventListener('click', () => { draft.enabled = true; draft.rules = Object.fromEntries(keys.map(key => [key,true])); setStatus(dirty() ? '已恢复默认选择，保存后生效' : '当前已是默认设置'); render(); });
$('#save').addEventListener('click', async () => {
  if (!dirty() || saving) return;
  saving = true; setStatus('正在保存…'); render();
  try {
    const result = await request('POST', {...draft, revision:saved.revision});
    saved = result; draft = values(result); renderLive(result); setStatus('已保存，规则已应用到柚子岛');
  } catch (error) {
    setStatus(error.status ? error.message : '保存结果未确认，请重新连接核对。', true);
    if (error.status === 409) { $('#connection-error').hidden = false; text('#connection-error-message', '设置已在其他位置改变。重新连接后载入最新设置。'); }
    if (!error.status) { connected = false; $('#connection-error').hidden = false; text('#connection-error-message', '无法连接柚子岛。请先打开应用，再重新连接。'); }
  } finally { saving = false; render(); }
});
$('#reload').addEventListener('click', () => {
  if (dirty() && !window.confirm('重新载入会放弃当前未保存的修改。继续吗？')) return;
  load(true);
});
const customCopy = {
  people:['指定联系人的提醒', '对方在私聊或群聊中发来的消息，都按这里的规则处理。', '还没有单独设置的联系人', '从飞书选择一个人，为他的消息单独设置提醒。', '联系人规则优先于所在群的规则；被屏蔽的人或群仍优先屏蔽。'],
  groups:['指定群聊的提醒', '按群决定哪些消息需要提醒，覆盖该群的默认规则。', '还没有单独设置的群聊', '从飞书选择一个群，设置全部提醒、仅@相关或仅收录。', '群规则覆盖默认规则；如果发送者有联系人规则，优先使用联系人规则。'],
  blocks:['不再出现在岛上的消息', '屏蔽指定联系人或群聊，飞书中的原始消息不受影响。', '目前没有屏蔽对象', '选择不需要出现在柚子岛上的人或群。', '屏蔽优先于所有提醒：新消息不再收录，已有消息暂时隐藏。解除后恢复已有记录，不补回屏蔽期间的消息。']
};
const modeLabels = {all:'全部提醒', mentions:'仅@我或@所有人时提醒', quiet:'仅收录，不提醒'};
function selectTab(tab) {
  activeTab = tab;
  $$('[data-tab]').forEach(button => { const active = button.dataset.tab === tab; button.classList.toggle('active', active); button.setAttribute('aria-selected', String(active)); });
  $('#defaults-panel').hidden = tab !== 'defaults'; $('#custom-panel').hidden = tab === 'defaults';
  $('#reset').hidden = tab !== 'defaults';
  renderCustom();
}
function changed() { setStatus(dirty() ? '有未保存的修改，点击保存后生效' : '已与柚子岛同步'); render(); }
function el(tag, className, content) { const element = document.createElement(tag); if (className) element.className = className; if (content !== undefined) element.textContent = content; return element; }
let customRenderKey = '';
function renderCustom() {
  if (!draft) return;
  const nextKey = JSON.stringify([activeTab, connected, saving, draft.customRules]);
  if (nextKey === customRenderKey) return;
  customRenderKey = nextKey;
  const custom = draft.customRules;
  text('#people-count', custom.people.length); text('#groups-count', custom.groups.length); text('#blocks-count', custom.blockedPeople.length + custom.blockedGroups.length);
  $('#add-people').disabled = $('#add-groups').disabled = !connected || saving;
  if (activeTab === 'defaults') return;
  const copy = customCopy[activeTab];
  text('#custom-title', copy[0]); text('#custom-description', copy[1]); text('#empty-title',copy[2]); text('#empty-description',copy[3]); text('#custom-foot',copy[4]);
  $('#add-people').hidden = activeTab === 'groups'; $('#add-groups').hidden = activeTab === 'people';
  $('#empty-icon').setAttribute('href', `#i-${activeTab === 'people' ? 'person' : activeTab === 'groups' ? 'group' : 'block'}`);
  const rows = activeTab === 'blocks'
    ? [...custom.blockedPeople.map(target => ({target, bucket:'blockedPeople'})), ...custom.blockedGroups.map(target => ({target, bucket:'blockedGroups'}))]
    : custom[activeTab].map(rule => ({...rule, bucket:activeTab}));
  $('#custom-empty').hidden = rows.length > 0; $('#custom-list').hidden = rows.length === 0;
  const nodes = rows.map(row => {
    const target = row.target, person = row.bucket === 'people' || row.bucket === 'blockedPeople';
    const entry = el('div', 'custom-row');
    const avatar = el('span','target-avatar',Array.from(target.name)[0] || '?');
    const info = el('div','target-info');
    const title = el('h3','target-name',target.name); title.title = target.name;
    const detail = el('p','target-detail',`${target.detail || (person ? '飞书联系人' : '飞书群聊')} · ${target.id.slice(-6)}`); detail.title = target.id;
    info.append(title,detail);
    const blocked = (person ? custom.blockedPeople : custom.blockedGroups).some(item => item.id === target.id);
    if (activeTab !== 'blocks' && blocked) info.append(el('span','blocked-badge','已屏蔽，当前规则暂不生效'));
    const controls = el('div','row-controls');
    if (row.mode) {
      const select = el('select','mode-select'); select.setAttribute('aria-label', `${target.name}的提醒方式`);
      Object.entries(modeLabels).forEach(([mode,label]) => { const option = el('option','',label); option.value = mode; select.append(option); });
      select.value = row.mode; select.disabled = saving || !connected;
      select.addEventListener('change', () => { const rule = draft.customRules[row.bucket].find(item => item.target.id === target.id); if (rule) rule.mode = select.value; changed(); });
      controls.append(select);
    } else controls.append(el('span','blocked-badge',person ? '屏蔽联系人' : '屏蔽群聊'));
    const remove = el('button','remove-rule',row.mode ? '取消单独设置' : '解除屏蔽');
    remove.setAttribute('aria-label',row.mode ? `移除${target.name}的单独规则` : `解除对${target.name}的屏蔽`); remove.disabled = saving || !connected;
    remove.addEventListener('click', () => { draft.customRules[row.bucket] = draft.customRules[row.bucket].filter(item => (item.target || item).id !== target.id); changed(); });
    controls.append(remove); entry.append(avatar,info,controls); return entry;
  });
  $('#custom-list').replaceChildren(...nodes);
}
$$('[data-tab]').forEach(button => button.addEventListener('click', () => selectTab(button.dataset.tab)));

let pickerKind = 'people', pickerBlocking = false, pickerSelected = new Map(), pickerRows = [], pickerToken = '', pickerQuery = '', pickerGeneration = 0, pickerLoading = false;
function pickerBucket() { return pickerBlocking ? (pickerKind === 'people' ? 'blockedPeople' : 'blockedGroups') : pickerKind; }
function existingTarget(id) { return draft.customRules[pickerBucket()].some(item => (item.target || item).id === id); }
function pickerSelection() {
  text('#picker-summary', pickerSelected.size ? `已选择${pickerSelected.size}项` : '尚未选择');
  text('#picker-add', pickerBlocking ? `加入屏蔽${pickerSelected.size ? `（${pickerSelected.size}）` : ''}` : `加入设置${pickerSelected.size ? `（${pickerSelected.size}）` : ''}`);
  $('#picker-add').disabled = pickerSelected.size === 0 || !connected || saving;
}
function renderPickerRows() {
  if (!pickerRows.length && !pickerLoading) { $('#picker-results').replaceChildren(el('div','picker-empty','没有找到匹配对象，可以换一个姓名或群名再试。')); return; }
  const rows = pickerRows.map(target => {
    const label = el('label','picker-person');
    const checkbox = document.createElement('input'); checkbox.type = 'checkbox'; checkbox.setAttribute('aria-label',`选择${target.name}`); checkbox.checked = pickerSelected.has(target.id) || existingTarget(target.id); checkbox.disabled = existingTarget(target.id);
    checkbox.addEventListener('change', () => { if (checkbox.checked) pickerSelected.set(target.id,target); else pickerSelected.delete(target.id); pickerSelection(); });
    const avatar = el('span','target-avatar',Array.from(target.name)[0] || '?');
    const info = el('div','target-info'); info.append(el('strong','target-name',target.name),el('p','target-detail',`${target.detail || (pickerKind === 'people' ? '飞书联系人' : '飞书群聊')} · ${target.id.slice(-6)}`));
    label.append(checkbox,avatar,info); if (existingTarget(target.id)) label.append(el('span','outline-tag','已添加')); return label;
  });
  $('#picker-results').replaceChildren(...rows);
}
async function searchPicker(more = false) {
  const generation = ++pickerGeneration;
  if (!more) { pickerRows = []; pickerToken = ''; pickerQuery = $('#picker-query').value.trim(); $('#picker-results').replaceChildren(el('div','picker-empty','正在从飞书读取…')); }
  pickerLoading = true; $('#picker-search-button').disabled = true; $('#picker-more').hidden = true; text('#picker-hint',''); text('#picker-source','正在读取飞书…');
  const params = new URLSearchParams({kind:pickerKind,q:pickerQuery,pageToken:more ? pickerToken : ''});
  try {
    const result = await request('GET',undefined,`/api/directory?${params}`);
    if (generation !== pickerGeneration || !$('#picker').open) return;
    const seen = new Set(pickerRows.map(item => item.id)); pickerRows.push(...result.items.filter(item => !seen.has(item.id)));
    pickerToken = result.pageToken;
    text('#picker-source', `${result.source} · 当前显示${pickerRows.length}项`);
    text('#picker-hint', result.hasMore && pickerKind === 'people' ? '还有更多联系人，请输入更完整的姓名缩小范围。' : pickerKind === 'groups' ? '只为你已加入的群设置提醒。免打扰群不会因此恢复提醒。' : '联系人规则同时适用于私聊和群聊中由他发送的消息。');
    $('#picker-more').hidden = !(result.hasMore && pickerKind === 'groups' && pickerToken);
    pickerLoading = false; renderPickerRows();
  } catch (error) {
    if (generation !== pickerGeneration || !$('#picker').open) return;
    text('#picker-source', error.status ? error.message : '查询未完成，请检查柚子岛连接后重试。');
    if (!pickerRows.length) $('#picker-results').replaceChildren(el('div','picker-empty','没有取得有效结果。输入名称后可重新搜索。'));
  } finally { if (generation === pickerGeneration) { pickerLoading = false; $('#picker-search-button').disabled = false; pickerSelection(); } }
}
function closePicker() { pickerGeneration++; $('#picker').close(); }
function openPicker(kind) {
  if (!draft || !connected) return;
  pickerKind = kind; pickerBlocking = activeTab === 'blocks'; pickerSelected = new Map(); pickerRows = []; pickerToken = ''; pickerQuery = '';
  text('#picker-title', `${pickerBlocking ? '选择要屏蔽的' : '选择'}${kind === 'people' ? '联系人' : '群聊'}`);
  $('#picker-query').value = ''; $('#picker-query').placeholder = kind === 'people' ? '输入姓名搜索飞书联系人' : '输入群名搜索已加入的群';
  $('#picker-mode-row').hidden = pickerBlocking; $('#picker-mode').value = 'all'; pickerSelection();
  $('#picker').showModal(); $('#picker-query').focus(); searchPicker();
}
$('#add-people').addEventListener('click', () => openPicker('people')); $('#add-groups').addEventListener('click', () => openPicker('groups'));
$('#picker-search-form').addEventListener('submit', event => { event.preventDefault(); searchPicker(); });
$('#picker-more').addEventListener('click', () => searchPicker(true));
$('#picker-close').addEventListener('click',closePicker); $('#picker-cancel').addEventListener('click',closePicker);
$('#picker').addEventListener('cancel', () => pickerGeneration++);
$('#picker-add').addEventListener('click', () => {
  const bucket = pickerBucket(), mode = $('#picker-mode').value;
  pickerSelected.forEach(target => { if (!existingTarget(target.id)) draft.customRules[bucket].push(pickerBlocking ? targetValue(target) : {target:targetValue(target),mode}); });
  closePicker(); changed();
});
function selectPage(page) {
  if (!['general','feishu','modules','agents','skins','todos'].includes(page)) page = 'feishu';
  $$('.page').forEach(section => section.hidden = section.id !== `page-${page}`);
  $$('.nav-item').forEach(button => { const active = button.dataset.page === page; button.classList.toggle('active', active); if (active) button.setAttribute('aria-current','page'); else button.removeAttribute('aria-current'); });
  text('#breadcrumb', {general:'通用设置', feishu:'飞书消息', modules:'功能模块', agents:'Agent状态', skins:'皮肤设置', todos:'待办提醒'}[page]);
  if (location.hash !== `#${page}`) history.replaceState(null,'',`#${page}`);
}
$$('[data-page]').forEach(button => button.addEventListener('click', () => selectPage(button.dataset.page)));
window.addEventListener('hashchange', () => selectPage(location.hash.slice(1)));
$$('[data-preview]').forEach(button => button.addEventListener('click', () => { previewType = button.dataset.preview; renderPreview(); }));
window.addEventListener('beforeunload', event => { if (dirty()) { event.preventDefault(); event.returnValue = ''; } });
selectPage(location.hash.slice(1)); load(); setInterval(() => { if (!document.hidden) load(); }, 15000);

let agentSnapshot = null, agentDirty = false, agentSaving = false;
let queuedSkinChanges = null, writingSkin = false;
function agentNode(tag, className, content) {
  const node = document.createElement(tag); node.className = className;
  if (content !== undefined) node.textContent = content;
  return node;
}
function agentFormPreferences(changes = {}) {
  return {...agentSnapshot.preferences, enabled:$('#agent-enabled').checked, completionAlerts:$('#agent-completion').checked, quotaAlerts:$('#agent-quota').checked, ...changes};
}
function agentDisplayIDs(preferences) { return preferences.visibleIDs || preferences.profiles.map(profile => profile.id); }
function renderAgents(snapshot) {
  agentSnapshot = snapshot;
  const preferences = snapshot.preferences;
  window.skinPreferences = preferences;
  if (window.SkinStudio) window.SkinStudio.render({...preferences,...queuedSkinChanges}, snapshot);
  const visibleIDs = agentDisplayIDs(preferences);
  if (!agentDirty) {
    $('#agent-enabled').checked = preferences.enabled;
    $('#agent-completion').checked = preferences.completionAlerts;
    $('#agent-quota').checked = preferences.quotaAlerts;
  }
  $$('[data-agent-visible]').forEach(input => { input.checked = visibleIDs.includes(input.dataset.agentVisible); input.disabled = agentSaving; });
  $('#agent-only-primary').disabled = agentSaving;
  $('#agent-show-all').disabled = agentSaving;
  text('#agent-display-count', `显示${visibleIDs.length}个Agent`);
  $('#agent-cards').dataset.count = visibleIDs.length;
  $$('[data-agent-help]').forEach(paragraph => { paragraph.hidden = !visibleIDs.includes(paragraph.dataset.agentHelp); });
  $('#agent-refresh').disabled = snapshot.refreshing || !preferences.enabled || agentSaving;
  $('#agent-refresh').textContent = snapshot.refreshing ? '正在读取…' : '刷新额度';
  const cards = preferences.profiles.filter(profile => visibleIDs.includes(profile.id)).map(profile => {
    const data = snapshot.agents[profile.id] || {};
    const selected = preferences.primaryID === profile.id;
    const card = agentNode('article', `agent-card${selected ? ' selected' : ''}`);
    const heading = agentNode('div', 'agent-card-heading');
    const logo = agentNode('span', `agent-logo ${profile.id}`), icon = agentNode('img', '');
    icon.src = `/avatar-${profile.id}.png`; icon.alt = ''; logo.append(icon); heading.append(logo);
    const title = agentNode('div', ''); title.append(agentNode('h2', '', profile.name));
    title.append(agentNode('span', 'agent-connection', profile.id === 'claude' ? '尚未接入 · 待登录联调' : (data.quotas || []).some(q => q.fresh) ? '额度已连接' : '等待数据'));
    heading.append(title); card.append(heading);
    const status = agentNode('div', 'agent-task-state'); status.append(agentNode('i', `agent-dot ${data.state || 'unknown'}`), agentNode('span', '', data.stateLabel || '等待状态数据'));
    if (data.activeCount > 1) status.append(agentNode('small', '', `${data.activeCount}个任务`));
    card.append(status);
    const quotas = agentNode('div', 'agent-quota-list');
    if (!(data.quotas || []).length) quotas.append(agentNode('div', 'agent-no-quota', '暂无额度数据'));
    for (const quota of data.quotas || []) {
      const item = agentNode('div', `agent-quota${quota.fresh && quota.remainingPercent < 20 ? ' low' : ''}${quota.fresh ? '' : ' stale'}`);
      const line = agentNode('div', 'agent-quota-title'); line.append(agentNode('span', '', quota.label), agentNode('span', 'agent-quota-tag', quota.fresh ? '剩余' : '上次记录'));
      item.append(line, agentNode('strong', '', `${quota.remainingPercent.toFixed(1)}%`));
      const track = agentNode('progress', ''); track.max = 100; track.value = quota.remainingPercent; track.setAttribute('aria-label', `${quota.label}剩余${quota.remainingPercent.toFixed(1)}%`); item.append(track);
      if (quota.remainingUnits !== null) item.append(agentNode('p', '', `${quota.remainingUnits.toFixed(2)} / ${quota.totalUnits.toFixed(0)}积分`));
      if (quota.resetsAt) item.append(agentNode('p', '', `重置：${new Date(quota.resetsAt*1000).toLocaleString('zh-CN', {month:'numeric',day:'numeric',hour:'2-digit',minute:'2-digit'})}`));
      item.append(agentNode('small', '', `${quota.fresh ? '更新于' : '已过期 · 记录于'}${new Date(quota.updatedAt*1000).toLocaleTimeString('zh-CN', {hour:'2-digit',minute:'2-digit',hour12:false})}`));
      quotas.append(item);
    }
    card.append(quotas, agentNode('p', 'agent-detail', data.detail || '等待Agent数据。'));
    const choose = agentNode('button', selected ? 'primary' : 'secondary', selected ? '当前主用Agent' : '设为主用Agent');
    choose.disabled = selected || agentSaving;
    choose.addEventListener('click', async () => {
      await saveAgentPreferences(agentFormPreferences({primaryID:profile.id}), '主用Agent及提醒设置已保存。');
    }); card.append(choose);
    return card;
  });
  $('#agent-cards').replaceChildren(...cards);
  text('#agent-last-alert', snapshot.lastAlert ? `最近提醒：${snapshot.lastAlert}` : '');
  if (!agentDirty && !agentSaving) text('#agent-save-status', preferences.enabled ? '监测已启用 · 设置只保存在本机' : '监测已暂停');
}
async function loadAgents() {
  if (agentSaving) return;
  try {
    const response = await request('GET', undefined, '/api/agents');
    if (!agentSaving && (!agentSnapshot || response.preferences.revision >= agentSnapshot.preferences.revision)) renderAgents(response);
  }
  catch (error) { text('#agent-save-status', error.message); }
}
async function saveAgentPreferences(preferences, message, statusTarget = '#agent-save-status', preserveDraft = false) {
  if (agentSaving) return;
  const retainedDirty = preserveDraft && agentDirty;
  agentSaving = true; $('#agent-save').disabled = true;
  $$('[data-agent-visible]').forEach(input => { input.disabled = true; });
  $('#agent-only-primary').disabled = true; $('#agent-show-all').disabled = true;
  try {
    const response = await request('POST', preferences, '/api/agents');
    agentDirty = retainedDirty; agentSaving = false; renderAgents(response); text(statusTarget, message);
  } catch (error) {
    agentSaving = false; if (agentSnapshot) renderAgents(agentSnapshot); text(statusTarget, error.message);
  } finally {
    agentSaving = false; $('#agent-save').disabled = false;
    $$('[data-agent-visible]').forEach(input => { input.disabled = false; });
    $('#agent-only-primary').disabled = false; $('#agent-show-all').disabled = false;
  }
}
async function saveAgentVisibility(ids) {
  if (!agentSnapshot || agentSaving) return;
  if (!ids.length) {
    renderAgents(agentSnapshot); text('#agent-display-status', '至少保留一个Agent；如果想暂停监测，可关闭下方的“启用Agent监测”。'); return;
  }
  const primaryID = ids.includes(agentSnapshot.preferences.primaryID) ? agentSnapshot.preferences.primaryID : agentSnapshot.preferences.profiles.find(profile => ids.includes(profile.id)).id;
  const name = agentSnapshot.preferences.profiles.find(profile => profile.id === primaryID).name;
  await saveAgentPreferences(agentFormPreferences({visibleIDs:ids, primaryID}), `已保存，显示${ids.length}个Agent，主用${name}。`, '#agent-display-status');
}
$$('[data-agent-visible]').forEach(input => input.addEventListener('change', () => saveAgentVisibility($$('[data-agent-visible]').filter(item => item.checked).map(item => item.dataset.agentVisible))));
$('#agent-only-primary').addEventListener('click', () => { if (agentSnapshot) saveAgentVisibility([agentSnapshot.preferences.primaryID]); });
$('#agent-show-all').addEventListener('click', () => { if (agentSnapshot) saveAgentVisibility(agentSnapshot.preferences.profiles.map(profile => profile.id)); });
for (const id of ['#agent-enabled','#agent-completion','#agent-quota']) $(id).addEventListener('change', () => { agentDirty = true; text('#agent-save-status', '有未保存的提醒设置。'); });
$('#agent-save').addEventListener('click', () => {
  if (!agentSnapshot) return;
  saveAgentPreferences(agentFormPreferences(), '提醒设置已保存。');
});
$('#agent-refresh').addEventListener('click', async () => {
  $('#agent-refresh').disabled = true;
  try { renderAgents(await request('POST', {}, '/api/agents/refresh')); }
  catch (error) { text('#agent-save-status', error.message); }
});
loadAgents(); setInterval(() => { if (!document.hidden) loadAgents(); }, 2000);
window.addEventListener('beforeunload', event => { if (agentDirty) { event.preventDefault(); event.returnValue = ''; } });

window.addEventListener('skin-ready', () => { if (agentSnapshot) window.SkinStudio.render(agentSnapshot.preferences, agentSnapshot); });
// Local writes are serialized; rapid skin picks keep the user's final selection.
function changeSkinPreferences(changes) {
  if (!agentSnapshot) return;
  queuedSkinChanges = {...queuedSkinChanges,...changes};
  window.SkinStudio?.render({...agentSnapshot.preferences,...queuedSkinChanges},agentSnapshot);
  flushSkinPreferences();
}
async function flushSkinPreferences() {
  if (writingSkin) return;
  writingSkin = true;
  try {
    while (queuedSkinChanges) {
      if (agentSaving) { await new Promise(resolve=>setTimeout(resolve,16)); continue; }
      const changes=queuedSkinChanges;queuedSkinChanges=null;
      await saveAgentPreferences({...agentSnapshot.preferences,...changes}, '皮肤设置已保存，整座岛已换装。', '#skin-status', true);
    }
  } finally { writingSkin=false; }
}
window.addEventListener('skin-select', event => changeSkinPreferences({skinID:event.detail}));
$('#skin-effects-enabled').addEventListener('change', event => changeSkinPreferences({effectsEnabled:event.target.checked}));
let companionTimer;
$('#skin-companion').addEventListener('click', () => {
  const companion=$('#skin-companion');companion.classList.remove('greeted');void companion.offsetWidth;companion.classList.add('greeted');
  text('#skin-greeting','收到！陪你一起专心');clearTimeout(companionTimer);
  companionTimer=setTimeout(()=>{companion.classList.remove('greeted');text('#skin-greeting','点一下，打个招呼');},1200);
});
