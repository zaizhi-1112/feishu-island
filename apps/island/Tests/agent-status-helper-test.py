"""Exercise the real passive executable with synthetic hook payloads and config files."""
import json, subprocess, tempfile, hashlib, os, time
from pathlib import Path
import sys
helper=Path(sys.argv[1]).resolve()
root=Path(tempfile.mkdtemp(prefix='island-status-hooks-'))
count=0
def check(ok):
 global count
 assert ok
 count+=1
for provider,configdir in [('claude','.claude'),('workbuddy','.workbuddy')]:
 home=root/provider;settings=home/configdir/'settings.json';settings.parent.mkdir(parents=True)
 original={'env':{'SYNTHETIC_SECRET':'not-a-real-key'},'hooks':{'Stop':[{'hooks':[{'type':'command','command':'echo existing-user-hook'}]}]},'permissions':{'deny':['Bash(*)']},'statusLine':{'type':'command','command':"printf 'existing status line'",'padding':2}}
 settings.write_text(json.dumps(original));os.chmod(settings,0o600)
 for i in range(2):
  result=subprocess.run([str(helper),'--install',provider,'--test-root',str(home)],capture_output=True)
  check(result.returncode==0 and not result.stdout)
  j=json.loads(settings.read_text());check(j['env']==original['env'] and j['permissions']==original['permissions'])
  check(len(j['hooks']['Stop'])==2 and j['hooks']['Stop'][0]==original['hooks']['Stop'][0])
  check('timeout' not in j['hooks']['Stop'][-1]['hooks'][0])
 backups=list((home/'Library/Application Support/FeishuIsland/AgentStatus/config-backups').glob('*.json'))
 check(len(backups)==1 and json.loads(backups[0].read_text())==original)
 check(settings.stat().st_mode&0o777==0o600)
 recordroot=root/(provider+'-records');sid='synthetic-session-'+provider
 output=recordroot/provider/(hashlib.sha256(sid.encode()).hexdigest()+'.json')
 for event,extra,state,reason in [('UserPromptSubmit',{},'working',None),('PreToolUse',{'tool_name':'AskUserQuestion'},'waiting','input'),('PostToolUse',{},'working',None),('PermissionRequest',{'tool_name':'Bash'},'waiting','approval'),('PostToolUse',{},'working',None),('Stop',{},'completed',None)]:
  payload={'session_id':sid,'hook_event_name':event,'prompt':'SYNTHETIC-CONTENT-NOT-TO-STORE','tool_input':{'command':'DO-NOT-EXECUTE'},**extra}
  result=subprocess.run([str(helper),'--record',provider,'--test-root',str(recordroot)],input=json.dumps(payload).encode(),capture_output=True)
  check(result.returncode==0 and not result.stdout and not result.stderr)
  j=json.loads(output.read_text());check(j['state']==state and j.get('attentionReason')==reason)
  check('SYNTHETIC-CONTENT' not in output.read_text() and 'DO-NOT-EXECUTE' not in output.read_text() and sid not in output.read_text())
 # Some clients keep stdin open after a complete JSON object. Never wait for EOF.
 p=subprocess.Popen([str(helper),'--record',provider,'--test-root',str(recordroot)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 p.stdin.write(json.dumps({'session_id':sid,'hook_event_name':'PostToolUse'}).encode());p.stdin.flush()
 p.wait(timeout=.9);check(p.returncode==0 and not p.stdout.read() and not p.stderr.read());p.stdin.close()
 # Incomplete input also fails open within the observer's own deadline.
 p=subprocess.Popen([str(helper),'--record',provider,'--test-root',str(recordroot)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 p.stdin.write(b'{"incomplete":');p.stdin.flush();p.wait(timeout=.9)
 check(p.returncode==0 and not p.stdout.read() and not p.stderr.read());p.stdin.close()
 check(output.stat().st_mode&0o777==0o600)
 before=output.read_bytes()
 result=subprocess.run([str(helper),'--record',provider,'--test-root',str(recordroot)],input=b'{malformed',capture_output=True)
 check(result.returncode==0 and not result.stdout and output.read_bytes()==before)
 # Existing settings symlinks are never followed or replaced.
 blocked=root/(provider+'-blocked');(blocked/configdir).mkdir(parents=True)
 victim=root/(provider+'-victim');victim.write_text('{}');(blocked/configdir/'settings.json').symlink_to(victim)
 result=subprocess.run([str(helper),'--install',provider,'--test-root',str(blocked)],capture_output=True)
 check(result.returncode!=0 and victim.read_text()=='{}')
# WorkBuddy 5.3 does not expose account-snapshot.json. Classify the exact
# observed session's pending tool from metadata, never from message text.
provider="workbuddy";sid="synthetic-pending-question"
recordroot=root/'metadata-fallback';folder=recordroot/'source-workbuddy/projects/synthetic-project';folder.mkdir(parents=True)
log=folder/(sid+'.jsonl');log.write_text(json.dumps({'type':'function_call','sessionId':sid,'callId':'question-1','name':'AskUserQuestion','arguments':'NEVER-SAVE'})+'\n')
result=subprocess.run([str(helper),'--record',provider,'--test-root',str(recordroot)],input=json.dumps({'session_id':sid,'hook_event_name':'Notification','notification_type':'permission_prompt'}).encode(),capture_output=True)
output=recordroot/provider/(hashlib.sha256(sid.encode()).hexdigest()+'.json');j=json.loads(output.read_text())
check(result.returncode==0 and not result.stdout and not result.stderr)
check(j['state']=='waiting' and j['attentionReason']=='input' and j['attentionID'].startswith('tool:'))
check('NEVER-SAVE' not in output.read_text())
# Official Claude Code quota payload is separated from context usage and private fields.
home=root/'claude'; state=home/'Library/Application Support/FeishuIsland/AgentStatus'; quota=state/'claude-quota.json'
for used in [25, 31]:
 payload={'rate_limits':{'five_hour':{'used_percentage':used,'resets_at':time.time()+3600}}, 'context_window':{'used_percentage':90},'cwd':'PRIVATE-PATH','session_id':'PRIVATE-SESSION'}
 result=subprocess.run([str(helper),'--statusline','claude','--test-root',str(home)],input=json.dumps(payload).encode(),capture_output=True)
 check(result.returncode==0 and result.stdout==b'existing status line')
 j=json.loads(quota.read_text());check(j['quotas'][0]['remainingPercent']==100-used)
 check('PRIVATE' not in quota.read_text() and 'context_window' not in quota.read_text())
before=quota.read_bytes()
for payload in [{}, {'rate_limits':{'five_hour':{'used_percentage':20,'resets_at':1}}}, {'context_window':{'used_percentage':30}}]:
 result=subprocess.run([str(helper),'--statusline','claude','--test-root',str(home)],input=json.dumps(payload).encode(),capture_output=True)
 check(result.stdout==b'existing status line' and quota.read_bytes()==before)
check(quota.stat().st_mode&0o777==0o600)
print(f'{count} passive helper checks passed; only synthetic fixtures used')
