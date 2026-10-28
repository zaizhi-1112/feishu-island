import AppKit
import Foundation
import NookApp
import SwiftUI
@testable import IslandShell

/// Diagnostic evidence, not a passing regression suite. Uses only synthetic stores.
@MainActor func runSystemAuditProbes() throws {
    precondition(IslandRuntime.isSkinPreview)
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("system-audit-"+UUID().uuidString)
    var evidence:[String:Any]=[:]
    let now=Date()
    let store=WorkspaceStore(root:root.appendingPathComponent("todos"),startTimers:false)
    let done=try store.addTodo(title:"选中的完成记录",details:"这条记录的补充说明",now:now)
    store.complete(done,now:now)
    _=try store.addTodo(title:"与所选记录无关的待办",now:now)
    let copy=store.completionRecordsText([store.todoHistory[0]])
    evidence["singleRecordCopyIncludesUnrelatedTodo"]=copy.contains("与所选记录无关的待办")

    let event=FeishuScheduleEvent(id:"synthetic",title:"合成日程",start:now.addingTimeInterval(900),end:now.addingTimeInterval(1800),allDay:false,offsets:[15])
    _=store.mutate{$0.feishuSchedule=FeishuScheduleState(accountKey:"synthetic",events:[event])}
    store.todoPage="tasks"
    store.tickFeishuSchedules(now:now)
    evidence["scheduleChangesSelectedTodoPage"]=store.todoPage

    let mediaID="synthetic-media"
    _=store.mutate{
        $0.screenMaterials=[.init(id:mediaID,name:"合成素材",filename:nil,durationSeconds:8,hasAlpha:true)]
        $0.defaultTodoScreen = .init(materialID:mediaID)
    }
    evidence["defaultMaterialReportedInUse"]=store.materialIsUsed(mediaID)
    store.removeScreenMaterial(mediaID)
    evidence["removedDefaultMaterialStillSelected"]=store.disk.defaultTodoScreen?.materialID==mediaID && !store.screenMaterials.contains{$0.id==mediaID}

    let suite="system-audit-agent-"+UUID().uuidString
    let defaults=UserDefaults(suiteName:suite)!
    defer{defaults.removePersistentDomain(forName:suite)}
    let original=Data("{invalid synthetic preferences}".utf8)
    defaults.set(original,forKey:"preferences")
    let agents=AgentStore(defaults:defaults,allowsLiveReads:false,sessionIsLocked:{false})
    agents.selectSkin("virxact")
    evidence["damagedAgentPreferencesOverwrittenBySkinChange"]=defaults.data(forKey:"preferences") != original

    let batch=WorkspaceStore(root:root.appendingPathComponent("batch"),startTimers:false)
    let task=try batch.addTodo(title:"合成待办提醒",now:now.addingTimeInterval(-1200))
    _=batch.mutate{
        $0.defaultTodoScreen = .init()
        $0.items[0].screenReminder = .init()
        $0.feishuSchedule=FeishuScheduleState(accountKey:"synthetic",events:[event])
        $0.restReminder=RestReminderPlan(enabled:true,fireAt:now)
    }
    var shown:[String]=[]
    batch.presentScreenReminder={shown.append($0.title)}
    batch.tickReminders(now:now)
    evidence["sameTickScreenRequests"]=shown
    evidence["sameTickTodoConsumed"]=batch.disk.items.first{$0.id==task}?.reminded==true
    evidence["sameTickRestAdvanced"]=batch.restPlan.fireAt.map{$0>now}==true
    evidence["sameTickCalendarConsumed"]=batch.disk.feishuSchedule?.events.first?.consumed.isEmpty==false

    let archiveRoot=root.appendingPathComponent("archive")
    let archive=WorkspaceStore(root:archiveRoot,startTimers:false)
    let id=try archive.addTodo(title:"合成归档失败",now:now);archive.complete(id,now:now)
    let file=archiveRoot.appendingPathComponent("workspace.json")
    try FileManager.default.moveItem(at:file,to:archiveRoot.appendingPathComponent("before.json"))
    try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
    archive.archiveCompletedTodos(now:now)
    evidence["archiveSaveFailureLeavesCompletedRow"]=archive.completedTodos.contains{$0.id==id}
    evidence["archiveSaveFailureError"]=archive.error

    let recoveryRoot=root.appendingPathComponent("legacy")
    var disk=WorkDisk()
    var legacy=WorkItem(title:"旧版归档中断任务",input:"保留正文",instruction:"旧处理要求",service:"todo")
    legacy.archive=WorkArchiveReceipt(target:.init(mode:"new"),digest:"synthetic",state:"running")
    disk.items=[legacy]
    try FileManager.default.createDirectory(at:recoveryRoot,withIntermediateDirectories:true)
    try JSONEncoder().encode(disk).write(to:recoveryRoot.appendingPathComponent("workspace.json"))
    let recovery=WorkspaceStore(root:recoveryRoot,startTimers:false)
    evidence["legacyArchiveAfterRestart"]=recovery.disk.items[0].archive?.state ?? "none"
    evidence["legacyArchiveTaskCanEdit"]=WorkspaceStore.canEdit(recovery.disk.items[0])
    let bytes=try JSONSerialization.data(withJSONObject:evidence,options:[.prettyPrinted,.sortedKeys])
    print(String(decoding:bytes,as:UTF8.self))
}

