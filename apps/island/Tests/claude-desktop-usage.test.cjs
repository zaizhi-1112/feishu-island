const {test}=require('node:test');const assert=require('node:assert/strict');const zlib=require('node:zlib');
const {parseCache,crc32}=require('../Resources/claude-desktop-usage.cjs');
const org='11111111-1111-1111-1111-111111111111', now=1800000000;
function fixture({organization=org,stamp=now-10,reset=now+3600,used=20,encoding='zstd',body}={}){
 const key=Buffer.from(`1/0/https://claude.ai/api/organizations/${organization}/usage`),head=Buffer.alloc(24);
 head.writeBigUInt64LE(0xfcfb6d1ba7725c30n);head.writeUInt32LE(5,8);head.writeUInt32LE(key.length,12);
 const json=Buffer.from(JSON.stringify(body??{five_hour:{utilization:used,resets_at:new Date(reset*1000).toISOString()}}));
 const data=encoding==='zstd'?zlib.zstdCompressSync(json):encoding==='gzip'?zlib.gzipSync(json):encoding==='br'?zlib.brotliCompressSync(json):json;
 const footer=Buffer.alloc(24);footer.writeBigUInt64LE(0xf4fa6f45970d41d8n);footer.writeUInt32LE(1,8);footer.writeUInt32LE(crc32(data),12);
 return Buffer.concat([head,key,data,footer,Buffer.from(`HTTP/1.1 200 OK\0date:${new Date(stamp*1000).toUTCString()}\0content-encoding:${encoding}\0`)]);
}
for(const encoding of ['zstd','gzip','br'])test(`decodes actual reset and utilization: ${encoding}`,()=>{const q=parseCache(fixture({encoding}),org,now)[0];assert.equal(q.resetsAt,now+3600);assert.equal(q.remainingPercent,80);assert.equal(q.updatedAt,now-10);});
test('rejects another organization',()=>assert.equal(parseCache(fixture({organization:'22222222-2222-2222-2222-222222222222'}),org,now),null));
test('rejects expired window',()=>assert.equal(parseCache(fixture({reset:now-1}),org,now),null));
test('rejects stale response and future date',()=>{assert.equal(parseCache(fixture({stamp:now-90000}),org,now),null);assert.equal(parseCache(fixture({stamp:now+120}),org,now),null)});
test('does not fabricate reset or utilization',()=>{assert.equal(parseCache(fixture({body:{five_hour:{utilization:20}}}),org,now),null);assert.equal(parseCache(fixture({used:101}),org,now),null)});
test('rejects corrupt or incomplete cache body',()=>{const b=fixture();b[120]^=1;assert.equal(parseCache(b,org,now),null);assert.equal(parseCache(fixture().subarray(0,150),org,now),null)});
test('reads only the exact current-account usage cache file',()=>{
 const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
 const {read}=require('../Resources/claude-desktop-usage.cjs');
 const base=path.resolve(__dirname,'../../../.build');fs.mkdirSync(base,{recursive:true});
 const root=fs.mkdtempSync(path.join(base,'usage-cache-test-'));const dir=path.join(root,'Cache','Cache_Data');fs.mkdirSync(dir,{recursive:true});
 fs.writeFileSync(path.join(root,'plan-usage-history.json'),JSON.stringify({samples:[{org,t:now*1000,u:{fh:20}}]}));
 const key=`1/0/https://claude.ai/api/organizations/${org}/usage`;
 const name=crypto.createHash('sha1').update(key).digest().subarray(0,8).reverse().toString('hex')+'_0';
 fs.writeFileSync(path.join(dir,name),fixture());
 assert.equal(read(root,now)[0].resetsAt,now+3600);
 fs.writeFileSync(path.join(root,'plan-usage-history.json'),JSON.stringify({samples:[{org:'22222222-2222-2222-2222-222222222222',t:now*1000,u:{fh:20}}]}));
 assert.deepEqual(read(root,now),[]);
});
