'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os'),http=require('node:http');
const {createServer}=require('./server.cjs');
const name='feishu-island-0.7.0-build29-arm64.dmg';
const bytes=Buffer.from('abcdefghijklmnopqrstuvwxyz');
const owner={'X-Auth-User-Id':'synthetic-owner'};
async function fixture(t,{includePackage=true}={}){
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'island-download-test-'));
 if(includePackage)await fs.writeFile(path.join(root,name),bytes);
 await fs.writeFile(path.join(root,'index.html'),'<p>synthetic index</p>');
 await fs.writeFile(path.join(root,'SHA256SUMS'),'synthetic-checksum');
 const server=createServer({broker:{},root});
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 t.after(()=>server.close());
 return {root,base:'http://127.0.0.1:'+server.address().port};
}
function raw(base,pathname,headers=owner){
 return new Promise((resolve,reject)=>{
  const r=http.request(new URL(base),{path:pathname,headers},response=>{
   const chunks=[];response.on('data',chunk=>chunks.push(chunk));response.on('end',()=>resolve({status:response.statusCode,headers:response.headers,body:Buffer.concat(chunks)}));
  });r.on('error',reject);r.end();
 });
}

test('DMG downloads have the correct MIME, attachment name and exact streamed bytes',async t=>{
 const {base}=await fixture(t);const r=await fetch(base+'/'+name,{headers:owner});
 assert.equal(r.status,200);assert.equal(r.headers.get('content-type'),'application/x-apple-diskimage');
 assert.equal(r.headers.get('content-disposition'),'attachment; filename="'+name+'"; filename*=UTF-8\'\''+name);
 assert.equal(r.headers.get('content-length'),String(bytes.length));assert.equal(r.headers.get('accept-ranges'),'bytes');
 assert.equal(r.headers.get('cache-control'),'no-store');assert.equal(r.headers.get('x-content-type-options'),'nosniff');
 assert.deepEqual(Buffer.from(await r.arrayBuffer()),bytes);
});

test('HEAD returns full DMG metadata without a body, including when a Range is supplied',async t=>{
 const {base}=await fixture(t);
 for(const extra of [{},{Range:'bytes=1-3'}]){
  const r=await fetch(base+'/'+name,{method:'HEAD',headers:{...owner,...extra}});
  assert.equal(r.status,200);assert.equal(r.headers.get('content-length'),String(bytes.length));
  assert.equal(r.headers.get('content-type'),'application/x-apple-diskimage');assert.equal(r.headers.get('content-range'),null);
  assert.equal((await r.arrayBuffer()).byteLength,0);
 }
});

test('download metadata, full bytes and partial bytes all require company identity',async t=>{
 const {base}=await fixture(t);
 for(const method of ['GET','HEAD'])for(const headers of [{},{Range:'bytes=0-3'},{...owner,'X-Virxact-Device-Id':'synthetic-device'}]){
  const r=await fetch(base+'/'+name,{method,headers});
  assert.equal(r.status,401);assert.equal(r.headers.get('content-disposition'),null);assert.equal(r.headers.get('content-range'),null);
  assert(!Buffer.from(await r.arrayBuffer()).equals(bytes));
 }
});

test('single byte ranges support bounded, open-ended and suffix download resumption',async t=>{
 const {base}=await fixture(t);
 for(const [range,start,end] of [['bytes=0-3',0,3],['bytes=20-',20,25],['bytes=-4',22,25],['bytes=24-999',24,25],['bytes=-999',0,25]]){
  const r=await fetch(base+'/'+name,{headers:{...owner,Range:range}});
  assert.equal(r.status,206);assert.equal(r.headers.get('content-range'),'bytes '+start+'-'+end+'/'+bytes.length);
  assert.equal(r.headers.get('content-length'),String(end-start+1));assert.deepEqual(Buffer.from(await r.arrayBuffer()),bytes.subarray(start,end+1));
 }
 for(const range of ['bytes=99-100','bytes=3-1','bytes=-0','bytes=-','bytes=0-1,3-4','bytes=9007199254740992-','items=0-1']){
  const r=await fetch(base+'/'+name,{headers:{...owner,Range:range}});
  assert.equal(r.status,416);assert.equal(r.headers.get('content-range'),'bytes */'+bytes.length);assert.equal((await r.arrayBuffer()).byteLength,0);
 }
});

