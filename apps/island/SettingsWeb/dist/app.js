if (new URLSearchParams(location.search).get('embedded') === '1') { document.documentElement.classList.add('embedded'); document.documentElement.dataset.theme='dark'; }
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
const keys = ['mentionsMe', 'mentionsAll', 'directMessages', 'followedChats'];
let saved = null, draft = null, connected = false, saving = false, previewType = 'mentionsAll', activeTab = 'defaults';
const targetValue = (target) => ({id:target.id, name:target.name, detail:target.detail || ''});
const customValue = (custom = {}) => ({
  people:(custom.people || []).map(rule => ({target:targetValue(rule.target), mode:rule.mode})),
  groups:(custom.groups || []).map(rule => ({target:targetValue(rule.target), mode:rule.mode})),
  blockedPeople:(custom.blockedPeople || []).map(targetValue),
  blockedGroups:(custom.blockedGroups || []).map(targetValue)
});
const values = (state) => ({ danmu:{...(state.danmu || {enabled:false,paused:false})},connection:{...(state.connection || {cliPath:"",profile:"feishu-island"})},appearance:{...(state.appearance || {version:1,name:"默认",background:null,foreground:null,border:null,fontSize:28,corner:12,motion:"scroll"})},enabled: state.enabled, rules:Object.fromEntries(keys.map(key => [key,state.rules[key]])), customRules:customValue(state.customRules) });
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
  $$('[data-danmu]').forEach(button=>{button.setAttribute('aria-checked',String(draft.danmu[button.dataset.danmu]));button.disabled=saving||!connected;});
  for(const [id,key] of [['#cli-path','cliPath'],['#cli-profile','profile']]){if(document.activeElement!==$(id))$(id).value=draft.connection[key];$(id).disabled=saving||!connected;}
  $('#danmu-font').value=draft.appearance.fontSize; text('#danmu-font-value',draft.appearance.fontSize / 2);
  $('#danmu-theme').value=draft.appearance.background===null?'system':draft.appearance.background==='#111111'?'night':draft.appearance.background==='#ffffff'?'paper':'custom';
  $('#danmu-demo').disabled=!connected||saving||!saved?.enabled;
  text('#auth-hint','消息只读接收，材料归档单独授权。首次使用点“连接自己的飞书”；已有本机连接保留在高级设置中。');
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
  const delivery = state.delivery;
  text('#delivery-status', delivery ? `本次运行：岛内保留 ${delivery.retained} 条，其中重要 ${delivery.important} 条；进入阅读 ${delivery.islandReadingAccepted || 0} 条、待阅读 ${delivery.islandReadingPending || 0} 条。` : '当前应用尚未提供投递计数。');
  text('#account', state.account); text('#version', state.version);
  text('#receive-state', state.enabled ? '接收中' : '已停止');
  text('#mute-state', state.isMuted ? `静音至${new Date(state.mutedUntil * 1000).toLocaleTimeString('zh-CN', {hour:'2-digit', minute:'2-digit', hour12:false})}` : '正常提醒');
  text('#follow-count', `${state.followedCount}个`); text('#reader-status', state.status);
  $('#reader-dot').classList.toggle('off', !state.enabled || !state.status.startsWith('账号接收中'));
  text('#local-state', state.synthetic ? '合成模式 · 试播不上屏' : '已连接本机'); $('#local-dot').classList.remove('off');
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
    if (!saved || !dirty()) { saved = state; draft = values(state); setStatus('已与你的飞包同步'); }
    else if (state.revision !== saved.revision) { setStatus('设置在其他位置已变更，请重新连接以载入最新设置。', true); $('#connection-error').hidden = false; text('#connection-error-message', '设置在其他位置已变更，重新连接可载入最新设置。'); }
    if (manual) { saved = state; draft = values(state); setStatus('已重新载入最新设置'); }
    render();
  } catch {
    connected = false; $('#connection-error').hidden = false; text('#connection-error-message', '无法连接你的飞包。请先打开应用，再重新连接。');
    text('#local-state', '等待你的飞包连接'); $('#local-dot').classList.add('off');
    setStatus('尚未保存；请打开你的飞包后重新连接。', true); render();
  }
}
$$('[data-setting]').forEach(button => button.addEventListener('click', () => {
  const key = button.dataset.setting;
  if (key === 'enabled') draft.enabled = !draft.enabled; else draft.rules[key] = !draft.rules[key];
  setStatus(dirty() ? '有未保存的修改' : '已与你的飞包同步'); render();
}));
$('#reset').addEventListener('click', () => { draft.enabled = true; draft.rules = Object.fromEntries(keys.map(key => [key,true])); setStatus(dirty() ? '已恢复默认选择，保存后生效' : '当前已是默认设置'); render(); });
$('#save').addEventListener('click', async () => {
  if (!dirty() || saving) return;
  saving = true; setStatus('正在保存…'); render();
  try {
    const result = await request('POST', {...draft, revision:saved.revision});
    saved = result; draft = values(result); renderLive(result); setStatus('已保存，规则已应用到你的飞包');
  } catch (error) {
    setStatus(error.status ? error.message : '保存结果未确认，请重新连接核对。', true);
    if (error.status === 409) { $('#connection-error').hidden = false; text('#connection-error-message', '设置已在其他位置改变。重新连接后载入最新设置。'); }
    if (!error.status) { connected = false; $('#connection-error').hidden = false; text('#connection-error-message', '无法连接你的飞包。请先打开应用，再重新连接。'); }
  } finally { saving = false; render(); }
});
$('#reload').addEventListener('click', () => {
  if (dirty() && !window.confirm('重新载入会放弃当前未保存的修改。继续吗？')) return;
  load(true);
});
const customCopy = {
  people:['指定联系人的提醒', '对方在私聊或群聊中发来的消息，都按这里的规则处理。', '还没有单独设置的联系人', '从飞书选择一个人，为他的消息单独设置提醒。', '联系人规则优先于所在群的规则；被屏蔽的人或群仍优先屏蔽。'],
  groups:['指定群聊的提醒', '按群决定哪些消息需要提醒，覆盖该群的默认规则。', '还没有单独设置的群聊', '从飞书选择一个群，设置全部提醒、仅@相关或仅收录。', '群规则覆盖默认规则；如果发送者有联系人规则，优先使用联系人规则。'],
  blocks:['不再出现在岛上的消息', '屏蔽指定联系人或群聊，飞书中的原始消息不受影响。', '目前没有屏蔽对象', '选择不需要出现在你的飞包上的人或群。', '屏蔽优先于所有提醒：新消息不再收录，已有消息暂时隐藏。解除后恢复已有记录，不补回屏蔽期间的消息。']
};
const modeLabels = {all:'全部提醒', mentions:'仅@我或@所有人时提醒', quiet:'仅收录，不提醒'};
function selectTab(tab) {
  activeTab = tab;
  $$('[data-tab]').forEach(button => { const active = button.dataset.tab === tab; button.classList.toggle('active', active); button.setAttribute('aria-selected', String(active)); });
  $('#defaults-panel').hidden = tab !== 'defaults'; $('#custom-panel').hidden = tab === 'defaults';
  $('#reset').hidden = tab !== 'defaults';
  renderCustom();
}
function changed() { setStatus(dirty() ? '有未保存的修改，点击保存后生效' : '已与你的飞包同步'); render(); }
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
    text('#picker-source', error.status ? error.message : '查询未完成，请检查你的飞包连接后重试。');
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
  if (!['general','feishu','modules','workspace'].includes(page)) page = 'feishu';
  $$('.page').forEach(section => section.hidden = section.id !== `page-${page}`);
  $$('.nav-item').forEach(button => { const active = button.dataset.page === page; button.classList.toggle('active', active); if (active) button.setAttribute('aria-current','page'); else button.removeAttribute('aria-current'); });
  text('#breadcrumb', {workspace:'材料与待办', general:'通用设置', feishu:'飞书消息', modules:'功能模块'}[page]);
  if (location.hash !== `#${page}`) history.replaceState(null,'',`#${page}`);
}
$$('[data-page]').forEach(button => button.addEventListener('click', () => selectPage(button.dataset.page)));
window.addEventListener('hashchange', () => selectPage(location.hash.slice(1)));
$$('[data-preview]').forEach(button => button.addEventListener('click', () => { previewType = button.dataset.preview; renderPreview(); }));
window.addEventListener('beforeunload', event => { if (dirty()) { event.preventDefault(); event.returnValue = ''; } });
selectPage(location.hash.slice(1)); load(); setInterval(() => { if (!document.hidden) load(); }, 2000);

