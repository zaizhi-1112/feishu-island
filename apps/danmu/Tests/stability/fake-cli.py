#!/usr/bin/env python3
import sys,json,os,time,fcntl
args=sys.argv[1:];path=os.environ['DANMU_TEST_STATE']
def out(data): print(json.dumps({'ok':True,'identity':'user','data':data}));sys.exit(0)
if 'status' in args:
    with open(path,'w') as f: json.dump({'began':time.time(),'calls':0,'fault':False},f)
    print(json.dumps({'identities':{'user':{'available':True,'openId':'self'}}}));sys.exit(0)
with open(path,'r+') as f:
    fcntl.flock(f,fcntl.LOCK_EX);s=json.load(f);s['calls']+=1
    inject=s['calls']>=100 and not s['fault'] and '+chat-list' in args and '--exclude-muted' in args and '--page-all' not in args
    if inject:s['fault']=True
    f.seek(0);json.dump(s,f);f.truncate()
if inject:sys.exit(0) # The observed failure: success exit with empty output.
if '+messages-read-status' in args:
    ids=args[args.index('--message-ids')+1].split(',')
    out({'items':[{'message_id':i,'is_read':False} for i in ids],'invalid_message_ids':[]})
if '+chat-list' in args:
    out({'chats':[{'chat_id':'synthetic','chat_mode':'p2p','name':'synthetic'}],'has_more':False})
if 'api' in args:
    p=json.loads(args[args.index('--params')+1]);msgs=[]
    # Twenty successive incoming messages, retained for failure lookback/dedupe.
    for i in range(1,21):
        stamp=s['began']+i
        if float(p['start_time'])<=stamp<=float(p['end_time']):
            msgs.append({'message_id':str(i),'create_time':str(int(stamp*1000)),'sender':{'id':'other'},'msg_type':'text','body':{'content':'{"text":"synthetic"}'}})
    out({'items':msgs,'has_more':False})
raise Exception('Unexpected call')
