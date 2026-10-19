#!/usr/bin/env python3
import sys,json,os,time
args=sys.argv[1:]
path=os.environ['DANMU_TEST_STATE']
clock_offset=float(os.environ.get('DANMU_TEST_CLOCK_OFFSET','0'))
def out(data):print(json.dumps({'ok':True,'identity':'user','data':data}));sys.exit(0)
if 'status' in args:
    with open(path,'w') as f:json.dump({'began':time.time()},f)
    print(json.dumps({'identities':{'user':{'available':True,'openId':'self'}}}));sys.exit(0)
with open(path) as f:began=json.load(f)['began']
if '+messages-read-status' in args:
    ids=args[args.index('--message-ids')+1].split(',')
    out({'items':[{'message_id':i,'is_read':False} for i in ids],'invalid_message_ids':[]})
if '+chat-list' in args:
    # Slow full catalog runs in the background, while a previously cold chat
    # becomes first in the recent list one second after login.
    full='--page-all' in args
    if full:time.sleep(6)
    ids=list(range(105))
    if time.time()-began>=1:ids=[104]+ids[:-1]
    if not full:ids=ids[:12]
    out({'chats':[{'chat_id':f'oc_{i}','chat_mode':'p2p','name':f'chat{i}'} for i in ids],'has_more':not full})
if 'api' in args:
    p=json.loads(args[args.index('--params')+1]);created=began+1+clock_offset
    def msg(id, stamp):
        return {'message_id':id,'create_time':str(int(stamp*1000)),'sender':{'id':'other','sender_name':'合成发送者'},'msg_type':'text','body':{'content':json.dumps({'text':'合成测试'})}}
    msgs=[]
    if p['container_id']=='oc_104':
        # An API that includes a boundary/history item must not replay pre-start data.
        msgs.append(msg('old-before-start',began-60+clock_offset))
        if float(p['start_time'])<=created<=float(p['end_time']) and time.time()+clock_offset>=created:
            msgs.append(msg('new-in-cold-chat',created))
        # Delayed index visibility: time filtering is real in this fixture.
        late=began+0.25+clock_offset
        if time.time()>=began+4.5 and float(p['start_time'])<=late<=float(p['end_time']):
            msgs.append(msg('late-visible-message',late))
    out({'items':msgs,'has_more':False})
raise Exception('Unexpected call')
