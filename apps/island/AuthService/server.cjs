'use strict';
const http=require('node:http'),fs=require('node:fs/promises'),path=require('node:path');
const {Vault,Broker,AuthError}=require('./core.cjs');
const {DesktopAccess}=require('./desktop.cjs');
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
   const name=url.pathname==='/'?'index.html':url.pathname.slice(1);
   if(!/^[\w.-]+$/.test(name))throw new AuthError(404,'页面不存在');
   const types={'.html':'text/html; charset=utf-8','.js':'application/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.png':'image/png','.svg':'image/svg+xml','.zip':'application/zip'};
   let stat;try{stat=await fs.stat(path.join(root,name));}catch{throw new AuthError(404,'页面不存在');}
   if(!stat.isFile())throw new AuthError(404,'页面不存在');
   res.writeHead(200,{'Content-Type':types[path.extname(name)]||'text/plain; charset=utf-8','Content-Length':stat.size});
   if(req.method==='HEAD')return res.end();
   require('node:fs').createReadStream(path.join(root,name)).pipe(res);
  }catch(e){if(!res.headersSent)send(e instanceof AuthError?e.status:503,{error:e instanceof AuthError?e.message:'连接服务暂不可用，请稍后重试'});else res.destroy();}
 });
}
if(require.main===module){const broker=new Broker({vault:new Vault(process.env.AUTH_DATA_DIR||'/data/auth',process.env.AUTH_VAULT_KEY)});createServer({broker}).listen(Number(process.env.PORT)||8080,'0.0.0.0');}
module.exports={createServer};
