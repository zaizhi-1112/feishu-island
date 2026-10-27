'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path'),crypto=require('node:crypto');
const {Vault,Broker,PURPOSES}=require('./core.cjs');
const {createServer}=require('./server.cjs');
const mock=j=>({ok:true,json:async()=>j});
test('encrypted vault binds ciphertext to owner and purpose',async()=>{const root=await fs.mkdtemp(path.join(os.tmpdir(),'island-auth-test-'));const v=new Vault(root,crypto.randomBytes(32).toString('base64'));await v.save('alice','archive',{access:'synthetic-private-token'});const bytes=await fs.readFile(path.join(root,v.name('alice','archive')+'.enc'));assert(!bytes.includes('synthetic-private-token'));assert.equal(await v.read('bob','archive'),null);assert.equal((await v.read('alice','archive')).access,'synthetic-private-token');await fs.writeFile(path.join(root,v.name('bob','archive')+'.enc'),bytes);await assert.rejects(v.read('bob','archive'));});
test('scoped device flow, no token response, cancel and poll limits',async()=>{let now=0,calls=0;const saved=[];const b=new Broker({vault:{save:async(...v)=>saved.push(v),read:async()=>null},env:{FEISHU_ARCHIVE_SECRET:'synthetic-secret'},now:()=>now,fetcher:async(url,opts)=>{calls++;if(url.includes('device_authorization')){assert.equal(opts.body.get('scope'),PURPOSES.archive.scope);return mock({device_code:'synthetic-device',verification_uri_complete:'https://accounts.feishu.cn/device?user_code=TEST',interval:5,expires_in:240});}return mock({access_token:'synthetic-access',refresh_token:'synthetic-refresh',expires_in:3600,refresh_token_expires_in:86400,scope:PURPOSES.archive.scope});}});const f=await b.start('alice','archive');await assert.rejects(b.poll('bob',f.flow));assert.equal((await b.poll('alice',f.flow)).state,'pending');assert.equal(calls,1);await assert.rejects(b.start('alice','archive'));now=6000;assert.deepEqual(await b.poll('alice',f.flow),{state:'authorized',desktopConnected:false});assert.equal(saved[0][0],'alice');assert.equal(saved[0][1],'archive');await assert.rejects(b.poll('alice',f.flow));const f2=await b.start('alice','archive');b.cancel('alice',f2.flow);await assert.rejects(b.poll('alice',f2.flow));});
test('gateway identity, CSRF and device requests fail closed',async t=>{const server=createServer({broker:{status:async()=>({configured:true})}});await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>server.close());const url='http://127.0.0.1:'+server.address().port;assert.equal((await fetch(url+'/api/auth/status')).status,401);assert.equal((await fetch(url+'/api/auth/status',{headers:{'X-Auth-User-Id':'alice'}})).status,200);assert.equal((await fetch(url+'/api/auth/status',{headers:{'X-Auth-User-Id':'alice','X-Virxact-Device-Id':'device'}})).status,401);assert.equal((await fetch(url+'/api/auth/start',{method:'POST',headers:{'X-Auth-User-Id':'alice','content-type':'application/json',origin:'https://evil.example'},body:'{}'})).status,403);});
test('renewal preserves last saved credentials on network or persistence failure',async()=>{let now=10000;const prior={access:'old-access',refresh:'old-refresh',expires:0,refreshExpires:999999,scope:PURPOSES.archive.scope};let stored={...prior},count=0;const b=new Broker({vault:{read:async()=>stored,save:async(u,p,v)=>{stored=v;}},env:{FEISHU_ARCHIVE_SECRET:'synthetic-secret'},now:()=>now,fetcher:async()=>{count++;return mock({access_token:'new-access',refresh_token:'new-refresh',expires_in:3600,refresh_token_expires_in:86400,scope:PURPOSES.archive.scope});}});assert.equal((await b.access('alice','archive')).access,'new-access');assert.equal((await b.access('alice','archive')).access,'new-access');assert.equal(count,1);now+=3600000;b.fetcher=async()=>{throw new Error('synthetic network failure with secret');};const before={...stored};await assert.rejects(b.access('alice','archive'),/暂时失败/);assert.deepEqual(stored,before);b.fetcher=async()=>mock({access_token:'other',refresh_token:'other-refresh',expires_in:3600,refresh_token_expires_in:86400});b.vault.save=async()=>{throw Error('synthetic disk failure');};await assert.rejects(b.access('alice','archive'));assert.deepEqual(stored,before);});
test('expired flow and missing scopes never persist authorization',async()=>{let now=0,saved=0;const b=new Broker({vault:{save:async()=>{saved++;}},env:{FEISHU_ARCHIVE_SECRET:'synthetic-secret'},now:()=>now,fetcher:async url=>url.includes('device_authorization')?mock({device_code:'d',verification_uri:'https://accounts.feishu.cn/device',expires_in:10}):mock({access_token:'a',scope:'offline_access'})});const f=await b.start('alice','archive');now=6000;await assert.rejects(b.poll('alice',f.flow),/必要权限/);assert.equal(saved,0);const g=await b.start('alice','archive');now=20000;await assert.rejects(b.poll('alice',g.flow),/过期/);});

