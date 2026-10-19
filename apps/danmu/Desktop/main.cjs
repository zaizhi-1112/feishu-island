'use strict';
const {app,BrowserWindow,ipcMain,Menu,Tray,nativeImage,screen,powerMonitor,shell,dialog}=require('electron');
const fs=require('node:fs');const path=require('node:path');
const {CLI,Reader}=require('./core/reader.cjs');const {MessageBuffer,pages,duration}=require('./core/presentation.cjs');
let panel,overlay,tray,reader,cli,buffer=new MessageBuffer(),quitting=false,paused=false,busy=false,timer,authBusy=false,presenting=null,wasPaused=false;
let status={text:'正在连接飞书账号',health:'connecting'},latency='',received=0;
const prefs={size:32,palette:0,heavy:true,backdrop:true,opacity:1,duration:14,lanes:4,position:0,poll:1000,gray:[],hidden:[],cardSpeed:4};let preferencesFile;
if(!app.requestSingleInstanceLock())app.quit();
app.on('second-instance',()=>{panel?.show();panel?.focus();});
const state=()=>({status,latency,received,queue:buffer.queue.filter(m=>!m.demo).length,dropped:buffer.dropped,history:buffer.history,prefs,receiving:reader?.enabled||false,paused,version:app.getVersion(),authBusy});
function publish(){if(panel&&!panel.isDestroyed())panel.webContents.send('state',state());if(tray)tray.setToolTip(`飞书弹幕 · 未读待展示 ${buffer.queue.filter(m=>!m.demo).length} 条`);}
function save(){fs.writeFileSync(preferencesFile,JSON.stringify(prefs),{mode:0o600});reader.poll=prefs.poll;reader.gray=prefs.gray;reader.hidden=prefs.hidden;publish();}
function windowOptions(){return {webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,nodeIntegration:false,sandbox:true,backgroundThrottling:false},show:false};}
function secure(window){window.webContents.setWindowOpenHandler(()=>({action:'deny'}));window.webContents.on('will-navigate',e=>e.preventDefault());window.webContents.on('render-process-gone',()=>{if(window===overlay&&presenting){buffer.queue.unshift(presenting);presenting=null;}busy=false;window.reload();status={text:'显示窗口已恢复，账号接收继续',health:'connecting'};publish();});}
function rebuild(){
  if(presenting){buffer.queue.unshift(presenting);presenting=null;}
  if(overlay&&!overlay.isDestroyed())overlay.close();busy=false;
  const bounds=screen.getPrimaryDisplay().workArea;
  overlay=new BrowserWindow({...windowOptions(),...bounds,frame:false,transparent:true,backgroundColor:'#00000000',resizable:false,skipTaskbar:true,focusable:false,hasShadow:false});
  overlay.setIgnoreMouseEvents(true,{forward:true});overlay.setAlwaysOnTop(true,'screen-saver');overlay.setVisibleOnAllWorkspaces(true,{visibleOnFullScreen:true});secure(overlay);
  overlay.loadFile(path.join(__dirname,'ui/overlay.html'));overlay.once('ready-to-show',()=>publish());
}
function applyPrefs(input){
  for(const key of ['size','duration','lanes','position','poll','cardSpeed','opacity','palette'])if(Number.isFinite(input[key])){const ranges={size:[22,52],duration:[8,30],lanes:[1,8],position:[0,2],poll:[500,6000],cardSpeed:[2,8],opacity:[0.4,1],palette:[0,3]};prefs[key]=Math.max(ranges[key][0],Math.min(ranges[key][1],input[key]));}
  for(const key of ['backdrop','heavy'])if(typeof input[key]==='boolean')prefs[key]=input[key];
  for(const key of ['gray','hidden'])if(Array.isArray(input[key]))prefs[key]=input[key].filter(x=>typeof x==='string'&&x.trim()).slice(0,100).map(x=>x.slice(0,100));
  save();
}
async function connect(){
  if(authBusy)return;authBusy=true;reader.stop();publish();
  try{
    const a=await cli.call(['auth','status','--json']);
    if(!a.identities?.user){status={text:'首次使用：请先配置你本人的飞书应用，然后连接账号',health:'error'};return;}
    const start=await cli.call(['auth','login','--scope','im:message:readonly im:chat:read im:chat:read_p2p offline_access','--no-wait','--json'],{timeout:20000});
    const info=start.data||start;const url=info.verification_uri_complete||info.verification_url||info.verification_uri;
    if(!url||!info.device_code)throw new Error('未取得授权入口，请重试');
    const parsed=new URL(url);if(parsed.protocol!=='https:'||!/(^|\.)(feishu\.cn|larksuite\.com)$/.test(parsed.hostname))throw new Error('授权地址异常');
    status={text:'请在浏览器确认本人消息只读授权，完成后自动连接',health:'connecting'};publish();await shell.openExternal(url);
    await cli.call(['auth','login','--device-code',info.device_code,'--json'],{timeout:300000});
    reader.start();
  }catch(e){status={text:e.message,health:'error'};}finally{authBusy=false;publish();}
}
async function configure({appId,secret}){
  if(authBusy)return;if(!/^cli_[a-zA-Z0-9]+$/.test(appId)||typeof secret!=='string'||!secret.trim())throw new Error('请填写你本人应用的 App ID 和 App Secret');
  // Secrets are passed through stdin only; never arguments, logs or app prefs.
  const {spawn}=require('node:child_process');authBusy=true;reader.stop();publish();
  await new Promise((resolve,reject)=>{const child=spawn(cli.binary,['config','init','--name','feishu-danmu','--app-id',appId,'--app-secret-stdin','--brand','feishu'],{windowsHide:true,stdio:['pipe','ignore','ignore'],env:{...process.env,LARKSUITE_CLI_NO_UPDATE_NOTIFIER:'1',LARKSUITE_CLI_NO_SKILLS_NOTIFIER:'1'}});cli.children.add(child);const timer=setTimeout(()=>child.kill('SIGKILL'),15000);child.stdin.end(secret.trim()+'\n');child.on('error',()=>{clearTimeout(timer);cli.children.delete(child);reject(new Error('配置工具未启动'));});child.on('close',code=>{clearTimeout(timer);cli.children.delete(child);code===0?resolve():reject(new Error('配置失败，请检查本人应用信息'));});}).finally(()=>{authBusy=false;publish();});
  await connect();
}
app.whenReady().then(()=>{
  preferencesFile=path.join(app.getPath('userData'),'preferences.json');try{Object.assign(prefs,JSON.parse(fs.readFileSync(preferencesFile,'utf8')));}catch{}
  const base=app.isPackaged?path.join(process.resourcesPath,'cli'):path.join(__dirname,'vendor',`${process.platform==='win32'?'win':'mac'}-${process.arch}`);
  cli=new CLI(path.join(base,process.platform==='win32'?'lark-cli.exe':'lark-cli'));reader=new Reader(cli);reader.gray=prefs.gray;reader.hidden=prefs.hidden;reader.poll=prefs.poll;
  reader.on('status',s=>{status=s;publish();});reader.on('message',m=>{received++;buffer.enqueue(m);publish();});
  panel=new BrowserWindow({...windowOptions(),width:1080,height:830,minWidth:900,minHeight:650,title:'飞书弹幕 · 文豪野犬通信簿'});secure(panel);panel.loadFile(path.join(__dirname,'ui/index.html'));panel.once('ready-to-show',()=>panel.show());panel.on('close',e=>{if(!quitting){e.preventDefault();panel.hide();}});
  rebuild();screen.on('display-metrics-changed',rebuild);screen.on('display-added',rebuild);screen.on('display-removed',rebuild);
  const image=nativeImage.createFromPath(path.join(__dirname,'ui/app-icon.png')).resize({width:16,height:16});tray=new Tray(image);if(process.platform==='darwin')tray.setTitle('弹幕');
  tray.setContextMenu(Menu.buildFromTemplate([{label:'打开控制台',click:()=>panel.show()},{label:'暂停 / 继续',click:()=>{paused=!paused;publish();}},{label:'退出飞书弹幕',click:()=>app.quit()}]));tray.on('click',()=>panel.show());
  powerMonitor.on('suspend',()=>{reader.suspend();});powerMonitor.on('resume',()=>reader.resume());powerMonitor.on('lock-screen',()=>{wasPaused=paused;paused=true;overlay.webContents.send('state',{paused});publish();});powerMonitor.on('unlock-screen',()=>{paused=wasPaused;overlay.webContents.send('state',{paused});publish();reader.resume();});
  timer=setInterval(async()=>{
    if(paused||busy||reader.sleeping||!buffer.queue.length||overlay.webContents.isLoading())return;
    const m=buffer.queue[0];busy=true;
    try{
      if(!m.demo){const r=await reader.data(['im','+messages-read-status','--message-ids',m.id]);if(r.items?.find(x=>x.message_id===m.id)?.is_read!==false){buffer.queue.shift();busy=false;publish();return;}}
      if(buffer.queue[0]!==m){busy=false;return;}buffer.queue.shift();publish();
      const card=Array.from(m.text).length>10,parts=card?pages(m.text,{width:Math.min(600,Math.max(280,overlay.getBounds().width*.43)),font:prefs.size,lines:5}):[m.text];
      presenting=m;overlay.showInactive();overlay.webContents.send('present',{...m,parts,card,prefs});
      if(!m.demo){const receive=Math.max(0,m.receivedAt-m.createdAt)/1000,wait=Math.max(0,performance.now()-m.enqueuedAt)/1000;latency=`最近真实消息：接收 ${receive.toFixed(1)} 秒 + 排队 ${wait.toFixed(1)} 秒`;}publish();
    }catch{busy=false;status={text:'未读状态复查失败，保留待播消息后重试',health:'error'};publish();}
  },500);
  if(!process.argv.includes('--preview'))reader.start();else{status={text:'界面验收模式，不读取真实消息',health:'stopped'};publish();}
});
ipcMain.handle('get',()=>state());
ipcMain.handle('action',async(event,name,value)=>{
  const isPanel=event.sender===panel?.webContents,isOverlay=event.sender===overlay?.webContents;
  if(name==='presented'&&isOverlay){overlay.hide();presenting=null;busy=false;return;}
  if(!isPanel)return;
  try{
    if(name==='prefs')applyPrefs(value||{});
    if(name==='pause'){paused=!paused;overlay.webContents.send('state',{paused});publish();}
    if(name==='clear'){overlay.hide();presenting=null;buffer.clear();overlay.webContents.send('state',{clear:true});busy=false;publish();}
    if(name==='listen'){reader.enabled?reader.stop():reader.start();}
    if(name==='connect')await connect();
    if(name==='configure')await configure(value||{});
    if(name==='demo')buffer.enqueue({demo:true,sender:'演示',chat:'本机试播',text:'这是一条超过十个字的多行卡片消息。卡片停留期间可以完整阅读，较长内容会自动分页，不必追着一行长文字跑。'});
    if(name==='launch')app.setLoginItemSettings({openAtLogin:!!value});
    if(name==='guide')await shell.openPath(app.isPackaged?path.join(process.resourcesPath,'使用说明.html'):path.join(__dirname,'../使用说明.html'));
    publish();return {ok:true};
  }catch(e){status={text:e.message,health:'error'};publish();return {ok:false};}
});
app.on('before-quit',()=>{quitting=true;clearInterval(timer);reader?.stop();cli?.cancel();});
app.on('window-all-closed',()=>{});