test('If-Range mismatch restarts with the full object instead of mixing release bytes',async t=>{
 const {base}=await fixture(t);const initial=await fetch(base+'/'+name,{method:'HEAD',headers:owner});
 const modified=initial.headers.get('last-modified');assert(modified);
 const partial=await fetch(base+'/'+name,{headers:{...owner,Range:'bytes=0-3','If-Range':modified}});
 assert.equal(partial.status,206);assert.equal(await partial.text(),'abcd');
 for(const stale of ['Wed, 01 Jan 2020 00:00:00 GMT','"unknown-etag"']){
  const r=await fetch(base+'/'+name,{headers:{...owner,Range:'bytes=0-3','If-Range':stale}});
  assert.equal(r.status,200);assert.equal(r.headers.get('content-range'),null);assert.deepEqual(Buffer.from(await r.arrayBuffer()),bytes);
 }
});

test('only public release assets are served; traversal and symbolic links fail closed',async t=>{
 const {root,base}=await fixture(t);
 await fs.writeFile(path.join(root,'.env'),'synthetic-private');await fs.writeFile(path.join(root,'server.cjs'),'synthetic-private');
 await fs.writeFile(path.join(root,'other.dmg'),'synthetic-private');
 for(const pathname of ['/../index.html','/x/../index.html','/%2e%2e/index.html','/..\\index.html','//index.html','/%2findex.html','/index.html/..','/%252e%252e/index.html','/.env','/server.cjs','/other.dmg']){
  const r=await raw(base,pathname);assert.equal(r.status,404,pathname);assert(!r.body.toString().includes('synthetic-private'));
 }
 const symlink='feishu-island-0.7.0-build999-arm64.dmg';await fs.symlink(path.join(root,'.env'),path.join(root,symlink));
 assert.equal((await fetch(base+'/'+symlink,{headers:owner})).status,404);
 assert.equal((await fetch(base+'/',{headers:owner})).status,200);
 assert.equal((await fetch(base+'/SHA256SUMS',{headers:owner})).status,200);
});

test('existing web assets and ZIP downloads remain available from their explicit whitelist',async t=>{
 const {root,base}=await fixture(t);
 const assets=['start.html','start.css','connect.html','connect.js','desktop.html','desktop.js','desktop.css','install.css','install.js','agent-guide.html','agent-guide.js','icon.png','icon.svg','virxact-ui.css','vx.js'];
 for(const asset of assets){await fs.writeFile(path.join(root,asset),'synthetic asset');const response=await fetch(base+'/'+asset,{headers:owner});assert.equal(response.status,200,asset);if(asset==='start.css'){assert.equal(response.headers.get('content-type'),'text/css; charset=utf-8');assert(response.headers.get('content-security-policy').includes("style-src 'self'"));assert(!response.headers.get('content-security-policy').includes("'unsafe-inline'"));}}
 const zip='feishu-island-0.7.0-build29-arm64-pilot.zip';await fs.writeFile(path.join(root,zip),bytes);
 const r=await fetch(base+'/'+zip,{headers:owner});assert.equal(r.status,200);assert.equal(r.headers.get('content-type'),'application/zip');assert(r.headers.get('content-disposition').includes(zip));assert.deepEqual(Buffer.from(await r.arrayBuffer()),bytes);
});

test('large release files support HEAD and a tail range without loading the whole file',async t=>{
 const {root,base}=await fixture(t);const size=64*1024*1024+7;
 const file=await fs.open(path.join(root,name),'r+');await file.truncate(size);await file.write(Buffer.from('tail'),0,4,size-4);await file.close();
 const head=await fetch(base+'/'+name,{method:'HEAD',headers:owner});assert.equal(head.headers.get('content-length'),String(size));assert.equal((await head.arrayBuffer()).byteLength,0);
 const tail=await fetch(base+'/'+name,{headers:{...owner,Range:'bytes=-4'}});assert.equal(tail.status,206);assert.equal(tail.headers.get('content-range'),'bytes '+(size-4)+'-'+(size-1)+'/'+size);assert.equal(await tail.text(),'tail');
});

