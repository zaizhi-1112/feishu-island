#!/usr/bin/env python3
import sys, json, os, shutil
args = sys.argv[1:]
if args[:1] == ['--profile']:
    assert args[1] == 'synthetic-image'
    args = args[2:]
scopes = 'auth:user.id:read im:chat:read im:chat.user_setting:read im:message.group_msg:get_as_user im:message.p2p_msg:get_as_user im:message:readonly offline_access'
if args[:2] == ['auth', 'status']:
    print(json.dumps({'ok': True, 'verified': True, 'appId': 'cli_image_fixture', 'identities': {'user': {'available': True, 'verified': True, 'openId': 'ou_image_fixture', 'userName': '合成图片测试', 'scope': scopes}}}))
elif args[:2] == ['api', 'GET']:
    message_id = args[2].rsplit('/', 1)[-1]
    assert message_id.startswith('om_') and '--as' in args and args[args.index('--as')+1] == 'user'
    print(json.dumps({'ok': True, 'identity': 'user', 'data': {'items': [{'message_id': message_id, 'msg_type': 'image', 'body': {'content': json.dumps({'image_key': 'img_v3_synthetic'})}}]}}))
elif args[:2] == ['im', '+messages-resources-download']:
    assert args[args.index('--type')+1] == 'image' and args[args.index('--as')+1] == 'user'
    assert args[args.index('--file-key')+1] == 'img_v3_synthetic'
    target = args[args.index('--output')+1]
    assert target.endswith('.img') and '/FeishuIsland/MessageImages/' in target
    shutil.copyfile(os.environ['ISLAND_IMAGE_FIXTURE'], target)
    print(json.dumps({'ok': True, 'identity': 'user', 'data': {'downloaded': True}}))
else:
    raise RuntimeError('Unexpected synthetic image command')
