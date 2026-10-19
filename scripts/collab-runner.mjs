#!/usr/bin/env node
// GitHub credentials stay on this Mac. Only approved immutable versions can be released.
import {readFileSync,mkdirSync,writeFileSync,existsSync} from 'node:fs';
import {execFile} from 'node:child_process';import {promisify} from 'node:util';import path from 'node:path';import os from 'node:os';
import {fileURLToPath} from 'node:url';
const run=promisify(execFile),repo='zaizhi-1112/feishu-island';
const config=JSON.parse(readFileSync(process.argv[2]||path.join(os.homedir(),'.config/feishu-island/runner.json'),'utf8'));
const base=new URL(config.url);if(base.protocol!=='https:'&&!['127.0.0.1','localhost'].includes(base.hostname))throw Error('发布助手只连接 HTTPS 面板');
if(!/^[a-f0-9]{64}$/.test(config.token))throw Error('连接令牌无效');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
async function cmd(bin,args,options={}){const {stdout}=await run(bin,args,{cwd:root,timeout:120000,maxBuffer:4*1024*1024,...options});return stdout;}
async function gh(args){return JSON.parse(await cmd('gh',args));}
// This helper merges one approved source version on GitHub. No app deployment or installation.
let report={};
async function snapshot(number){const p=await gh(['api',`repos/${repo}/pulls/${number}`]);const checks=await gh(['api',`repos/${repo}/commits/${p.head.sha}/check-runs`]);const commit=await gh(['api',`repos/${repo}/commits/main`]);
 const required=checks.check_runs.filter(c=>c.name==='Synthetic message checks'&&c.app?.slug==='github-actions');
 const all=checks.check_runs.length>0&&checks.check_runs.every(c=>c.status==='completed'&&['success','neutral','skipped'].includes(c.conclusion))&&required.some(c=>c.conclusion==='success');
 return {pr:number,number,sha:p.head.sha,base:commit.sha,title:p.title,summary:(p.body||'未填写版本说明').slice(0,12000),tests:all?'GitHub 自动合成检查通过。此结论不替代真实消息、原生界面和多日运行验收。':'自动检查尚未通过。',checks:all,open:p.state==='open',mergeable:p.mergeable===true&&p.base.ref==='main'&&p.head.repo?.full_name===repo};}
function matches(j,v){return v.sha===j.sha&&v.base===j.base&&v.checks&&v.open&&v.mergeable&&v.summary===j.version.summary&&v.title===j.version.title;}
async function publish(j){
 // Validate before executing approved source, again before merge, and before publication.
 let latest=await snapshot(j.pr);if(!matches(j,latest))throw Error('代码、主版本或检查已变化，需要双方重新确认');
 if(j.version.target!=='github-source')throw Error('旧发布任务不适用，请双方重新确认 GitHub 源码版本');
 latest=await snapshot(j.pr);if(!matches(j,latest))throw Error('版本已变化，需要双方重新确认');
 const merged=await gh(['api',`repos/${repo}/pulls/${j.pr}/merge`,'--method','PUT','-f','merge_method=squash','-f','sha='+j.sha]);if(!merged.merged)throw Error('代码未合并，停止发布');
 const current=await gh(['api',`repos/${repo}/commits/main`]);if(current.sha!==merged.sha)throw Error('合并后主版本有其他变化，停止发布');
 report={job:j.id,digest:j.digest,sha:j.sha,mergeSha:merged.sha,commitUrl:'https://github.com/'+repo+'/commit/'+merged.sha};
 console.log('已发布：'+j.version.title);
}
const envelope=JSON.parse(readFileSync(process.argv[3],'utf8'));
const crypto=await import('node:crypto');
const signed=JSON.stringify({nonce:envelope.nonce,data:envelope.data});
const expected=crypto.createHmac('sha256',config.token).update(signed).digest('hex');
if(typeof envelope.mac!=='string'||envelope.mac.length!==64||!crypto.timingSafeEqual(Buffer.from(expected),Buffer.from(envelope.mac)))throw Error('发布任务签名无效');
const job=envelope.data.job;if(!job)throw Error('没有已批准的发布任务');
const reportPath=process.argv[4];if(!reportPath)throw Error('需要独立结果文件');
mkdirSync(path.dirname(path.resolve(reportPath)),{recursive:true,mode:0o700});
await publish(job);
writeFileSync(reportPath,JSON.stringify(report),{mode:0o600});
console.log('源代码已更新到 GitHub，结果写入指定文件。未构建安装包或部署产品服务。');