$$('[data-danmu]').forEach(button=>button.addEventListener('click',()=>{draft.danmu[button.dataset.danmu]=!draft.danmu[button.dataset.danmu];changed();}));
for(const [id,key] of [['#cli-path','cliPath'],['#cli-profile','profile']])$(id).addEventListener('input',()=>{draft.connection[key]=$(id).value;if(JSON.stringify(draft.connection)!==JSON.stringify(saved.connection))draft.enabled=false;changed();});
$('#danmu-font').addEventListener('input',()=>{draft.appearance.fontSize=Number($('#danmu-font').value);changed();});
$('#danmu-theme').addEventListener('change',()=>{const mode=$('#danmu-theme').value;if(mode==='custom')return;Object.assign(draft.appearance,{background:mode==='system'?null:mode==='night'?'#111111':'#ffffff',foreground:mode==='system'?null:mode==='night'?'#ffffff':'#111111'});changed();});
$('#danmu-demo').addEventListener('click',async()=>{try{await request('POST',{},'/api/demo');setStatus('已发送一条合成消息，不读取飞书。');}catch(e){setStatus(e.message,true);}});
$('#connect-agent').addEventListener('click',async()=>{const button=$('#connect-agent');try{const link=await request('POST',{},'/api/agent');await navigator.clipboard.writeText(`请按我接下来的描述定制你的飞包的个人灵动岛阅读外观。使用本机 MCP（Streamable HTTP）${link.endpoint}，Authorization: Bearer ${link.token}。先 initialize、tools/list，再 read_appearance、update_appearance；读取 saved=true 后才算保存成功。连接 30 分钟有效、锁屏撤销，请保持本机应用打开。仅外观；不得索取消息、凭据或修改核心设置。也可用本机 HTTP 工具发送标准 JSON-RPC。不要输出密钥，不让我手动贴回 JSON。`);button.textContent='已复制，发给 Agent';}catch(e){setStatus(e.message,true);}finally{setTimeout(()=>{button.textContent='接入 Agent';},4000);}});

