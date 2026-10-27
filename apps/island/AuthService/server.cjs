'use strict';
const http=require('node:http'),fs=require('node:fs/promises'),path=require('node:path');
const {constants:fsConstants}=require('node:fs');
const {Vault,Broker,AuthError}=require('./core.cjs');
const {DesktopAccess}=require('./desktop.cjs');
const PUBLIC_ASSETS=new Set(['index.html','start.html','start.css','start.js','connect.html','connect.js','desktop.html','desktop.js','desktop.css','install.css','install.js','landing.css','demo-feishu-compact.png','demo-feishu-expanded.png','demo-agent-idle.png','demo-agent-working.png','demo-agent-waiting.png','demo-agent-completed.png','demo-materials.png','demo-result.png','agent-guide.html','agent-guide.js','icon.png','mascot.png','icon.svg','virxact-ui.css','virxact-story.css','vx.js','SHA256SUMS']);
const PACKAGE_NAME=/^feishu-island-\d+\.\d+\.\d+-build\d+-arm64(?:-pilot)?\.(?:zip|dmg)$/;
const STATIC_TYPES={'.html':'text/html; charset=utf-8','.js':'application/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.png':'image/png','.svg':'image/svg+xml','.zip':'application/zip','.dmg':'application/x-apple-diskimage'};
function downloadRange(value,size){
 const match=/^bytes=(\d*)-(\d*)$/.exec(value.trim());
 if(!match||(!match[1]&&!match[2])||size===0)return null;
 const first=match[1]?Number(match[1]):null,last=match[2]?Number(match[2]):null;
 if((first!==null&&!Number.isSafeInteger(first))||(last!==null&&!Number.isSafeInteger(last)))return null;
 if(first===null)return last>0?{start:Math.max(0,size-last),end:size-1}:null;
 if(first>=size||(last!==null&&last<first))return null;
 return {start:first,end:last===null?size-1:Math.min(last,size-1)};
}
function createServer({broker,origin='https://feishu-island.virxact.net',root=path.join(__dirname,'public')}){
 const desktop=new DesktopAccess(broker);
 return http.createServer(async(req,res)=>{
  res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('Referrer-Policy','no-referrer');res.setHeader('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'self' https://virxact.net; base-uri 'none'; form-action 'none'");
  const send=(status,v)=>{res.writeHead(status,{'Content-Type':'application/json; charset=utf-8'});res.end(JSON.stringify(v));};
  try{
   const url=new URL(req.url,origin);
   const user=req.headers['x-auth-user-id'];
   if(typeof user!=='string'||!user||user.length>128||req.headers['x-virxact-device-id'])throw new AuthError(401,'请使用本人中台账号登录');
   if(url.pathname.startsWith('/api/')){
    if(req.method==='GET'&&url.pathname==='/api/auth/status')return send(200,await broker.status(user));
    if(req.method!=='POST')throw new AuthError(405,'不支持的操作');
    if(req.headers.origin!==origin||req.headers['x-island-auth']!=='1'||!req.headers['content-type']?.startsWith('application/json'))throw new AuthError(403,'请从工作岛连接页面操作');
    let input='';for await(const b of req){input+=b;if(Buffer.byteLength(input)>4096)throw new AuthError(413,'请求过大');}
    let data;try{data=JSON.parse(input);}catch{throw new AuthError(400,'请求格式不正确');}
    if(!data||typeof data!=='object'||Array.isArray(data))throw new AuthError(400,'请求格式不正确');
    if(url.pathname==='/api/auth/start')return send(200,await broker.start(user,data.purpose));
    if(url.pathname==='/api/auth/poll')return send(200,await broker.poll(user,data.flow));
    if(url.pathname==='/api/auth/cancel')return send(200,broker.cancel(user,data.flow));
    if(url.pathname==='/api/auth/access')return send(200,await desktop.access(user,data.purpose));
    throw new AuthError(404,'接口不存在');
   }
   if(req.method!=='GET'&&req.method!=='HEAD')throw new AuthError(405,'不支持的操作');
   // Match the raw path as well: URL normalization must not turn a traversal
   // request into a permitted asset. Only named release assets are downloadable.
   if(req.url.split('?')[0]!==url.pathname)throw new AuthError(404,'页面不存在');
   let name=url.pathname==='/'?'index.html':url.pathname.slice(1);
   const download=PACKAGE_NAME.test(name);
   if(!PUBLIC_ASSETS.has(name)&&!download)throw new AuthError(404,'页面不存在');
   let file,stat,previousRelease=false;
   try{file=await fs.open(path.join(root,name),fsConstants.O_RDONLY|fsConstants.O_NOFOLLOW);stat=await file.stat();}
   catch(error){
    if(file)await file.close();
    // A long-lived Feishu tab may still request an earlier published filename.
    // Only build-generated, same-origin aliases may resolve a missing package.
    let target;
    if(download&&error.code==='ENOENT'){
     try{target=JSON.parse(await fs.readFile(path.join(root,'download-aliases.json'),'utf8'))[name];}catch{}
    }
    if(typeof target!=='string'||target===name||!PACKAGE_NAME.test(target))throw new AuthError(404,'页面不存在');
    try{file=await fs.open(path.join(root,target),fsConstants.O_RDONLY|fsConstants.O_NOFOLLOW);stat=await file.stat();}
    catch{if(file)await file.close();throw new AuthError(404,'页面不存在');}
    name=target;previousRelease=true;
   }
   if(!stat.isFile()||!Number.isSafeInteger(stat.size)){await file.close();throw new AuthError(404,'页面不存在');}
   const response={'Content-Type':STATIC_TYPES[path.extname(name)]||'text/plain; charset=utf-8','Content-Length':stat.size};
   let status=200,range;
   if(download){
    const modified=stat.mtime.toUTCString();
    response['Content-Disposition']='attachment; filename="'+name+'"; filename*=UTF-8\'\''+encodeURIComponent(name);
    response['Accept-Ranges']='bytes';response['Last-Modified']=modified;
    // An obsolete URL always returns the complete current package (200), even
    // for Range requests: never append new bytes to an older partial download.
    // HEAD describes the full object. A mismatching If-Range means send a new
    // full download, preventing a client from combining different release bytes.
    if(!previousRelease&&req.method==='GET'&&req.headers.range&&(!req.headers['if-range']||req.headers['if-range']===modified)){
     range=downloadRange(req.headers.range,stat.size);
     if(!range){await file.close();res.writeHead(416,{'Content-Range':'bytes */'+stat.size,'Content-Length':0});return res.end();}
     status=206;response['Content-Range']='bytes '+range.start+'-'+range.end+'/'+stat.size;response['Content-Length']=range.end-range.start+1;
    }
   }
   if(req.method==='HEAD'||stat.size===0){await file.close();res.writeHead(status,response);return res.end();}
   const stream=file.createReadStream(range||{});
   stream.once('error',()=>res.destroy());res.once('close',()=>stream.destroy());
   res.writeHead(status,response);stream.pipe(res);
  }catch(e){if(!res.headersSent)send(e instanceof AuthError?e.status:503,{error:e instanceof AuthError?e.message:'连接服务暂不可用，请稍后重试'});else res.destroy();}
 });
}
if(require.main===module){const broker=new Broker({vault:new Vault(process.env.AUTH_DATA_DIR||'/data/auth',process.env.AUTH_VAULT_KEY)});createServer({broker}).listen(Number(process.env.PORT)||8080,'0.0.0.0');}
module.exports={createServer};