test('every asset referenced by the real landing and guide pages is served with its browser MIME type',async t=>{
 const {root,base}=await fixture(t);
 const source=process.env.ISLAND_DOWNLOAD_SITE||path.join(__dirname,'public');
 const pages=process.env.ISLAND_DOWNLOAD_SITE?['index.html','start.html','agent-guide.html']:['connect.html'];
 const content=await Promise.all(pages.map(page=>fs.readFile(path.join(source,page),'utf8')));
 if(process.env.ISLAND_DOWNLOAD_SITE){assert(!/<style>|\s(?:style|on\w+)\s*=/i.test(content[1]),'hosted guide must honor the self-only CSP');}
 const html=content.join('\n');
 const assets=[...new Set([...html.matchAll(/<(?:link|script|img)\b[^>]*(?:href|src)="([^"]+)"/g)].map(match=>match[1]).filter(asset=>!asset.startsWith('data:image/')))];
 assert(assets.length>0);assert(assets.includes('virxact-ui.css'));
 const types={'.jpg':'image/jpeg','.css':'text/css; charset=utf-8','.js':'application/javascript; charset=utf-8','.svg':'image/svg+xml','.png':'image/png'};
 for(const asset of assets){
  assert.equal(path.basename(asset),asset,'homepage resources must be named local assets');
  const bytes=await fs.readFile(path.join(source,asset));await fs.writeFile(path.join(root,asset),bytes);
  const response=await fetch(base+'/'+asset,{headers:owner});
  assert.equal(response.status,200,asset);
  assert.equal(response.headers.get('content-type'),types[path.extname(asset)],asset);
  assert.deepEqual(Buffer.from(await response.arrayBuffer()),bytes,asset);
 }
});


test('cached Feishu release URLs download the current package with its correct filename',async t=>{
 const {root,base}=await fixture(t);const old='feishu-island-0.7.0-build28-arm64.dmg';
 await fs.writeFile(path.join(root,'download-aliases.json'),JSON.stringify({[old]:name}));
 for(const headers of [owner,{...owner,Range:'bytes=10-'},{...owner,Range:'bytes=10-','If-Range':'Wed, 01 Jan 2020 00:00:00 GMT'}]){
  const r=await fetch(base+'/'+old,{headers});assert.equal(r.status,200);assert.equal(r.headers.get('content-range'),null);
  assert(r.headers.get('content-disposition').includes(name));assert.deepEqual(Buffer.from(await r.arrayBuffer()),bytes);
 }
 const head=await fetch(base+'/'+old,{method:'HEAD',headers:owner});assert.equal(head.status,200);assert.equal(head.headers.get('content-length'),String(bytes.length));
 assert.equal((await fetch(base+'/'+old)).status,401);
 assert.equal((await fetch(base+'/download-aliases.json',{headers:owner})).status,404);
});

test('release aliases cannot expose private files, symlinks or external URLs',async t=>{
 const {root,base}=await fixture(t);const old='feishu-island-0.7.0-build28-arm64.dmg';
 await fs.writeFile(path.join(root,'.env'),'private');
 const symlink='feishu-island-0.7.0-build99-arm64.dmg';await fs.symlink(path.join(root,'.env'),path.join(root,symlink));
 for(const target of ['../.env','https://example.com/file.dmg',symlink,old]){
  await fs.writeFile(path.join(root,'download-aliases.json'),JSON.stringify({[old]:target}));
  const r=await fetch(base+'/'+old,{headers:owner});assert.equal(r.status,404);assert(!(await r.text()).includes('private'));
 }
});

test('product portraits stay public to company users while removed previews are unavailable',async t=>{
 const root=process.env.ISLAND_DOWNLOAD_SITE||path.join(__dirname,'../Distribution/site');
 const server=createServer({broker:{},root});await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>server.close());
 const base='http://127.0.0.1:'+server.address().port;
 for(const id of ['codex','workbuddy','deepseek']){
  const name='native-agent-'+id+'.png';
  const denied=await fetch(base+'/'+name);assert.equal(denied.status,401);
  const response=await fetch(base+'/'+name,{headers:owner});assert.equal(response.status,200);assert.equal(response.headers.get('content-type'),'image/png');
  assert.deepEqual(Buffer.from(await response.arrayBuffer()),await fs.readFile(path.join(__dirname,'../Distribution/site',name)));
 }
 for(const removed of ['native-messages.jpg','native-guide-1.jpg','native-private.jpg','native-preview-manifest.json','../../workspace.json']){
  assert.equal((await raw(base,'/'+removed)).status,404);
 }
});

test('web-only downloads resolve directly to the exact installer asset, never a GitHub page',async t=>{
 const {root,base}=await fixture(t,{includePackage:false});
 const old='feishu-island-0.7.0-build28-arm64.dmg';
 const url='https://github.com/synthetic-owner/island-downloads/releases/download/v0.7.0-build29/'+name;
 await fs.writeFile(path.join(root,'download-aliases.json'),JSON.stringify({[old]:name}));
 await fs.writeFile(path.join(root,'download-fallback.json'),JSON.stringify({package:name,url}));
 for(const file of [name,old])for(const method of ['GET','HEAD']){
  const response=await fetch(base+'/'+file,{method,headers:owner,redirect:'manual'});
  assert.equal(response.status,303);assert.equal(response.headers.get('location'),url);
  assert.equal((await response.arrayBuffer()).byteLength,0);
 }
 assert.equal((await fetch(base+'/'+name,{redirect:'manual'})).status,401);
 assert.equal((await fetch(base+'/download-fallback.json',{headers:owner})).status,404);
 assert.equal((await fetch(base+'/feishu-island-0.7.0-build999-arm64.dmg',{headers:owner,redirect:'manual'})).status,404);
 const partial=await fetch(base+'/'+old,{headers:{...owner,Range:'bytes=10-'},redirect:'manual'});
 assert.equal(partial.status,409);assert.equal(partial.headers.get('location'),null);
});

test('download fallbacks reject arbitrary hosts, credentials, query targets and mismatched packages',async t=>{
 const {root,base}=await fixture(t,{includePackage:false});
 const asset='https://github.com/owner/repo/releases/download/v0.7.0-build29/'+name;
 for(const url of ['https://example.com/package','https://github.com@evil.example/releases/tag/v1','http://github.com/owner/repo/releases/tag/v1','https://github.com/owner/repo/releases/tag/v0.7.0-build29',asset+'?next=bad',asset.replace('build29/','build28/'),asset.replace(name,'another.dmg')]){
  await fs.writeFile(path.join(root,'download-fallback.json'),JSON.stringify({package:name,url}));
  assert.equal((await fetch(base+'/'+name,{headers:owner,redirect:'manual'})).status,404);
 }
 await fs.writeFile(path.join(root,'download-fallback.json'),JSON.stringify({package:'feishu-island-0.7.0-build999-arm64.dmg',url:asset}));
 assert.equal((await fetch(base+'/'+name,{headers:owner,redirect:'manual'})).status,404);
});

test('brand motion resources use the same company gate and exact bundled bytes',async t=>{
 const root=process.env.ISLAND_DOWNLOAD_SITE||path.join(__dirname,'../Distribution/site');
 const server=createServer({broker:{},root});await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>server.close());
 const base='http://127.0.0.1:'+server.address().port;
 for(const [file,type] of [['brand-particles.js','application/javascript; charset=utf-8'],['virxact-mark.svg','image/svg+xml']]){
  assert.equal((await fetch(base+'/'+file)).status,401);
  const response=await fetch(base+'/'+file,{headers:owner});assert.equal(response.status,200);
  assert.equal(response.headers.get('content-type'),type);
  assert.deepEqual(Buffer.from(await response.arrayBuffer()),await fs.readFile(path.join(__dirname,'../Distribution/site',file)));
 }
});
