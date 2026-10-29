/* The real Virxact mark, sampled into a quiet field of moving particles. */
(() => {
  const canvas=document.querySelector('#brand-particles');
  const context=canvas?.getContext('2d');
  if(!context)return;
  const reduced=matchMedia('(prefers-reduced-motion: reduce)');
  const narrow=matchMedia('(max-width: 700px)');
  const dialog=document.querySelector('#feedback-dialog');
  let points=[],width=0,height=0,frame=0,previous=0,elapsed=0,ready=false,paused=false;
  const pointer={x:-1000,y:-1000};
  const seed=n=>{const v=Math.sin(n*127.1+311.7)*43758.5453;return v-Math.floor(v);};
  function draw(){
    context.clearRect(0,0,width,height);
    context.fillStyle=getComputedStyle(document.documentElement).getPropertyValue('--brand-paper').trim();
    const size=Math.min(width*(narrow.matches?1.05:.64),760);
    const centerX=width*(narrow.matches?.82:.78),centerY=height*(narrow.matches?.29:.40);
    const time=elapsed/1000;
    for(let i=0;i<points.length;i++){
      const point=points[i],phase=seed(i)*Math.PI*2;
      const breath=1+Math.sin(time*.22)*.018;
      let x=centerX+point.x*size*breath+Math.sin(time*.38+phase)*2.8;
      let y=centerY+point.y*size*breath+Math.cos(time*.31+phase)*2.8;
      if(!reduced.matches){
        const dx=x-pointer.x,dy=y-pointer.y,distance=Math.hypot(dx,dy);
        if(distance>0&&distance<125){const shift=(1-distance/125)*12;x+=dx/distance*shift;y+=dy/distance*shift;}
      }
      context.globalAlpha=.10+seed(i+17)*.13;
      context.beginPath();context.arc(x,y,.7+seed(i+31)*.9,0,Math.PI*2);context.fill();
    }
    // A few loose points carry the same mark into the surrounding empty space.
    const count=narrow.matches?16:32;
    for(let i=0;i<count;i++){
      const x=seed(i+400)*width+Math.sin(time*.15+i)*9;
      const y=seed(i+800)*height+Math.cos(time*.13+i)*12;
      context.globalAlpha=.06+seed(i+600)*.10;
      context.beginPath();context.arc(x,y,.8+seed(i+900)*.7,0,Math.PI*2);context.fill();
    }
    context.globalAlpha=1;
  }
  function tick(now){
    frame=requestAnimationFrame(tick);
    if(previous&&now-previous<1000/30)return;
    if(previous)elapsed+=Math.min(now-previous,100);
    previous=now;draw();
  }
  function sync(){
    cancelAnimationFrame(frame);frame=0;previous=0;
    if(!ready)return;
    const hold=reduced.matches||document.hidden||dialog?.open||paused;
    canvas.dataset.motion=hold?'paused':'playing';
    draw();
    if(!hold)frame=requestAnimationFrame(tick);
  }
  function resize(){
    width=document.documentElement.clientWidth;height=innerHeight;
    const ratio=Math.min(devicePixelRatio||1,1.5);
    canvas.width=Math.round(width*ratio);canvas.height=Math.round(height*ratio);
    context.setTransform(ratio,0,0,ratio,0,0);sync();
  }
  addEventListener('resize',resize,{passive:true});
  addEventListener('pointermove',event=>{pointer.x=event.clientX;pointer.y=event.clientY;},{passive:true});
  document.addEventListener('pointerleave',()=>{pointer.x=-1000;pointer.y=-1000;});
  document.addEventListener('visibilitychange',sync);
  document.addEventListener('island:motion',event=>{paused=Boolean(event.detail?.paused);sync();});
  reduced.addEventListener('change',sync);
  if(dialog)new MutationObserver(sync).observe(dialog,{attributes:true,attributeFilter:['open']});
  const mark=new Image();
  mark.onload=()=>{
    const mask=document.createElement('canvas');mask.width=240;mask.height=240;
    const brush=mask.getContext('2d',{willReadFrequently:true});
    if(!brush)return;
    const markHeight=240*mark.naturalHeight/mark.naturalWidth;
    brush.drawImage(mark,0,(240-markHeight)/2,240,markHeight);
    const pixels=brush.getImageData(0,0,240,240).data;
    for(let y=2;y<240;y+=5)for(let x=2;x<240;x+=5){
      if(pixels[(y*240+x)*4+3]>128)points.push({x:x/240-.5,y:y/240-.5});
    }
    ready=true;resize();
  };
  mark.onerror=()=>{canvas.dataset.motion='unavailable';};
  mark.src='virxact-mark.svg';
})();
