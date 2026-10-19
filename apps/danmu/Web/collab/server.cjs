'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');const {createStore}=require('./model.cjs');
function createPanel({dir,owner=process.env.COLLAB_OWNER_ID,preview=false}={}){
 if(preview&&process.env.NODE_ENV==='production')throw Error('禁止生产预览');
 const nonces=new Map();
 const store=createStore(dir,preview?'preview-a':owner);
 if(preview&&store.s.members.length===1){store.s.members.push({id:'preview-b',name:'伙伴（合成）',owner:false});store.upsert({pr:4,number:600,sha:'a'.repeat(40),base:'b'.repeat(40),title:'0.6.0 融合预览',summary:'同一个接收器驱动灵动岛列表与透明弹幕。\n增加本机设置与个人外观 Agent。\n预览版独立运行，不替换现用弹幕。',tests:'合成消息与隐藏渲染检查通过；真实消息与原生交互尚未验收。',checks:true,open:true,mergeable:true});store.save();}
 function json(res,status,value){res.writeHead(status,{'Content-Type':'application/json; charset=utf-8'});res.end(JSON.stringify(value));}
 async function body(req){let size=0,parts=[];for await(const p of req){size+=p.length;if(size>1048576)throw Error('内容过长');parts.push(p);}return JSON.parse(Buffer.concat(parts).toString()||'{}');}
 return {store,async handle(req,res,url,uid){
  if(!url.pathname.startsWith('/collab'))return false;
  res.setHeader('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'self' https://virxact.net; base-uri 'none'; form-action 'self'");
  try{
   const route=url.pathname.slice('/collab'.length)||'/';
   // Header-based identity comes only from the platform proxy. Local demo switches synthetic actors only.
   if(preview)uid=url.searchParams.get('actor')==='b'?'preview-b':'preview-a';
   if(route.startsWith('/runner/')){
    if(req.method!=='POST')return json(res,405,{error:'请求方式不支持'}),true;
    const envelope=await body(req),secret=store.s.runner.secret;
    const signed=JSON.stringify({endpoint:route.slice('/runner/'.length),nonce:envelope.nonce,time:envelope.time,data:envelope.data});
    const mac=secret?crypto.createHmac('sha256',secret).update(signed).digest('hex'):'';
    if(!secret||typeof envelope.mac!=='string'||envelope.mac.length!==64||!crypto.timingSafeEqual(Buffer.from(mac),Buffer.from(envelope.mac))||Math.abs(Date.now()-envelope.time)>60000||typeof envelope.nonce!=='string'||nonces.has(envelope.nonce))return json(res,403,{error:'发布助手签名无效或已经过期'}),true;
    nonces.set(envelope.nonce,Date.now());for(const [key,time]of nonces)if(Date.now()-time>60000)nonces.delete(key);
    const input=envelope.data;
    const reply=(value)=>{const data={nonce:envelope.nonce,data:value};json(res,200,{...data,mac:crypto.createHmac('sha256',secret).update(JSON.stringify(data)).digest('hex')});};
    if(route==='/runner/heartbeat'){store.s.runner.lastSeen=Date.now();store.save();reply({ok:true});}
    else if(route==='/runner/sync'){if(!Array.isArray(input.versions)||input.versions.length>50)throw Error('版本列表无效');for(const v of input.versions)store.upsert(v);store.s.runner.lastSeen=Date.now();store.save();reply({ok:true});}
    else if(route==='/runner/claim')reply({job:store.claim()});
    else if(route==='/runner/result'){store.result(input);reply({ok:true});}
    else json(res,404,{error:'接口不存在'});return true;
   }
   if(!uid)return json(res,401,{error:'请先登录虚实中台'}),true;
   if(route==='/api/identity'&&req.method==='GET'){json(res,200,{id:uid,configured:!!store.s.members.length});return true;}
   if(req.method==='POST'){
    let origin;try{origin=new URL(req.headers.origin);}catch{};
    if(!origin||origin.host!==req.headers.host||!/^application\/json(?:;|$)/.test(req.headers['content-type']||''))return json(res,403,{error:'请从当前面板操作'}),true;
    const input=await body(req);
    if(route==='/api/join'){let name;try{name=Buffer.from(req.headers['x-auth-user-display-name-b64']||'','base64url').toString();}catch{}store.join(uid,name||'待核对的伙伴');json(res,200,{ok:true});return true;}
    if(!store.member(uid))return json(res,403,{error:'请先申请加入，并由负责人确认'}),true;
    if(route==='/api/action'){store.action(uid,input);json(res,200,{ok:true});}
    else if(route==='/api/vote'){store.vote(uid,input.id,input.digest,input.agree===true);json(res,200,{ok:true});}
    else if(route==='/api/runner-token')json(res,200,{token:store.token(uid)});
    else json(res,404,{error:'接口不存在'});return true;
   }
   if(route==='/api/state'&&req.method==='GET'){
    if(!store.member(uid))json(res,403,{error:store.s.members.length?'请申请加入，由宰治确认身份':'面板正在配置负责人，请稍后打开',canJoin:store.s.members.length===1});else json(res,200,store.view(uid));return true;
   }
   if(req.method!=='GET'){json(res,405,{error:'请求方式不支持'});return true;}
   const root=path.join(__dirname,'public'),name=route==='/'?'index.html':route.slice(1),file=path.resolve(root,name);
   if(!file.startsWith(root+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){json(res,404,{error:'页面不存在'});return true;}
   const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.svg':'image/svg+xml'};res.writeHead(200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream'});fs.createReadStream(file).pipe(res);return true;
  }catch(e){json(res,400,{error:e.message||'操作失败，请刷新后重试'});return true;}
 }};
}
module.exports={createPanel};
