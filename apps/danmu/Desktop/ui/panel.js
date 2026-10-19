const $=id=>document.getElementById(id);let current;
function render(s){current=s;$('status').textContent=s.status.text;$('latency').textContent=s.latency;$('counter').textContent=`真实消息 ${s.received} 条${s.dropped?' · 积压已移出 '+s.dropped+' 条':''}`;$('pending').textContent=`未读待展示 ${s.queue} 条`;$('badge').textContent=s.queue;$('badge').hidden=!s.queue;$('pause').textContent=s.paused?'继续播放':'暂停画面';$('listen').textContent=s.receiving?'停止接收':'开启接收';$('version').textContent=`v${s.version}`;$('connect').disabled=s.authBusy;$('configure').disabled=s.authBusy;
 for(const k of ['size','duration','cardSpeed','palette','position','poll','opacity'])if(document.activeElement!==$(k))$(k).value=s.prefs[k];
 for(const k of ['heavy','backdrop'])$(k).checked=s.prefs[k];for(const k of ['size','duration','cardSpeed'])$(k+'Value').textContent=s.prefs[k];
 for(const k of ['gray','hidden'])if(document.activeElement!==$(k))$(k).value=s.prefs[k].join('，');
 $('history').textContent=s.history.map(m=>`${m.chat} · ${m.sender}\n${m.text}`).join('\n\n');
}
for(const b of document.querySelectorAll('[data-page]'))b.onclick=()=>{document.querySelectorAll('.page').forEach(p=>p.hidden=p.id!==b.dataset.page);document.querySelectorAll('[data-page]').forEach(x=>x.classList.toggle('active',x===b));};document.querySelector('[data-page]').classList.add('active');
for(const k of ['size','duration','cardSpeed','palette','position','poll','opacity'])$(k).onchange=()=>window.danmu.action('prefs',{[k]:Number($(k).value)});
for(const k of ['heavy','backdrop'])$(k).onchange=()=>window.danmu.action('prefs',{[k]:$(k).checked});
for(const k of ['pause','listen','connect','clear','demo','guide'])$(k).onclick=()=>window.danmu.action(k);
$('rules').onclick=()=>window.danmu.action('prefs',Object.fromEntries(['gray','hidden'].map(k=>[k,$(k).value.split(/[,，、\n]/).map(x=>x.trim()).filter(Boolean)])));
$('configure').onclick=async()=>{const secret=$('secret').value;$('secret').value='';await window.danmu.action('configure',{appId:$('appId').value.trim(),secret});};$('launch').onchange=()=>window.danmu.action('launch',$('launch').checked);
window.danmu.onState(render);window.danmu.get().then(render);
