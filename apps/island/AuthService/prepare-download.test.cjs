'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path');
const {createHash}=require('node:crypto');
const {prepareDownload,validateSource}=require('./prepare-download.cjs');
const packageName='feishu-island-1.2.3-build99-arm64.dmg';
const bytes=Buffer.from('synthetic installer');
const source={package:packageName,url:'https://github.com/synthetic-owner/island/releases/download/v1.2.3-build99/'+packageName,
 size:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')};
async function fixture(){
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'island-build-download-'));
 await fs.mkdir(path.join(root,'public'));await fs.writeFile(path.join(root,'download-source.json'),JSON.stringify(source));return root;
}
function response(body=bytes){return new Response(body,{headers:{'content-length':String(body.length)}});}

test('build fetches only a pinned public installer, verifies bytes, and sends no identity',async()=>{
 const root=await fixture();const calls=[];
 const result=await prepareDownload(root,{fetchImpl:async(url,options)=>{
  calls.push({url,options});
  if(calls.length===1)return new Response(null,{status:302,headers:{location:'https://release-assets.githubusercontent.com/synthetic/package?signature=synthetic'}});
  return response();
 }});
 assert.equal(result.sha256,source.sha256);assert.equal(calls.length,2);
 assert.equal(calls[0].url,source.url);
 for(const call of calls){assert.equal(call.options.redirect,'manual');assert.deepEqual(call.options.headers,{Accept:'application/octet-stream',Range:'bytes=0-'+(bytes.length-1)});}
 assert.deepEqual(await fs.readFile(path.join(root,'public',packageName)),bytes);
 await assert.rejects(fs.stat(path.join(root,'installer.partial')),{code:'ENOENT'});
});

test('a failed checksum, short body or oversized body never becomes a downloadable package',async()=>{
 for(const body of [Buffer.alloc(bytes.length,33),bytes.subarray(1),Buffer.concat([bytes,bytes])]){
  const root=await fixture();
  await assert.rejects(prepareDownload(root,{fetchImpl:async()=>new Response(body,{headers:{'content-length':String(bytes.length)}})}),/size|checksum/);
  await assert.rejects(fs.stat(path.join(root,'public',packageName)),{code:'ENOENT'});
 }
});

test('build rejects untrusted redirects and upstream errors without downloading their bodies',async()=>{
 for(const location of ['http://release-assets.githubusercontent.com/file','https://github.com.evil.example/file','https://127.0.0.1/file','https://user:pass@objects.githubusercontent.com/file','https://objects.githubusercontent.com:444/file']){
  let calls=0;const root=await fixture();
  await assert.rejects(prepareDownload(root,{fetchImpl:async()=>{calls++;return new Response(null,{status:302,headers:{location}});}}),/redirect/);
  assert.equal(calls,1);
 }
 const root=await fixture();await assert.rejects(prepareDownload(root,{fetchImpl:async()=>new Response('not a package',{status:503})}),/response/);
});

test('build rejects arbitrary URLs, mismatched release metadata, invalid hashes and excessive size',()=>{
 for(const change of [{package:'../private.dmg'},{url:source.url.replace('build99/','build98/')},{url:source.url+'?next=bad'},
  {url:source.url.replace('github.com','example.com')},{size:100000001},{sha256:'bad'}])assert.throws(()=>validateSource({...source,...change}),/metadata/);
 for(const assetUrl of ['https://evil.example/file','http://release-assets.githubusercontent.com/file',
  'https://release-assets.githubusercontent.com/file?se=2020-01-01T00%3A00%3A00Z'])assert.throws(()=>validateSource({...source,assetUrl}),/asset/);
});

test('build accepts a fresh official CDN link while still verifying the pinned installer bytes',async()=>{
 const root=await fixture();
 const assetUrl='https://release-assets.githubusercontent.com/synthetic/file?se='+encodeURIComponent(new Date(Date.now()+3600000).toISOString());
 await fs.writeFile(path.join(root,'download-source.json'),JSON.stringify({...source,assetUrl}));
 const result=await prepareDownload(root,{fetchImpl:async url=>{assert.equal(url,assetUrl);return response();}});
 assert.equal(result.sha256,source.sha256);
});


test('out-of-order bounded ranges assemble one exact installer and reject wrong Content-Range',async()=>{
 const root=await fixture();let active=0,peak=0;
 const fetchImpl=async(url,options)=>{
  const [start,end]=options.headers.Range.slice(6).split('-').map(Number);
  active++;peak=Math.max(peak,active);await new Promise(resolve=>setTimeout(resolve,start===0?15:1));active--;
  return new Response(bytes.subarray(start,end+1),{status:206,headers:{'content-length':String(end-start+1),'content-range':`bytes ${start}-${end}/${bytes.length}`}});
 };
 await prepareDownload(root,{fetchImpl,chunkBytes:4});
 assert(peak>1&&peak<=16);assert.deepEqual(await fs.readFile(path.join(root,'public',packageName)),bytes);
 const badRoot=await fixture();
 await assert.rejects(prepareDownload(badRoot,{chunkBytes:4,fetchImpl:async()=>new Response(bytes.subarray(0,4),{status:206,headers:{'content-length':'4','content-range':'bytes 0-3/999'}})}),/range/);
 await assert.rejects(fs.stat(path.join(badRoot,'public',packageName)),{code:'ENOENT'});
});

test('build download budget is separate from upload size and stays bounded',()=>{
 assert.doesNotThrow(()=>validateSource({...source,size:48212104}));
 assert.doesNotThrow(()=>validateSource({...source,size:100000000}));
 assert.throws(()=>validateSource({...source,size:100000001}),/Invalid audited/);
});
