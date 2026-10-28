'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {DesktopAccess}=require('./desktop.cjs');
const {PURPOSES}=require('./core.cjs');
const {createServer}=require('./server.cjs');
const origin='https://feishu-island.virxact.net';
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

// Regression: authorizing calendar on the same Feishu app can widen the receive
// grant. Test the complete broker -> desktop -> HTTP path with a fresh token.
for (const purpose of ['receive','calendar','archive']) {
 test(`${purpose} HTTP handoff downscopes fresh broad grants and preserves other purposes`,async t=>{
  const {Broker}=require('./core.cjs');
  const other=purpose==='receive'?'calendar':'receive';
  const broad=[...new Set((PURPOSES[purpose].scope+' '+PURPOSES[other].scope).split(' '))].join(' ');
  const stored=new Map([[purpose,{access:'synthetic-broad',refresh:'synthetic-old-refresh',expires:3600000,refreshExpires:86400000,scope:broad}],[other,{sentinel:'unchanged'}]]);
  let refreshes=0,identities=0;
  const broker=new Broker({vault:{read:async(u,p)=>stored.get(p),save:async(u,p,v)=>stored.set(p,v)},env:{[PURPOSES[purpose].secret]:'synthetic-secret'},now:()=>0,fetcher:async(url,options)=>{
   if(url.endsWith('/user_info')){identities++;assert.equal(options.headers.Authorization,'Bearer synthetic-narrow');return {ok:true,json:async()=>({code:0,data:{open_id:'ou_synthetic'}})};}
   refreshes++;const body=JSON.parse(options.body);assert.equal(body.scope,PURPOSES[purpose].scope);assert.equal(body.refresh_token,'synthetic-old-refresh');
   return {ok:true,json:async()=>({access_token:'synthetic-narrow',refresh_token:'synthetic-new-refresh',scope:PURPOSES[purpose].scope,expires_in:3600,refresh_token_expires_in:86400})};
  }});
  const base=await localServer(t,broker);
  for(let i=0;i<2;i++){
   const r=await fetch(base+'/api/auth/access',{method:'POST',headers,body:JSON.stringify({purpose})});
   assert.equal(r.status,200);const j=await r.json();assert.equal(j.scope,PURPOSES[purpose].scope);assert.equal(j.access,'synthetic-narrow');assert(!JSON.stringify(j).includes('refresh'));
  }
  assert.equal(refreshes,1);assert.equal(identities,1);assert.deepEqual(stored.get(other),{sentinel:'unchanged'});
 });
}

test('provider ignoring requested downscope stays blocked and retains rotated refresh safely',async t=>{
 const {Broker}=require('./core.cjs');
 const broad=PURPOSES.receive.scope+' calendar:calendar:read';
 let stored={access:'synthetic-broad',refresh:'synthetic-r1',expires:3600000,refreshExpires:86400000,scope:broad},calls=0;
 const b=new Broker({vault:{read:async()=>stored,save:async(u,p,v)=>{stored=v;}},env:{FEISHU_RECEIVE_SECRET:'synthetic'},now:()=>0,fetcher:async(url,options)=>{
  assert(!url.endsWith('/user_info'));const body=JSON.parse(options.body);assert.equal(body.scope,PURPOSES.receive.scope);assert.equal(body.refresh_token,calls===0?'synthetic-r1':'synthetic-r2');calls++;
  return {ok:true,json:async()=>({access_token:'synthetic-still-broad',refresh_token:'synthetic-r2',scope:broad,expires_in:3600,refresh_token_expires_in:86400})};
 }});
 const base=await localServer(t,b);
 for(let i=0;i<2;i++){
  const r=await fetch(base+'/api/auth/access',{method:'POST',headers,body:JSON.stringify({purpose:'receive'})});
  assert.equal(r.status,403);const j=await r.json();assert.deepEqual(Object.keys(j),['error']);assert(!JSON.stringify(j).includes('synthetic'));
 }
 assert.equal(calls,2);assert.equal(stored.refresh,'synthetic-r2');
});
