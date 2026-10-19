const test=require('node:test'),assert=require('node:assert/strict');
const {Reader,Clock,CLI,messageText}=require('../core/reader.cjs');const {pages,duration,MessageBuffer}=require('../core/presentation.cjs');const {performance}=require('node:perf_hooks');
const clock=()=>new Clock(async()=>({server:Date.now()+45000,wall:Date.now(),mono:performance.now()}));
test('Long Chinese and emoji messages remain complete across small/large screens',()=>{
 const text=('一段非常长的消息\n含 emoji 👨‍👩‍👧‍👦 和链接 https://example.com。').repeat(200);
 for(const width of [280,600])for(const font of [22,52]){const parts=pages(text,{width,font});assert.equal(parts.join(''),text);assert.ok(parts.length>1);assert.ok(parts.every(x=>duration(x)>=12000));assert.ok(parts.every(x=>x.length<1000));}
});
test('Paused queue and recent history are bounded with visible overflow',()=>{const b=new MessageBuffer();for(let i=0;i<100000;i++)b.enqueue({id:String(i),text:'synthetic'});assert.equal(b.queue.length,500);assert.equal(b.history.length,100);assert.equal(b.dropped,99500);assert.equal(b.queue[0].id,'99500');b.clear();assert.equal(b.dropped,0);});
test('Topic/bot coverage, actual unread filtering, dedupe, failure retry and restart cancellation',async()=>{
 let fail=true,requests=0;const delivered=[];const cli={cancel(){},async call(args){requests++;if(args.includes('status'))return {identities:{user:{available:true,openId:'self'}}};let data;
  if(args.includes('+chat-list'))data={chats:[{chat_id:'topic',chat_mode:'topic',name:'AIHOT'},{chat_id:'bot',chat_mode:'p2p',p2p_target_type:'bot',name:'机器人'}],has_more:false};
  else if(args.includes('+messages-read-status')){if(fail){fail=false;throw Error('synthetic network fault');}data={items:args[args.indexOf('--message-ids')+1].split(',').filter(id=>id!=='unknown').map(id=>({message_id:id,is_read:id==='read'||id==='readbot'})),invalid_message_ids:['unknown']};}
  else{const p=JSON.parse(args[args.indexOf('--params')+1]);assert.equal(p.only_thread_root_messages,'false');data={items:['unread','read','own','deleted','unknown'].map(id=>({message_id:p.container_id+'-'+id,create_time:String(r.clock.now()+1),sender:{id:id==='own'?'self':'bot'},deleted:id==='deleted',body:{content:'{"text":"synthetic"}'},msg_type:'text'})),has_more:false};data.items=data.items.map(m=>({...m,message_id:m.message_id.split('-').at(-1)+(p.container_id==='bot'?'bot':'')}));}
  return {identity:'user',ok:true,data};}};
 const r=new Reader(cli,{clock:clock(),poll:10,retry:10,pageDelay:10,catalogInterval:100});r.on('message',m=>delivered.push(m));await r.start();await new Promise(res=>setTimeout(res,200));r.stop();const count=delivered.length;await new Promise(res=>setTimeout(res,30));assert.equal(delivered.length,count);assert.ok(requests>20);assert.equal(delivered.filter(x=>x.id==='unread').length,1);assert.ok(!delivered.some(x=>x.id==='read'||x.id==='own'||x.id==='deleted'||x.id==='unknown'));assert.ok(delivered.some(x=>x.chat==='AIHOT'));
});
test('Official child empty response is surfaced and process handles released',async()=>{const cli=new CLI(process.execPath);await assert.rejects(cli.call(['-e','process.exit(0)'],{profile:false}),/未有效返回/);assert.equal(cli.children.size,0);const data=await cli.call(['-e','console.log(JSON.stringify({ok:true,data:{test:true}}))'],{profile:false});assert.equal(data.data.test,true);});
test('Child timeout kills a nonresponsive process',async()=>{const cli=new CLI(process.execPath);await assert.rejects(cli.call(['-e','setInterval(()=>{},1000)'],{profile:false,timeout:50}),/超时/);assert.equal(cli.children.size,0);});
test('Rich card text is parsed without evaluating HTML',()=>{assert.equal(messageText({msg_type:'interactive',body:{content:JSON.stringify({elements:[{tag:'markdown',content:'<script>hello</script>'}]})}}),'<script>hello</script>');});
test('Long-running dedupe expires only outside the replay window',async()=>{
 let now=Date.now(),sequence=0;const clock={now:()=>now,async refresh(){}};
 const cli={cancel(){},async call(args){let data;if(args.includes('+messages-read-status'))data={items:args[args.indexOf('--message-ids')+1].split(',').map(message_id=>({message_id,is_read:false}))};else data={items:[{message_id:'m'+sequence,create_time:String(now),sender:{id:'other'},msg_type:'text',body:{content:'{"text":"synthetic"}'}}],has_more:false};return {identity:'user',data};}};
 const r=new Reader(cli,{clock});r.enabled=true;const s={started:now-1,own:'self',progress:new Map(),seen:new Map(),flights:new Set()};r.session=s;let count=0;r.on('message',()=>count++);
 for(sequence=0;sequence<5000;sequence++){now+=2000;await r.receive({id:'chat',kind:'p2p',name:'synthetic',muted:false},s,false);}
 assert.equal(count,5000);assert.ok(s.seen.get('chat').size<=62);r.stop();
});
test('Initial offline connection retries automatically and stop prevents restart',async()=>{
 let attempts=0;const cli={cancel(){},async call(args){if(args.includes('status')){if(++attempts<3)throw Error('offline');return {identities:{user:{available:true,openId:'self'}}};}return {identity:'user',data:{chats:[],has_more:false}};}};
 const r=new Reader(cli,{clock:clock(),retry:10,poll:10,pageDelay:10});await r.start();assert.equal(attempts,3);r.suspend();await r.resume();r.stop();const count=attempts;await new Promise(res=>setTimeout(res,30));assert.equal(attempts,count);
});
test('Older concurrent backfill cannot replay IDs after a newer quick query prunes',async()=>{
 let now=Date.now(),release;const gate=new Promise(r=>release=r);let first=true;const oldTime=now-5000;
 const cli={cancel(){},async call(args){if(args.includes('+messages-read-status'))return {identity:'user',data:{items:[{message_id:'seen',is_read:false}]}};
  if(first){first=false;await gate;}return {identity:'user',data:{items:[{message_id:'seen',create_time:String(oldTime),sender:{id:'other'},msg_type:'text',body:{content:'{"text":"synthetic"}'}}],has_more:false}};}};
 const r=new Reader(cli,{clock:{now:()=>now,async refresh(){}}});r.enabled=true;const s={started:now-600000,own:'self',progress:new Map([['chat',now]]),seen:new Map([['chat',new Map([['seen',oldTime]])]]),flights:new Set(),windows:new Map()};r.session=s;let emitted=0;r.on('message',()=>emitted++);const chat={id:'chat',name:'synthetic',kind:'p2p',muted:false};
 const old=r.receive(chat,s,false);await new Promise(res=>setTimeout(res,0));now+=300000;s.progress.set('chat',now);await r.receive(chat,s,true);assert.ok(s.seen.get('chat').has('seen'));release();await old;assert.equal(emitted,0);assert.equal(s.windows.size,0);r.stop();
});
