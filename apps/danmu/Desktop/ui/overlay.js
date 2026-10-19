const box=document.getElementById('message'),heading=document.getElementById('heading'),text=document.getElementById('text'),page=document.getElementById('page');let paused=false,clearToken=0;
const wait=async(ms,token)=>{let remaining=ms,last=performance.now();while(remaining>0&&token===clearToken){await new Promise(r=>setTimeout(r,50));const now=performance.now();if(!paused)remaining-=Math.min(100,now-last);last=now;}return token===clearToken;};
window.danmu.onState(s=>{if('paused'in s)paused=s.paused;if(s.clear){clearToken++;box.hidden=true;}});
window.danmu.onMessage(async m=>{
 const token=++clearToken,p=m.prefs;const width=Math.min(600,Math.max(280,innerWidth*.43));box.style.width=m.card?width+'px':'auto';box.style.fontSize=p.size+'px';box.style.fontWeight=p.heavy?'700':'500';box.style.opacity=p.opacity;box.style.background=m.card||p.backdrop?'rgba(16,19,25,.94)':'transparent';box.style.color=m.gray?'#c2c4ca':[['#ffffff','#ff80a5','#ffdc70'],['#80e7df','#aeddf9'],['#ffb088','#ffd078'],['#ffffff']][p.palette][0];box.style.top=p.position===1?'35%':p.position===2?'auto':'54px';box.style.bottom=p.position===2?'54px':'auto';box.style.right='24px';box.style.left='auto';heading.textContent=m.demo?'[演示]':`${m.chat} · ${m.sender}`;box.hidden=false;
 if(m.card){
   // Conservative core pages are checked against real DOM height; if a font
   // wraps more widely, split the page further without dropping characters.
   const pending=[...m.parts];const fitted=[];
   while(pending.length){let chunk=pending.shift();text.textContent=chunk;const maxHeight=innerHeight*.55-90;
     if(text.getBoundingClientRect().height>maxHeight&&Array.from(chunk).length>1){const chars=Array.from(new Intl.Segmenter('zh',{granularity:'grapheme'}).segment(chunk),x=>x.segment),middle=Math.floor(chars.length/2);pending.unshift(chars.slice(middle).join(''));pending.unshift(chars.slice(0,middle).join(''));}else fitted.push(chunk);
   }
   for(let i=0;i<fitted.length&&token===clearToken;i++){text.textContent=fitted[i];page.hidden=false;page.textContent=`${i+1} / ${fitted.length} 页 · 正文完整分页`;const hold=Math.max(12000,Math.min(45000,4000+Array.from(fitted[i]).length/p.cardSpeed*1000));if(!await wait(hold,token))break;}
 }else{text.textContent=m.text;page.hidden=true;box.style.right='auto';box.style.left=innerWidth+'px';const full=innerWidth+box.offsetWidth;let elapsed=0,last=performance.now();while(elapsed<p.duration*1000&&token===clearToken){await new Promise(r=>requestAnimationFrame(r));const now=performance.now();if(!paused)elapsed+=Math.min(100,now-last);last=now;box.style.left=(innerWidth-full*elapsed/(p.duration*1000))+'px';}}
 if(token===clearToken)box.hidden=true;window.danmu.action('presented');
});
