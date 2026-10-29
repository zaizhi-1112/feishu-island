import AppKit
import Foundation
import SwiftUI
import NookApp
@testable import IslandShell

@MainActor func runFocusedFixChecks(check:(Bool,String)->Void) async throws {
    check(TodoRepeatUnit.minutes.minutes(from:"1")==1 && TodoRepeatUnit.minutes.minutes(from:"60")==60,"minute input supports one through sixty")
    check(TodoRepeatUnit.hours.minutes(from:"1")==60 && TodoRepeatUnit.hours.minutes(from:"3")==180 && TodoRepeatUnit.hours.minutes(from:"24")==1440,"hour input supports one through twenty-four without user conversion")
    for text in ["", "0", "-1", "61", "1.5", "abc", "99999999999999999999999999"] {check(TodoRepeatUnit.minutes.minutes(from:text)==nil,"invalid minute input rejected: "+text)}
    for text in ["0", "25", "1.5", "abc"] {check(TodoRepeatUnit.hours.minutes(from:text)==nil,"invalid hour input rejected: "+text)}
    let todoRoot=FileManager.default.temporaryDirectory.appendingPathComponent("focused-todo-"+UUID().uuidString)
    let todos=WorkspaceStore(root:todoRoot,startTimers:false)
    let start=Date()
    let todo=try todos.addTodo(title:"原始文字",now:start)
    var fired=0;todos.notify={_ in fired += 1}
    todos.tickReminders(now:start.addingTimeInterval(1199));check(fired==0,"default reminder does not fire early")
    todos.tickReminders(now:start.addingTimeInterval(1201));todos.tickReminders(now:start.addingTimeInterval(1202))
    check(fired==1,"new todo fires exactly once at twenty minutes")
    let beforeEdit=todos.disk.items.first{$0.id==todo}!
    _=try todos.configureTodoReminder(todo,dates:[],now:start.addingTimeInterval(1203),title:"只改正文",details:"保留补充说明",deadline:.some(start.addingTimeInterval(86400)),preserveReminderSchedule:true)
    let afterEdit=todos.disk.items.first{$0.id==todo}!
    check(afterEdit.title=="只改正文" && afterEdit.due==beforeEdit.due && afterEdit.reminded==beforeEdit.reminded && afterEdit.todoReminder==beforeEdit.todoReminder,"text edit preserves a consumed reminder and does not rearm it")
    todos.tickReminders(now:start.addingTimeInterval(1800));check(fired==1,"saving text does not replay the old reminder")
    _=try todos.configureTodoReminder(todo,dates:[start.addingTimeInterval(2400)],now:start.addingTimeInterval(1801))
    todos.complete(todo);todos.reopenTodo(todo);todos.tickReminders(now:start.addingTimeInterval(2500))
    check(fired==1 && todos.pendingTodos.first?.title=="只改正文" && todos.pendingTodos.first?.input=="保留补充说明","reopen preserves task content and cancels its old reminder")
    let reload=WorkspaceStore(root:todoRoot,startTimers:false)
    check(reload.pendingTodos.first?.id==todo && reload.todoHistory.count==1,"reopened task and completion history survive restart")

    let modes=WorkspaceStore(root:todoRoot.appendingPathComponent("modes"),startTimers:false)
    let m=try modes.addTodo(title:"提醒模式互斥",now:start)
    _=try modes.configureTodoReminder(m,dates:[start.addingTimeInterval(60)],repeatMinutes:60,now:start)
    check(modes.disk.items.first?.todoReminder?.repeatMinutes==60,"sixty minute interval can be entered directly")
    _=try modes.configureTodoReminder(m,dates:[start.addingTimeInterval(120),start.addingTimeInterval(240)],now:start)
    check(modes.disk.items.first?.todoReminder?.repeatMinutes==nil && modes.disk.items.first?.todoReminder?.pendingDates.count==2,"specified times replace repeating mode")
    var modeFires=0;modes.notify={_ in modeFires += 1}
    modes.tickReminders(now:start.addingTimeInterval(61));check(modeFires==0,"old repeating schedule no longer fires after changing mode")
    _=try modes.configureTodoReminder(m,dates:[],now:start)
    modes.tickReminders(now:start.addingTimeInterval(4000))
    check(modeFires==0 && modes.disk.items.first?.due==nil && modes.disk.items.first?.todoReminder==nil,"off mode clears both fixed and repeating schedules")
    for invalid in [0,-1,10081] {
        do {_=try modes.configureTodoReminder(m,dates:[start.addingTimeInterval(60)],repeatMinutes:invalid,now:start);check(false,"invalid interval rejected")}
        catch {check(modes.disk.items.first?.todoReminder==nil,"invalid interval leaves stored mode unchanged")}
    }

    let suite="focused-agent-"+UUID().uuidString
    let defaults=UserDefaults(suiteName:suite)!
    defer {defaults.removePersistentDomain(forName:suite)}
    var locked=false
    let agents=AgentStore(defaults:defaults,allowsLiveReads:false,sessionIsLocked:{locked})
    let center=NookActivityCenter();agents.start(activities:center.activities(for:"focused-check"))
    var p=agents.preferences;p.enabled=true;p.primaryID="codex";p.setVisibleIDs(["codex"]);p.monitoredIDs=["codex","workbuddy"];p.quotaDisplayEnabled=false;try agents.update(p)
    let t=Date().timeIntervalSince1970
    agents.ingestSnapshots(["codex":.init(),"workbuddy":.init()],now:t)
    func snapshot(_ id:String,_ state:AgentState,_ time:Double)->AgentSnapshot {.init(sessions:[.init(id:id,state:state,updatedAt:time,completionID:state == .completed ? id+"-done":nil)])}
    agents.ingestSnapshots(["codex":snapshot("c",.working,t+1),"workbuddy":snapshot("w",.working,t+1)],now:t+1)
    check(agents.completionNotice?.profileID=="codex","first simultaneous start remains visible")
    check(agents.state(for:"workbuddy",now:t+1) == .working,"nonprimary WorkBuddy running state is monitored independently")
    let first=agents.completionNotice!.id
    agents.finishNotice(first)
    check(agents.completionNotice?.profileID=="workbuddy" && agents.primary.id=="codex","queued nonprimary start is shown without changing primary")
    agents.finishNotice(first)
    check(agents.completionNotice?.profileID=="workbuddy","expired timer cannot dismiss another Agent notice")
    agents.finishNotice(agents.completionNotice!.id)
    agents.ingestSnapshots(["codex":snapshot("c",.completed,t+2),"workbuddy":snapshot("w",.completed,t+2)],now:t+2)
    agents.ingestSnapshots(["codex":snapshot("c",.completed,t+2),"workbuddy":snapshot("w",.completed,t+2)],now:t+23)
    check(agents.completionNotice?.profileID=="codex","first completion survives simultaneous settled completions")
    agents.finishNotice(agents.completionNotice!.id)
    check(agents.completionNotice?.profileID=="workbuddy" && agents.completionNotice?.attention==nil,"nonprimary completion is delivered next")
    agents.finishNotice(agents.completionNotice!.id)
    p=agents.preferences;p.setVisibleIDs([]);try agents.update(p)
    agents.ingestSnapshots(["workbuddy":snapshot("w2",.working,t+24)],now:t+24)
    check(agents.completionNotice?.profileID=="workbuddy" && center.primary?.activity.keepsCompactVisible==true,"alerts-only tool can reveal a notice with no visible tools or quota display")
    agents.finishNotice(agents.completionNotice!.id)
    let quota=AgentQuota(id:"workbuddy/credits",label:"积分",remainingPercent:10,resetsAt:t+86400,updatedAt:t+25)
    agents.ingestSnapshots(["workbuddy":.init(quotas:[quota])],now:t+25)
    check(agents.lastAlert.contains("WorkBuddy") && agents.lastAlert.contains("10.0%"),"nonprimary low-quota alert names its own source")
    check(agents.completionNotice?.isQuota==true,"quota notices use the same delivery queue")
    if let notice=agents.completionNotice {agents.finishNotice(notice.id)}
    p=agents.preferences;p.setVisibleIDs(["codex"]);try agents.update(p)
    agents.ingestSnapshots(["codex":snapshot("c2",.working,t+26),"workbuddy":snapshot("w3",.working,t+26)],now:t+26)
    p=agents.preferences;p.monitoredIDs=["codex"];try agents.update(p)
    if let notice=agents.completionNotice {agents.finishNotice(notice.id)}
    check(agents.completionNotice==nil,"turning a tool off removes its queued notices")
    p=agents.preferences;p.monitoredIDs=["codex","workbuddy"];try agents.update(p)
    agents.ingestSnapshots(["workbuddy":.init()],now:t+27)
    agents.ingestSnapshots(["codex":snapshot("c3",.working,t+28),"workbuddy":snapshot("w4",.working,t+28)],now:t+28)
    locked=true;agents.handleSessionLock();locked=false
    check(agents.completionNotice==nil && center.primary==nil,"locking clears the current and queued notices")

    let folder=FileManager.default.temporaryDirectory.appendingPathComponent("prompt-handoff-"+UUID().uuidString)
    let connection=try AgentPromptConnection(root:folder)
    check(connection.prompt.contains(connection.manifestURL.path) && connection.prompt.contains(connection.statusURL.path),"generic prompt includes its own local handoff paths")
    check(try connection.connect(to:agents)==nil,"copying a prompt does not claim a connection")
    let originalPrimary=agents.primary.id, originalIDs=agents.preferences.profiles.map(\.id)
    try Data(#"{"version":1,"name":"合成接入工具"}"#.utf8).write(to:connection.manifestURL)
    do {_=try connection.connect(to:agents);check(false,"missing state file must not register")}catch {check(agents.preferences.profiles.map(\.id)==originalIDs,"missing state preserves all tools")}
    try Data(#"{"sessions":[],"source":"合成接入工具","detail":"仅验证本机接入"}"#.utf8).write(to:connection.statusURL)
    check(try connection.connect(to:agents)=="合成接入工具","valid handoff registers tool without manual paths")
    check(agents.primary.id==originalPrimary,"handoff preserves primary")
    let custom=agents.preferences.profiles.first{$0.name=="合成接入工具"}!
    check(custom.dataPath==connection.statusURL.path && agents.preferences.isMonitoring(custom.id),"handoff connects existing file reader and monitoring")
    check(try CustomAgentReader.read(custom).quotas.isEmpty,"unknown quota remains absent")
    _=try connection.connect(to:agents)
    check(agents.preferences.profiles.filter{$0.name==custom.name}.count==1,"repeated handoff does not duplicate a tool")
    let persisted=AgentStore(defaults:defaults,allowsLiveReads:false)
    check(persisted.preferences.profiles.contains{$0.id==custom.id && $0.dataPath==custom.dataPath},"connection survives app restart")
    let builtin=try AgentPromptConnection(root:folder)
    try Data(#"{"version":1,"name":"WorkBuddy","builtinID":"workbuddy"}"#.utf8).write(to:builtin.manifestURL)
    check(try builtin.connect(to:agents)=="WorkBuddy" && agents.preferences.profiles.filter{$0.id=="workbuddy"}.count==1,"generic prompt reuses builtin readers without duplicate profiles")
    let invalid=try AgentPromptConnection(root:folder)
    try Data(#"{"version":2,"name":"不应导入"}"#.utf8).write(to:invalid.manifestURL)
    let before=agents.preferences.revision
    do{_=try invalid.connect(to:agents);check(false,"bad handoff version rejected")}catch{check(agents.preferences.revision==before,"invalid handoff makes no preference changes")}
    let link=try AgentPromptConnection(root:folder)
    try FileManager.default.createSymbolicLink(at:link.manifestURL,withDestinationURL:builtin.manifestURL)
    do{_=try link.connect(to:agents);check(false,"symlink handoff rejected")}catch{check(true,"symlink handoff rejected")}
}

@MainActor private var focusedReviewWindow:NSWindow?
@MainActor private var focusedSettingsWindow:NSWindow?
@MainActor func showFocusedReview() throws {
    precondition(IslandRuntime.isSkinPreview)
    NookEditMenu.installIfNeeded()
    let store=WorkspaceStore(root:FileManager.default.temporaryDirectory.appendingPathComponent("focused-native-"+UUID().uuidString),startTimers:false)
    let done=try store.addTodo(title:"通过一段通用提示词接入Agent");store.complete(done)
    _=try store.addTodo(title:"整理本周工作记录")
    _=try store.addTodo(title:"核对新版Agent提醒，确保多个工具同时工作时都能正常提示。")
    let agents=AgentStore.shared
    var p=agents.preferences;p.skinID="virxact";p.effectsEnabled=true;p.enabled=true;p.startAlerts=false;try agents.update(p)
    let appState=AppState();var appearance=appState.appearancePreferences;appearance.chromePalette = .light;appState.replaceAppearancePreferences(appearance)
    let settingsModel=UnifiedSettingsModel();settingsModel.appState=appState;settingsModel.visible=true;settingsModel.section = .agents
    let settings=NSWindow(contentRect:NSRect(x:100,y:100,width:1020,height:760),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
    settings.title="设置交互验证 · 合成数据";settings.isReleasedWhenClosed=false
    settings.contentView=NSHostingView(rootView:UnifiedSettingsRoot(model:settingsModel))
    settings.makeKeyAndOrderFront(nil);focusedSettingsWindow=settings
    let window=NSWindow(contentRect:NSRect(x:80,y:80,width:440,height:440),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    window.title="待办修复验证 · 合成数据";window.isReleasedWhenClosed=false
    window.contentView=NSHostingView(rootView:FocusedTodoReview(store:store,agents:agents))
    window.makeKeyAndOrderFront(nil);focusedReviewWindow=window
    print("READY: isolated native todo and settings windows")
}
private struct FocusedTodoReview:View {
    @ObservedObject var store:WorkspaceStore
    @ObservedObject var agents:AgentStore
    @State private var dark=false
    var body:some View {
        let theme=NookResolvedTheme.resolve(theme:agents.selectedSkin.theme,preferences:.init(chromePalette:dark ? .dark:.light),effectiveColorScheme:dark ? .dark:.light,reduceTransparency:true)
        VStack(spacing:12) {
            HStack {Text("400×336点 · 合成数据").font(.system(size:12));Spacer();Button(dark ? "切换浅色":"切换深色"){dark.toggle()}}
            UnifiedTodoPanel(store:store).frame(width:400,height:336)
        }.padding(20).environment(\.nookResolvedTheme,theme).environment(\.nookTheme,agents.selectedSkin.theme)
            .environment(\.nookSurfaceAnimationActive,true).foregroundStyle(theme.primaryLabel)
            .background {IslandSkinBackdrop(store:agents,dark:dark,compact:false,notched:false).allowsHitTesting(false)}
            .preferredColorScheme(dark ? .dark:.light)
    }
}
