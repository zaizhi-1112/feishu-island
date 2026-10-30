'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {DesktopAccess}=require('./desktop.cjs');
const {PURPOSES}=require('./core.cjs');
const {createServer}=require('./server.cjs');
const origin='https://island.example.invalid';
const token=(extra={})=>({access:'synthetic-access',expires:3600000,scope:PURPOSES.archive.scope,...extra});
const identity=(extra={})=>({r:{ok:true},j:{code:0,data:{open_id:'ou_synthetic_alice',name:'合成本人',...extra}}});
const expectedKeys=['access','appId','expires','openId','scope','userId','userName'].sort();
const headers={'X-Auth-User-Id':'alice',Origin:origin,'X-Island-Auth':'1','Content-Type':'application/json'};
async function localServer(t,broker){const server=createServer({broker});await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));t.after(()=>server.close());return 'http://127.0.0.1:'+server.address().port;}

test('desktop access returns a strict short-lived token and validated identity envelope',async()=>{
 const calls=[];
 const broker={now:()=>0,access:async(user,purpose)=>{assert.equal(user,'alice');assert.equal(purpose,'archive');return token({refresh:'synthetic-refresh-never-export',appSecret:'synthetic-secret-never-export'});},request:async(url,options)=>{calls.push([url,options]);return identity({refresh_token:'synthetic-upstream-refresh',email:'synthetic-private-email'});}};
 const result=await new DesktopAccess(broker).access('alice','archive');
 assert.deepEqual(Object.keys(result).sort(),expectedKeys);
 assert.deepEqual(result,{appId:PURPOSES.archive.id,access:'synthetic-access',expires:3600000,scope:PURPOSES.archive.scope,userId:'alice',openId:'ou_synthetic_alice',userName:'合成本人'});
 assert.equal(calls.length,1);assert.equal(calls[0][0],'https://open.feishu.cn/open-apis/authen/v1/user_info');
 assert.deepEqual(calls[0][1],{headers:{Authorization:'Bearer synthetic-access'}});
 const json=JSON.stringify(result);assert(!json.includes('refresh'));assert(!json.includes('secret'));assert(!json.includes('email'));
});

test('identity cache is bound to user, purpose and current token and expires',async()=>{
 let current='synthetic-access',now=0,checks=0;
 const broker={now:()=>now,access:async(user,purpose)=>token({access:current,expires:now+3600000,scope:PURPOSES[purpose].scope}),request:async()=>{checks++;return identity({open_id:current==='synthetic-access'?'ou_synthetic_old':'ou_synthetic_rotated'});}};
 const desktop=new DesktopAccess(broker);
 assert.equal((await desktop.access('alice','archive')).openId,'ou_synthetic_old');
 await desktop.access('alice','archive');assert.equal(checks,1);
 current='synthetic-rotated-access';
 assert.equal((await desktop.access('alice','archive')).openId,'ou_synthetic_rotated');assert.equal(checks,2);
 await desktop.access('bob','archive');assert.equal(checks,3);
 await desktop.access('alice','receive');assert.equal(checks,4);
 now=3600001;await desktop.access('alice','archive');assert.equal(checks,5);
});

test('invalid or unsuccessful upstream identity fails closed and is not cached',async()=>{
 const invalid=[
  {r:{ok:false},j:{code:0,data:{open_id:'ou_valid'}}},
  {r:{ok:true},j:{code:1,data:{open_id:'ou_valid'}}},
  {r:{ok:true},j:{code:0,data:null}},
  identity({open_id:''}),identity({open_id:'ou_'}),identity({open_id:'other_user'}),
  identity({open_id:'ou_a\n'}),identity({open_id:'ou_a/b'}),identity({open_id:123}),identity({open_id:'ou_'+ 'a'.repeat(129)})
 ];
 for(const response of invalid){
  let checks=0;const desktop=new DesktopAccess({now:()=>0,access:async()=>token(),request:async()=>{checks++;return response;}});
  await assert.rejects(desktop.access('alice','archive'),e=>e.status===502&&e.message.includes('核对'));
  await assert.rejects(desktop.access('alice','archive'));assert.equal(checks,2);assert.equal(desktop.identities.size,0);
 }
});

test('unknown desktop purpose rejects before any credential request',async()=>{
 let calls=0;const desktop=new DesktopAccess({access:async()=>{calls++;}});
 for(const purpose of ['all','__proto__','',undefined])await assert.rejects(desktop.access('alice',purpose),e=>e.status===400);
 assert.equal(calls,0);
});

