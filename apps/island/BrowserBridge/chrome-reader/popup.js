'use strict';
let material=null;
const status=document.querySelector('#status'),preview=document.querySelector('#preview'),send=document.querySelector('#send'),read=document.querySelector('#read');
read.addEventListener('click',async()=>{
  material=null;send.disabled=true;read.disabled=true;status.textContent='正在读取当前页面…';
  try {
    const [tab]=await chrome.tabs.query({active:true,currentWindow:true});
    if(!tab?.id) throw new Error('请先打开要收录的网页。');
    const result=await chrome.scripting.executeScript({target:{tabId:tab.id},func:extractCurrentPage,args:[document.querySelector('#selection').checked]});
    material=result[0]?.result;
    if(!material?.text) throw new Error('当前页面不允许读取，请在普通网页重试。');
    preview.value=material.text;document.querySelector('#title').textContent=material.title;
    status.textContent=`已读取 ${material.text.length} 字，请核对后送入草稿。`;send.disabled=false;
  } catch(e) { status.textContent=e.message; } finally {read.disabled=false;}
});
send.addEventListener('click',async()=>{
  if(!material)return;send.disabled=true;read.disabled=true;status.textContent='正在送入工作岛…';
  try {
    const payload={...material,text:preview.value};
    if(!payload.text.trim()||new TextEncoder().encode(JSON.stringify(payload)).length>120000) throw new Error('正文为空或过长，请调整后重试。');
    const response=await fetch('http://127.0.0.1:18766/api/chrome-import',{method:'POST',credentials:'omit',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload),signal:AbortSignal.timeout(8000)});
    const result=await response.json();
    if(!response.ok||!result.saved) throw new Error(result.error||'未保存，请重试。');
    status.textContent='已送到工作岛「材料」草稿。回到灵动岛，可选交给 AI 或直接归档。';material=null;
  } catch(e) {status.textContent=e.name==='TypeError'?'无法连接本机工作岛，请确认应用已打开并开启“接收Chrome当前网页”。':e.message;send.disabled=false;} finally {read.disabled=false;}
});
