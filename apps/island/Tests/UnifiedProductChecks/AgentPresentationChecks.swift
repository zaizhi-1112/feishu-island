import AppKit
import SwiftUI
import NookApp
@testable import IslandShell

@MainActor func runAgentPresentationChecks(check:(Bool,String)->Void,output:URL?) async throws {
    let agents=AgentStore(defaults:UserDefaults(suiteName:"agent-indicator-"+UUID().uuidString)!,allowsLiveReads:false,sessionIsLocked:{false})
    var p=agents.preferences;p.enabled=true;p.effectsEnabled=false;p.startAlerts=false;p.completionAlerts=false;p.attentionAlerts=false;p.quotaDisplayEnabled=true
    try agents.update(p)
    let now=Date().timeIntervalSince1970
    let quota=AgentQuota(id:"codex/primary",label:"周额度",remainingPercent:77,resetsAt:nil,updatedAt:now)
    func snapshot(_ state:AgentState,time:Double=0)->AgentSnapshot {.init(sessions:[.init(id:"running",state:state,updatedAt:time==0 ? now:time)],quotas:[quota])}
    agents.ingestSnapshots(["codex":snapshot(.working)],now:now)
    check(agents.completionNotice==nil,"persistent running indicator does not depend on a start notification")
    let theme=NookResolvedTheme.resolve(theme:agents.selectedSkin.theme,preferences:.init(chromePalette:.light),effectiveColorScheme:.light,reduceTransparency:true)
    if let output {try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)}
    func capture(_ view:AnyView,_ name:String,size:CGSize=CGSize(width:360,height:46)) async throws -> Int {
        let root=view.frame(width:size.width,height:size.height).environment(\.nookResolvedTheme,theme).preferredColorScheme(.light).background(Color.white)
        let host=NSHostingView(rootView:root)
        let window=NSWindow(contentRect:CGRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=host
        host.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(150))
        guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else{throw WorkError.message("Missing indicator bitmap")}
        host.cacheDisplay(in:host.bounds,to:bitmap)
        var red=0
        for y in stride(from:0,to:bitmap.pixelsHigh,by:2) {for x in stride(from:0,to:bitmap.pixelsWide,by:2) {
            if let c=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),c.redComponent>0.65,c.greenComponent<0.45,c.blueComponent<0.45 {red += 1}
        }}
        if let output {try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))}
        check(!window.isVisible,"indicator fixture stays off-screen: "+name);window.close();return red
    }
    let withQuota=try await capture(AnyView(AgentPersistentCompactSlot(store:agents,leading:false)),"running-with-quota")
    check(withQuota>8,"real persistent quota slot renders a red light while running")
    var summary=AgentActivityDisplay.selectedQuotaSummary(snapshots:agents.snapshots,preferences:agents.preferences,refreshing:false,now:now)
    check(summary.text(leading:false)=="正在运行 · 周 77%" && summary.isRunning,"running text retains selected quota")
    p=agents.preferences;p.quotaDisplayEnabled=false;try agents.update(p)
    check(try await capture(AnyView(AgentPersistentCompactSlot(store:agents,leading:false)),"running-without-quota")>8,"red light also renders with quotas off")
    agents.ingestSnapshots(["codex":snapshot(.completed)],now:now)
    check(try await capture(AnyView(AgentPersistentCompactSlot(store:agents,leading:false)),"completed-without-quota")==0,"red light disappears when work ends")
    p=agents.preferences;p.quotaDisplayEnabled=true;try agents.update(p)
    agents.ingestSnapshots(["codex":snapshot(.working,time:now-901)],now:now)
    summary=AgentActivityDisplay.selectedQuotaSummary(snapshots:agents.snapshots,preferences:agents.preferences,refreshing:false,now:now)
    check(!summary.isRunning,"stale sessions do not claim to be running")
    check(try await capture(AnyView(AgentPersistentCompactSlot(store:agents,leading:false)),"stale-with-quota")==0,"stale running data does not leave a red light")
    p=agents.preferences;p.primaryID="workbuddy";try agents.update(p)
    var credits=AgentQuota(id:"workbuddy/credits",label:"积分",remainingPercent:80,resetsAt:nil,updatedAt:now);credits.remainingUnits=128.5
    agents.ingestSnapshots(["workbuddy":.init(sessions:[.init(id:"w",state:.working,updatedAt:now)],quotas:[credits])],now:now)
    summary=AgentActivityDisplay.selectedQuotaSummary(snapshots:agents.snapshots,preferences:agents.preferences,refreshing:false,now:now)
    check(summary.text(leading:false)=="正在运行 · 剩余 128.5积分","WorkBuddy keeps its own credits during running")
    check(try await capture(AnyView(AgentPersistentCompactSlot(store:agents,leading:false)),"workbuddy-running")>8,"WorkBuddy has the same persistent red light")
    let notice=AgentCompletionNotice(profileID:"codex",name:"Codex",count:1,stillWorking:true,attention:"running")
    check(try await capture(AnyView(AgentCompletionStatus(notice:notice,motion:false)),"running-preview")>8,"running preview and light reminder render red")
    p=agents.preferences;p.monitoredIDs=[];try agents.update(p)
    check(try await capture(AnyView(AgentPersistentCompactSlot(store:agents,leading:false)),"monitoring-paused")==0,"paused monitoring removes running claim")
    let center=NookActivityCenter()
    agents.start(activities:center.activities(for:"switch-check"))
    p=agents.preferences;p.enabled=false;p.quotaDisplayEnabled=false;p.setVisibleIDs(["codex","claude","workbuddy"]);try agents.update(p)
    agents.selectPrimary("claude")
    check(agents.primarySwitchNotice?.profileID=="claude" && agents.completionNotice==nil,"selection feedback is independent from disabled task notifications")
    check(center.primary?.activity.keepsCompactVisible==true && center.primary?.activity.accessibilityLabel=="已切换为Claude Code","selection reveals the pill with the selected identity")
    let first=agents.primarySwitchNotice?.id
    agents.selectPrimary("claude");check(agents.primarySwitchNotice?.id==first,"reselecting the same Agent does not restart feedback")
    agents.selectPrimary("codex");agents.selectPrimary("workbuddy")
    check(agents.primarySwitchNotice?.profileID=="workbuddy","rapid selection keeps only the latest Agent")
    try await Task.sleep(for:.milliseconds(4200))
    check(agents.primarySwitchNotice==nil && center.primary==nil,"feedback expires and stops holding the pill open even with status and quotas off (notice=\(agents.primarySwitchNotice?.profileID ?? "nil"), activity=\(center.primary?.activity.id ?? "nil"))")
    agents.selectPrimary("codex");agents.handleSessionLock()
    check(agents.primarySwitchNotice==nil && center.primary==nil,"screen lock clears selection feedback")
    agents.selectPrimary("claude");p=agents.preferences;p.setVisibleIDs(["codex","workbuddy"]);try agents.update(p)
    check(agents.primarySwitchNotice==nil,"hiding the selected Agent clears obsolete feedback")
    if output != nil {
        _=try await capture(AnyView(HStack(spacing:12){ForEach(agents.preferences.visibleProfiles){profile in AgentPrimaryChoice(profile:profile,selected:profile.id=="codex",motion:false){}}}.padding(12)),"primary-cards",size:CGSize(width:600,height:210))
    }
}
