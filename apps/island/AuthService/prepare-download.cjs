'use strict';
// Deployment build only. No credentials, runtime proxy, or arbitrary download URL.
const fs=require('node:fs/promises'),path=require('node:path');
const {createHash}=require('node:crypto');
const {constants}=require('node:fs');

function validateSource(source){
 const version=/^feishu-island-(\d+\.\d+\.\d+)-build(\d+)-arm64\.dmg$/.exec(source.package||'');
 const asset=/^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/releases\/download\/([\w.-]+)\/([\w.-]+)$/.exec(source.url||'');
 if(!version||!asset||asset[1]!==`v${version[1]}-build${version[2]}`||asset[2]!==source.package||
    !/^[a-f0-9]{64}$/.test(source.sha256||'')||!Number.isSafeInteger(source.size)||source.size<1||source.size>48000000)
  throw new Error('Invalid audited download metadata');
 if(source.assetUrl){
  let url;try{url=new URL(source.assetUrl);}catch{throw new Error('Invalid asset URL');}
  if(url.protocol!=='https:'||url.hostname!=='release-assets.githubusercontent.com'||url.port||url.username||url.password||
     !(Date.parse(url.searchParams.get('se'))>Date.now()+120000))throw new Error('Invalid asset URL or expired download');
 }
}

async function prepareDownload(root,{fetchImpl=fetch,onProgress=()=>{}}={}){
 const source=JSON.parse(await fs.readFile(path.join(root,'download-source.json'),'utf8'));
 validateSource(source);
 let url=source.assetUrl||source.url,response;
 // Leave five minutes of the platform's 15-minute build window for image export.
 const signal=AbortSignal.timeout(600000);
 for(let hop=0;hop<3;hop++){
  response=await fetchImpl(url,{redirect:'manual',signal,headers:{Accept:'application/octet-stream'}});
  if(![301,302,303,307,308].includes(response.status))break;
  const location=response.headers.get('location');
  await response.body?.cancel();
  let next;try{next=new URL(location);}catch{throw new Error('Invalid asset redirect');}
  if(next.protocol!=='https:'||next.username||next.password||next.port||
     !['release-assets.githubusercontent.com','objects.githubusercontent.com'].includes(next.hostname))
   throw new Error('Unexpected asset redirect host');
  url=next.href;
 }
 if(response.status!==200||!response.body||Number(response.headers.get('content-length'))!==source.size){
  await response.body?.cancel();throw new Error('Download response does not match the audited package');
 }
 onProgress(`Installer source accepted: ${source.size} bytes`);
 const partial=path.join(root,'installer.partial');
 const file=await fs.open(partial,constants.O_WRONLY|constants.O_CREAT|constants.O_TRUNC|constants.O_NOFOLLOW,0o600);
 const hash=createHash('sha256');let size=0,reported=0;
 try{
  for await(const bytes of response.body){
   size+=bytes.length;if(size>source.size)throw new Error('Installer exceeds audited size');
   hash.update(bytes);let offset=0;
   while(offset<bytes.length){const result=await file.write(bytes,offset,bytes.length-offset);offset+=result.bytesWritten;}
   if(size-reported>=5*1024*1024){reported=size;onProgress(`Installer received: ${size}/${source.size} bytes`);}
  }
  if(size!==source.size||hash.digest('hex')!==source.sha256)throw new Error('Installer checksum or size mismatch');
 }finally{await file.close();}
 await fs.rename(partial,path.join(root,'public',source.package));
 return {package:source.package,size,sha256:source.sha256};
}

if(require.main===module)prepareDownload(__dirname,{onProgress:message=>console.log(message)}).then(result=>{
 console.log(`Audited installer ready: ${result.package}; ${result.size} bytes; SHA-256 ${result.sha256}`);
}).catch(error=>{
 const reason=/^(Invalid audited|Invalid asset|Unexpected asset|Download response|Installer exceeds|Installer checksum)/.test(error.message)?error.message:
  (/^[A-Z_]+$/.test(error.cause?.code||error.code||'')?(error.cause?.code||error.code):'Network or file operation failed');
 console.error(`Audited installer preparation failed: ${reason}. Retain the previous release.`);process.exitCode=1;
});
module.exports={prepareDownload,validateSource};
