'use strict';
const {spawn} = require('node:child_process');
const {performance} = require('node:perf_hooks');
const {EventEmitter} = require('node:events');
const sleep = ms => new Promise(r=>setTimeout(r,ms));
class CLI {
  constructor(binary,profile='feishu-danmu'){this.binary=binary;this.profile=profile;this.children=new Set();}
  call(args,{timeout=8000,profile=true,onURL}={}){
    return new Promise((resolve,reject)=>{
      const child=spawn(this.binary,[...(profile?['--profile',this.profile]:[]),...args],{windowsHide:true,stdio:['ignore','pipe','pipe'],env:{...process.env,LARKSUITE_CLI_NO_UPDATE_NOTIFIER:'1',LARKSUITE_CLI_NO_SKILLS_NOTIFIER:'1'}});
      this.children.add(child);let stdout=[],stderr=[],bytes=0,timedOut=false,force;let urlTail='';
      const timer=setTimeout(()=>{timedOut=true;child.kill();force=setTimeout(()=>child.kill('SIGKILL'),1000);},timeout);
      const receive=(target,data)=>{
        bytes+=data.length;
        if(bytes>8*1024*1024){child.kill('SIGKILL');return;}
        target.push(data);
        if(onURL){urlTail=(urlTail+data.toString('utf8')).slice(-4096);for(const match of urlTail.matchAll(/https:\/\/[^\s<>"\x1b]+/g)) onURL(match[0]);}
      };
      child.stdout.on('data',b=>receive(stdout,b));child.stderr.on('data',b=>receive(stderr,b));
      child.once('error',()=>{cleanup();reject(new Error('读取工具无法启动，请重新安装'));});
      child.once('close',code=>{
        cleanup();
        if(timedOut)return reject(new Error('连接超时，正在重试'));
        if(bytes>8*1024*1024)return reject(new Error('接口返回过大，暂停本批读取'));
        try{
          const raw=Buffer.concat(stdout.length?stdout:stderr).toString('utf8');const result=JSON.parse(raw);
          if(code!==0||result.ok===false) { const failure=new Error(`飞书接口错误 ${Number(result.error?.code)||'未知'}，请检查授权或网络`); failure.diagnostic=result.error; throw failure; }
          resolve(result);
        }catch(e){reject(e.message.startsWith('飞书接口错误')?e:new Error(`接口未有效返回（退出码 ${code}）`));}
      });
      const cleanup=()=>{clearTimeout(timer);clearTimeout(force);this.children.delete(child);child.stdout.destroy();child.stderr.destroy();};
    });
  }
  cancel(){for(const child of this.children){child.kill();setTimeout(()=>{if(this.children.has(child))child.kill('SIGKILL');},1000);}}
}
class Clock {
  constructor(probe){this.probe=probe||Clock.probe;this.sample=null;this.pending=null;}
  now(){return this.sample?this.sample.server+performance.now()-this.sample.mono:Date.now();}
  async refresh(force=false){
    if(this.sample&&!force&&performance.now()-this.sample.mono<300000&&Math.abs(Date.now()-this.sample.wall-(performance.now()-this.sample.mono))<2000)return;
    if(this.pending)return this.pending;
    this.pending=(async()=>{this.sample=await this.probe();})().finally(()=>this.pending=null);return this.pending;
  }
  static async probe(){
    const begin=performance.now();const r=await fetch(`https://open.feishu.cn/open-apis/im/v1/messages?danmu_clock_probe=${crypto.randomUUID()}`,{method:'HEAD',cache:'no-store',signal:AbortSignal.timeout(4000)});
    const end=performance.now(),stamp=Date.parse(r.headers.get('date'));
    if(!Number.isFinite(stamp)||end-begin>4000)throw new Error('飞书时间校准失败，请检查网络');
    return {server:stamp+500+(end-begin)/2,mono:end,wall:Date.now()};
  }
}
function messageText(message){
  let body;try{body=JSON.parse(message.body?.content||'{}');}catch{body={};}
  const pieces=[];const walk=x=>{if(!x)return;if(Array.isArray(x)){x.forEach(walk);return;}if(typeof x==='object'){if(typeof x.text==='string')pieces.push(x.text);if(x.tag==='markdown'&&typeof x.content==='string')pieces.push(x.content);if(typeof x.title==='string')pieces.push(x.title);for(const [key,v]of Object.entries(x))if(!['text','title'].includes(key))walk(v);}};
  walk(body);if(pieces.length)return pieces.join('\n');
  return {image:'[图片]',audio:'[语音]',media:'[视频]',file:body.file_name||'[文件]',sticker:'[表情]',merge_forward:'[合并转发]',interactive:'[卡片消息]'}[message.msg_type]||'[消息]';
}
class Reader extends EventEmitter {
  constructor(cli,{clock=new Clock(),poll=1000,catalogInterval=60000,retry=5000,pageDelay=150}={}){super();Object.assign(this,{cli,clock,poll,catalogInterval,retry,pageDelay});this.enabled=false;this.gray=[];this.hidden=[];this.sleeping=false;}
  async data(args){const r=await this.cli.call([...args,'--as','user','--format','json']);if(r.identity!=='user'||!r.data)throw new Error('接口身份或结构异常');return r.data;}
  status(text,health='connecting'){this.emit('status',{text,health,lastSuccess:this.lastSuccess||null});}
  alive(s){return this.enabled&&this.session===s;}
  async start(){
    if(this.enabled)return;this.enabled=true;const s={started:null,own:null,progress:new Map(),seen:new Map(),flights:new Set(),windows:new Map(),catalog:[],selected:0};this.session=s;
    while(this.alive(s)&&!s.started){
      try{this.status('正在连接你的飞书账号');const a=await this.cli.call(['auth','status','--json']);if(!a.identities?.user?.available)throw new Error('请点击“连接飞书”，完成本人授权');await this.clock.refresh();if(!this.alive(s))return;s.started=this.clock.now();s.own=a.identities.user.openId;}
      catch(e){if(!this.alive(s))return;this.status(`${e.message} · 自动重试中`,'error');await sleep(this.retry);}
    }
    if(this.alive(s)){this.fast(s);this.backfill(s);}
  }
  stop(){this.enabled=false;this.session=null;this.cli.cancel();this.status('账号接收已停止','stopped');}
  suspend(){this.sleeping=true;this.cli.cancel();this.status('电脑休眠中，唤醒后恢复','sleeping');}
  async resume(){this.sleeping=false;try{await this.clock.refresh(true);}catch{}this.status('已唤醒，正在恢复接收');}
  allowed(chat){return !this.hidden.some(x=>chat.name.toLowerCase().includes(x.toLowerCase()))&&(!chat.muted||this.gray.some(x=>chat.name.toLowerCase().includes(x.toLowerCase())));}
  async chats(full,exclude=true){
    const a=['im','+chat-list','--types=p2p,group','--sort','active_time','--page-size',full?'100':'12'];if(full)a.push('--page-all','--page-limit','1000');if(exclude)a.push('--exclude-muted');
    const d=await this.data(a);if(!Array.isArray(d.chats)||(full&&d.has_more))throw new Error('会话列表未完整返回');return d.chats;
  }
  catalog(rows,allowedIDs){return rows.filter(x=>['p2p','group','topic'].includes(x.chat_mode)).map(x=>({id:x.chat_id,name:x.name||'飞书会话',kind:x.chat_mode,muted:!allowedIDs.has(x.chat_id)}));}
  async fast(s){while(this.alive(s)){
    if(this.sleeping){await sleep(500);continue;}const began=performance.now();let failed=false;
    try{
      await this.clock.refresh();const unmuted=await this.chats(false);if(!this.alive(s))return;
      const rows=this.gray.length?await this.chats(false,false):unmuted;const chats=this.catalog(rows,new Set(unmuted.map(x=>x.chat_id))).filter(x=>this.allowed(x)).slice(0,6);
      // High urgency requires a seconds-scale foreground poll, isolated from
      // full directory pagination. Only two CLI calls run on this hot path.
      let cursor=0;const lane=async()=>{while(cursor<chats.length&&this.alive(s)){try{await this.receive(chats[cursor++],s,true);}catch{failed=true;}}};await Promise.all([lane(),lane()]);
      if(!this.alive(s))return;if(!failed)this.lastSuccess=this.clock.now();
      this.status(`${failed?'接收异常，重试中':'账号接收中'} · ${s.selected}/${s.catalog.length} 个会话 · 快查 ${((performance.now()-began)/1000).toFixed(1)} 秒${s.unavailable?' · 部分消息未读状态不可用，已跳过':''}`,failed?'error':'ready');
    }catch(e){failed=true;if(this.alive(s))this.status(`${e.message} · 自动重试中`,'error');}
    await sleep(failed?this.retry:this.poll);
  }}
  async backfill(s){let refreshed=-Infinity,cursor=0;while(this.alive(s)){
    if(this.sleeping){await sleep(500);continue;}
    try{
      if(performance.now()-refreshed>=this.catalogInterval){const rows=await this.chats(true,false),allowed=await this.chats(true);if(!this.alive(s))return;s.catalog=this.catalog(rows,new Set(allowed.map(x=>x.chat_id)));s.selected=s.catalog.filter(x=>this.allowed(x)).length;refreshed=performance.now();}
      const chat=s.catalog[cursor++%s.catalog.length];if(chat&&this.allowed(chat))await this.receive(chat,s,false);await sleep(Math.max(this.pageDelay,chat?0:500));
    }catch{if(this.alive(s))this.status('后台补读异常，前台快查继续运行','error');await sleep(this.retry);}
  }}
  async receive(chat,s,fast){
    const flight=`${chat.id}:${fast}`;if(!this.alive(s)||s.flights.has(flight)||!this.allowed(chat))return;s.flights.add(flight);
    const start=Math.max(s.started,(s.progress.get(chat.id)||s.started)-120000);s.windows??=new Map();s.windows.set(flight,{chat:chat.id,start});
    try{
      await this.clock.refresh();const end=this.clock.now();
      const seen=s.seen.get(chat.id)||new Map();s.seen.set(chat.id,seen);const retainedFrom=Math.min(start,...Array.from(s.windows.values()).filter(x=>x.chat===chat.id).map(x=>x.start));for(const [id,at]of seen)if(at<retainedFrom)seen.delete(id);
      let page;let pages=0;
      do{
        const p={container_id_type:'chat',container_id:chat.id,start_time:String(Math.floor(start/1000)),end_time:String(Math.floor(end/1000)),sort_type:'ByCreateTimeDesc',page_size:'50',with_sender_name:'true',only_thread_root_messages:'false'};if(page)p.page_token=page;
        const d=await this.data(['api','GET','/open-apis/im/v1/messages','--params',JSON.stringify(p)]);if(!this.alive(s))return;if(!Array.isArray(d.items))throw new Error('消息结构异常');
        const candidates=d.items.filter(m=>!seen.has(m.message_id)&&m.sender?.id!==s.own&&!m.deleted&&Number(m.create_time)>=s.started);
        let states={items:[]};if(candidates.length)states=await this.data(['im','+messages-read-status','--message-ids',candidates.map(x=>x.message_id).join(',')]);
        if(!this.alive(s))return;if(!Array.isArray(states.items))throw new Error('未读状态无法确认，暂停本批显示');
        const readable=new Map(states.items.map(x=>[x.message_id,x.is_read]));
        for(const m of candidates.reverse()){
          if(seen.has(m.message_id))continue;seen.set(m.message_id,Number(m.create_time));
          if(readable.get(m.message_id)!==false){if(!readable.has(m.message_id))s.unavailable=true;continue;}
          if(this.allowed(chat))this.emit('message',{id:m.message_id,chat:chat.name,sender:m.sender?.sender_name||'飞书消息',text:messageText(m),createdAt:Number(m.create_time),receivedAt:this.clock.now(),gray:chat.muted||this.gray.some(x=>chat.name.toLowerCase().includes(x.toLowerCase()))});
        }
        const next=d.has_more?d.page_token:null;if(d.has_more&&(!next||next===page))throw new Error('消息分页异常');page=next;pages++;
        if(fast&&pages>=2&&page)return;if(pages>=1000&&page)throw new Error('补读尚未完成');
      }while(page);
      if(this.alive(s))s.progress.set(chat.id,Math.max(s.progress.get(chat.id)||s.started,end));
    }finally{s.flights.delete(flight);s.windows.delete(flight);}
  }
}
module.exports={CLI,Clock,Reader,messageText,sleep};