const syntheticGrant=(extra={})=>({access_token:'synthetic-new-access',refresh_token:'synthetic-new-refresh',expires_in:3600,refresh_token_expires_in:86400,scope:PURPOSES.archive.scope,...extra});
const syntheticDevice=()=>mock({device_code:'synthetic-one-use-code',verification_uri:'https://accounts.feishu.cn/device',expires_in:60,interval:5});
test('device grant retries only persistence and serializes concurrent requests',async()=>{
 let now=0,exchanges=0,saves=0,stored=null,release;
 const gate=new Promise(r=>release=r);
 const b=new Broker({vault:{read:async()=>stored,save:async(u,p,v)=>{saves++;if(saves===1)throw Error('synthetic disk failure');stored=v;}},env:{FEISHU_ARCHIVE_SECRET:'synthetic-secret'},now:()=>now,fetcher:async url=>{
  if(url.includes('device_authorization'))return syntheticDevice();
  exchanges++;await gate;return mock(syntheticGrant());
 }});
 const f=await b.start('alice','archive');now=6000;
 const first=b.poll('alice',f.flow);const rejected=assert.rejects(first,/暂未保存/);
 assert.equal((await b.poll('alice',f.flow)).state,'pending');
 assert.throws(()=>b.cancel('alice',f.flow),/正在核对/);
 await assert.rejects(b.access('alice','archive'),/更新中/);
 await assert.rejects(b.start('alice','archive'),/正在处理/);
 release();await rejected;
 assert.equal(stored,null);assert.equal((await b.status('alice')).archive.authorized,false);
 assert.equal((await b.poll('alice',f.flow)).state,'pending');
 await assert.rejects(b.poll('bob',f.flow),/不存在/);
 now=12000;
 assert.deepEqual(await b.poll('alice',f.flow),{state:'authorized',desktopConnected:false});
 assert.equal(exchanges,1);assert.equal(saves,2);
 assert.equal((await b.status('alice')).archive.authorized,true);
 assert.equal(stored.access,'synthetic-new-access');
});
test('cancelled or expired unsaved device grants cannot exchange or save again',async()=>{
 let now=0,exchanges=0,saves=0;
 const b=new Broker({vault:{read:async()=>null,save:async()=>{saves++;throw Error('synthetic disk failure');}},env:{FEISHU_ARCHIVE_SECRET:'synthetic-secret'},now:()=>now,fetcher:async url=>{if(url.includes('device_authorization'))return syntheticDevice();exchanges++;return mock(syntheticGrant());}});
 const f=await b.start('alice','archive');now=6000;await assert.rejects(b.poll('alice',f.flow),/暂未保存/);
 assert.deepEqual(b.cancel('alice',f.flow),{cancelled:true});now=12000;
 await assert.rejects(b.poll('alice',f.flow),/不存在/);
 const f2=await b.start('alice','archive');now=18000;await assert.rejects(b.poll('alice',f2.flow),/暂未保存/);
 now=80000;await assert.rejects(b.poll('alice',f2.flow),/过期/);
 assert.equal(exchanges,2);assert.equal(saves,2);
 assert.equal((await b.status('alice')).archive.authorized,false);
});
test('rotated refresh credentials are saved before returning and never exchanged twice after disk failure',async()=>{
 let now=10000,exchanges=0,saves=0,release;
 const prior={access:'synthetic-old-access',refresh:'synthetic-old-refresh',expires:0,refreshExpires:999999,scope:PURPOSES.archive.scope};
 let stored=prior;
 const gate=new Promise(r=>release=r);
 const b=new Broker({vault:{read:async()=>stored,save:async(u,p,v)=>{saves++;if(saves===1)throw Error('synthetic disk failure');await gate;stored=v;}},env:{FEISHU_ARCHIVE_SECRET:'synthetic-secret'},now:()=>now,fetcher:async(url,opts)=>{exchanges++;assert.equal(JSON.parse(opts.body).refresh_token,prior.refresh);return mock(syntheticGrant());}});
 await assert.rejects(b.access('alice','archive'),/暂未保存/);
 assert.equal(stored,prior);assert.equal((await b.status('alice')).archive.authorized,false);
 const retry=b.access('alice','archive');
 await assert.rejects(b.access('alice','archive'),/更新中/);
 assert.equal(stored,prior);assert.equal(exchanges,1);
 release();assert.equal((await retry).access,'synthetic-new-access');
 assert.equal(stored.refresh,'synthetic-new-refresh');assert.equal(exchanges,1);assert.equal(saves,2);
 assert.equal((await b.status('alice')).archive.authorized,true);
 assert.equal((await b.access('alice','archive')).access,'synthetic-new-access');assert.equal(exchanges,1);
});
test('expired unsaved refresh blocks old-token replay until a new authorization is saved',async()=>{
 let now=10000,exchanges=0,fail=true;
 let stored={access:'synthetic-old-access',refresh:'synthetic-old-refresh',expires:0,refreshExpires:999999,scope:PURPOSES.archive.scope};
 const b=new Broker({vault:{read:async()=>stored,save:async(u,p,v)=>{if(fail)throw Error('synthetic disk failure');stored=v;}},env:{FEISHU_ARCHIVE_SECRET:'synthetic-secret'},now:()=>now,fetcher:async url=>{
  if(url.includes('device_authorization'))return syntheticDevice();exchanges++;
  return mock(syntheticGrant(exchanges===1?{refresh_token_expires_in:1}:{}));
 }});
 await assert.rejects(b.access('alice','archive'),/暂未保存/);now=12000;fail=false;
 await assert.rejects(b.access('alice','archive'),/重新授权/);
 await assert.rejects(b.access('alice','archive'),/重新授权/);
 assert.equal(exchanges,1);assert.equal((await b.status('alice')).archive.authorized,false);
 const f=await b.start('alice','archive');now=18000;
 assert.equal((await b.poll('alice',f.flow)).state,'authorized');
 assert.equal(exchanges,2);assert.equal(b.pendingRefresh.size,0);
 assert.equal((await b.access('alice','archive')).access,'synthetic-new-access');assert.equal(exchanges,2);
});

