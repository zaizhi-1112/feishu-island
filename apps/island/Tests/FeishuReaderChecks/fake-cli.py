#!/usr/bin/python3
# Synthetic integration fixture only. Never used by the production app.
import sys, json, os, fcntl, time
# Serialize fixture state writes; production calls still execute concurrently.
state_lock = open(os.environ["DANMU_TEST_STATE"] + ".lock", "w")
fcntl.flock(state_lock, fcntl.LOCK_EX)
# Fusion routing checks need repeated backfill turns, not a 105-process catalog sweep.
# Reader pagination checks retain the default 105-chat fixture.
catalog_size = 12 if os.environ.get('DANMU_TEST_FUSION_COMPACT') == '1' else 105
args=sys.argv[1:]
profile = ""
if args[:1] == ["--profile"]:
    profile = args[1]; args=args[2:]
path=os.environ['DANMU_TEST_STATE']
try:
    with open(path) as f: state=json.load(f)
except FileNotFoundError: state={'attempts':{},'read':[],'bad':[],'statusChecks':{}}
if profile != "synthetic-island": state['bad'].append("profile mismatch")
def save():
    with open(path,'w') as f: json.dump(state,f)
def out(data):
    save();print(json.dumps({'ok':True,'identity':'user','data':data}));sys.exit(0)
if 'status' in args:
    sys.stdin.read()
    print('Synthetic CLI diagnostic on stderr',file=sys.stderr)
    print(json.dumps({'identities':{'user':{'available':True,'openId':'self'}}}));sys.exit(0)
if '/open-apis/im/v1/messages/read_status' in args:
    ids=json.loads(args[args.index('--data')+1])['message_ids']
    assert args[:2]==['api','POST']
    checks=state.setdefault('statusChecks',{})
    for i in ids: checks[i]=checks.get(i,0)+1
    out({'items':[{'message_id':i,'is_read':i=='already_read'} for i in ids if i!='unknown' or checks[i]>2],'invalid_message_ids':[]})
if '+chat-list' in args:
    for required in ['--types=p2p,group','--sort','active_time']:
        if required not in args:state['bad'].append(required)
    chats=[{'chat_id':f'oc_{i}','chat_mode':'p2p' if i%2==0 else 'group','name':f'chat{i}'} for i in range(catalog_size)]
    size=int(args[args.index('--page-size')+1])
    cursor=int(args[args.index('--page-token')+1]) if '--page-token' in args else 0
    chats=chats[cursor:cursor+size]
    if '--exclude-muted' in args:chats=[c for c in chats if c['chat_id'] not in ['oc_2','oc_3']]
    out({'chats':chats,'has_more':cursor+size<catalog_size,'page_token':str(cursor+size) if cursor+size<catalog_size else ''})
if 'api' in args and '/open-apis/im/v1/messages' in args:
    params=json.loads(args[args.index('--params')+1])
    chat=params['container_id'];page=params.get('page_token','')
    for required in ['start_time','end_time','sort_type','with_sender_name']:
        if required not in params:state['bad'].append(required)
    if params.get('sort_type') != 'ByCreateTimeDesc':state['bad'].append('sort_type')
    state['read'].append(chat)
    key=chat+page;state['attempts'][key]=state['attempts'].get(key,0)+1
    if chat=='oc_1' and page=='next' and state['attempts'][key]==1:
        save();print(json.dumps({'ok':False,'error':{'code':429}}));sys.exit(1)
    def msg(id, sender='other',deleted=False):return {'message_id':id,'create_time':str(int(time.time()*1000)),'sender':{'id':sender,'sender_name':'测试同事'},'body':{'content':json.dumps({'text':'测试内容'})},'msg_type':'text','deleted':deleted}
    if chat=='oc_0':
        out({'items':[msg('m0'),msg('unknown'),msg('already_read'),msg('own','self'),msg('deleted',deleted=True)] if not page else [msg('m0')] if page=='next' else [msg('m1')],'has_more':page!='last','page_token':'next' if not page else 'last' if page=='next' else ''})
    if chat=='oc_1':out({'items':[msg('m2' if not page else 'm3')],'has_more':not bool(page),'page_token':'next' if not page else ''})
    if chat=='oc_3':out({'items':[msg('gray')],'has_more':False})
    if chat==f'oc_{catalog_size-1}':out({'items':[msg('tail')],'has_more':False})
    out({'items':[],'has_more':False})
raise Exception('Unexpected invocation')