async function workspaceAction(payload) {
  try {
    const state = await request(payload ? 'POST' : 'GET', payload, '/api/workspace');
    text('#workspace-state', `${state.aiAvailable ? `本机${state.aiTool}已找到` : '未找到本机AI工具'} · ${state.taskCount}项材料/待办 · ${state.hubConnected ? '中台已连接' : '中台待本人授权'}`);
    if (document.activeElement !== $('#workspace-minutes')) $('#workspace-minutes').value = state.reminderMinutes;
    text('#workspace-feedback', state.error || state.hubError || (payload ? '操作已提交' : ''));
  } catch(e) { text('#workspace-feedback', e.message); }
}
$('#workspace-open').addEventListener('click',()=>workspaceAction({action:'open'}));
$('#workspace-connect').addEventListener('click',()=>workspaceAction({action:'connect'}));
$('#workspace-disconnect').addEventListener('click',()=>workspaceAction({action:'disconnect'}));
$('#workspace-save-minutes').addEventListener('click',()=>workspaceAction({action:'minutes',minutes:Number($('#workspace-minutes').value)}));
$('#workspace-add-recipe').addEventListener('click',()=>workspaceAction({action:'recipe',title:$('#workspace-recipe-title').value,instruction:$('#workspace-recipe-instruction').value}));
workspaceAction();
setInterval(()=>{ if (!$('#page-workspace').hidden) workspaceAction(); },15000);

async function companyAction(action) {
  const buttons=['#company-open','#company-receive','#company-archive','#company-disable-receive','#company-disable-archive','#company-reset'].map($);
  buttons.forEach(b=>b.disabled=true);
  if(action)text('#company-status','正在处理连接…');
  try {
    const result=await request(action?'POST':'GET',action?{action}:undefined,'/api/company');
    text('#company-status',result.message || '公司连接采用各自授权，已有本机接收保持原配置。');
    if(action==='receive'){saved=null;draft=null;await load();}
  } catch(e){text('#company-status',e.message);}
  finally{buttons.forEach(b=>b.disabled=false);}
}
$('#company-open').addEventListener('click',()=>companyAction('open'));
$('#company-receive').addEventListener('click',()=>companyAction('receive'));
$('#company-archive').addEventListener('click',()=>companyAction('archive'));
$('#company-disable-receive').addEventListener('click',()=>companyAction('disableReceive'));
$('#company-disable-archive').addEventListener('click',()=>companyAction('disableArchive'));
$('#company-reset').addEventListener('click',()=>companyAction('reset'));
companyAction();
