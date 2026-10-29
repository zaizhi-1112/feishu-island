'use strict';
// Build90 interaction model. Synthetic state never leaves this page.
(() => {
  const $ = selector => document.querySelector(selector);
  const $$ = selector => [...document.querySelectorAll(selector)];
  const escape = text => String(text).replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  const desktop = $('#demo-desktop'), island = $('#island'), panel = $('#demo-panel');
  const moduleNames = ['飞书消息', 'Agent 状态', '待办与日程', '我的卡片'];
  const captions = ['点开一条消息，试试完整阅读。','切换工具，看看状态和额度各自怎样呈现。','记下一件小事，完成后还能找回来。','展开卡片看全文，快捷入口在独立轮盘里。'];
  let current = 0, pinned = false, keyboardMode = false, collapseTimer, toastTimer, readerTimer;
  document.addEventListener("keydown", event => { if (event.key === "Tab") keyboardMode = true; });
  document.addEventListener("pointerdown", () => { keyboardMode = false; });
  let messageMode = 'important', reading = null, readingPage = 0, automatic = false, muted = false;
  let agentID = 'codex', agentState = 'working', todoPage = 'tasks', editing = null, completedOpen = false, nextTodo = 3, scheduleEditing = false;
  let reminderOffsets = ['提前 1 天', '提前 15 分钟'];
  const today = new Date();
  const tomorrow = new Date(today.getFullYear(), today.getMonth(), today.getDate()+1, 15, 0);
  const dateText = value => new Date(value).toLocaleString('zh-CN',{year:'numeric',month:'long',day:'numeric',hour:'2-digit',minute:'2-digit',hour12:false});
  const messages = [
    {id:'plan',source:'项目讨论',sender:'林同学',reason:'提到我',important:true,viewed:false,pages:['下午的讨论改到 3 点。方案已整理成三个部分：活动流程、物料检查和现场分工。\n\n请大家先看一遍，缺少的内容在会前补齐。','现场物料会在明天上午统一核对。请负责签到、设备和摄影的同学确认清单。\n\n这是一段用于网页体验的示例消息。翻页后仍能回到前文，不会截断长消息。']},
    {id:'reply',source:'陈同学',sender:'陈同学',reason:'私聊',important:true,viewed:false,pages:['材料收到了，等你方便时一起核对。']},
    {id:'group',source:'日常交流',sender:'许同学',reason:'普通群消息',important:false,viewed:false,pages:['今天的分享资料已整理好，大家按需查看。']}
  ];
  const initialTodos = () => [{id:1,title:'确认下午的活动流程',done:false,deadline:tomorrow.toISOString(),reminder:''},{id:2,title:'整理本周工作计划',done:false,deadline:'',reminder:''}];
  let todos = initialTodos();
  const action = (name, label, extras='') => `<button data-action="${name}" ${extras}>${label}</button>`;
  function toast(message) { clearTimeout(toastTimer); $('#demo-toast').textContent=message; $('#demo-toast').hidden=false; toastTimer=setTimeout(()=>{$('#demo-toast').hidden=true;},4200); }
  function openIsland() { clearTimeout(collapseTimer); desktop.dataset.phase='open'; $('#expand-island').setAttribute('aria-expanded','true'); $('#island-content').inert=false; }
  function closeIsland() {
    const inputActive = island.contains(document.activeElement) && document.activeElement.matches('input,select,textarea');
    if (desktop.dataset.autoplay==='playing' || pinned || editing !== null || inputActive || (keyboardMode && island.contains(document.activeElement)) || !$('#wheel-overlay').hidden) return;
    stopReading(); desktop.dataset.phase='closed'; $('#expand-island').setAttribute('aria-expanded','false'); $('#island-content').inert=true;
  }
  function scheduleCollapse() { clearTimeout(collapseTimer); collapseTimer=setTimeout(closeIsland,650); }
  island.addEventListener('pointerenter',()=>{clearTimeout(collapseTimer);if($('#hover-mode').value==='full')openIsland();});
  island.addEventListener('pointerleave',scheduleCollapse);
  island.addEventListener('focusin',openIsland);
  island.addEventListener('focusout',()=>{if(!island.matches(':hover'))scheduleCollapse();});
  $('#expand-island').addEventListener('click',openIsland);
  $('#pin-island').addEventListener('click',()=>{pinned=!pinned;$('#pin-island').setAttribute('aria-pressed',String(pinned));$('#pin-island').setAttribute('aria-label',pinned?'取消固定':'固定展开');toast(pinned?'已固定，移开也会保持展开。':'已取消固定，移开后收起。');});
  $('#hover-mode').addEventListener('change',()=>{ $('#compact-title').textContent='一切在岛';$('#experience-note').textContent=$('#hover-mode').value==='peek'?'先露出胶囊模式：移入后点击胶囊，才会展开。':'完整展开模式：鼠标移入即展开，移开收起。'; if(!pinned){desktop.dataset.phase='closed';$('#expand-island').setAttribute('aria-expanded','false');$('#island-content').inert=true;} });
  $('#demo-theme').addEventListener('click',()=>{const light=desktop.dataset.theme!=='light';desktop.dataset.theme=light?'light':'dark';$('#demo-theme').setAttribute('aria-pressed',String(light));$('#demo-theme').textContent=light?'切换深色':'切换浅色';});
  function stopReading() {clearTimeout(readerTimer);automatic=false;}
  function readerTick() {
    clearTimeout(readerTimer);
    if(!automatic || reading===null || document.hidden || !demoVisible)return;
    readerTimer=setTimeout(()=>{if(readingPage+1<messages[reading].pages.length){readingPage++;render();readerTick();}else{automatic=false;render();}},12000);
  }
  function renderMessages() {
    if(reading!==null){const msg=messages[reading];return `${action('back','‹ 消息列表')}<div class="native-row reader-title"><h4>${msg.source}</h4><small>10:24</small></div>${msg.source!==msg.sender?`<small>${msg.sender}</small>`:''}<div class="native-card reader-body">${escape(msg.pages[readingPage])}</div><div class="reader-buttons">${action('previous','上一页',readingPage===0?'disabled':'')}<small>${readingPage+1} / ${msg.pages.length}</small>${action('next','下一页',readingPage+1===msg.pages.length?'disabled':'')}${action('automatic',automatic?'暂停':'自动',`aria-pressed="${automatic}"`)}</div><div class="reader-buttons">${action('remind-message','稍后提醒')}${action('open-chat','打开会话')}${action('done-message','读完')}</div>`;}
    const list=messages.filter(msg=>messageMode==='recent'||msg.important);
    return `<div class="native-segment">${action('important',`重要 ${messages.filter(m=>m.important&&!m.viewed).length}`,`aria-pressed="${messageMode==='important'}"`)}${action('recent','最近',`aria-pressed="${messageMode==='recent'}"`)}</div>${list.map(msg=>`<button class="message-card" data-message="${msg.id}"><div class="native-row"><strong>${msg.source}</strong><small>10:24${msg.viewed?' · 已看过':''}</small></div><p>${escape(msg.pages[0])}</p><span class="reason">${msg.reason}</span></button>`).join('')}<div class="native-footer">${action('mute',muted?'恢复提醒':'静音 1 小时')}<small>本页示例，不改变飞书已读</small></div>`;
  }
  function renderAgent() {
    const data={codex:{name:'Codex',glyph:'codex',detail:'只查看状态与额度，不在岛内派发任务。'},workbuddy:{name:'WorkBuddy',glyph:'workbuddy',detail:'积分按来源显示，不能当作任务完成进度。'},deepseek:{name:'DeepSeek Harness',glyph:'deepseek',detail:'仅查看本人账户余额，不推测任务状态。'}}[agentID];
    const state={working:'正在运行',waiting:'等你确认',completed:'已完成'}[agentState];
    let quotas=agentID==='codex'?`<div class="quota-row"><div class="native-row"><span>5 小时额度</span><span><strong>77.0%</strong> 剩余</span></div><meter min="0" max="100" value="77" aria-label="示例 5 小时额度剩余 77%"></meter></div><div class="quota-row"><div class="native-row"><span>周额度</span><span><strong>42.0%</strong> 剩余</span></div><meter min="0" max="100" value="42" aria-label="示例周额度剩余 42%"></meter></div>`:agentID==='workbuddy'?'<div class="quota-row"><div class="native-row"><span>剩余积分</span><strong>128.5 <small>积分</small></strong></div></div>':'<div class="quota-row"><div class="native-row"><span>账户余额</span><strong>—</strong></div><small>等待账户余额</small></div>';
    return `<div class="native-segment">${['codex','workbuddy','deepseek'].map(id=>`<button data-agent="${id}" aria-pressed="${id===agentID}">${{codex:'Codex',workbuddy:'WorkBuddy',deepseek:'DeepSeek'}[id]}</button>`).join('')}</div><div class="native-card" data-state="${agentState}"><div class="native-row agent-intro"><span class="agent-portrait" aria-hidden="true"><img src="native-agent-${data.glyph}.png" width="46" height="46" alt=""></span><div><h3>${data.name}</h3><p><span class="state-dot"></span>${agentID==='deepseek'?'等待余额':state}</p></div></div></div>${quotas}<small>${data.detail}</small><div class="native-footer">${action('refresh-agent','刷新状态')}<small>合成示例</small></div>${agentID!=='deepseek'?`<div class="demo-scenario"><span>体验状态</span>${Object.entries({working:'运行',waiting:'待确认',completed:'完成'}).map(([key,label])=>`<button data-state-choice="${key}" aria-pressed="${agentState===key}">${label}</button>`).join('')}</div>`:''}`;
  }
  function todoRow(todo){return `<div class="native-card ${todo.done?'todo-done':''}"><div class="todo-line"><button class="check-task" data-complete="${todo.id}" aria-label="${todo.done?'重新打开：':'完成：'}${escape(todo.title)}">${todo.done?'●':'○'}</button><div class="todo-text">${escape(todo.title)}${todo.done?`<small>完成于 ${escape(dateText(todo.completedAt))}</small>`:todo.deadline?`<small>完成期限 · ${escape(dateText(todo.deadline))}</small>`:''}${todo.reminder&&!todo.done?`<small>提醒 · ${escape(dateText(todo.reminder))}</small>`:''}</div>${todo.done?`<button class="edit-task" data-complete="${todo.id}">重新打开</button>`:`<button class="edit-task" data-edit="${todo.id}" aria-label="编辑：${escape(todo.title)}">编辑</button>`}</div></div>`;}
  function localDateValue(value){if(!value)return '';const d=new Date(value);return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}T${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`;}
  function renderTodos() {
    const segments=`<div class="native-segment">${action('tasks','我的待办',`aria-pressed="${todoPage==='tasks'}" ${editing!==null?'disabled':''}`)}${action('calendar','飞书日程',`aria-pressed="${todoPage==='calendar'}" ${editing!==null?'disabled':''}`)}</div>`;
    if(todoPage==='calendar')return segments+renderCalendar();
    if(editing!==null){const todo=todos.find(t=>t.id===editing);return segments+`<div class="native-editor"><div class="native-row"><h3>编辑待办</h3>${action('cancel-edit','取消')}</div><label for="edit-title">待办事项</label><input id="edit-title" maxlength="80" value="${escape(todo.title)}"><label for="edit-deadline">完成期限</label><input id="edit-deadline" type="datetime-local" value="${localDateValue(todo.deadline)}"><label for="edit-reminder">提醒时间</label><input id="edit-reminder" type="datetime-local" value="${localDateValue(todo.reminder)}"><small class="date-hint">时间仅用于网页体验，不会创建实际提醒。</small>${action('save-edit','保存')}</div>`;}
    const pending=todos.filter(t=>!t.done),done=todos.filter(t=>t.done);
    return segments+`<div class="native-row"><h3>待办</h3><small>${pending.length} 项待完成</small></div><div class="todo-add"><input id="todo-input" aria-label="接下来要做的事" placeholder="接下来要做的事" maxlength="80"><button data-action="add-todo" aria-label="添加待办" disabled>＋</button></div>${pending.length?pending.map(todoRow).join(''):'<p class="native-empty">暂无待办事项</p>'}<details class="todo-history" ${completedOpen?'open':''}><summary>已完成 ${done.length}</summary><div class="todo-history-list">${done.length?done.map(todoRow).join(''):'<small>完成的事项会显示在这里。</small>'}</div></details>`;
  }
  function renderCalendar(){return `<div class="native-row">${action('sync-calendar','立即同步')}${action('new-calendar','新建日程 ↗')}</div><small>示例账号 · 本人主日历 · 未来 30 天</small><p class="calendar-heading">${tomorrow.toLocaleDateString('zh-CN',{month:'long',day:'numeric',weekday:'long'})}</p><div class="native-card"><h4>项目方案讨论</h4><p class="schedule-time">15:00—16:00</p><div class="chips">${reminderOffsets.length?reminderOffsets.map(o=>`<span>${o}</span>`).join(''):'<span>不提醒</span>'}</div><div class="native-footer">${action('schedule-edit','修改提醒')}${action('view-calendar','在飞书中查看 ↗')}</div>${scheduleEditing?`<div class="schedule-form">${['提前 1 天','提前 1 小时','提前 15 分钟'].map(o=>`<label><input type="checkbox" name="schedule-offset" value="${o}" ${reminderOffsets.includes(o)?'checked':''}>${o}</label>`).join('')}${action('schedule-save','保存提醒')}</div>`:''}</div><small>日程从飞书只读同步；新建和编辑回到飞书。</small>`;}
  function renderHub(){return `<div class="native-row"><h3>我的卡片</h3>${action('refresh-hub','刷新')}</div><details class="native-card hub-card" open><summary>工作计划</summary><p>1. 整理本周项目进展。\n2. 和同事核对新版交互。\n3. 为下次讨论准备材料。</p>${action('open-hub','打开中台原页 ↗')}</details><details class="native-card hub-card"><summary>项目备忘</summary><p>把关心的内容放进个人卡片。每张卡片可以展开阅读，也能返回原来的页面。</p>${action('open-hub','打开中台原页 ↗')}</details>`;}
  function render(){const scroll=panel.scrollTop;panel.innerHTML=[renderMessages,renderAgent,renderTodos,renderHub][current]();panel.scrollTop=scroll;}
  function select(index,focus=false){stopReading();current=(index+4)%4;$('#demo-caption').textContent=captions[current];$('#compact-title').textContent=moduleNames[current];$$('[data-slide]').forEach((button,i)=>{button.setAttribute('aria-selected',String(i===current));button.tabIndex=i===current?0:-1;});$$('[data-module]').forEach((button,i)=>button.setAttribute('aria-pressed',String(i===current)));panel.setAttribute('aria-labelledby',`tab-${current}`);render();panel.scrollTop=0;openIsland();if(focus)$(`[data-slide="${current}"]`).focus();}
  $$('[data-slide]').forEach(button=>button.addEventListener('click',()=>select(Number(button.dataset.slide))));
  $$('[data-module]').forEach(button=>button.addEventListener('click',()=>select(Number(button.dataset.module))));
  function tabKeyboard(buttons,callback){buttons.forEach((button,i)=>button.addEventListener('keydown',event=>{const index={ArrowRight:(i+1)%buttons.length,ArrowLeft:(i+buttons.length-1)%buttons.length,Home:0,End:buttons.length-1}[event.key];if(index!==undefined){event.preventDefault();callback(index);buttons[index].focus();}}));}
  tabKeyboard($$('[data-slide]'),index=>select(index));
  function addTodo(){const input=$('#todo-input');const title=input.value.trim();if(!title)return;if(todos.length>=20){toast('体验里最多保留 20 条，可以重置再试。');return;}todos.unshift({id:nextTodo++,title,done:false,deadline:'',reminder:''});render();$('#todo-input').focus();}
  panel.addEventListener('input',event=>{if(event.target.id==='todo-input')$('[data-action="add-todo"]').disabled=!event.target.value.trim();});
  panel.addEventListener('keydown',event=>{if(event.target.id==='todo-input'&&event.key==='Enter'&&!event.isComposing){event.preventDefault();addTodo();}});
  panel.addEventListener('toggle',event=>{if(event.target.classList.contains('todo-history'))completedOpen=event.target.open;},true);
  panel.addEventListener('click',event=>{
    const button=event.target.closest('button');if(!button)return;
    if(button.dataset.message){reading=messages.findIndex(m=>m.id===button.dataset.message);readingPage=0;stopReading();render();panel.scrollTop=0;return;}
    if(button.dataset.agent){agentID=button.dataset.agent;render();return;}
    if(button.dataset.stateChoice){agentState=button.dataset.stateChoice;render();toast({working:'Codex · 正在运行',waiting:'Codex · 等你确认',completed:'Codex · 已完成'}[agentState].replace('Codex',agentID==='codex'?'Codex':'WorkBuddy'));return;}
    if(button.dataset.complete){const todo=todos.find(t=>t.id===Number(button.dataset.complete));todo.done=!todo.done;todo.completedAt=new Date().toISOString();if(!todo.done)todo.reminder='';completedOpen=true;render();toast(todo.done?'又完成一件事。已放进完成记录。':'已恢复待办，旧提醒已关闭。');return;}
    if(button.dataset.edit){editing=Number(button.dataset.edit);render();panel.scrollTop=0;$('#edit-title').focus();return;}
    switch(button.dataset.action){
      case 'important':messageMode='important';render();break;
      case 'recent':messageMode='recent';render();break;
      case 'back':stopReading();reading=null;render();break;
      case 'previous':stopReading();readingPage=Math.max(0,readingPage-1);render();break;
      case 'next':stopReading();readingPage=Math.min(messages[reading].pages.length-1,readingPage+1);render();break;
      case 'automatic':automatic=!automatic;render();readerTick();break;
      case 'done-message':messages[reading].viewed=true;reading=null;stopReading();render();toast('已在岛内读完，不改变飞书已读状态。');break;
      case 'remind-message':messages[reading].viewed=true;reading=null;stopReading();render();toast('示例已设稍后提醒；网页不会创建真实提醒。');break;
      case 'open-chat':toast('安装版会打开对应飞书会话；网页使用合成消息。');break;
      case 'mute':muted=!muted;render();toast(muted?'本页演示已静音。':'本页演示已恢复提醒。');break;
      case 'refresh-agent':toast('这是合成状态。安装版按所连接工具读取实际数据。');break;
      case 'tasks':todoPage='tasks';render();break;
      case 'calendar':todoPage='calendar';render();panel.scrollTop=0;break;
      case 'add-todo':addTodo();break;
      case 'cancel-edit':editing=null;render();break;
      case 'save-edit':{const title=$('#edit-title').value.trim();if(!title){$('#edit-title').focus();return;}const todo=todos.find(t=>t.id===editing);todo.title=title;todo.deadline=$('#edit-deadline').value;todo.reminder=$('#edit-reminder').value;editing=null;render();toast('已保存到本页体验。');break;}
      case 'schedule-edit':scheduleEditing=!scheduleEditing;render();break;
      case 'schedule-save':reminderOffsets=$$('input[name="schedule-offset"]:checked').map(i=>i.value);scheduleEditing=false;render();toast('已更新示例日程的提醒。');break;
      case 'sync-calendar':toast('示例日程已是最新；安装版读取本人未来 30 天日程。');break;
      case 'new-calendar':case 'view-calendar':toast('安装版会打开飞书日历，在飞书内新建或查看。');break;
      case 'refresh-hub':toast('示例卡片已刷新；安装版读取你有权限的中台内容。');break;
      case 'open-hub':toast('安装版会打开这张卡片的中台原页。');break;
    }
  });
  $('#reset-demo').addEventListener('click',()=>{todos=initialTodos();nextTodo=3;editing=null;reading=null;readingPage=0;messageMode='important';muted=false;agentID='codex';agentState='working';todoPage='tasks';completedOpen=false;scheduleEditing=false;reminderOffsets=['提前 1 天','提前 15 分钟'];messages.forEach(m=>m.viewed=false);pinned=false;$('#pin-island').setAttribute('aria-pressed','false');$('#pin-island').setAttribute('aria-label','固定展开');select(0);toast('已恢复最初的合成示例。');});
  $('#download').addEventListener('click',()=>{$('#download-feedback').hidden=false;});
  // A wheel stays inside the demo; it never launches native apps or external pages.
  const wheel=$('#shortcut-wheel'),wheelButtons=$$('[data-destination]');let wheelArmed=false,wheelIndex=-1;
  function closeWheel(message){$('#wheel-overlay').hidden=true;$('#island-content').inert=desktop.dataset.phase==='closed';$('#demo-caption').textContent=captions[current];$('#open-wheel').focus();if(message)toast(message);}
  $('#open-wheel').addEventListener('click',()=>{wheelArmed=false;wheelIndex=-1;wheelButtons.forEach(b=>b.setAttribute('aria-pressed','false'));$('#wheel-overlay').hidden=false;$('#island-content').inert=true;$('#demo-caption').textContent='从中央滑向外圈，或直接点选；Esc 取消。';$('#wheel-cancel').focus();});
  $('#wheel-cancel').addEventListener('click',()=>closeWheel());
  wheelButtons.forEach(button=>button.addEventListener('click',()=>closeWheel(`已选择“${button.dataset.destination}”。安装版会打开对应入口。`)));
  wheel.addEventListener('pointermove',event=>{if(event.pointerType!=='mouse')return;const rect=wheel.getBoundingClientRect(),x=event.clientX-rect.left-rect.width/2,y=event.clientY-rect.top-rect.height/2,r=Math.hypot(x,y);if(r<40){wheelArmed=true;wheelIndex=-1;}else{wheelIndex=Math.round((Math.atan2(y,x)+Math.PI/2+Math.PI*2)%(Math.PI*2)/(Math.PI/4))%8;}wheelButtons.forEach((b,i)=>b.setAttribute('aria-pressed',String(i===wheelIndex)));if(wheelArmed&&r>140&&wheelIndex>=0)closeWheel(`已选择“${wheelButtons[wheelIndex].dataset.destination}”。安装版会打开对应入口。`);});
  document.addEventListener('keydown',event=>{if(event.key==='Escape'&&!$('#wheel-overlay').hidden){event.preventDefault();closeWheel();}});
  // Feedback stays in a modal; drafts are kept only in the current page.
  const feedbackDialog=$('#feedback-dialog');
  $('#open-feedback').addEventListener('click',()=>{if(!$('#wheel-overlay').hidden)closeWheel();pauseForInteraction();feedbackDialog.showModal();document.body.classList.add('dialog-open');});
  $('#close-feedback').addEventListener('click',()=>feedbackDialog.close());
  feedbackDialog.addEventListener('close',()=>{document.body.classList.remove('dialog-open');pauseForInteraction();});
  feedbackDialog.addEventListener('click',event=>{if(event.target===feedbackDialog){const r=feedbackDialog.getBoundingClientRect();if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)feedbackDialog.close();}});
  // Mailto hands a reviewed draft to the user's mail client. No fake sent state.
  const recipient='zaizhi@virxact.com';
  const feedbackBody=()=>`一切在岛反馈\n版本：0.11.1 · build 90\n类型：${$('#feedback-type').value}\n\n${$('#feedback-content').value.trim()}`;
  function validFeedback(){if(!$('#feedback-content').value.trim()){$('#feedback-content').setCustomValidity('请先写下你遇到的问题或建议。');}else{$('#feedback-content').setCustomValidity('');}return $('#feedback-form').reportValidity();}
  function updateMailLink(){ $('#feedback-mail').href=`mailto:${recipient}?subject=${encodeURIComponent('一切在岛 · '+$('#feedback-type').value)}&body=${encodeURIComponent(feedbackBody())}`; $('#feedback-status').textContent='会打开你的邮件应用，确认后发送。若没有打开，可复制内容手动发邮件。'; }
  $('#feedback-content').addEventListener('input',()=>{$('#feedback-content').setCustomValidity('');updateMailLink();});
  $('#feedback-type').addEventListener('change',updateMailLink);
  $('#feedback-form').addEventListener('submit',event=>event.preventDefault());
  $('#feedback-mail').addEventListener('click',event=>{if(!validFeedback()){event.preventDefault();return;}$('#feedback-mail').href=`mailto:${recipient}?subject=${encodeURIComponent('一切在岛 · '+$('#feedback-type').value)}&body=${encodeURIComponent(feedbackBody())}`;$('#feedback-status').textContent='邮件内容已准备，请在打开的邮箱里确认并发送。网页尚未发送邮件。';});
  async function copy(text,success){try{await navigator.clipboard.writeText(text);$('#feedback-status').textContent=success;}catch{$('#feedback-status').textContent='浏览器未允许复制，请选中文字手动复制。';}}
  $('#copy-feedback').addEventListener('click',()=>{if(validFeedback())copy(feedbackBody(),`反馈已复制。请粘贴到邮件，发送给 ${recipient}。`);});
  // Rotate only when the demo is visible and nobody is working in it.
  // A single timer serves this local preview; it never polls a backend.
  const carouselInterval=8000, idleDelay=20000;
  let demoVisible=false, carouselEnabled=true, carouselTimer, lastInteraction=-idleDelay;
  function holdsCarousel(){
    const active=document.activeElement;
    return document.hidden || !demoVisible || feedbackDialog.open || pinned ||
      editing!==null || reading!==null || scheduleEditing || !$('#wheel-overlay').hidden ||
      Boolean($('#todo-input')?.value.trim()) ||
      ($('#demo').contains(active) && (active.matches('input,select,textarea') || keyboardMode));
  }
  function scheduleCarousel(delay=carouselInterval){
    clearTimeout(carouselTimer);
    if(!carouselEnabled || holdsCarousel()){desktop.dataset.autoplay='paused';return;}
    carouselTimer=setTimeout(()=>{
      if(!carouselEnabled || holdsCarousel()){desktop.dataset.autoplay='paused';return;}
      const remaining=idleDelay-(performance.now()-lastInteraction);
      if(remaining>0){scheduleCarousel(remaining);return;}
      select(current+1);
      desktop.dataset.autoplay='playing';
      scheduleCarousel();
    },delay);
  }
  function pauseForInteraction(){
    lastInteraction=performance.now();
    desktop.dataset.autoplay='paused';
    clearTimeout(carouselTimer);
    queueMicrotask(()=>scheduleCarousel(idleDelay));
  }
  for(const eventName of ['pointerdown','keydown','input','change']){
    $('#demo').addEventListener(eventName,event=>{if(!event.target.closest('#autoplay-toggle'))pauseForInteraction();},true);
  }
  $('#demo').addEventListener('focusout',()=>queueMicrotask(()=>scheduleCarousel()));
  $('#autoplay-toggle').addEventListener('click',()=>{
    carouselEnabled=!carouselEnabled;
    $('#autoplay-toggle').textContent=carouselEnabled?'暂停轮播':'继续轮播';
    document.dispatchEvent(new CustomEvent('island:motion',{detail:{paused:!carouselEnabled}}));
    if(carouselEnabled){lastInteraction=-idleDelay;openIsland();desktop.dataset.autoplay='playing';}
    scheduleCarousel();
  });
  new IntersectionObserver(entries=>{
    demoVisible=entries[0].isIntersecting;
    if(!demoVisible){clearTimeout(readerTimer);clearTimeout(collapseTimer);}else if(automatic)readerTick();
    scheduleCarousel();
  },{threshold:.25}).observe(desktop);
  document.addEventListener('visibilitychange',()=>{if(document.hidden)clearTimeout(readerTimer);else if(automatic)readerTick();scheduleCarousel();});
  select(0);
  desktop.dataset.autoplay='playing';
})();
