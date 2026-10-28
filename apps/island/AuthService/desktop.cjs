'use strict';
const crypto=require('node:crypto');
const {AuthError,PURPOSES}=require('./core.cjs');
// The company's authenticated WebView obtains only short-lived user tokens.
// No public pairing endpoint, refresh token, App Secret, or arbitrary API proxy.
class DesktopAccess {
 constructor(broker){this.broker=broker;this.identities=new Map();}
 async access(user,purpose){
  if(!Object.hasOwn(PURPOSES,purpose))throw new AuthError(400,'未知连接类型');
  const token=await this.broker.access(user,purpose);
  const allowed=new Set(PURPOSES[purpose].scope.split(' '));
  const granted=String(token.scope||'').split(/\s+/).filter(Boolean);
  if(granted.some(s=>!allowed.has(s))||[...allowed].some(s=>!granted.includes(s)))throw new AuthError(403,'飞书返回权限与本次用途不一致；额外：'+granted.filter(s=>!allowed.has(s)).map(s=>/^[a-zA-Z0-9_.:-]{1,160}$/.test(s)?s:'unknown').join(',')+'；缺少：'+[...allowed].filter(s=>!granted.includes(s)).join(','));
  const key=crypto.createHash('sha256').update(JSON.stringify([user,purpose,token.access])).digest('hex');
  for(const [id,entry] of this.identities)if(entry.expires<=this.broker.now())this.identities.delete(id);
  let identity=this.identities.get(key);
  if(!identity){
   const {r,j}=await this.broker.request('https://open.feishu.cn/open-apis/authen/v1/user_info',{headers:{Authorization:'Bearer '+token.access}});
   if(!r.ok||j.code!==0||typeof j.data?.open_id!=='string'||!/^ou_[A-Za-z0-9_-]{1,128}$/.test(j.data.open_id))throw new AuthError(502,'无法核对本次飞书授权身份，请稍后重试');
   identity={openId:j.data.open_id,userName:typeof j.data.name==='string'?j.data.name.slice(0,128):'本人飞书账号',expires:token.expires};
   if(this.identities.size>=200)this.identities.delete(this.identities.keys().next().value);
   this.identities.set(key,identity);
  }
  return {appId:PURPOSES[purpose].id,access:token.access,expires:token.expires,scope:token.scope,userId:user,openId:identity.openId,userName:identity.userName};
 }
}
module.exports={DesktopAccess};
