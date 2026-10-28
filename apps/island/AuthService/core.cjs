'use strict';
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');
const PURPOSES = Object.freeze({
 calendar:{id:'cli_aa217b534af89cdc',secret:'FEISHU_RECEIVE_SECRET',scope:'auth:user.id:read calendar:calendar:read calendar:calendar.event:read calendar:calendar.event:create calendar:calendar.event:update offline_access'},
 receive:{id:'cli_aa217b534af89cdc',secret:'FEISHU_RECEIVE_SECRET',scope:'auth:user.id:read im:chat:read im:chat.user_setting:read im:message.group_msg:get_as_user im:message.p2p_msg:get_as_user im:message:readonly offline_access'},
 archive:{id:'cli_aa534c191338dd29',secret:'FEISHU_ARCHIVE_SECRET',scope:'auth:user.id:read docx:document:create docx:document:write_only docx:document:readonly docs:document.media:upload drive:file:upload base:record:create base:field:read base:record:read wiki:node:read offline_access'}
});
class AuthError extends Error { constructor(status,message){super(message);this.status=status;} }
class Vault {
 constructor(root,key){this.root=root;this.key=Buffer.from(key||'','base64');if(this.key.length!==32)throw new Error('AUTH_VAULT_KEY must be a 32-byte base64 key');}
 name(user,purpose){if(!Object.hasOwn(PURPOSES,purpose))throw new AuthError(400,'未知连接类型');return crypto.createHash('sha256').update(JSON.stringify([user,purpose])).digest('hex');}
 async save(user,purpose,value){await fs.mkdir(this.root,{recursive:true,mode:0o700});const name=this.name(user,purpose);const iv=crypto.randomBytes(12);const c=crypto.createCipheriv('aes-256-gcm',this.key,iv);c.setAAD(Buffer.from(name));const bytes=Buffer.concat([iv,c.update(JSON.stringify(value)),c.final(),c.getAuthTag()]);const temp=path.join(this.root,name+'.'+crypto.randomUUID()+'.tmp');await fs.writeFile(temp,bytes,{mode:0o600,flag:'wx'});await fs.rename(temp,path.join(this.root,name+'.enc'));}
 async read(user,purpose){const name=this.name(user,purpose);let b;try{b=await fs.readFile(path.join(this.root,name+'.enc'));}catch(e){if(e.code==='ENOENT')return null;throw e;}const d=crypto.createDecipheriv('aes-256-gcm',this.key,b.subarray(0,12));d.setAAD(Buffer.from(name));d.setAuthTag(b.subarray(-16));return JSON.parse(Buffer.concat([d.update(b.subarray(12,-16)),d.final()]));}
}
class Broker {
 constructor({vault,env=process.env,fetcher=fetch,now=Date.now}){this.vault=vault;this.env=env;this.fetcher=fetcher;this.now=now;this.flows=new Map();this.locks=new Set();this.pendingRefresh=new Map();}
 config(purpose){const p=PURPOSES[purpose];if(!p)throw new AuthError(400,'未知连接类型');if(!this.env[p.secret])throw new AuthError(503,'管理员尚未配置此连接');return p;}
 async request(url,options){let r,j;try{r=await this.fetcher(url,{...options,redirect:'error',signal:AbortSignal.timeout(15000)});j=await r.json();}catch{throw new AuthError(502,'飞书连接暂时失败，请稍后再试');}if(!j||typeof j!=='object')throw new AuthError(502,'飞书响应格式异常');return {r,j};}
 prune(){for(const [id,f] of this.flows)if(!f.busy&&f.expires<=this.now())this.flows.delete(id);}
 async start(user,purpose){const lock=JSON.stringify([user,purpose]);if(this.locks.has(lock))throw new AuthError(409,'授权请求正在处理');this.locks.add(lock);try{return await this.begin(user,purpose);}finally{this.locks.delete(lock);}}
 async begin(user,purpose){this.prune();const p=this.config(purpose);if(this.flows.size>=100||[...this.flows.values()].some(f=>f.user===user&&f.purpose===purpose))throw new AuthError(409,'已有授权进行中，请完成或取消后再试');const {r,j}=await this.request('https://accounts.feishu.cn/oauth/v1/device_authorization',{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded',authorization:'Basic '+Buffer.from(p.id+':'+this.env[p.secret]).toString('base64')},body:new URLSearchParams({client_id:p.id,scope:p.scope})});if(!r.ok||j.error||!j.device_code)throw new AuthError(502,'飞书未能创建授权，请检查应用配置');let u;try{u=new URL(j.verification_uri_complete||j.verification_uri);}catch{throw new AuthError(502,'飞书授权地址异常');}if(u.protocol!=='https:'||u.hostname!=='accounts.feishu.cn'||u.username||u.password||u.port)throw new AuthError(502,'飞书授权地址异常');const id=crypto.randomBytes(32).toString('base64url');const interval=Math.max(5,Math.min(60,Number(j.interval)||5))*1000;this.flows.set(id,{user,purpose,code:j.device_code,expires:this.now()+Math.min(600,Math.max(1,Number(j.expires_in)||240))*1000,interval,next:this.now()+interval});return {flow:id,url:u.href,interval:interval/1000};}
 owned(user,id){this.prune();const f=this.flows.get(id);if(!f||f.user!==user)throw new AuthError(404,'授权不存在或已过期');return f;}
 cancel(user,id){const f=this.owned(user,id);if(f.busy)throw new AuthError(409,'正在核对授权，请稍后取消');this.flows.delete(id);return {cancelled:true};}
 async poll(user,id){
  const f=this.owned(user,id),key=JSON.stringify([user,f.purpose]);
  if(f.busy||this.locks.has(key)||this.now()<f.next)return {state:'pending',interval:Math.ceil(f.interval/1000)};
  f.busy=true;this.locks.add(key);f.next=this.now()+f.interval;
  try{
   if(!f.grant){
    const p=this.config(f.purpose);const {r,j}=await this.request('https://open.feishu.cn/open-apis/authen/v2/oauth/token',{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:device_code',device_code:f.code,client_id:p.id,client_secret:this.env[p.secret]})});
    if(j.error==='authorization_pending'||j.error==='slow_down'){if(j.error==='slow_down')f.interval=Math.min(60000,f.interval+5000);f.next=this.now()+f.interval;return {state:'pending',interval:f.interval/1000};}
    if(!r.ok||j.error||!j.access_token){this.flows.delete(id);throw new AuthError(400,'授权未完成或已拒绝，请重新连接');}
    const granted=new Set(String(j.scope||'').split(/\s+/));
    if(!p.scope.split(' ').every(s=>granted.has(s))){this.flows.delete(id);throw new AuthError(400,'必要权限未全部授权，连接未保存');}
    if(!j.refresh_token||!Number.isFinite(j.expires_in)||j.expires_in<=0||!Number.isFinite(j.refresh_token_expires_in)||j.refresh_token_expires_in<=0){this.flows.delete(id);throw new AuthError(502,'飞书未返回完整有效期，连接未保存');}
    // The one-use device code has been consumed. Retain the grant until durable save,
    // cancellation or this flow's original deadline; never exchange that code again.
    f.grant={access:j.access_token,refresh:j.refresh_token,expires:this.now()+j.expires_in*1000,refreshExpires:this.now()+j.refresh_token_expires_in*1000,scope:j.scope,connectedAt:this.now()};
    f.code=null;
   }
   if(this.flows.get(id)!==f||f.expires<=this.now()||f.grant.refreshExpires<=this.now()){this.flows.delete(id);throw new AuthError(404,'授权不存在或已过期');}
   try{await this.vault.save(user,f.purpose,f.grant);}catch{throw new AuthError(503,'授权暂未保存，请稍后再次核对');}
   this.pendingRefresh.delete(key);this.flows.delete(id);
   return {state:'authorized',desktopConnected:false};
  }finally{f.busy=false;this.locks.delete(key);}
 }
 async access(user,purpose){
  this.prune();const key=JSON.stringify([user,purpose]);
  if(this.locks.has(key)||[...this.flows.values()].some(f=>f.user===user&&f.purpose===purpose&&f.grant))throw new AuthError(409,'连接更新中，请稍后重试');
  this.locks.add(key);
  try{
   const p=this.config(purpose);
   let v=this.pendingRefresh.get(key);
   if(v){
    // A rotated refresh token must be persisted before use. Keep an expired
    // pending grant as a tombstone: retrying the previous token is not safe.
    if(v.refreshExpires<=this.now())throw new AuthError(401,'请重新授权此连接');
    try{await this.vault.save(user,purpose,v);}catch{throw new AuthError(503,'续期暂未保存，请稍后重试');}
    this.pendingRefresh.delete(key);
   }else v=await this.vault.read(user,purpose);
   if(!v?.refresh||v.refreshExpires<=this.now())throw new AuthError(401,'请重新授权此连接');
   // Feishu may return the union of earlier grants for the same app. Every
   // purpose must downscope through OAuth before desktop handoff, not just calendar.
   const granted=new Set(String(v.scope||'').split(/\s+/).filter(Boolean));
   const scopeExact=granted.size===p.scope.split(' ').length&&p.scope.split(' ').every(s=>granted.has(s));
   if(v.expires>this.now()+120000&&scopeExact)return {access:v.access,expires:v.expires,scope:v.scope};
   const {r,j}=await this.request('https://open.feishu.cn/open-apis/authen/v2/oauth/token',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({grant_type:'refresh_token',refresh_token:v.refresh,client_id:p.id,client_secret:this.env[p.secret],scope:p.scope})});
   if(!r.ok||j.error||!j.access_token||!j.refresh_token||!Number.isFinite(j.expires_in)||j.expires_in<=0||!Number.isFinite(j.refresh_token_expires_in)||j.refresh_token_expires_in<=0)throw new AuthError(502,'续期未完成，原连接状态已保留');
   const scope=String(j.scope||v.scope);if(!p.scope.split(' ').every(s=>scope.split(/\s+/).includes(s)))throw new AuthError(403,'续期权限不完整');
   const next={...v,access:j.access_token,refresh:j.refresh_token,expires:this.now()+j.expires_in*1000,refreshExpires:this.now()+j.refresh_token_expires_in*1000,scope};
   this.pendingRefresh.set(key,next);
   try{await this.vault.save(user,purpose,next);}catch{throw new AuthError(503,'续期暂未保存，请稍后重试');}
   this.pendingRefresh.delete(key);
   return {access:next.access,expires:next.expires,scope};
  }finally{this.locks.delete(key);}
 }
 async status(user){
  this.prune();const result={};
  for(const [purpose,p] of Object.entries(PURPOSES)){
   const key=JSON.stringify([user,purpose]);const v=await this.vault.read(user,purpose);
   const unsaved=this.pendingRefresh.has(key)||[...this.flows.values()].some(f=>f.user===user&&f.purpose===purpose&&f.grant);
   result[purpose]={configured:!!this.env[p.secret],authorized:!unsaved&&!!v?.refresh&&v.refreshExpires>this.now(),accessExpires:unsaved?null:v?.expires||null,desktopConnected:false};
  }
  return result;
 }
}
module.exports={Vault,Broker,AuthError,PURPOSES};