@MainActor private var systemAuditWindow:NSWindow?
@MainActor func showSystemAuditReview() throws {
    precondition(IslandRuntime.isSkinPreview)
    NookEditMenu.installIfNeeded()
    let store=WorkspaceStore(root:FileManager.default.temporaryDirectory.appendingPathComponent("native-audit-"+UUID().uuidString),startTimers:false)
    let id=try store.addTodo(title:"已经整理好本周的工作记录，也核对了待办提醒与日程安排。完成记录需要保留清楚、完整的文字，方便以后回看具体做了什么。",details:"已逐项核对提醒时间、完成记录和保存结果。\n这段补充说明在任务完成后仍然可以完整查看，不需要重新打开待办。\n第三项：保留长正文的阅读空间，直接复制所选记录。")
    store.complete(id)
    _=try store.addTodo(title:"核对新的完成记录显示",details:"这是补充说明，完成后也应该能回看。")
    _=store.mutate{$0.screenSchedules=[WorkScreenSchedule(title:"午饭后散步",fireAt:Date().addingTimeInterval(3600),repeatMinutes:60),WorkScreenSchedule(title:"晚间复盘",fireAt:Date().addingTimeInterval(7200),enabled:false)]}
    let agents=AgentStore.shared
    var p=agents.preferences;p.skinID="virxact";p.effectsEnabled=false;try agents.update(p)
    let window=NSWindow(contentRect:NSRect(x:90,y:120,width:800,height:690),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    window.title="项目审查 · 隔离合成数据";window.isReleasedWhenClosed=false
    window.contentView=NSHostingView(rootView:SystemAuditReview(store:store,agents:agents))
    window.makeKeyAndOrderFront(nil);systemAuditWindow=window
    print("READY: audit window; synthetic data only")
}
private struct SystemAuditReview:View {
    @ObservedObject var store:WorkspaceStore
    @ObservedObject var agents:AgentStore
    @State private var dark=false
    @State private var page="island"
    @StateObject private var recovery=AgentStore(defaults:{
        let defaults=UserDefaults(suiteName:"audit-recovery-preview")!
        defaults.set(Data("{synthetic invalid}".utf8),forKey:"preferences")
        return defaults
    }(),allowsLiveReads:false,sessionIsLocked:{false})
    var body:some View {
        let theme=NookResolvedTheme.resolve(theme:agents.selectedSkin.theme,preferences:.init(chromePalette:dark ? .dark:.light),effectiveColorScheme:dark ? .dark:.light,reduceTransparency:true)
        VStack(spacing:10) {
            HStack {Text("原生界面验收 · 合成数据");Spacer();Button(dark ? "切换浅色":"切换深色"){dark.toggle()}}.font(.system(size:12))
            HStack {Button("触发合成日程提醒"){
                let now=Date()
                _=store.mutate{$0.feishuSchedule=FeishuScheduleState(accountKey:"synthetic",events:[.init(id:UUID().uuidString,title:"编辑中到达的合成日程",start:now,end:now.addingTimeInterval(1800),allDay:false,offsets:[0])])}
                store.tickFeishuSchedules(now:now)
            };Spacer()}.font(.system(size:12))
            Picker("验收页面",selection:$page) {Text("岛内待办").tag("island");Text("完成记录").tag("history");Text("休息设置").tag("rest");Text("配置恢复").tag("recovery")}.pickerStyle(.segmented)
            if page=="island" {UnifiedTodoPanel(store:store).frame(width:400,height:336);Spacer()}
            else {ScrollView {if page=="history" {TodoCompletionHistory(store:store)} else if page=="rest" {UnifiedRestSettings(store:store)} else {AgentPreferencesRecovery(store:recovery)}}.frame(maxWidth:.infinity,maxHeight:.infinity)}
        }.padding(20).environment(\.nookResolvedTheme,theme).environment(\.nookTheme,agents.selectedSkin.theme)
            .foregroundStyle(theme.primaryLabel)
            .background{IslandSkinBackdrop(store:agents,dark:dark,compact:false,notched:false).allowsHitTesting(false)}
            .toggleStyle(.switch).preferredColorScheme(dark ? .dark:.light)
    }
}
