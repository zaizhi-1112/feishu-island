#!/usr/bin/python3
"""Synthetic responses for the memory check; never access an actual account."""
import json
import sys

args = sys.argv[1:]
if "status" in args:
    result = {"identities": {"user": {"available": True, "openId": "self"}}}
elif "+chat-list" in args:
    # Keep the fast path idle so the indefinitely running backfill is measured.
    full = args[args.index("--page-size") + 1] == "100"
    chats = [{"chat_id": "oc_synthetic", "chat_mode": "group", "name": "synthetic"}] if full else []
    result = {"ok": True, "identity": "user", "data": {"chats": chats, "has_more": False}}
elif "/open-apis/im/v1/messages" in args:
    # The messages predate startup, so no user-visible messages or status reads
    # are generated. Extra nested fields exercise Foundation's JSON objects.
    items = [
        {
            "message_id": f"synthetic-{index}",
            "create_time": "1000",
            "sender": {"id": "other"},
            "body": {"content": "synthetic"},
            "meta": [{"key": f"field-{n}", "value": f"synthetic-{index}-{n}"} for n in range(20)],
        }
        for index in range(50)
    ]
    result = {"ok": True, "identity": "user", "data": {"items": items, "has_more": False}}
else:
    sys.exit(2)
print(json.dumps(result))
