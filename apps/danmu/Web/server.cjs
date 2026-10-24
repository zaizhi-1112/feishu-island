'use strict';
const http=require('node:http'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {spawn}=require('node:child_process');const Appearance=require('./public/appearance-schema.js');const {CLI,Reader}=require('./core/reader.cjs');
const SCOPES='auth:user.id:read im:message:readonly im:message.group_msg:get_as_user im:message.p2p_msg:get_as_user im:chat:read im:chat.user_setting:read offline_access';
const demoText='桌面弹幕试播';
function createApp({preview=false,binary=process.env.LARK_BINARY||'/opt/lark/lark-cli',makeCLI=(profile)=>new CLI(binary,profile),makeReader=cli=>new Reader(cli),dataDir=process.env.DANMU_DATA_DIR||'/data'}={}){
 const sessions=new Map();
 const panel=require('./collab/server.cjs').createPanel({dir:path.join(dataDir||'/tmp','collab'),preview:preview&&process.env.COLLAB_PREVIEW==='1'});
 function session(uid){
  if(sessions.has(uid)){const s=sessions.get(uid);s.touched=Date.now();return s;}
  if(sessions.size>=8)throw new Error('会话数达到上限，请稍后再试');
  const profile='web-'+crypto.createHash('sha256').update(uid).digest('hex').slice(0,32),cli=makeCLI(profile),reader=makeReader(cli);
  const prefPath=dataDir?path.join(dataDir,profile+'-preferences.json'):null;let stopped=false;try{stopped=JSON.parse(fs.readFileSync(prefPath,'utf8')).stopped===true;}catch{}
  const s={cli,reader,profile,prefPath,stopped,touched:Date.now(),busy:false,received:0,next:0,events:[],status:{text:stopped?'账号接收已停止':'尚未连接飞书，请先完成只读授权',health:'stopped'}};
  reader.on('status',x=>{s.status=x;});reader.on('message',m=>{s.received++;s.events.push({...m,seq:++s.next});if(s.events.length>100)s.events.shift();});s.initialized=cli.call(['config','show']).then(async c=>{s.configured=!!c.appId;if(!preview&&s.configured&&!s.stopped){const a=await cli.call(['auth','status','--json']);if(a.identities?.user?.available)begin(s);}}).catch(()=>{});sessions.set(uid,s);return s;
 }
 function preference(s,stopped){if(s.prefPath){fs.mkdirSync(path.dirname(s.prefPath),{recursive:true,mode:0o700});fs.writeFileSync(s.prefPath,JSON.stringify({stopped}),{mode:0o600});}s.stopped=stopped;}
 function begin(s){s.reader.poll=1500;s.reader.start();}
 function json(res,code,data){res.writeHead(code,{'content-type':'application/json; charset=utf-8'});res.end(JSON.stringify(data));}
 async function body(req){let chunks=[],size=0;for await(const c of req){size+=c.length;if(size>16384)throw new Error('请求过大');chunks.push(c);}return JSON.parse(Buffer.concat(chunks).toString()||'{}');}
 const server=http.createServer(async(req,res)=>{
  res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('Referrer-Policy','no-referrer');
  res.setHeader('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self' http://127.0.0.1:48763; frame-ancestors 'self'; base-uri 'none'; form-action 'self'");
  try{
   const uid=preview?'local-preview':req.headers['x-auth-user-id'];
   if(typeof uid!=='string'||!uid.trim()||uid.length>256)return json(res,401,{error:'请先通过虚实中台登录'});
   const url=new URL(req.url,'http://localhost');
   if(url.pathname.startsWith('/collab')){await panel.handle(req,res,url,uid);return;}
   // Sharing the collaboration page never shares the owner's existing danmu entry.
   if(process.env.DANMU_OWNER_ID&&uid!==process.env.DANMU_OWNER_ID)return json(res,403,{error:'弹幕入口仅本人可用；协作请打开 /collab/'});
   if(url.pathname.startsWith('/api/')){
    if(!['GET','POST'].includes(req.method))return json(res,405,{error:'请求方式不支持'});
    if(req.method==='POST'){
     // Proxy adds identity; same-origin JSON requests prevent cross-site configuration or account switches.
     const origin=req.headers.origin;
     if(!origin||new URL(origin).host!==req.headers.host||!/^application\/json(?:;|$)/.test(req.headers['content-type']||''))return json(res,403,{error:'请从当前页面操作'});
    }
    const s=session(uid);
    if(req.method==='GET'&&url.pathname==='/api/state'){await s.initialized;return json(res,200,{configured:!!s.configured,authUrl:s.busy?s.authUrl:null,status:s.status,busy:s.busy,received:s.received,receiving:s.reader.enabled,preview,version:'0.7.1'});}
    if(req.method==='GET'&&url.pathname==='/api/appearance'){let appearance=Appearance.defaults;try{appearance=Appearance.validate(JSON.parse(fs.readFileSync(path.join(dataDir,s.profile+'-appearance.json'),'utf8')));}catch{}return json(res,200,{appearance});}
    if(req.method==='GET'&&url.pathname==='/api/messages'){
     const since=Number(url.searchParams.get('since'))||0;return json(res,200,{next:s.next,missed:!!(s.events.length&&since<s.events[0].seq-1),messages:s.events.filter(x=>x.seq>since)});
    }
    if(req.method!=='POST')return json(res,404,{error:'接口不存在'});
    const input=await body(req);
    if(url.pathname==='/api/appearance'){let appearance;try{appearance=Appearance.validate(input);}catch(e){return json(res,400,{error:e.message});}if(dataDir){fs.mkdirSync(dataDir,{recursive:true,mode:0o700});fs.writeFileSync(path.join(dataDir,s.profile+'-appearance.json'),JSON.stringify(appearance),{mode:0o600});}return json(res,200,{appearance});}
    if(url.pathname==='/api/demo')return json(res,200,{message:{demo:true,text:demoText,chat:'网页试播',sender:'演示'}});
    if(url.pathname==='/api/stop'){preference(s,true);await s.initialized;s.reader.stop();s.events=[];return json(res,200,{ok:true});}
    if(url.pathname==='/api/read-status'){
     if(!Array.isArray(input.ids)||input.ids.length>50||input.ids.some(x=>typeof x!=='string'||!/^om_[a-zA-Z0-9]+$/.test(x)))return json(res,400,{error:'消息编号无效'});
     if(!input.ids.length)return json(res,200,{items:[]});
     const d=await s.reader.data(['im','+messages-read-status','--message-ids',input.ids.join(',')]);return json(res,200,{items:d.items||[]});
    }
    if(url.pathname==='/api/start'){
     await s.initialized;
     if(preview)return json(res,400,{error:'本地预览不读取真实消息'});
     if(s.busy)return json(res,409,{error:'正在授权，请稍候'});
     const a=await s.cli.call(['auth','status','--json']);if(!a.identities?.user?.available)return json(res,400,{error:'请先连接飞书'});
     s.reader.gray=Array.isArray(input.gray)?input.gray.filter(x=>typeof x==='string'&&x.trim()).slice(0,100).map(x=>x.slice(0,100)):[];
     s.reader.hidden=Array.isArray(input.hidden)?input.hidden.filter(x=>typeof x==='string'&&x.trim()).slice(0,100).map(x=>x.slice(0,100)):[];
     // New unread messages need seconds-scale delivery; reused Reader isolates 2 foreground requests from catalog pagination.
     preference(s,false);begin(s);return json(res,200,{ok:true});
    }
    if(url.pathname==='/api/connect'){
     if(preview)return json(res,400,{error:'本地预览不配置账号'});
     if(s.busy)return json(res,409,{error:'正在授权，请勿重复操作'});
     if(input.consent!==true)return json(res,400,{error:'请先同意服务器只读处理消息'});
     const updating=!!(input.appId||input.secret);if(updating&&(!/^cli_[a-zA-Z0-9]+$/.test(input.appId)||typeof input.secret!=='string'||!input.secret.trim()))return json(res,400,{error:'请填写已有飞书只读应用的 App ID 和 App Secret'});
     await s.initialized;preference(s,false);s.busy=true;s.reader.stop();s.events=[];
     try{
      if(updating)await new Promise((resolve,reject)=>{
       const child=spawn(binary,['config','init','--name',s.profile,'--app-id',input.appId,'--app-secret-stdin','--brand','feishu'],{stdio:['pipe','ignore','ignore'],env:{...process.env,LARKSUITE_CLI_NO_UPDATE_NOTIFIER:'1',LARKSUITE_CLI_NO_SKILLS_NOTIFIER:'1'}});
       s.cli.children.add(child);const timer=setTimeout(()=>child.kill('SIGKILL'),15000);child.stdin.on('error',()=>{});child.stdin.end(input.secret.trim()+'\n');input.secret='';
       child.once('error',()=>{clearTimeout(timer);s.cli.children.delete(child);reject(new Error('配置工具无法启动'));});child.once('close',code=>{clearTimeout(timer);s.cli.children.delete(child);code===0?resolve():reject(new Error('应用配置失败，请检查应用信息'));});
      });
      await s.initialized;s.configured=true;const raw=await s.cli.call(['auth','login','--scope',SCOPES,'--no-wait','--json'],{timeout:20000}),info=raw.data||raw;
      const link=info.verification_uri_complete||info.verification_url||info.verification_uri,u=new URL(link);
      if(u.protocol!=='https:'||!/(^|\.)(feishu\.cn|larksuite\.com)$/.test(u.hostname)||!info.device_code)throw new Error('未取得有效的飞书授权地址');
      s.status={text:'请在飞书授权页面确认本人消息只读权限',health:'connecting'};
      s.authUrl=u.href;json(res,200,{url:u.href});
      s.cli.call(['auth','login','--device-code',info.device_code,'--json'],{timeout:300000}).then(()=>{if(!s.stopped)begin(s);}).catch(()=>{s.status={text:s.stopped?'账号接收已停止':'授权未完成或已过期，请重新连接飞书',health:s.stopped?'stopped':'error'};}).finally(()=>{s.busy=false;});return;
     }catch(e){s.busy=false;const d=e.diagnostic;if(d){const clean=x=>String(x||'').replace(/https?:\/\/\S+/g,'[address]').replace(/[a-zA-Z0-9_-]{20,}/g,'[redacted]').slice(0,300);console.warn(JSON.stringify({authFailure:true,keys:Object.keys(d),code:clean(d.code),message:clean(d.message),type:clean(d.type)}));}s.status={text:e.message,health:'error'};throw e;}
    }
    return json(res,404,{error:'接口不存在'});
   }
   if(req.method!=='GET')return json(res,405,{error:'请求方式不支持'});
   const name=url.pathname==='/'?'index.html':decodeURIComponent(url.pathname).slice(1),root=path.join(__dirname,'public'),file=path.resolve(root,name);
   if(!file.startsWith(root+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile())return json(res,404,{error:'页面不存在'});
   const mime={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.svg':'image/svg+xml'};
   res.writeHead(200,{'content-type':mime[path.extname(file)]||'application/octet-stream'});fs.createReadStream(file).pipe(res);
  }catch(e){if(!res.headersSent)json(res,400,{error:/请求过大|配置|授权|应用|会话/.test(e.message)?e.message:'飞书连接或请求失败，请检查授权后重试'});else res.end();}
 });
 // No unattended collection: after 2 minutes without an authenticated tab, stop and discard message memory.
 const sweep=setInterval(()=>{for(const [id,s]of sessions)if(Date.now()-s.touched>120000){s.reader.stop();s.cli.cancel();sessions.delete(id);}},30000);sweep.unref();
 server.on('close',()=>{clearInterval(sweep);for(const s of sessions.values())s.reader.stop();});return server;
}
if(require.main===module){const preview=process.env.DANMU_WEB_PREVIEW==='1';if(preview&&process.env.NODE_ENV==='production')throw new Error('禁止生产预览');createApp({preview}).listen(Number(process.env.PORT)||8080,preview?'127.0.0.1':'0.0.0.0');}
module.exports={createApp};
