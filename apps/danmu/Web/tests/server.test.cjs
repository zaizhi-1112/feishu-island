const {test}=require('node:test'),assert=require('node:assert/strict'),{EventEmitter}=require('node:events');const {createApp}=require('../server.cjs');
class FakeReader extends EventEmitter{constructor(){super();this.enabled=false;}start(){this.enabled=true;this.emit('message',{id:'om_test',text:'合成消息',chat:'合成',sender:'合成'});}stop(){this.enabled=false;}async data(){return {items:[{message_id:'om_test',is_read:false}]};}}
test('identity boundary, origin protection, user isolation, no credentials exposed',async()=>{
 const readers=[];const server=createApp({dataDir:null,makeCLI:()=>({call:async()=>({identities:{user:{available:true}}}),cancel(){}}),makeReader:()=>{const r=new FakeReader();readers.push(r);return r;}});await new Promise(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+server.address().port;
 const req=(route,user,body,origin=base)=>fetch(base+route,{method:body===undefined?'GET':'POST',headers:{...(user?{'x-auth-user-id':user}:{}),'content-type':'application/json',origin},body:body===undefined?undefined:JSON.stringify(body)});
 try{
 assert.equal((await req('/api/state')).status,401);assert.equal((await req('/')).status,401);
 assert.equal((await req('/api/start','a',{},'https://attacker.example')).status,403);
 assert.equal((await req('/api/connect','a',{consent:false})).status,400);
 assert.equal((await req('/api/start','a',{})).status,200);
 assert.equal((await (await req('/api/messages','a')).json()).messages[0].text,'合成消息');
 assert.equal((await (await req('/api/messages','b')).json()).messages.length,0);
 assert.equal((await req('/api/read-status','a',{ids:['invalid']})).status,400);
 assert.equal((await req('/api/read-status','a',{ids:['om_test']})).status,200);
 const state=await(await req('/api/state','a')).json();assert.equal(state.received,1);assert.equal('cli'in state,false);
 assert.equal((await req('/core/reader.cjs','a')).status,404);
 assert.equal((await req('/api/stop','a',{})).status,200);assert.equal((await(await req('/api/messages','a')).json()).messages.length,0);
 }finally{await new Promise(r=>server.close(r));}
});
test('authorized page auto-starts, explicit stop survives reload and service restart',async()=>{
 const fs=require('node:fs'),path=require('node:path');const dir=fs.mkdtempSync(path.join(require('node:os').tmpdir(),'danmu-prefs-test-'));
 const make=()=>createApp({dataDir:dir,makeCLI:()=>({call:async args=>args[0]==='config'?{appId:'cli_test'}:{identities:{user:{available:true}}},cancel(){}}),makeReader:()=>new FakeReader()});
 let server,base;async function start(){server=make();await new Promise(r=>server.listen(0,'127.0.0.1',r));base='http://127.0.0.1:'+server.address().port;}
 const get=async()=> (await fetch(base+'/api/state',{headers:{'x-auth-user-id':'auto-user'}})).json();
 const post=route=>fetch(base+'/api/'+route,{method:'POST',headers:{'x-auth-user-id':'auto-user','content-type':'application/json',origin:base},body:'{}'});
 await start();try{assert.equal((await get()).receiving,true);await post('stop');assert.equal((await get()).receiving,false);await new Promise(r=>server.close(r));await start();assert.equal((await get()).receiving,false);await post('start');assert.equal((await get()).receiving,true);}finally{await new Promise(r=>server.close(r));}
});
test('authorization completion starts automatically, but stop during authorization wins',async()=>{
 let complete;let authorized=false;const server=createApp({dataDir:null,makeCLI:()=>({call:async args=>{if(args[0]==='config')return{appId:'cli_test'};if(args[1]==='status')return{identities:{user:{available:authorized}}};if(args.includes('--no-wait'))return{verification_uri:'https://open.feishu.cn/test',device_code:'synthetic'};return new Promise(r=>{complete=()=>{authorized=true;r({});};});},cancel(){}}),makeReader:()=>new FakeReader()});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+server.address().port;
 const post=(route,body)=>fetch(base+'/api/'+route,{method:'POST',headers:{'x-auth-user-id':'auth-user','content-type':'application/json',origin:base},body:JSON.stringify(body||{})});const state=async()=> (await fetch(base+'/api/state',{headers:{'x-auth-user-id':'auth-user'}})).json();
 try{await state();assert.equal((await post('connect',{consent:true})).status,200);complete();await new Promise(r=>setImmediate(r));assert.equal((await state()).receiving,true);await post('connect',{consent:true});await post('stop');complete();await new Promise(r=>setImmediate(r));assert.equal((await state()).receiving,false);}finally{await new Promise(r=>server.close(r));}
});
