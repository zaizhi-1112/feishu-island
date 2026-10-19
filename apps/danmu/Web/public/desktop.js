'use strict';
(()=>{
 const base='http://127.0.0.1:48763';let token=null,pending=null,connected=false,instance=null,lastInstance=null;
 const label=text=>{document.getElementById('desktopStatus').textContent=text;};
 async function request(path,body){const response=await fetch(base+path,{method:body===undefined?'GET':'POST',headers:body===undefined?{}:{'content-type':'application/json','x-danmu-token':token},body:body===undefined?undefined:JSON.stringify(body),cache:'no-store',targetAddressSpace:'loopback',signal:AbortSignal.timeout(2500)});if(!response.ok)throw new Error('本机组件请求失败');return response.json();}
 function appearance(){return window.PersonalAppearance.get();}
 async function connect(){if(connected)return true;if(pending)return pending;pending=(async()=>{try{const info=await request('/handshake');if(info.version!=='0.7.1'||typeof info.token!=='string')throw new Error('本机组件版本不匹配');token=info.token;instance=info.instance;connected=true;await window.PersonalAppearance.ready;await request('/appearance',appearance());await request('/control',{paused:typeof paused==='boolean'?paused:false});localStorage.setItem('danmu-desktop-enabled','1');label('桌面组件已连接 · 透明置顶 · 鼠标穿透');return true;}catch{connected=false;token=null;label('桌面组件未连接。请启动本机组件；若浏览器询问访问本地网络，请允许。');return false;}finally{pending=null;}})();return pending;}
 async function send(path,body){if(!connected)throw new Error('桌面组件尚未连接');try{return await request(path,body);}catch(e){connected=false;token=null;label('桌面连接中断，请点击“连接桌面组件”重连。');throw e;}}
 window.DesktopBridge={get connected(){return connected;},connect,present:async message=>send('/present',{id:message.id||'',demo:!!message.demo,text:message.demo?message.text:`${message.chat} · ${message.sender}：${message.text}`}),agentConnect:()=>send('/agent/connect',{}),control:body=>connected?send('/control',body):Promise.resolve(),appearance:body=>connected?send('/appearance',body):Promise.resolve()};
 document.getElementById('desktopConnect').onclick=connect;
 // Local-only polling gives Agent skin edits immediate feedback; it never polls Feishu.
 let syncing=false;
 setInterval(async()=>{if(!connected||syncing)return;syncing=true;try{const state=await send('/agent/state',{});if(!state.saved){await window.PersonalAppearance.save(state.appearance);await send('/agent/ack',{revision:state.revision});}}catch{}finally{syncing=false;}},2000);
 document.addEventListener('danmu-appearance',e=>{if(connected)window.DesktopBridge.appearance(e.detail).catch(()=>{});});
 // Heartbeat keeps an in-memory overlay alive while users work in Feishu; no messages are written to disk.
 setInterval(async()=>{if(!connected){if(localStorage.getItem('danmu-desktop-enabled')==='1')connect();return;}try{await send('/heartbeat',{});}catch{}},10000);
 if(new URLSearchParams(location.search).get('desktop')==='1'||localStorage.getItem('danmu-desktop-enabled')==='1')connect();
})();
