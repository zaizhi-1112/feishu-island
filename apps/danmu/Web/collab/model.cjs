'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const hash=x=>crypto.createHash('sha256').update(typeof x==='string'?x:JSON.stringify(x)).digest('hex');
function text(x,n=2000){if(typeof x!=='string'||!x.trim()||x.length>n)throw Error('请填写完整内容，并缩短过长的文字');return x.trim();}
function createStore(dir,owner){
 fs.mkdirSync(dir,{recursive:true,mode:0o700});const file=path.join(dir,'project.json');
 let s;try{s=JSON.parse(fs.readFileSync(file,'utf8'));}catch(e){if(e.code!=='ENOENT')throw e;s={revision:0,members:[],requests:[],needs:[],versions:[],events:[],runner:{},jobs:[]};}
 if(owner&&!s.members.length)s.members=[{id:owner,name:'宰治',owner:true}];
 function save(){s.revision++;s.events=s.events.slice(-1000);const tmp=file+'.tmp';fs.writeFileSync(tmp,JSON.stringify(s),{mode:0o600});fs.renameSync(tmp,file);}
 function event(actor,kind,detail){s.events.push({id:crypto.randomUUID(),at:new Date().toISOString(),actor,kind,detail});}
 function member(id){return s.members.find(x=>x.id===id);}
 function requireMember(id){const m=member(id);if(!m)throw Error('你还未加入这个项目');return m;}
 function own(id){if(!requireMember(id).owner)throw Error('只有项目负责人可以操作');}
 function version(id){const v=s.versions.find(v=>v.id===id);if(!v)throw Error('版本不存在');return v;}
 function upsert(input){
  if(!Number.isSafeInteger(input.pr)||input.pr<1||!Number.isSafeInteger(input.number)||input.number<1)throw Error('版本编号无效');
  if(!/^[a-f0-9]{40}$/.test(input.sha)||!/^[a-f0-9]{40}$/.test(input.base))throw Error('代码版本无效');
  const value={id:'pr-'+input.pr,pr:input.pr,number:input.number,sha:input.sha,base:input.base,title:text(input.title,200),summary:text(input.summary,12000),tests:text(input.tests,4000),target:'both',checks:input.checks===true,open:input.open===true,mergeable:input.mergeable===true};
  const digest=hash(value);let v=s.versions.find(v=>v.id===value.id);
  if(!v){v={...value,digest,approvals:{},state:'review',seen:Date.now()};s.versions.unshift(v);event('发布助手','version','新增版本：'+v.title);}
  else if(v.digest!==digest){if(['building','published'].includes(v.state))throw Error('此版本正在发布或已经发布');s.jobs=s.jobs.filter(j=>j.version!==v.id||j.status==='published');Object.assign(v,value,{digest,approvals:{},state:'review',seen:Date.now()});event('发布助手','changed','版本有变化，原同意已作废：'+v.title);}
  else v.seen=Date.now();
  save();return v;
 }
 function vote(uid,id,digest,agree){requireMember(uid);const v=version(id);
  if(v.digest!==digest)throw Error('版本内容已经变化，请刷新后重新查看');
  if(['building','published'].includes(v.state))throw Error('版本已进入发布，请查看发布结果');
  if(!agree){v.approvals={};v.state='changes';s.jobs=s.jobs.filter(j=>j.version!==id);event(member(uid).name,'changes','要求修改：'+v.title);save();return v;}
  if(s.members.length!==2)throw Error('需要两位成员先加入项目');
  if(!v.open||!v.checks||!v.mergeable||Date.now()-v.seen>180000)throw Error('请等待发布助手同步最新代码与通过的检查');
  v.approvals[uid]={digest,at:new Date().toISOString()};event(member(uid).name,'agree','同意上线：'+v.title);
  if(s.members.every(m=>v.approvals[m.id]?.digest===v.digest)){
   v.state='queued';if(!s.jobs.some(j=>j.version===id&&['queued','building'].includes(j.status)))s.jobs.push({id:crypto.randomUUID(),version:id,digest,sha:v.sha,base:v.base,pr:v.pr,status:'queued'});
  }else v.state='review';save();return v;
 }
 function claim(){s.runner.lastSeen=Date.now();let j=s.jobs.find(j=>j.status==='queued');if(j){let v=version(j.version);if(v.digest!==j.digest||!s.members.every(m=>v.approvals[m.id]?.digest===j.digest)){j.status='cancelled';save();return null;}j.status='building';j.started=Date.now();v.state='building';event('发布助手','build','开始构建：'+v.title);}save();return j?{...j,version:version(j.version)}:null;}
 function result(input){const j=s.jobs.find(j=>j.id===input.job);if(!j||j.status!=='building')throw Error('发布任务状态不匹配');const v=version(j.version);if(input.digest!==j.digest||input.sha!==j.sha)throw Error('发布结果与批准版本不符');
  if(input.ok===true){if(!j.artifact)throw Error('下载包还没上传到面板');if(!/^https:\/\/github\.com\/zaizhi-1112\/feishu-island\/releases\/tag\/[a-zA-Z0-9._-]+$/.test(input.macUrl||'')||input.webUrl!=='https://feishu-danmu.virxact.net')throw Error('两个发布结果尚未齐全');v.url=input.macUrl;v.download='/collab/download/'+j.id;v.webUrl=input.webUrl;v.state='published';j.status='published';event('发布助手','published','网页版与 Mac 下载包已发布：'+v.title);}else{v.state='failed';v.approvals={};j.status='failed';v.error=text(input.error||'发布失败，请让 Agent 检查',1000);if(input.macUrl&&/^https:\/\/github\.com\/zaizhi-1112\/feishu-island\/releases\/tag\/[a-zA-Z0-9._-]+$/.test(input.macUrl))v.url=input.macUrl;event('发布助手','failed',v.error);}save();}
 function action(uid,input){const m=requireMember(uid);
  switch(input.type){
   case 'need':{const n={id:crypto.randomUUID(),title:text(input.title,140),detail:text(input.detail,6000),by:m.name,status:'待安排',at:new Date().toISOString()};s.needs.unshift(n);event(m.name,'need','记录需求：'+n.title);break;}
   case 'need-status':{const n=s.needs.find(n=>n.id===input.id);if(!n||!['待安排','开发中','待验收','已完成'].includes(input.status))throw Error('需求状态无效');n.status=input.status;event(m.name,'progress',n.title+' → '+n.status);break;}
   case 'note':event(m.name,'note',text(input.detail,6000));break;
   case 'join':own(uid);if(s.members.length!==1)throw Error('项目仅供两位成员使用');{const p=s.requests.find(p=>p.id===input.id);if(!p)throw Error('加入申请不存在');s.members.push({...p,owner:false});s.requests=[];event(m.name,'member','确认伙伴加入：'+p.name);}break;
   default:throw Error('操作不存在');
  }save();
 }
 function join(uid,name){if(!uid||uid.length>256)throw Error('登录身份无效');if(member(uid))return;if(!s.requests.some(x=>x.id===uid)){s.requests.push({id:uid,name:text(name,120),at:new Date().toISOString()});s.requests=s.requests.slice(-20);save();}}
 function token(uid){own(uid);const value=crypto.randomBytes(32).toString('hex');s.runner.tokenHash=hash(value);s.runner.secret=value;s.runner.lastSeen=0;event(member(uid).name,'runner','更新发布助手连接');save();return value;}
 function runner(value){return typeof value==='string'&&value.length===64&&s.runner.tokenHash===hash(value);}
 function view(uid){const m=requireMember(uid);const {tokenHash,secret,...status}=s.runner;return {...s,me:m,runner:{...status,online:Date.now()-(status.lastSeen||0)<135000},requests:m.owner?s.requests:[]};}
 return {s,save,event,member,own,upsert,vote,claim,result,action,join,token,runner,view,hash};
}
module.exports={createStore,hash};
