/* Runs in Chrome's isolated content world after an explicit action. No fetch or storage. */
function extractCurrentPage(selectionOnly) {
  if (!['http:', 'https:'].includes(location.protocol)) throw new Error('只支持当前打开的 HTTP/HTTPS 网页。');
  const blocked = 'script,style,noscript,iframe,svg,canvas,nav,header,footer,aside,form,input,textarea,select,button,[contenteditable="true"],[hidden],[aria-hidden="true"]';
  function visible(node) {
    if (node.closest(blocked)) return false;
    for (let p=node;p && p!==document.documentElement;p=p.parentElement) {
      const s=getComputedStyle(p);
      if(s.display==='none'||s.visibility==='hidden'||s.visibility==='collapse'||Number(s.opacity)===0) return false;
    }
    return node.getClientRects().length>0;
  }
  let text='';
  if(selectionOnly) {
    const selection=getSelection();
    if(!selection || selection.isCollapsed) throw new Error('请先在页面选中需要的正文，再打开收录。');
    const parent=selection.anchorNode?.parentElement;
    if(!parent || !visible(parent)) throw new Error('不能收录输入框或隐藏内容。');
    text=selection.toString().trim();
  } else {
    const candidates=[...document.querySelectorAll('article,main,[role="main"],#js_content')].filter(visible);
    const root=candidates.sort((a,b)=>(b.innerText||'').length-(a.innerText||'').length)[0] || document.body;
    const walker=document.createTreeWalker(root,4 /* SHOW_TEXT */);
    const chunks=[]; let n, count=0, bytes=0;
    while((n=walker.nextNode())) {
      if(++count>50000) throw new Error('页面过大，请选中需要的正文后收录。');
      if(!n.parentElement || !visible(n.parentElement)) continue;
      const line=n.textContent.replace(/\s+/g,' ').trim();
      if(line) { bytes+=new TextEncoder().encode(line).length+1; if(bytes>100000) throw new Error('正文超过100KB，请选中需要的部分。'); chunks.push(line); }
    }
    text=chunks.join('\n');
  }
  if(!text) throw new Error('没有找到可读正文。请在网页展开内容，或选中文字后再试。');
  if(new TextEncoder().encode(text).length>100000) throw new Error('正文超过100KB，请选中需要的部分。');
  const url=new URL(location.href); url.search=''; url.hash=''; url.username=''; url.password='';
  return {url:url.href,title:document.title.slice(0,500),text};
}
