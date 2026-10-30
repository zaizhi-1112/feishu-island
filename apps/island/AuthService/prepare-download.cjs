'use strict';
// Deployment build only. No credentials, runtime proxy, or arbitrary download URL.
const fs=require('node:fs/promises'),path=require('node:path');
const {createHash}=require('node:crypto');
const {constants}=require('node:fs');

// This file is downloaded during build, not included in the 50 MB upload archive.
// Keep a separate 100 MB cap; transfer concurrency and 1 MiB range bounds remain unchanged.
function validateSource(source){
 const version=/^feishu-island-(\d+\.\d+\.\d+)-build(\d+)-arm64\.dmg$/.exec(source.package||'');
 const asset=/^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/releases\/download\/([\w.-]+)\/([\w.-]+)$/.exec(source.url||'');
 if(!version||!asset||asset[1]!==`v${version[1]}-build${version[2]}`||asset[2]!==source.package||
    !/^[a-f0-9]{64}$/.test(source.sha256||'')||!Number.isSafeInteger(source.size)||source.size<1||source.size>100000000)
  throw new Error('Invalid audited download metadata');
 if(source.assetUrl){
  let url;try{url=new URL(source.assetUrl);}catch{throw new Error('Invalid asset URL');}
  if(url.protocol!=='https:'||url.hostname!=='release-assets.githubusercontent.com'||url.port||url.username||url.password||
     !(Date.parse(url.searchParams.get('se'))>Date.now()+120000))throw new Error('Invalid asset URL or expired download');
 }
}

async function prepareDownload(root,{fetchImpl=fetch,onProgress=()=>{},chunkBytes=1024*1024}={}){
 const source=JSON.parse(await fs.readFile(path.join(root,'download-source.json'),'utf8'));
 validateSource(source);
 if(!Number.isSafeInteger(chunkBytes)||chunkBytes<1||chunkBytes>1024*1024)throw new Error('Invalid asset chunk size');
 // Bounded ranges avoid a single slow overseas connection exhausting the build window.
 const controller=new AbortController();
 const signal=AbortSignal.any([AbortSignal.timeout(600000),controller.signal]);
 const partial=path.join(root,'installer.partial');
 const file=await fs.open(partial,constants.O_RDWR|constants.O_CREAT|constants.O_TRUNC|constants.O_NOFOLLOW,0o600);
 const count=Math.ceil(source.size/chunkBytes);
 let next=0,total=0,reported=0,accepted=false;
 async function part(index){
  const start=index*chunkBytes,end=Math.min(source.size-1,start+chunkBytes-1),length=end-start+1;
  let url=source.assetUrl||source.url,response;
  for(let hop=0;hop<3;hop++){
   response=await fetchImpl(url,{redirect:'manual',signal,headers:{Accept:'application/octet-stream',Range:`bytes=${start}-${end}`}});
   if(![301,302,303,307,308].includes(response.status))break;
   const location=response.headers.get('location');await response.body?.cancel();
   let target;try{target=new URL(location);}catch{throw new Error('Invalid asset redirect');}
   if(target.protocol!=='https:'||target.username||target.password||target.port||
      !['release-assets.githubusercontent.com','objects.githubusercontent.com'].includes(target.hostname))throw new Error('Unexpected asset redirect host');
   url=target.href;
  }
  const whole=response.status===200&&start===0&&length===source.size;
  const range=response.status===206&&response.headers.get('content-range')===`bytes ${start}-${end}/${source.size}`;
  if((!whole&&!range)||!response.body||Number(response.headers.get('content-length'))!==length){
   await response.body?.cancel();throw new Error('Download response range or size differs from the audited package');
  }
  if(!accepted){accepted=true;onProgress(`Installer source accepted: ${source.size} bytes in ${count} verified ranges`);}
  let received=0;
  for await(const bytes of response.body){
   if(received+bytes.length>length)throw new Error('Installer exceeds audited range size');
   let offset=0;
   while(offset<bytes.length){const result=await file.write(bytes,offset,bytes.length-offset,start+received+offset);offset+=result.bytesWritten;}
   received+=bytes.length;total+=bytes.length;
   if(total-reported>=5*1024*1024){reported=total;onProgress(`Installer received: ${total}/${source.size} bytes`);}
  }
  if(received!==length)throw new Error('Installer range size mismatch');
 }
 try{
  await file.truncate(source.size);
  const workers=Array.from({length:Math.min(16,count)},async()=>{
   try{while(next<count&&!signal.aborted){const index=next++;await part(index);}}
   catch(error){controller.abort();throw error;}
  });
  const results=await Promise.allSettled(workers);
  const failure=results.find(result=>result.status==='rejected');if(failure)throw failure.reason;
  if(total!==source.size)throw new Error('Installer total size mismatch');
  const hash=createHash('sha256');
  for await(const bytes of file.createReadStream({start:0,autoClose:false}))hash.update(bytes);
  if(hash.digest('hex')!==source.sha256)throw new Error('Installer checksum mismatch');
 }finally{await file.close();}
 await fs.rename(partial,path.join(root,'public',source.package));
 return {package:source.package,size:source.size,sha256:source.sha256};
}

if(require.main===module)prepareDownload(__dirname,{onProgress:message=>console.log(message)}).then(result=>{
 console.log(`Audited installer ready: ${result.package}; ${result.size} bytes; SHA-256 ${result.sha256}`);
}).catch(error=>{
 const reason=/^(Invalid audited|Invalid asset|Unexpected asset|Download response|Installer exceeds|Installer checksum|Installer range|Installer total)/.test(error.message)?error.message:
  (/^[A-Z_]+$/.test(error.cause?.code||error.code||'')?(error.cause?.code||error.code):'Network or file operation failed');
 console.error(`Audited installer preparation failed: ${reason}. Retain the previous release.`);process.exitCode=1;
});
module.exports={prepareDownload,validateSource};
