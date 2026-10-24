import fs from 'node:fs';import crypto from 'node:crypto';import {execFileSync} from 'node:child_process';
const [configPath,output]=process.argv.slice(2),config=JSON.parse(fs.readFileSync(configPath,'utf8'));const repo='zaizhi-1112/feishu-island';
const gh=route=>JSON.parse(execFileSync('gh',['api',route],{encoding:'utf8',stdio:['ignore','pipe','pipe'],maxBuffer:4*1024*1024}));
const base=gh(`repos/${repo}/commits/main`).sha,versions=[];
for(const pr of gh(`repos/${repo}/pulls?state=open&per_page=30`)){
 const p=gh(`repos/${repo}/pulls/${pr.number}`),runs=gh(`repos/${repo}/commits/${p.head.sha}/check-runs`).check_runs;
 const checks=runs.length>0&&runs.every(c=>c.status==='completed'&&['success','neutral','skipped'].includes(c.conclusion))&&runs.some(c=>c.name==='Synthetic message checks'&&c.app?.slug==='github-actions'&&c.conclusion==='success');
 versions.push({pr:p.number,number:p.number,sha:p.head.sha,base,title:p.title,summary:(p.body||'未填写版本说明').slice(0,12000),tests:checks?'GitHub 自动合成检查通过。此结论不替代真实消息、原生界面和多日运行验收。':'自动检查尚未通过。',checks,open:p.state==='open',mergeable:p.mergeable===true&&p.base.ref==='main'&&p.head.repo?.full_name===repo});
}
const data={endpoint:'sync',nonce:crypto.randomUUID(),time:Date.now(),data:{versions}};fs.writeFileSync(output,JSON.stringify({...data,mac:crypto.createHmac('sha256',config.token).update(JSON.stringify(data)).digest('hex')}),{mode:0o600});
