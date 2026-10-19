'use strict';
(()=>{
 const $=id=>document.getElementById(id),schema=window.DanmuAppearance;let current={...schema.defaults};
 function apply(input){current=schema.validate(input);for(const [key,prop]of [['background','--danmu-surface'],['foreground','--danmu-ink'],['border','--danmu-border']]){if(current[key])document.body.style.setProperty(prop,current[key]);else document.body.style.removeProperty(prop);}document.body.style.setProperty('--danmu-size',current.fontSize+'px');document.body.style.setProperty('--danmu-corner',current.corner+'px');document.body.dataset.layout=current.layout;document.body.dataset.motion=current.motion;$('historyCard').hidden=!current.showHistory;$('size').value=current.fontSize;$('size').dispatchEvent(new Event('input'));document.dispatchEvent(new CustomEvent('danmu-appearance',{detail:{...current}}));}
 async function save(input){const a=schema.validate(input),r=await fetch('/api/appearance',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(a)}),x=await r.json();if(!r.ok)throw new Error(x.error||'外观保存失败');apply(x.appearance);return current;}
 const ready=fetch('/api/appearance',{cache:'no-store'}).then(r=>{if(!r.ok)throw new Error('外观加载失败');return r.json();}).then(x=>apply(x.appearance));
 ready.catch(()=>{$('copyAgent').title='外观加载失败，请刷新后重试';});
 window.PersonalAppearance={get:()=>({...current}),save,ready};
 $('copyAgent').onclick=async()=>{
  const button=$('copyAgent');button.disabled=true;
  try{
   await ready;
   if(!await window.DesktopBridge.connect())throw new Error('请先连接桌面组件');
   const connection=await window.DesktopBridge.agentConnect();
   const prompt=`请通过本机飞书弹幕 MCP 按我接下来的描述调整个人外观。\nStreamable HTTP：${connection.endpoint}\nAuthorization: Bearer ${connection.token}\n有效期 30 分钟，仅在这台电脑的 Agent 中使用，保持飞书弹幕网页打开。先 initialize，再 tools/list，调用 read_appearance 读取当前设置，update_appearance 修改；最后读取到 saved=true 才说明保存成功。若尚未配置 MCP，也可用本机 HTTP 客户端向此地址 POST 标准 JSON-RPC，Accept: application/json, text/event-stream，Content-Type: application/json。仅可修改个人外观，不读取消息或凭证，不修改源码、接收、授权、过滤或部署。不要输出连接密钥，不让我手动编辑或贴回 JSON。`;
   await navigator.clipboard.writeText(prompt);
   button.textContent='已复制，发给 Agent';
  }catch(e){button.textContent=e.message==='请先连接桌面组件'?e.message:'接入失败，点击重试';button.title=e.message;}
  finally{button.disabled=false;setTimeout(()=>{button.textContent='接入 Agent';},5000);}
 };
})();