test('calendar grant is separate and least privilege',()=>{
 assert.equal(PURPOSES.calendar.id,PURPOSES.receive.id);
 assert.deepEqual(PURPOSES.calendar.scope.split(' ').sort(),['auth:user.id:read','calendar:calendar:read','calendar:calendar.event:read','calendar:calendar.event:create','calendar:calendar.event:update','offline_access'].sort());
 assert(!PURPOSES.receive.scope.includes('calendar:'));
});

test('calendar access downscopes an existing broad grant before releasing it',async()=>{
 let saved={access:'synthetic-broad',refresh:'synthetic-r1',scope:PURPOSES.calendar.scope+' im:message',expires:3600000,refreshExpires:86400000},calls=0;
 const b=new Broker({vault:{read:async()=>saved,save:async(u,p,v)=>{assert.equal(p,'calendar');saved=v;}},env:{FEISHU_RECEIVE_SECRET:'synthetic'},now:()=>0,fetcher:async(url,options)=>{
  calls++;const body=JSON.parse(options.body);assert.equal(body.scope,PURPOSES.calendar.scope);assert.equal(body.grant_type,'refresh_token');
  return mock({access_token:'synthetic-narrow',refresh_token:'synthetic-r2',scope:PURPOSES.calendar.scope,expires_in:3600,refresh_token_expires_in:86400});
 }});
 assert.equal((await b.access('alice','calendar')).access,'synthetic-narrow');
 assert.equal(saved.scope,PURPOSES.calendar.scope);
 assert.equal((await b.access('alice','calendar')).access,'synthetic-narrow');assert.equal(calls,1);
});
