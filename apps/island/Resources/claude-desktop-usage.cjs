'use strict';
// Read only Claude's cached usage response. No cookies, credentials, chat bodies or network.
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const crypto = require('node:crypto');
const END = Buffer.from('d8410d97456ffaf4', 'hex');
function crc32(b) { let c = 0xffffffff; for (const v of b) { c ^= v; for(let i=0;i<8;i++) c=(c>>>1)^((c&1)?0xedb88320:0); } return (c^0xffffffff)>>>0; }
function keyOf(b, org) {
  if(b.length<24 || b.readBigUInt64LE(0)!==0xfcfb6d1ba7725c30n || b.readUInt32LE(8)!==5) return null;
  const size=b.readUInt32LE(12); if(size>2048 || size<1 || b.length<24+size) return null;
  const key=b.subarray(24,24+size).toString('utf8');
  return key===`1/0/https://claude.ai/api/organizations/${org}/usage` || key===`1/0/https://claude.ai/api/organizations/${org}/usage?skip_spend=1` ? 24+size : null;
}
function parseCache(b, org, now) {
  const start=keyOf(b,org); if(start===null) return null;
  const end=b.indexOf(END,start); if(end<start || end+24>b.length || b.readUInt32LE(end+8)!==1) return null;
  const raw=b.subarray(start,end); if(crc32(raw)!==b.readUInt32LE(end+12)) return null;
  const headers=b.subarray(end+24).toString('latin1');
  const date=headers.match(/(?:^|\0)date:\s*([^\0\r\n]+)/i);
  const stamp=date?Date.parse(date[1])/1000:NaN;
  if(!Number.isFinite(stamp)||stamp>now+60||now-stamp>86400) return null;
  let data;
  try {
    const options={maxOutputLength:262144};
    if(/content-encoding:\s*zstd(?:\0|\r|\n)/i.test(headers)) data=zlib.zstdDecompressSync(raw,options);
    else if(/content-encoding:\s*gzip(?:\0|\r|\n)/i.test(headers)) data=zlib.gunzipSync(raw,options);
    else if(/content-encoding:\s*br(?:\0|\r|\n)/i.test(headers)) data=zlib.brotliDecompressSync(raw,options);
    else if(/content-encoding:/i.test(headers)) return null;
    else data=raw;
    if(data.length>262144) return null;
    const value=JSON.parse(data.toString('utf8'));
    const quotas=[['five_hour','fh','5小时额度'],['seven_day','sd','周额度']].flatMap(([key,id,label])=>{
      const row=value[key]; if(!row || typeof row.utilization!=='number' || !Number.isFinite(row.utilization) || row.utilization<0 || row.utilization>100) return [];
      const reset=typeof row.resets_at==='string'?Date.parse(row.resets_at)/1000:NaN;
      if(!Number.isFinite(reset)||reset<=now||reset>stamp+8*86400) return [];
      return [{id,label,remainingPercent:100-row.utilization,resetsAt:reset,updatedAt:stamp}];
    });
    return quotas.length?quotas:null;
  }catch{return null;}
}
function read(root,now=Date.now()/1000) {
  const historyPath=path.join(root,'plan-usage-history.json');
  if(fs.statSync(historyPath).size>4194304) return [];
  const samples=JSON.parse(fs.readFileSync(historyPath,'utf8')).samples;
  if(!Array.isArray(samples))return [];
  const latest=samples.filter(x=>typeof x.t==='number'&&x.t/1000<=now+60).sort((a,b)=>b.t-a.t)[0];
  if(!latest || typeof latest.org!=='string' || !/^[a-f0-9-]{36}$/i.test(latest.org)) return [];
  const dir=path.join(root,'Cache','Cache_Data'), found=new Map();
  // Chromium Simple Cache keys use the first SHA-1 uint64 in little-endian form.
  // Address only these two known usage entries; never enumerate or read other responses.
  const names=['','?skip_spend=1'].map(suffix=>crypto.createHash('sha1').update(`1/0/https://claude.ai/api/organizations/${latest.org}/usage${suffix}`).digest().subarray(0,8).reverse().toString('hex')+'_0');
  for(const name of names) {
    let fd;
    try {
      fd=fs.openSync(path.join(dir,name),fs.constants.O_RDONLY|fs.constants.O_NOFOLLOW);
      const stat=fs.fstatSync(fd); if(!stat.isFile()||stat.size>1048576||stat.size<48)continue;
      const header=Buffer.alloc(Math.min(2072,stat.size));fs.readSync(fd,header,0,header.length,0);
      if(keyOf(header,latest.org)===null)continue;
      const b=Buffer.alloc(stat.size); if(fs.readSync(fd,b,0,b.length,0)!==b.length)continue;
      for(const q of parseCache(b,latest.org,now)||[]) if(!found.has(q.id)||found.get(q.id).updatedAt<q.updatedAt)found.set(q.id,q);
    }catch{}finally{if(fd!==undefined)fs.closeSync(fd);}
  }
  return [...found.values()];
}
module.exports={parseCache,read,crc32,keyOf};
if(require.main===module) { try { console.log(JSON.stringify({quotas:read(path.join(require('node:os').homedir(),'Library/Application Support/Claude'))})); }catch{console.log('{"quotas":[]}');} }