test('desktop HTTP endpoint rejects missing identity, device identities and cross-origin requests',async t=>{
 let calls=0;const url=await localServer(t,{access:async()=>{calls++;return token();},now:()=>0,request:async()=>identity()});
 const post=async h=>fetch(url+'/api/auth/access',{method:'POST',headers:h,body:JSON.stringify({purpose:'archive'})});
 const noIdentity={...headers};delete noIdentity['X-Auth-User-Id'];
 assert.equal((await post(noIdentity)).status,401);
 assert.equal((await post({...headers,'X-Auth-User-Id':''})).status,401);
 assert.equal((await post({...headers,'X-Virxact-Device-Id':'synthetic-device'})).status,401);
 assert.equal((await post({...headers,Origin:'https://evil.example'})).status,403);
 const noOrigin={...headers};delete noOrigin.Origin;assert.equal((await post(noOrigin)).status,403);
 const noMarker={...headers};delete noMarker['X-Island-Auth'];assert.equal((await post(noMarker)).status,403);
 assert.equal((await post({...headers,'Content-Type':'text/plain'})).status,403);
 assert.equal((await fetch(url+'/api/auth/access',{headers})).status,405);
 assert.equal(calls,0);
});

test('same-origin HTTP access uses gateway owner and never echoes injected account or private fields',async t=>{
 let calls=0;
 const url=await localServer(t,{now:()=>0,access:async(user,purpose)=>{calls++;assert.equal(user,'alice');assert.equal(purpose,'archive');return token({refresh:'synthetic-never-export',secret:'synthetic-never-export'});},request:async()=>identity()});
 const response=await fetch(url+'/api/auth/access',{method:'POST',headers,body:JSON.stringify({purpose:'archive',user:'bob',userId:'bob',scope:'arbitrary',refresh:'injected'})});
 assert.equal(response.status,200);assert.equal(response.headers.get('cache-control'),'no-store');
 const body=await response.json();assert.deepEqual(Object.keys(body).sort(),expectedKeys);
 assert.equal(body.userId,'alice');assert.equal(body.appId,PURPOSES.archive.id);assert.equal(body.scope,PURPOSES.archive.scope);
 assert(!JSON.stringify(body).includes('synthetic-never-export'));assert.equal(calls,1);
});

test('HTTP identity-validation failure does not expose credentials or upstream payloads',async t=>{
 const url=await localServer(t,{now:()=>0,access:async()=>token(),request:async()=>identity({open_id:'invalid',access_token:'synthetic-never-export',refresh_token:'synthetic-never-export'})});
 const response=await fetch(url+'/api/auth/access',{method:'POST',headers,body:JSON.stringify({purpose:'archive'})});
 assert.equal(response.status,502);const body=await response.json();assert.deepEqual(Object.keys(body),['error']);assert(!JSON.stringify(body).includes('synthetic-'));assert(!JSON.stringify(body).includes('invalid'));
});


test('desktop rejects extra or missing scope before validating identity or exporting any token',async()=>{
 for(const purpose of Object.keys(PURPOSES)){
  const exact=PURPOSES[purpose].scope;
  for(const scope of [exact+' im:message:send_as_user',exact.split(' ').slice(1).join(' '),'',undefined,PURPOSES[purpose==='archive'?'receive':'archive'].scope]){
   let identityCalls=0;
   const desktop=new DesktopAccess({now:()=>0,access:async()=>token({scope}),request:async()=>{identityCalls++;return identity();}});
   await assert.rejects(desktop.access('alice',purpose),e=>e.status===403&&e.message.includes('权限'));
   assert.equal(identityCalls,0);assert.equal(desktop.identities.size,0);
  }
  const equivalent='  '+exact.split(' ').reverse().join('  ')+' '+exact.split(' ')[0]+'  ';
  const desktop=new DesktopAccess({now:()=>0,access:async()=>token({scope:equivalent}),request:async()=>identity()});
  assert.equal((await desktop.access('alice',purpose)).access,'synthetic-access');
 }
});

test('HTTP extra scope rejection returns only a safe error and no access token',async t=>{
 let identityCalls=0;
 const url=await localServer(t,{now:()=>0,access:async()=>token({scope:PURPOSES.archive.scope+' im:message:send_as_user'}),request:async()=>{identityCalls++;return identity();}});
 const response=await fetch(url+'/api/auth/access',{method:'POST',headers,body:JSON.stringify({purpose:'archive'})});
 assert.equal(response.status,403);const body=await response.json();assert.deepEqual(Object.keys(body),['error']);
 assert(!JSON.stringify(body).includes('synthetic-access'));assert.equal(identityCalls,0);
});
