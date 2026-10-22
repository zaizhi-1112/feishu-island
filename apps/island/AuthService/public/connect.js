'use strict';
// Only an explicitly initiated OAuth flow polls at the provider interval; stops on completion/cancel.
let flow=null,interval=5,timer=null,busy=false;
const feedback=document.querySelector('#feedback');
async function api(route,data){const r=await fetch('/api/auth/'+route,{method:data?'POST':'GET',headers:data?{'content-type':'application/json','X-Island-Auth':'1'}:{},body:data?JSON.stringify(data):undefined,signal:AbortSignal.timeout(20000)});const j=await r.json();if(!r.ok)throw new Error(j.error||'连接失败');return j;}
async function status(){try{const s=await api('status');for(const purpose of ['receive','archive']){const v=s[purpose];document.querySelector('#'+purpose+'-status').textContent=!v.configured?'服务未配置，请联系维护者':v.authorized?'已保存个人授权 · 可回 Mac 启用':'服务已配置 · 待本人授权';document.querySelector('[data-purpose="'+purpose+'"]').disabled=!!flow||!v.configured;}}catch(e){feedback.textContent=e.message;}}
function controls(on){for(const id of ['authorize','check','cancel'])document.querySelector('#'+id).hidden=!on;}
async function poll(){if(!flow||busy)return;busy=true;try{const r=await api('poll',{flow});if(r.state==='authorized'){flow=null;controls(false);feedback.textContent='个人授权已保存。请回到 Mac 设置启用对应连接，接收和归档的实际状态以 Mac 为准。';await status();}else{interval=r.interval||5;feedback.textContent='等待飞书确认授权…';timer=setTimeout(poll,interval*1000);}}catch(e){feedback.textContent=e.message+'；可点检查连接重试。';}finally{busy=false;}}
for(const button of document.querySelectorAll('[data-purpose]'))button.addEventListener('click',async()=>{if(flow||busy)return;busy=true;button.disabled=true;feedback.textContent='正在准备授权页…';try{const r=await api('start',{purpose:button.dataset.purpose});flow=r.flow;interval=r.interval;document.querySelector('#authorize').href=r.url;controls(true);feedback.textContent='点击打开飞书授权页，核对是你自己的账号，再确认权限。';timer=setTimeout(poll,interval*1000);}catch(e){feedback.textContent=e.message;}finally{busy=false;await status();}});
document.querySelector('#check').addEventListener('click',()=>{clearTimeout(timer);poll();});
document.querySelector('#cancel').addEventListener('click',async()=>{clearTimeout(timer);if(!flow)return;try{await api('cancel',{flow});flow=null;controls(false);feedback.textContent='本次连接已取消。';await status();}catch(e){feedback.textContent=e.message;}});
window.addEventListener('pagehide',()=>clearTimeout(timer));status();
