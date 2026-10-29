import AppKit
import SwiftUI
@testable import IslandShell

@MainActor func runAgentRestChecks(check:(Bool,String)->Void) async throws {
    let now=Date(timeIntervalSince1970:1_793_000_000)
    var plan=RestReminderPlan();plan.enabled=true;plan.restart(now:now)
    check(plan.remaining(at:now.addingTimeInterval(600))==3000,"rest counts elapsed time")
    plan.setPaused(true,now:now.addingTimeInterval(600))
    check(plan.fireAt==nil && plan.remaining(at:now.addingTimeInterval(1000))==3000,"manual pause freezes remaining time")
    plan.setAway(true,now:now.addingTimeInterval(700));plan.setAway(false,now:now.addingTimeInterval(1700))
    check(plan.paused && plan.fireAt==nil,"wake does not undo manual pause")
    plan.setPaused(false,now:now.addingTimeInterval(2000));plan.setAway(true,now:now.addingTimeInterval(2100));plan.setAway(false,now:now.addingTimeInterval(12100))
    check(plan.remaining(at:now.addingTimeInterval(12100))==2900,"sleep resumes preserved remaining duration")
    plan.restart(now:now,seconds:600);check(plan.remaining(at:now)==600,"postpone gives ten minutes")
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("agent-rest-"+UUID().uuidString)
    let store=WorkspaceStore(root:root,startTimers:false)
    let old=try store.upsertScreenSchedule(title:"原来的计划",firstFire:Date().addingTimeInterval(3600),repeatMinutes:30,style:.init())
    store.setRestEnabled(true,now:now)
    var effects=0;var isRest=false;store.presentScreenReminder={request in effects += 1;isRest=request.isRest}
    store.tickRest(now:now.addingTimeInterval(3600),away:false)
    store.tickRest(now:now.addingTimeInterval(3600),away:false)
    check(isRest,"rest includes rest actions")
    check(effects==1,"consumed rest does not fire twice")
    let restored=WorkspaceStore(root:root,startTimers:false)
    check(restored.screenSchedules.contains{$0.id==old},"old schedules survive rest changes")
    check(restored.restPlan.enabled && restored.restPlan.fireAt==now.addingTimeInterval(7200),"rest schedule persists before playback")
    restored.changeRest{$0.intervalMinutes=0};check(restored.restPlan.intervalMinutes==60,"invalid interval cannot persist")
    let suite="agent-rest-check-"+UUID().uuidString
    let agents=AgentStore(defaults:UserDefaults(suiteName:suite)!,allowsLiveReads:false)
    var prefs=agents.preferences;prefs.enabled=true;prefs.startAlerts=false;prefs.completionAlerts=false;prefs.attentionAlerts=true
    try agents.update(prefs)
    let t=Date().timeIntervalSince1970
    agents.ingestSnapshots(["codex":.init(sessions:[.init(id:"test",state:.working,updatedAt:t)])],now:t)
    check(agents.completionNotice==nil,"start toggle independently suppresses start reminder")
    agents.ingestSnapshots(["codex":.init(sessions:[.init(id:"test",state:.waiting,updatedAt:t+1,attentionID:"input-1",attentionReason:"input")])],now:t+1)
    check(agents.completionNotice?.attention=="input","attention reminder works with completion disabled")
    var updated=agents.preferences;updated.attentionAlerts=false;try agents.update(updated)
    check(agents.completionNotice==nil,"disabling attention clears its live reminder")
    var launcher=AgentProfile(id:"custom-tool-kimi",name:"Kimi",kind:"launcher");launcher.launchURL="https://www.kimi.com"
    var p=agents.preferences;p.profiles.append(launcher);check(p.validationError==nil,"saved launcher does not claim a monitor")
    p.profiles[p.profiles.count-1].launchURL="https://example.com/?token=secret";check(p.validationError != nil,"launch URLs cannot persist tokens")
    let original=AgentPreferences();let legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as! [String:Any]
    var oldPrefs=legacy;oldPrefs.removeValue(forKey:"startAlerts");oldPrefs.removeValue(forKey:"attentionAlerts")
    let decoded=try JSONDecoder().decode(AgentPreferences.self,from:JSONSerialization.data(withJSONObject:oldPrefs))
    check(decoded.startAlerts && decoded.attentionAlerts,"existing notification preferences migrate without dropping events")
    check(Set(AgentSetupOption.all.map(\.id)).count==AgentSetupOption.all.count,"setup catalog has unique tools")
}
