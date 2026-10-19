#!/usr/bin/env python3
"""Read-only timing probe. Never prints or persists content, names, IDs or credentials."""
import subprocess,json,time,datetime,concurrent.futures,os,urllib.request,urllib.error,email.utils,uuid
from pathlib import Path
project=Path(__file__).resolve().parent.parent
candidates=[project.parent/'飞书弹幕.app/Contents/Helpers/lark-cli',project/'飞书弹幕.app/Contents/Helpers/lark-cli',project/'tools/lark-cli/bin/lark-cli']
CLI=os.environ.get('DANMU_LARK_CLI') or str(next(p for p in candidates if p.is_file()))
server_offset=None
try:
    began_wall=time.time();began=time.monotonic()
    request=urllib.request.Request('https://open.feishu.cn/open-apis/im/v1/messages?danmu_clock_probe='+uuid.uuid4().hex,method='HEAD',headers={'Cache-Control':'no-cache, no-store'})
    try:response=urllib.request.urlopen(request,timeout=4)
    except urllib.error.HTTPError as error:response=error
    with response:
        elapsed=time.monotonic()-began;ended_wall=time.time()
        header=response.headers.get('Date')
        if header and abs(ended_wall-began_wall-elapsed)<1:
            server=email.utils.parsedate_to_datetime(header).timestamp()
            server_offset=server+0.5+elapsed/2-ended_wall
    print(json.dumps({'stage':'clock_calibration','server_minus_local_seconds':round(server_offset,2) if server_offset is not None else None}),flush=True)
except Exception:
    print(json.dumps({'stage':'clock_calibration','available':False}),flush=True)
def call(args):
    start=time.monotonic()
    r=subprocess.run([CLI,'--profile','feishu-danmu']+args,capture_output=True,timeout=25)
    try:j=json.loads(r.stdout)
    except Exception:raise RuntimeError('invalid JSON') from None
    if r.returncode or j.get('ok') is False:raise RuntimeError('API error '+str(j.get('error',{}).get('code','unknown')))
    return j.get('data',{}),round(time.monotonic()-start,2)
args=['im','+chat-list','--types=p2p,group','--sort','active_time','--page-size','100','--page-all','--page-limit','1000','--as','user','--format','json']
a,t=call(args); rows=a.get('chats',[])
print(json.dumps({'stage':'full_catalog','seconds':t,'count':len(rows),'has_more':a.get('has_more')},ensure_ascii=False),flush=True)
u,t=call(args+['--exclude-muted']); allowed={r['chat_id'] for r in u.get('chats',[])}
print(json.dumps({'stage':'unmuted_catalog','seconds':t,'count':len(allowed)},ensure_ascii=False),flush=True)
selected=[r for r in rows if r.get('chat_id') in allowed]
def probe(i):
    r=selected[i]
    try:
        params={'container_id_type':'chat','container_id':r['chat_id'],'page_size':'1','sort_type':'ByCreateTimeDesc'}
        d,t=call(['api','GET','/open-apis/im/v1/messages','--params',json.dumps(params),'--as','user','--format','json'])
        msgs=d.get('items',[]); age=None; field_type=None
        if msgs:
            v=msgs[0].get('create_time');field_type=type(v).__name__
            try:
                f=float(v);ts=f/1000 if f>1e11 else f
            except (ValueError,TypeError):
                try:ts=datetime.datetime.fromisoformat(str(v).replace('Z','+00:00')).timestamp()
                except Exception:ts=None
            if ts and server_offset is not None:age=round(time.time()+server_offset-ts,1)
        return {'rank':i+1,'kind':r.get('chat_mode'),'seconds':t,'latest_age_seconds':age,'time_type':field_type,'message_fields':list(msgs[0]) if msgs else []}
    except Exception as e:return {'rank':i+1,'error':str(e)}
indices=[i for i in list(range(10))+[20,50,100,130] if i<len(selected)]
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
    for result in pool.map(probe,indices):print(json.dumps(result,ensure_ascii=False),flush=True)
