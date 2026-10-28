import AppKit
import Foundation
@testable import IslandShell

@MainActor func runSystemAuditFixChecks(check:(Bool,String)->Void) throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("audit-fix-"+UUID().uuidString)
    let now=Date()
    let store=WorkspaceStore(root:root.appendingPathComponent("todos"),startTimers:false)
    let done=try store.addTodo(title:"完成记录A",details:"A的完整补充说明",now:now)
    store.complete(done,now:now)
    _=try store.addTodo(title:"无关的待办B",now:now)
    let copied=store.completionRecordsText(store.todoHistory)
    check(copied.contains("完成记录A") && copied.contains("A的完整补充说明"),"completion copy includes full selected content")
    check(!copied.contains("无关的待办B") && !copied.contains("请根据"),"completion copy excludes pending tasks and instructions")
    check(store.completionRecordsText([])=="这段时间没有完成记录。","empty completion copy has no unrelated content")
    let event=FeishuScheduleEvent(id:"event",title:"合成日程",start:now.addingTimeInterval(900),end:now.addingTimeInterval(1800),allDay:false,offsets:[15])
    _=store.mutate{$0.feishuSchedule=FeishuScheduleState(accountKey:"synthetic",events:[event])}
    store.todoDraft="尚未保存的草稿";store.todoPage="tasks";store.tickFeishuSchedules(now:now)
    check(store.todoPage=="tasks" && store.todoDraft=="尚未保存的草稿","reminder preserves selected page and draft")
    check(store.hasUnviewedScheduleReminder,"calendar reminder remains discoverable")
    store.todoPage="calendar";check(!store.hasUnviewedScheduleReminder,"explicit calendar navigation clears pending marker")

    var invalidPreferences=AgentPreferences();invalidPreferences.profiles=[]
    for invalid in [Data("{broken}".utf8),try JSONEncoder().encode(invalidPreferences)] {
        let suite="audit-agent-"+UUID().uuidString
        // The suite used below is isolated and contains no real account data.
        let isolated=UserDefaults(suiteName:suite)!
        defer {isolated.removePersistentDomain(forName:suite)}
        isolated.set(invalid,forKey:"preferences")
        let agents=AgentStore(defaults:isolated,allowsLiveReads:false,sessionIsLocked:{false})
        check(agents.preferencesReadError != nil && !agents.preferences.enabled,"invalid Agent configuration pauses monitoring")
        agents.selectSkin("virxact");agents.selectPrimary("workbuddy")
        check(isolated.data(forKey:"preferences")==invalid,"ordinary Agent changes preserve unreadable bytes")
        let exported=root.appendingPathComponent(UUID().uuidString+".json")
        try agents.exportOriginalPreferences(to:exported)
        check(try Data(contentsOf:exported)==invalid,"recovery export preserves original bytes")
        agents.reloadPreferences();check(agents.preferencesReadError != nil,"failed reload remains protected")
        let valid=try JSONEncoder().encode(AgentPreferences())
        let repaired=root.appendingPathComponent(UUID().uuidString+".json");try valid.write(to:repaired)
        do {try agents.restorePreferences(from:exported);check(false,"invalid import rejected")} catch {check(isolated.data(forKey:"preferences")==invalid,"invalid recovery import preserves original")}
        try agents.restorePreferences(from:repaired)
        let backupKey=isolated.dictionaryRepresentation().keys.first{$0.hasPrefix("preferencesRecoveryBackup.")}
        check(backupKey.flatMap{isolated.data(forKey:$0)}==invalid,"explicit recovery keeps original bytes in backup")
        check(agents.preferencesReadError==nil && isolated.data(forKey:"preferences")==valid,"valid reload does not rewrite bytes")
        agents.selectSkin("virxact");check(agents.preferences.skinID=="virxact","normal changes resume after valid reload")
    }
    let batch=WorkspaceStore(root:root.appendingPathComponent("batch"),startTimers:false)
    _=try batch.addTodo(title:"合成待办",now:now.addingTimeInterval(-1200))
    _=batch.mutate{$0.defaultTodoScreen = .init();$0.items[0].screenReminder = .init();$0.feishuSchedule=FeishuScheduleState(accountKey:"synthetic",events:[event]);$0.restReminder=RestReminderPlan(enabled:true,fireAt:now)}
    var locked=false
    let presenter=ScreenReminderPresenter(displaysWindows:false,sessionIsLocked:{locked})
    let frame=CGRect(x:0,y:0,width:1000,height:800)
    var failures:[String]=[]
    batch.presentScreenReminder={request in do {try presenter.present(request,testFrame:frame)} catch {failures.append(error.localizedDescription)}}
    batch.tickReminders(now:now)
    check(presenter.deliveredTitles.count==1 && presenter.pendingCount==2,"simultaneous sources queue without replacing visible reminder")
    presenter.dismiss();presenter.dismiss()
    check(presenter.deliveredTitles.count==3 && presenter.deliveredTitles[1].contains("日程") && presenter.deliveredTitles[2].contains("待办"),"all three reminder sources are delivered in order")
    presenter.dismiss();batch.tickReminders(now:now)
    check(presenter.deliveredTitles.count==3 && failures.isEmpty,"consumed reminders are not replayed on next tick")
    let request=try batch.screenReminderRequest(style:.init(),title:"锁屏保留提醒")
    try presenter.present(request,testFrame:frame);try presenter.present(request,testFrame:frame)
    locked=true;presenter.suspendForLock()
    check(presenter.verificationWindows.isEmpty && presenter.pendingCount==2,"lock hides current and retains accepted reminders")
    locked=false;presenter.resumePending();check(presenter.pendingCount==1 && presenter.verificationWindows.count==2,"unlock resumes one reminder at a time")
    presenter.dismissAll();check(presenter.pendingCount==0 && presenter.verificationWindows.isEmpty,"explicit stop clears visible and waiting reminders")
    try presenter.present(request,testFrame:frame)
    for _ in 0..<32 {try presenter.present(request,testFrame:frame)}
    do {try presenter.present(request,testFrame:frame);check(false,"queue overflow rejected")} catch {check(presenter.pendingCount==32,"bounded queue rejects extra request for caller fallback")}
    presenter.dismissAll()
    // A queued video may disappear before presentation; fall back and continue, never wedge the queue.
    try presenter.present(request,testFrame:frame)
    let video=root.appendingPathComponent("synthetic.mov");try Data([0]).write(to:video)
    let videoRequest=ScreenReminderRequest(title:"失效素材",style:.init(),material:.init(id:"video",name:"合成",durationSeconds:8,hasAlpha:true),videoURL:video)
    try presenter.present(videoRequest,testFrame:frame);try presenter.present(request,testFrame:frame)
    try FileManager.default.moveItem(at:video,to:root.appendingPathComponent("moved.mov"))
    presenter.deliveryFailed={r,_ in failures.append(r.title)};presenter.dismiss()
    check(failures==["失效素材"] && presenter.pendingCount==0 && presenter.verificationWindows.count==2,"failed queued delivery falls back and advances")
    presenter.dismissAll()

    let media="custom"
    _=store.mutate{$0.screenMaterials=[.init(id:media,name:"合成视频",durationSeconds:8,hasAlpha:true)];$0.defaultTodoScreen = .init(materialID:media)}
    check(store.materialIsUsed(media),"default todo and schedule material is protected")
    store.removeScreenMaterial(media);check(store.screenMaterials.contains{$0.id==media},"referenced material cannot be removed")
    _=store.mutate{$0.defaultTodoScreen=nil;$0.items[0].completionReminder = .init(materialID:media);$0.items[0].archivedAt=now}
    check(store.materialIsUsed(media),"archived completion effect remains protected")
    _=store.mutate{$0.trash=[$0.items.removeFirst()]}
    check(store.materialIsUsed(media),"recoverable trash effect remains protected")
    _=store.mutate{$0.trash?[0].completionReminder=nil}
    check(!store.materialIsUsed(media),"unreferenced material can be removed")

    let archiveRoot=root.appendingPathComponent("archive"),archive=WorkspaceStore(root:root.appendingPathComponent("archive"),startTimers:false)
    let id=try archive.addTodo(title:"失败后仍保留",now:now);archive.complete(id,now:now)
    let file=archiveRoot.appendingPathComponent("workspace.json")
    try FileManager.default.moveItem(at:file,to:archiveRoot.appendingPathComponent("before.json"));try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
    check(!archive.archiveCompletedTodos(now:now) && archive.completedTodos.contains{$0.id==id},"archive failure reports false and retains completed item")
    try FileManager.default.moveItem(at:file,to:archiveRoot.appendingPathComponent("obstruction"))
    check(archive.archiveCompletedTodos(now:now) && archive.completedTodos.isEmpty,"archive success is reported only after durable save")

    for state in ["running","pending"] {
        for intent:String? in [nil,"write_document"] {
            let dir=root.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            var disk=WorkDisk(),item=WorkItem(title:"旧记录",input:"保留原正文",instruction:"原指令",service:"todo")
            item.archive=WorkArchiveReceipt(target:.init(mode:"new"),digest:"original",state:state,document:"original-document",intent:intent)
            disk.items=[item];var trashed=item;trashed.id=UUID();disk.trash=[trashed];try JSONEncoder().encode(disk).write(to:dir.appendingPathComponent("workspace.json"))
            let recovery=WorkspaceStore(root:dir,startTimers:false),recovered=recovery.disk.items[0]
            check(WorkspaceStore.canEdit(recovery.disk.trash![0])==(intent==nil),"recoverable legacy trash gets the same lock migration")
            check(WorkspaceStore.canEdit(recovered)==(intent==nil),"legacy lock reflects unresolved write intent")
            check(recovered.archive?.document=="original-document" && recovered.archive?.digest=="original" && recovered.archive?.intent==intent,"legacy receipt remains intact")
        }
    }
}

