"""Exercise the real passive executable with synthetic hook payloads and config files."""
import json, subprocess, tempfile, hashlib, os
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
 original={'env':{'SYNTHETIC_SECRET':'not-a-real-key'},'hooks':{'Stop':[{'hooks':[{'type':'command','command':'echo existing-user-hook'}]}]},'permissions':{'deny':['Bash(*)']}}
 settings.write_text(json.dumps(original));os.chmod(settings,0o600)
 for i in range(2):
  result=subprocess.run([str(helper),'--install',provider,'--test-root',str(home)],capture_output=True)
  check(result.returncode==0 and not result.stdout)
  j=json.loads(settings.read_text());check(j['env']==original['env'] and j['permissions']==original['permissions'])
  check(len(j['hooks']['Stop'])==2 and j['hooks']['Stop'][0]==original['hooks']['Stop'][0])
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
 check(output.stat().st_mode&0o777==0o600)
 before=output.read_bytes()
 result=subprocess.run([str(helper),'--record',provider,'--test-root',str(recordroot)],input=b'{malformed',capture_output=True)
 check(result.returncode==0 and not result.stdout and output.read_bytes()==before)
 # Existing settings symlinks are never followed or replaced.
 blocked=root/(provider+'-blocked');(blocked/configdir).mkdir(parents=True)
 victim=root/(provider+'-victim');victim.write_text('{}');(blocked/configdir/'settings.json').symlink_to(victim)
 result=subprocess.run([str(helper),'--install',provider,'--test-root',str(blocked)],capture_output=True)
 check(result.returncode!=0 and victim.read_text()=='{}')
print(f'{count} passive helper checks passed; only synthetic fixtures used')
