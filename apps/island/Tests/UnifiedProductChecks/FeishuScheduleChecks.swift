import AppKit
import SwiftUI
import NookApp
@testable import IslandShell

@MainActor func runFeishuScheduleChecks(check: @escaping (Bool,String)->Void, renderTo: URL?) async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("schedule-check-"+UUID().uuidString)
    let store=WorkspaceStore(root:root,startTimers:false)
    let account=LocalFeishuAccount(appID:"cli_fixture",openID:"ou_fixture",userName:"合成账号")
    let connection=FeishuConnection(cliPath:"/fixture/cli",profile:"fixture",localAccount:account)
    let now=Date(),start=now.addingTimeInterval(86400*2)
    var event=FeishuScheduleEvent(id:"recurring_1",title:"项目方案讨论",start:start,end:start.addingTimeInterval(3600),allDay:false,appLink:nil)
    var state=FeishuScheduleState(accountKey:FeishuScheduleState.key(connection)!)
    state.apply([event],calendarID:"primary",now:now)
    check(state.events.count==1 && state.events[0].offsets==[1440,15],"import creates default one day and fifteen minutes")
    state.apply([event,event].uniquedSchedule(),calendarID:"primary",now:now)
    check(state.events.count==1,"repeated synchronization stays one card")
    _=store.mutate{$0.feishuSchedule=state}
    let task=try store.addTodo(title:"普通待办保留")
    store.complete(task,now:now)
    let beforeTasks=store.disk.items,beforeHistory=store.disk.todoHistory
    try store.setScheduleReminders(event.id,offsets:[60,15,60],now:now)
    check(store.disk.feishuSchedule!.events[0].offsets==[60,15],"custom schedule reminders deduplicate")
    event.start=start.addingTimeInterval(7200);event.end=event.start.addingTimeInterval(3600)
    _=store.mutate{$0.feishuSchedule?.apply([event],calendarID:"primary",now:now)}
    check(store.disk.feishuSchedule!.events[0].start==event.start && store.disk.feishuSchedule!.events[0].offsets==[60,15],"reschedule preserves user's offsets")
    var notifications:[String]=[];store.notify={notifications.append($0)}
    store.tickReminders(now:event.start.addingTimeInterval(-3600))
    store.tickReminders(now:event.start.addingTimeInterval(-3599))
    check(notifications.count==1,"first reminder fires once")
    let reload=WorkspaceStore(root:root,startTimers:false);reload.notify={notifications.append($0)}
    reload.tickReminders(now:event.start.addingTimeInterval(-3598))
    check(notifications.count==1,"consumed reminders survive restart")
    reload.tickReminders(now:event.start.addingTimeInterval(-900))
    check(notifications.count==2,"second reminder fires independently")
    _=reload.mutate{$0.feishuSchedule?.apply([],calendarID:"primary",now:now)}
    check(reload.disk.feishuSchedule?.events.isEmpty==true,"deleted event disappears after complete synchronization")
    reload.tickReminders(now:event.start)
    check(notifications.count==2,"cancelled event never fires")
    check(reload.disk.items==beforeTasks && reload.disk.todoHistory==beforeHistory,"calendar changes preserve ordinary tasks and history")
    let soon=FeishuScheduleEvent(id:"soon",title:"两小时后",start:now.addingTimeInterval(7200),end:now.addingTimeInterval(10800),allDay:false)
    _=reload.mutate{$0.feishuSchedule?.apply([soon],calendarID:"primary",now:now)}
    reload.tickReminders(now:now.addingTimeInterval(1));check(notifications.count==2,"import skips missed one day reminder")
    reload.tickReminders(now:soon.start.addingTimeInterval(-899));check(notifications.count==3,"near event retains future fifteen minute reminder")
    try reload.setScheduleReminders(soon.id,offsets:[],now:now)
    check(reload.disk.feishuSchedule?.events.first{$0.id==soon.id}?.offsets.isEmpty==true,"disable per-event reminders")
    do{try reload.setScheduleReminders(soon.id,offsets:[-1],now:now);check(false,"reject negative offsets")}catch{check(true,"reject negative offsets")}
    do{try reload.setScheduleReminders(soon.id,offsets:Array(repeating:15,count:13),now:now);check(false,"limit reminder count")}catch{check(true,"limit reminder count")}
    check(!LocalFeishuPurpose.calendar.scopes.contains("calendar:calendar.event:create") && !LocalFeishuPurpose.calendar.scopes.contains("calendar:calendar.event:update"),"calendar scope no longer requests writes")
    let raw:[String:Any]=["event_id":"all-day","summary":"全天活动","start_time":["date":"2026-11-01"],"end_time":["date":"2026-11-01"]]
    let allday=try FeishuScheduleClient.parse(raw)
    check(allday.allDay && Calendar.current.dateComponents([.day],from:allday.start,to:allday.end).day==1,"inclusive all day end covers full local day")
    let instance:[String:Any]=["event_id":"repeat-instance-123","summary":"每周例会","recurrence":"FREQ=WEEKLY","start_time":["timestamp":String(Int(start.timeIntervalSince1970))],"end_time":["timestamp":String(Int(start.timeIntervalSince1970+3600))]]
    check(try FeishuScheduleClient.parse(instance).id=="repeat-instance-123","expanded recurring occurrence accepted")
    do{_=try FeishuScheduleClient.parse(["event_id":"broken"]);check(false,"invalid events reject whole snapshot")}catch{check(true,"invalid events reject whole snapshot")}
    var client=FeishuScheduleClient(localConnection:connection)
    var methods:[String]=[]
    client.requestOverride={method,path,params in
        methods.append(method+" "+path)
        if path=="calendars/primary"{return ["calendars":[["user_id":"ou_fixture","calendar":["type":"primary","calendar_id":"primary"]]]]}
        check(params["start_time"] != nil && params["end_time"] != nil,"bounded future window in read query")
        return ["items":[instance,instance]]
    }
    check(try await client.primary()=="primary","primary calendar matched to bound user")
    check(try await client.events(calendarID:"primary",from:now,to:now.addingTimeInterval(30*86400)).count==1,"duplicate API instances deduplicate")
    check(methods==["POST calendars/primary","GET calendars/primary/events/instance_view"],"only documented read endpoints called")
    client.requestOverride={_,_,_ in [:]}
    check(try await client.events(calendarID:"primary",from:now,to:now.addingTimeInterval(86400)).isEmpty,"official empty data response represents empty calendar")
    client.requestOverride={_,_,_ in ["items":"bad"]}
    do{_=try await client.events(calendarID:"primary",from:now,to:now.addingTimeInterval(86400));check(false,"malformed list rejected")}catch{check(true,"malformed list rejected")}
    reload.removeScheduleEvent(soon.id)
    check(reload.disk.feishuSchedule?.events.isEmpty == true, "local calendar removal removes reminders")
    let afterRemoval=WorkspaceStore(root:root,startTimers:false)
    _=afterRemoval.mutate{$0.feishuSchedule?.apply([soon],calendarID:"primary",now:now)}
    check(afterRemoval.disk.feishuSchedule?.events.isEmpty == true, "local calendar removal persists through restart and resync")
    check(afterRemoval.disk.items == beforeTasks, "calendar removal preserves ordinary todos")
    check(!afterRemoval.restoreScheduleEvent(soon,accountKey:"different-account"),"undo cannot restore into a different account")
    check(afterRemoval.restoreScheduleEvent(soon,accountKey:state.accountKey),"local deletion can be undone for the original account")
    check(!afterRemoval.restoreScheduleEvent(soon,accountKey:state.accountKey),"repeated undo cannot duplicate an event")
    var different=connection;different.localAccount=LocalFeishuAccount(appID:"cli_fixture",openID:"ou_other",userName:"另一合成账号")
    check(reload.activateFeishuSchedule(different) && reload.disk.feishuSchedule!.events.isEmpty,"changing account clears previous schedule state")
    check(reload.disk.items==beforeTasks && reload.disk.todoHistory==beforeHistory,"account isolation preserves other data")
    // Legacy optional fields disappear on save; task content remains byte-for-byte equivalent after decoding.
    let encoder=JSONEncoder(),bytes=try encoder.encode(store.disk)
    var legacy=try JSONSerialization.jsonObject(with:bytes) as! [String:Any]
    legacy["calendarSyncEnabled"]=true
    var items=legacy["items"] as! [[String:Any]];items[0]["calendarSync"]=true;items[0]["calendarLink"]=["eventID":"old"];items[0]["calendarError"]="old";legacy["items"]=items
    let decoded=try JSONDecoder().decode(WorkDisk.self,from:JSONSerialization.data(withJSONObject:legacy))
    let cleaned=String(decoding:try encoder.encode(decoded),as:UTF8.self)
    check(!cleaned.contains("calendarSync") && !cleaned.contains("calendarLink") && !cleaned.contains("calendarError"),"old write-sync records removed from persisted data")
    check(decoded.items==store.disk.items,"legacy record cleanup preserves tasks")
    let restoredEvent=store.todoHistory[0]
    try store.reopenTodoCompletion(restoredEvent);try store.reopenTodoCompletion(restoredEvent)
    check(store.pendingTodos.filter{$0.id==restoredEvent.taskID}.count==1 && store.todoHistory.count==1,"history reopen is idempotent and keeps completion record")
    check(store.pendingTodos[0].due==nil && store.pendingTodos[0].todoReminder==nil,"history reopen leaves old reminder disabled")
    let missing=WorkTodoCompletion(taskID:UUID(),title:"旧完成记录",content:"旧内容",completedAt:now)
    try store.reopenTodoCompletion(missing);try store.reopenTodoCompletion(missing)
    check(store.pendingTodos.filter{$0.id==missing.taskID}.count==1,"historical record without task can be reopened once")
    var gated=FeishuScheduleState(accountKey:"fixture");gated.apply([event],calendarID:"fixture",now:now)
    _=store.mutate{$0.feishuSchedule=gated}
    let countBefore=notifications.count
    store.remindersAreLocked={true};store.tickReminders(now:event.start.addingTimeInterval(-900))
    check(notifications.count==countBefore,"lock prevents calendar reminders")
    store.remindersAreLocked={false};_=store.mutate{$0.feishuSchedule?.enabled=false};store.tickReminders(now:event.start.addingTimeInterval(-900))
    check(notifications.count==countBefore,"paused calendar prevents reminders")
    _=store.mutate{$0.feishuSchedule?.enabled=true};store.tickReminders(now:event.end.addingTimeInterval(1))
    check(notifications.count==countBefore,"ended events do not catch up after sleep")
    if let renderTo {
        try FileManager.default.createDirectory(at:renderTo,withIntermediateDirectories:true)
        let fixtures=WorkspaceStore(root:root.appendingPathComponent("render"),startTimers:false)
        _=fixtures.mutate{$0.feishuSchedule=state;$0.todoCompletionEncouragement=true}
        fixtures.calendarStatus="已同步2个日程 · 刚刚"
        for (title,offset) in [("整理本周完成记录",0),("核对新版交互",-3600),("整理项目参考资料",-86400)] {
            let id=try fixtures.addTodo(title:title);fixtures.complete(id,now:now.addingTimeInterval(Double(offset)))
        }
        var second=event;second.id="meeting-2";second.title="产品体验评审";second.start=start.addingTimeInterval(86400);second.end=second.start.addingTimeInterval(5400)
        _=fixtures.mutate{$0.feishuSchedule?.apply([event,second],calendarID:"primary",now:now)}
        func shot<V:View>(_ view:V,_ name:String,_ size:CGSize) async throws {
            let theme=NookResolvedTheme.resolve(theme:AgentStore.shared.selectedSkin.theme,preferences:.init(chromePalette:.light),effectiveColorScheme:.light,reduceTransparency:true)
            let host=NSHostingView(rootView:view.frame(width:size.width,height:size.height).environment(\.nookResolvedTheme,theme).environment(\.nookTheme,AgentStore.shared.selectedSkin.theme).preferredColorScheme(.light).foregroundStyle(theme.primaryLabel).background(Color.white))
            let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.borderless],backing:.buffered,defer:false)
            window.contentView=host;host.layoutSubtreeIfNeeded()
            try await Task.sleep(for:.milliseconds(250))
            guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else{throw WorkError.message("无法渲染待办画面。")}
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:renderTo.appendingPathComponent(name+".png"));window.orderOut(nil)
        }
        try await shot(ScrollView{UnifiedTodoSettings(store:fixtures).padding(28)},"todo-settings",CGSize(width:750,height:1250))
        fixtures.todoPage="calendar"
        try await shot(UnifiedTodoPanel(store:fixtures),"todo-island",CGSize(width:400,height:350))
        let empty=WorkspaceStore(root:root.appendingPathComponent("empty"),startTimers:false)
        try await shot(UnifiedTodoPanel(store:empty),"todo-empty",CGSize(width:400,height:350))
    }
    if CommandLine.arguments.contains("--real-calendar-read") {
        guard let connection=LocalFeishuBindings.connection(.calendar,defaults:UserDefaults(suiteName:"local.zaizhi.feishu-island.preview")!) else{throw WorkError.message("没有本机日历绑定。")}
        let client=FeishuScheduleClient(localConnection:connection)
        let primary=try await client.primary()
        let events=try await client.events(calendarID:primary,from:now,to:Calendar.current.date(byAdding:.day,value:30,to:now)!)
        print("REAL CALENDAR READ: verified bound primary; \(events.count) events; no event write requests")
    }
}
private extension Array where Element==FeishuScheduleEvent {
    func uniquedSchedule()->Self {Array(Dictionary(map{($0.id,$0)},uniquingKeysWith:{a,_ in a}).values)}
}

