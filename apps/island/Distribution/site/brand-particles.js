/* Virxact page dust: official mark contours, flowing strokes and spring return.
   Reference: the hub's masthead dust effect, checked on 2026-10-29.
   This standalone drawing reads only the bundled brand SVG, never hub/user data. */
(() => {
  const canvas=document.querySelector('#brand-particles');
  const context=canvas?.getContext('2d');
  if(!context)return;
  const reduced=matchMedia('(prefers-reduced-motion: reduce)');
  const dialog=document.querySelector('#feedback-dialog');
  const diagonal=Math.SQRT1_2;
  const waves=[
    {kx:.0105,ky:.0175,speed:.22,strength:300,phase:.3},
    {kx:.019,ky:.008,speed:-.16,strength:240,phase:2.1},
    {kx:.0062,ky:.026,speed:.13,strength:200,phase:4.2}
  ];
  let width=0,height=0,frame=0,previous=0,elapsed=0,visible=false,paused=false,ready=false;
  let ink='',outlines=[],particles=[],wind=[],protectedAreas=[],bounds,mark={x:0,y:0,radius:1,scale:1,visible:true};
  const pointer={x:-10000,y:-10000};
  let randomState=11;
  function random(){
    randomState=(randomState+1831565813)|0;
    let value=Math.imul(randomState^(randomState>>>15),1|randomState);
    value^=value+Math.imul(value^(value>>>7),61|value);
    return ((value^(value>>>14))>>>0)/4294967296;
  }
  function resetWind(particle,spread=false){
    if(spread||random()<.25){particle.x=random()*width;particle.y=random()*height;}
    else if(random()<height/(width+height)){particle.x=-8;particle.y=random()*height;}
    else{particle.x=random()*width;particle.y=height+8;}
    particle.life=5+random()*10;particle.tone=Math.floor(random()*4);
  }
  function flow(x,y,time){
    const dx=x-mark.x,dy=y-mark.y;
    const along=(dx-dy)*diagonal,across=(dx+dy)*diagonal;
    const distance=along*along+across*across,radius=mark.visible?mark.radius*mark.radius:0;
    let vx=0,vy=0;
    if(distance>radius){
      const squared=distance*distance;
      const forward=1-radius*(along*along-across*across)/squared;
      const side=-2*radius*along*across/squared;
      vx=20*(forward+side)*diagonal;vy=20*(-forward+side)*diagonal;
    }
    for(const wave of waves){
      const a=wave.kx*x+wave.speed*time+wave.phase;
      const b=wave.ky*y-wave.speed*time+wave.phase*.7;
      vx+=wave.strength*wave.ky*Math.sin(a)*Math.cos(b);
      vy-=wave.strength*wave.kx*Math.cos(a)*Math.sin(b);
    }
    const px=x-pointer.x,py=y-pointer.y,d=Math.hypot(px,py);
    if(!reduced.matches&&d>.1&&d<100){
      const force=160*(1-d/100)**2;vx+=force*px/d;vy+=force*py/d;
    }
    return {vx,vy};
  }
  function addPoint(x,y,edge,order){
    const tx=mark.x+(x-bounds.cx)*mark.scale,ty=mark.y+(y-bounds.cy)*mark.scale;
    const direction=x-y>bounds.cx-bounds.cy?1:-1;
    const travel=300+random()*260,offset=(random()-.5)*70;
    const settled=reduced.matches||elapsed>0;
    particles.push({tx,ty,x:settled?tx:tx+direction*travel*diagonal+offset*diagonal,
      y:settled?ty:ty-direction*travel*diagonal+offset*diagonal,vx:0,vy:0,edge,order,
      delay:.1+(edge?order:random())*.55+random()*.12,phase:random()*Math.PI*2});
  }
  function rebuild(){
    randomState=11;particles=[];wind=[];
    const viewport=document.documentElement.clientWidth;
    mark.radius=Math.min(110,Math.max(64,64+(viewport-1100)*.2));
    mark.scale=mark.radius/(bounds.height/2);
    mark.x=width-Math.min(width*.34,520)/2;mark.y=84+288*.47;
    mark.visible=viewport>1100;
    for(const outline of mark.visible?outlines:[]){
      const length=outline.node.getTotalLength(),count=Math.ceil(length*mark.scale/2);
      for(let index=0;index<count;index++){
        const point=outline.node.getPointAtLength(length*index/count);
        addPoint(point.x,point.y,true,index/count);
      }
      const fillCount=Math.round(count*1.2);
      for(let added=0,attempts=0;added<fillCount&&attempts<fillCount*12;attempts++){
        const x=bounds.x+random()*bounds.width,y=bounds.y+random()*bounds.height;
        if(outline.brush.isPointInPath(outline.path,x,y)){addPoint(x,y,false,random());added++;}
      }
    }
    wind=Array.from({length:Math.min(width<700?450:2200,Math.round(width*height/(width<700?1000:570)))},()=>{
      const particle={x:0,y:0,vx:0,vy:0,life:0,tone:0};resetWind(particle,true);return particle;
    });
  }
  function protectContent(){
    const origin=canvas.getBoundingClientRect();protectedAreas=[];
    for(const element of document.querySelectorAll('.brand,.site-nav nav,#hero-title,.hero-copy,.download-button,.download-alternative,.download-feedback,.feature-tabs,.demo-controls,.experience-note,.demo-toolbar')){
      if(!element.getClientRects().length)continue;
      let rectangles;
      if(element.matches('.brand,#hero-title,.hero-copy,.download-alternative,.download-feedback')){
        const range=document.createRange();range.selectNodeContents(element);rectangles=[...range.getClientRects()];
      }else rectangles=[element.getBoundingClientRect()];
      for(const box of rectangles)if(box.width&&box.height)protectedAreas.push({left:box.left-origin.left-8,right:box.right-origin.left+8,top:box.top-origin.top-8,bottom:box.bottom-origin.top+8});
    }
  }
  function contentFade(x,y){
    let fade=1;
    for(const box of protectedAreas){
      const dx=Math.max(box.left-x,0,x-box.right),dy=Math.max(box.top-y,0,y-box.bottom);
      fade=Math.min(fade,Math.hypot(dx,dy)/20);if(fade===0)break;
    }
    return fade;
  }
  function paint(dt){
    const time=elapsed/1000;
    context.clearRect(0,0,width,height);
    context.strokeStyle=ink;context.fillStyle=ink;context.lineWidth=1.1;context.lineCap='round';
    for(const particle of wind){
      const velocity=flow(particle.x,particle.y,time);
      particle.vx=velocity.vx;particle.vy=velocity.vy;
      particle.x+=particle.vx*dt;particle.y+=particle.vy*dt;particle.life-=dt;
      const distanceToMark=Math.hypot(particle.x-mark.x,particle.y-mark.y);
      const inside=mark.visible&&distanceToMark<mark.radius;
      if(particle.life<=0||particle.x<-12||particle.x>width+12||particle.y<-12||particle.y>height+12||inside){
        if(dt)resetWind(particle);continue;
      }
      const edgeFade=Math.max(0,Math.min(1,particle.x/28,(width-particle.x)/28,particle.y/24,(height-particle.y)/24));
      const emphasis=mark.visible&&distanceToMark<290?1:(width<700?.55:.75);
      context.globalAlpha=[.13,.21,.32,.46][particle.tone]*edgeFade*emphasis*contentFade(particle.x,particle.y);
      if(context.globalAlpha<.01)continue;
      context.beginPath();context.moveTo(particle.x,particle.y);
      context.lineTo(particle.x-particle.vx*.26,particle.y-particle.vy*.26);context.stroke();
    }
    for(const particle of particles){
      if(!reduced.matches&&time<particle.delay)continue;
      if(dt){
        const drift=time>2.5?.5:0;
        let ax=30*(particle.tx+Math.sin(time*1.4+particle.phase)*drift-particle.x)-8.5*particle.vx;
        let ay=30*(particle.ty+Math.cos(time*1.1+particle.phase)*drift-particle.y)-8.5*particle.vy;
        const dx=particle.x-pointer.x,dy=particle.y-pointer.y,distance=Math.hypot(dx,dy);
        if(distance>.1&&distance<84){const force=5200*(1-distance/84)**2;ax+=force*dx/distance;ay+=force*dy/distance;}
        particle.vx+=ax*dt;particle.vy+=ay*dt;particle.x+=particle.vx*dt;particle.y+=particle.vy*dt;
      }
      const sweep=(time-2.5)%6/1.4;
      const highlight=particle.edge&&sweep>0&&sweep<1&&Math.abs(particle.order-sweep)<.06;
      const size=particle.edge?(highlight?2:1.6):1.15;
      context.globalAlpha=particle.edge?(highlight?1:.78):.26;
      context.fillRect(particle.x-size/2,particle.y-size/2,size,size);
    }
    context.globalAlpha=1;
    canvas.dataset.phase=time>2.5||reduced.matches?'settled':'arriving';
  }
  function tick(now){
    frame=requestAnimationFrame(tick);
    if(previous&&now-previous<1000/30)return;
    const dt=previous?Math.min((now-previous)/1000,.05):0;
    previous=now;elapsed+=dt*1000;paint(dt);
  }
  function sync(){
    cancelAnimationFrame(frame);frame=0;previous=0;
    const hold=!ready||!width||!height||!visible||document.hidden||dialog?.open||paused||reduced.matches;
    canvas.dataset.motion=hold?'paused':'playing';
    if(ready&&width&&height){
      if(reduced.matches)for(const particle of particles)Object.assign(particle,{x:particle.tx,y:particle.ty,vx:0,vy:0});
      paint(0);if(!hold)frame=requestAnimationFrame(tick);
    }
  }
  function resize(){
    const box=canvas.getBoundingClientRect(),nextWidth=box.width,nextHeight=box.height;
    protectContent();
    if(nextWidth===width&&nextHeight===height){sync();return;}
    width=nextWidth;height=nextHeight;
    const ratio=Math.min(devicePixelRatio||1,1.5);
    canvas.width=Math.round(width*ratio);canvas.height=Math.round(height*ratio);
    context.setTransform(ratio,0,0,ratio,0,0);
    ink=getComputedStyle(document.documentElement).getPropertyValue('--brand-ink').trim();
    if(ready&&width&&height)rebuild();sync();
  }
  const sizeObserver=new ResizeObserver(resize);sizeObserver.observe(canvas);
  sizeObserver.observe(document.querySelector('.hero'));
  new IntersectionObserver(([entry])=>{visible=entry.isIntersecting;sync();}).observe(canvas);
  addEventListener('pointermove',event=>{
    const box=canvas.getBoundingClientRect();pointer.x=event.clientX-box.left;pointer.y=event.clientY-box.top;
  },{passive:true});
  document.addEventListener('pointerleave',()=>{pointer.x=-10000;pointer.y=-10000;});
  document.addEventListener('visibilitychange',sync);
  document.addEventListener('island:motion',event=>{paused=Boolean(event.detail?.paused);sync();});
  reduced.addEventListener('change',sync);
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change',()=>{
    ink=getComputedStyle(document.documentElement).getPropertyValue('--brand-ink').trim();sync();
  });
  if(dialog)new MutationObserver(sync).observe(dialog,{attributes:true,attributeFilter:['open']});
  fetch('virxact-mark.svg').then(response=>{
    if(!response.ok)throw new Error('Brand asset unavailable');return response.text();
  }).then(source=>{
    const svg=new DOMParser().parseFromString(source,'image/svg+xml').documentElement;
    const [x,y,w,h]=svg.getAttribute('viewBox').split(/\s+/).map(Number);
    bounds={x,y,width:w,height:h,cx:x+w/2,cy:y+h/2};
    outlines=[...svg.querySelectorAll('path')].map(node=>({
      node,path:new Path2D(node.getAttribute('d')),
      brush:document.createElement('canvas').getContext('2d')
    }));
    if(!outlines.length||outlines.some(outline=>!outline.brush)||![x,y,w,h].every(Number.isFinite))throw new Error('Invalid brand geometry');
    ready=true;width=0;height=0;resize();
  }).catch(()=>{canvas.dataset.motion='unavailable';});
})();
