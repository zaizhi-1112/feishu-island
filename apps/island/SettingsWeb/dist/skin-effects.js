'use strict';
// A shared manifest supplies both the Swift theme and this studio. All art is bundled.
(() => {
  const root=document.documentElement, reduced=matchMedia('(prefers-reduced-motion: reduce)');
  let manifest, geometry, brandFlow, current='codex', effects=true, lastSkin='', lastAlert='', lastPreferences;
  const instances=new Set(), disposals=[];
  function velocity(x,y,t,pointer) {
    const a=.13,angle=-Math.PI/4,c=Math.cos(angle),s=Math.sin(angle),px=x-.57,py=y-.15,qx=px*c+py*s,qy=-px*s+py*c;
    const r2=Math.max(qx*qx+qy*qy,a*a*1.02),r4=r2*r2,k=11;
    const u=.055*(1-a*a*(qx*qx-qy*qy)/r4),v=-.11*a*a*qx*qy/r4;
    let vx=u*c-v*s,vy=u*s+v*c;
    const radius=Math.max(.0001,Math.hypot(px,py)),q=Math.min(1,Math.max(0,(radius/a-1.05)/.35)),damp=q*q*(3-2*q),derivative=q>0&&q<1?6*q*(1-q)/(a*.35):0,sx=Math.sin(k*x+t*.13),sy=Math.sin(k*y-t*.11),psi=.006/k*sx*sy;
    vx+=.006*damp*sx*Math.cos(k*y-t*.11)+psi*derivative*py/radius;
    vy-=.006*damp*Math.cos(k*x+t*.13)*sy+psi*derivative*px/radius;
    if(pointer){const dx=x-pointer.x,dy=y-pointer.y,d2=Math.max(.0025,dx*dx+dy*dy),strength=.00012*Math.exp(-d2/.05);vx+=strength*(dy*dy-dx*dx)/(d2*d2);vy-=strength*2*dx*dy/(d2*d2);}
    return [vx,vy];
  }
  const contours=[], lanes=[];
  function makeContours(){for(const points of geometry.paths){let distances=[0];for(let i=1;i<points.length;i++)distances.push(distances.at(-1)+Math.hypot(points[i][0]-points[i-1][0],(points[i][1]-points[i-1][1])/geometry.aspect));contours.push({points,distances,length:distances.at(-1)});}}
  function atLength(contour,d){d=((d%contour.length)+contour.length)%contour.length;let i=1;while(i<contour.distances.length-1&&contour.distances[i]<d)i++;const a=contour.points[i-1],b=contour.points[i],f=(d-contour.distances[i-1])/Math.max(.00001,contour.distances[i]-contour.distances[i-1]);return[a[0]+(b[0]-a[0])*f,a[1]+(b[1]-a[1])*f];}
  class Flow {
    constructor(canvas){
      this.canvas=canvas;this.ctx=canvas.getContext('2d',{alpha:true});this.back=document.createElement('canvas');this.front=document.createElement('canvas');this.pointer=null;this.visible=false;this.running=false;this.raf=0;this.tick=0;this.frames=0;this.timings=[];
      if(!this.ctx){canvas.dataset.fallback='static';canvas.parentElement.classList.add('flow-fallback');return;}
      this.resize=new ResizeObserver(()=>{this.fit();this.refresh();});this.resize.observe(canvas);
      this.intersection=new IntersectionObserver(entries=>{this.visible=entries[0].isIntersecting;this.refresh();});this.intersection.observe(canvas);
      this.move=e=>{const b=canvas.parentElement.getBoundingClientRect();this.pointer={x:(e.clientX-b.left)/b.width,y:(e.clientY-b.top)/b.width};};this.leave=()=>{this.pointer=null;};
      canvas.parentElement.addEventListener('pointermove',this.move,{passive:true});canvas.parentElement.addEventListener('pointerleave',this.leave);
      instances.add(this);this.fit();this.refresh();
    }
    fit(){const rect=this.canvas.getBoundingClientRect();this.w=rect.width;this.h=rect.height;this.dpr=Math.min(1.5,devicePixelRatio||1);const width=Math.max(1,Math.round(this.w*this.dpr)),height=Math.max(1,Math.round(this.h*this.dpr));for(const c of [this.canvas,this.back,this.front]){c.width=width;c.height=height;}
      this.artRect=this.canvas.parentElement.querySelector('#skin-live-art')?.getBoundingClientRect();this.canvasRect=this.canvas.getBoundingClientRect();const card=this.canvas.dataset.flow&&this.canvas.dataset.flow!=='selected';this.count=card?30:this.canvas.id==='skin-ambient'?45:80;this.points=Array.from({length:this.count},()=>this.spawn());this.last=0;this.tick=0;}
    spawn(){return{x:Math.random(),y:Math.random()*this.h/Math.max(1,this.w),life:4+Math.random()*14,phase:Math.random()};}
    get skin(){return this.canvas.dataset.flow&&this.canvas.dataset.flow!=='selected'?this.canvas.dataset.flow:current;}
    refresh(){if(!this.ctx)return;const should=this.visible&&!document.hidden&&effects&&!reduced.matches&&this.w>0&&this.h>0;if(should&&!this.running){this.running=true;this.last=0;this.raf=requestAnimationFrame(t=>this.frame(t));}else if(!should){this.running=false;cancelAnimationFrame(this.raf);if(this.visible&&!document.hidden&&this.w>0&&this.h>0)this.draw(17,0,true);}}
    frame(now){if(!this.running)return;if(now-this.tick<32){this.raf=requestAnimationFrame(t=>this.frame(t));return;}const start=performance.now();this.tick=now;const dt=Math.min(.05,this.last?(now-this.last)/1000:0);this.last=now;this.draw(now/1000,dt,false);this.frames++;this.timings.push(performance.now()-start);if(this.timings.length>120)this.timings.shift();this.raf=requestAnimationFrame(t=>this.frame(t));}
    draw(t,dt,staticFrame){
      const id=this.skin,skin=manifest.skins.find(s=>s.id===id)||manifest.skins[0],palette=skin[this.canvas.dataset.flow==='virxact'||root.dataset.theme==='dark'?'dark':'light'];
      const ctx=this.front.getContext('2d');ctx.clearRect(0,0,this.front.width,this.front.height);
      if(!staticFrame){ctx.globalAlpha=.93;ctx.drawImage(this.back,0,0);ctx.globalAlpha=1;ctx.globalCompositeOperation='destination-out';ctx.fillStyle='rgba(0,0,0,.025)';ctx.fillRect(0,0,this.front.width,this.front.height);ctx.globalCompositeOperation='source-over';}
      ctx.save();ctx.scale(this.dpr,this.dpr);ctx.strokeStyle=palette.glow;ctx.fillStyle=palette.glow;ctx.lineCap='round';
      for(let i=0;i<this.points.length;i++){
        let p=this.points[i];const v=velocity(p.x,p.y,t,this.pointer),mid=velocity(p.x+v[0]*dt*.5,p.y+v[1]*dt*.5,t,this.pointer);
        const old=[p.x,p.y];p.x+=mid[0]*dt;p.y+=mid[1]*dt;p.life-=dt;
        if(p.x<-.05||p.x>1.05||p.y<-.1||p.y>this.h/Math.max(1,this.w)+.1||p.life<0){p=this.points[i]=this.spawn();}
        const fade=Math.min(1,p.life/1.5),bright=id==='virxact'?.09:id==='claude'?.038:.028;
        ctx.globalAlpha=bright*fade*(.4+.6*p.phase);ctx.lineWidth=id==='claude'?.8:.65;
        ctx.beginPath();ctx.moveTo(p.x*this.w,p.y*this.w);const trail=id==='virxact'?.28:id==='workbuddy'?.055:.035;
        ctx.lineTo((p.x-mid[0]*trail)*this.w,(p.y-mid[1]*trail)*this.w);ctx.stroke();
        if(id==='claude'||id==='workbuddy'){ctx.globalAlpha*=.6;ctx.beginPath();ctx.arc(p.x*this.w,p.y*this.w,id==='claude'?1:1.3,0,Math.PI*2);ctx.fill();}
      }
      if(id==='virxact'&&this.canvas.id!=='skin-ambient'){
        const card=this.canvas.dataset.flow==='virxact',bounds=this.artRect,parent=this.canvasRect,w=card?this.w*.80:(bounds?.width||200),h=w/geometry.aspect,ox=card?this.w*.10:(bounds?bounds.left-parent.left:(this.w-w)/2),oy=card?(this.h-h)/2:(bounds?bounds.top-parent.top+(bounds.height-h)/2:(this.h-h)/2);
        ctx.lineWidth=.48;
        for(let i=0;i<lanes.length;i++){
          const line=lanes[i];ctx.globalAlpha=staticFrame?.20:.11;ctx.beginPath();line.points.forEach((p,j)=>{const x=ox+p[0]*w,y=oy+p[1]*h;j?ctx.lineTo(x,y):ctx.moveTo(x,y);});ctx.stroke();
          const speed=.009*Math.min(1.8,Math.max(.5,line.speed*80)),distance=(t*speed+i*.061)%line.length;
          const head=atLength(line,distance),tail=atLength(line,Math.max(0,distance-.010)),fade=Math.min(1,Math.min(distance,line.length-distance)/.006);
          ctx.globalAlpha=.7*fade;ctx.lineWidth=.72;ctx.beginPath();ctx.moveTo(ox+tail[0]*w,oy+tail[1]*h);ctx.lineTo(ox+head[0]*w,oy+head[1]*h);ctx.stroke();
        }
      }else if(id==='codex'){
        ctx.globalAlpha=.09;ctx.lineWidth=.7;const x=this.w*.7,y=this.h*.3;ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x+14,y+12);ctx.lineTo(x,y+24);ctx.moveTo(x+24,y+24);ctx.lineTo(x+44,y+24);ctx.stroke();
      }
      ctx.restore();this.ctx.clearRect(0,0,this.canvas.width,this.canvas.height);this.ctx.drawImage(this.front,0,0);[this.front,this.back]=[this.back,this.front];
    }
    reset(){this.back.getContext('2d').clearRect(0,0,this.back.width,this.back.height);this.refresh();}
  }
  function applyPalette(){const def=manifest.skins.find(s=>s.id===current)||manifest.skins[0],p=def[root.dataset.theme==='dark'?'dark':'light'];
    const names={accentInk:'accent-ink',accentSoft:'accent-soft',onAccent:'on-accent',bg:'bg',surface:'surface',sidebar:'sidebar',well:'well',ink:'ink',secondary:'secondary',muted:'muted',border:'border',line:'line',accent:'accent',glow:'skin-glow'};
    for(const[key,name]of Object.entries(names))root.style.setProperty('--'+name,p[key]);
    root.style.setProperty('--skin-portrait',`url(/${def.id==='virxact'?'avatar-virxact.png':'pet-'+def.id+'.png'})`);root.style.setProperty('--skin-logo-filter',root.dataset.theme==='dark'?'none':'invert(.82)');
    root.style.setProperty('--skin-dark',def.dark.surface);root.style.setProperty('--skin-pale',def.light.surface);
    for(const flow of instances)flow.reset();
  }
  function render(preferences,snapshot){
    if(!manifest)return;lastPreferences=preferences;effects=preferences.effectsEnabled!==false;const selection=preferences.skinID||'auto';current=selection==='auto'?preferences.primaryID:selection;
    const def=manifest.skins.find(s=>s.id===current);if(!def)return;root.dataset.skin=current;root.dataset.effects=effects?'on':'off';
    if(lastSkin!==current){lastSkin=current;applyPalette();document.querySelector('#skin-live-art').src=current==='virxact'?'/virxact-logo.svg':`/pet-${current}.png`;document.querySelector('#skin-live-art').classList.toggle('brand-lettering',current==='virxact');}
    document.querySelector('#skin-name').textContent=def.title.split(' · ')[1];document.querySelector('#skin-pet').src=`/avatar-${current}.png`;
    document.querySelector('#skin-mood').textContent=def.mood;document.querySelector('#skin-live-title').textContent=def.title;document.querySelector('#skin-live-subtitle').textContent=def.subtitle;
    document.querySelectorAll('button[data-skin]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.skin===selection)));
    document.querySelector('#skin-effects-enabled').checked=effects;
    document.querySelector('#skin-status').textContent=`当前：${def.title} · ${selection==='auto'?'跟随主用Agent':'自选皮肤，切换Agent不会改变'}`;
    const id=preferences.primaryID,profile=preferences.profiles.find(p=>p.id===id),data=snapshot?.agents[id]||{};
    document.querySelector('#skin-preview-agent').src=`/avatar-${id}.png`;document.querySelector('#skin-preview-agent').alt=profile?.name||id;
    document.querySelector('#skin-preview-name').textContent=profile?.name||id;document.querySelector('#skin-preview-state').textContent=data.stateLabel||'等待状态数据';document.querySelector('#skin-preview-dot').className=`agent-dot ${data.state||'unknown'}`;
    if(snapshot?.lastAlert&&snapshot.lastAlert!==lastAlert){lastAlert=snapshot.lastAlert;if(effects&&!reduced.matches)document.querySelector('.skin-island-preview').animate([{filter:'brightness(1.08)'},{filter:'brightness(1)'}],{duration:700});}
    for(const flow of instances)flow.refresh();
  }
  const ready=Promise.all([fetch('/skins.json').then(r=>{if(!r.ok)throw Error('主题清单未载入');return r.json();}),fetch('/brand-geometry.json').then(r=>r.json()),fetch('/brand-flow.json').then(r=>r.json())]).then(([m,g,f])=>{
    manifest=m;geometry=g;brandFlow=f;makeContours();for(let i=0;i<f.lanes.length;i+=3){const line=f.lanes[i];let distances=[0];for(let j=1;j<line.points.length;j++)distances.push(distances.at(-1)+Math.hypot(line.points[j][0]-line.points[j-1][0],(line.points[j][1]-line.points[j-1][1])/g.aspect));lanes.push({...line,distances,length:distances.at(-1)});}const gallery=document.querySelector('#skin-gallery');
    for(const skin of m.skins){const button=document.createElement('button');button.className='skin-design-card';button.dataset.skin=skin.id;button.setAttribute('aria-pressed','false');
      const art=document.createElement('span');art.className=`skin-design-art ${skin.id}`;const canvas=document.createElement('canvas');canvas.className='brand-flow';canvas.dataset.flow=skin.id;canvas.setAttribute('aria-hidden','true');art.append(canvas);
      const img=document.createElement('img');img.src=skin.id==='virxact'?'/virxact-logo.svg':`/pet-${skin.id}.png`;img.alt='';img.className=skin.id==='virxact'?'lettering':'pet-art';art.append(img);
      const check=document.createElement('span');check.className='skin-selected-check';check.textContent='✓';art.append(check);button.append(art);
      const name=document.createElement('strong');name.textContent=skin.title;button.append(name);const mood=document.createElement('span');mood.className='skin-card-mood';mood.textContent=skin.mood;button.append(mood);
      button.addEventListener('click',()=>window.dispatchEvent(new CustomEvent('skin-select',{detail:skin.id})));gallery.append(button);
    }
    document.querySelector('button[data-skin="auto"]').addEventListener('click',()=>window.dispatchEvent(new CustomEvent('skin-select',{detail:'auto'})));
    document.querySelectorAll('.brand-flow,#skin-ambient').forEach(c=>new Flow(c));
    document.querySelectorAll('[data-island-mode]').forEach(b=>b.addEventListener('click',()=>{document.querySelector('#skin-island-preview').dataset.mode=b.dataset.islandMode;document.querySelectorAll('[data-island-mode]').forEach(x=>x.classList.toggle('active',x===b));}));
    new MutationObserver(()=>applyPalette()).observe(root,{attributes:true,attributeFilter:['data-theme']});
    document.addEventListener('visibilitychange',()=>instances.forEach(f=>f.refresh()));reduced.addEventListener('change',()=>instances.forEach(f=>f.refresh()));
    if(window.skinPreferences)render(window.skinPreferences);window.dispatchEvent(new Event('skin-ready'));return true;
  }).catch(error=>{document.querySelector('#skin-status').textContent=error.message;console.error(error);});
  window.SkinStudio={render,ready,stats:()=>[...instances].map(f=>({skin:f.skin,active:f.running,frames:f.frames,meanMs:f.timings.length?f.timings.reduce((a,b)=>a+b,0)/f.timings.length:0})),velocity};
})();