@MainActor private var todoReviewWindow: NSWindow?
@MainActor func showTodoReview() throws {
    let store=WorkspaceStore(root:FileManager.default.temporaryDirectory.appendingPathComponent("todo-ui-review-"+UUID().uuidString),startTimers:false)
    let now=Date()
    for (title,offset) in [("整理本周完成记录",0),("核对新版交互",-3600),("整理项目参考资料",-86400)] {
        let id=try store.addTodo(title:title);store.complete(id,now:now.addingTimeInterval(Double(offset)))
    }
    let a=FeishuScheduleEvent(id:"one",title:"项目方案讨论",start:now.addingTimeInterval(2*86400),end:now.addingTimeInterval(2*86400+3600),allDay:false)
    let b=FeishuScheduleEvent(id:"two",title:"产品体验评审",start:now.addingTimeInterval(3*86400),end:now.addingTimeInterval(3*86400+5400),allDay:false)
    _=store.mutate{$0.feishuSchedule=FeishuScheduleState(accountKey:"fixture",events:[a,b],lastSync:now);$0.todoCompletionEncouragement=true}
    store.calendarStatus="已同步2个日程 · 合成验证";store.todoPage="calendar"
    let theme=NookResolvedTheme.resolve(theme:AgentStore.shared.selectedSkin.theme,preferences:.init(chromePalette:.light),effectiveColorScheme:.light,reduceTransparency:true)
    let root=HStack(alignment:.top,spacing:24) {
        VStack(alignment:.leading,spacing:20){Text("岛内交互 · 400点").font(.headline);UnifiedTodoPanel(store:store).frame(width:400,height:336);Spacer()}.padding(20)
        ScrollView{TodoCompletionHistory(store:store).padding(24)}.frame(width:680)
    }.frame(height:640).environment(\.nookResolvedTheme,theme).environment(\.nookTheme,AgentStore.shared.selectedSkin.theme).preferredColorScheme(.light).foregroundStyle(theme.primaryLabel).background(Color.white)
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1144,height:640),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    window.title="待办交互验证 · 合成数据";window.isReleasedWhenClosed=false;window.contentView=NSHostingView(rootView:root);window.center();window.makeKeyAndOrderFront(nil);todoReviewWindow=window
}