@MainActor func runScreenQueueTimerReview() async throws {
    NSApplication.shared.setActivationPolicy(.accessory)
    let presenter=ScreenReminderPresenter(sessionIsLocked:{false})
    for title in ["第一条 · 合成休息提醒","第二条 · 合成日程提醒","第三条 · 合成待办提醒"] {
        try presenter.present(ScreenReminderRequest(title:title,style:.init(durationSeconds:2),material:.init(id:"cat",name:"测试",durationSeconds:0.1,hasAlpha:true)))
    }
    guard presenter.verificationWindows.allSatisfy({$0.isVisible}) else {throw WorkError.message("屏幕提醒窗口不可见")}
    try await Task.sleep(for:.seconds(2.5))
    guard presenter.presentationCount==2,presenter.pendingCount==1 else {throw WorkError.message("第二条计时交接失败")}
    try await Task.sleep(for:.seconds(2))
    guard presenter.presentationCount==3,presenter.pendingCount==0 else {throw WorkError.message("第三条计时交接失败")}
    try await Task.sleep(for:.seconds(2))
    guard !presenter.isPresenting,presenter.verificationWindows.isEmpty else {throw WorkError.message("最终提醒未收起")}
    print("PASS: three actual screen reminders delivered by timers in order and dismissed")
}
