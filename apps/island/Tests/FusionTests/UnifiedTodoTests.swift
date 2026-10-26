import AppKit
import Foundation
import SwiftUI
import NookApp
@testable import IslandShell

extension FusionTests {
    @MainActor func testUnifiedTodoPersistenceAndReminders() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("unified-todo-check-"+UUID().uuidString)
        let store=WorkspaceStore(root:root,startTimers:false)
        let start=Date()
        var notices=0, screens:[ScreenReminderRequest]=[]
        store.notify={_ in notices+=1}; store.presentScreenReminder={screens.append($0)}
        let first=try store.addTodo(title:"合成任务：整理反馈",details:"保留全部任务内容",now:start)
        let second=try store.addTodo(title:"合成任务：检查进度",now:start)
        XCTAssertEqual(store.pendingTodos.count,2)
        XCTAssertEqual(store.disk.items.first(where:{$0.id==first})?.service,"todo")
        XCTAssertNil(store.disk.items.first(where:{$0.id==first})?.archiveTarget)
        XCTAssertNil(store.disk.items.first(where:{$0.id==first})?.due)
        XCTAssertEqual(store.disk.items.first(where:{$0.id==first})?.instruction,"")
        let style=ScreenReminderStyle(materialID:"cat",durationSeconds:10)
        XCTAssertTrue(try store.configureTodoReminder(first,dates:[start.addingTimeInterval(60),start.addingTimeInterval(120),start.addingTimeInterval(180)],completionStyle:style,now:start))
        store.tickReminders(now:start.addingTimeInterval(61)); store.tickReminders(now:start.addingTimeInterval(62))
        XCTAssertEqual(notices,1); XCTAssertEqual(screens.count,0)
        XCTAssertEqual(store.disk.items.first(where:{$0.id==first})?.due,start.addingTimeInterval(120))
        let reload=WorkspaceStore(root:root,startTimers:false)
        reload.notify={_ in notices+=1}; reload.presentScreenReminder={screens.append($0)}
        reload.tickReminders(now:start.addingTimeInterval(63)); XCTAssertEqual(notices,1)
        reload.tickReminders(now:start.addingTimeInterval(181)); XCTAssertEqual(notices,2)
        reload.tickReminders(now:start.addingTimeInterval(182)); XCTAssertEqual(notices,2)
        XCTAssertTrue(reload.disk.items.first(where:{$0.id==first})?.reminded == true)
        reload.complete(first,now:start.addingTimeInterval(190)); reload.complete(first,now:start.addingTimeInterval(191))
        XCTAssertEqual(screens.count,1); XCTAssertEqual(reload.todoHistory.count,1)
        XCTAssertEqual(reload.todoHistory.first?.completedAt,start.addingTimeInterval(190))
        XCTAssertEqual(reload.todoHistory.first?.content,"保留全部任务内容")
        XCTAssertEqual(reload.pendingTodos.map(\.id),[second]); XCTAssertEqual(reload.completedTodos.map(\.id),[first])
        reload.archiveItem(first); XCTAssertTrue(reload.completedTodos.isEmpty); XCTAssertEqual(reload.archivedTodos.map(\.id),[first])
        let historyReload=WorkspaceStore(root:root,startTimers:false)
        historyReload.tickReminders(now:start.addingTimeInterval(10*366*86400))
        XCTAssertEqual(historyReload.todoHistory.count,1); XCTAssertEqual(historyReload.archivedTodos.count,1)
        historyReload.unarchiveItem(first); XCTAssertEqual(historyReload.completedTodos.count,1)
        historyReload.reopenTodo(first); XCTAssertEqual(historyReload.todoHistory.count,1); XCTAssertEqual(historyReload.pendingTodos.count,2)
        historyReload.complete(first,now:start.addingTimeInterval(300)); XCTAssertEqual(historyReload.todoHistory.count,2)
        let export=root.appendingPathComponent("history.json"); try historyReload.exportTodoHistory(to:export)
        let exported=try JSONSerialization.jsonObject(with:Data(contentsOf:export)) as! [String:Any]
        XCTAssertEqual(exported["schema_version"] as? Int,1); XCTAssertEqual(exported["retention"] as? String,"indefinite")
        XCTAssertEqual((exported["completions"] as? [[String:Any]])?.count,2)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath:export.path)[.posixPermissions] as? Int,0o600)

        // Only chosen completions fold away; the decision survives relaunch and never changes history.
        let foldRoot=root.appendingPathComponent("selective-folding")
        let foldStore=WorkspaceStore(root:foldRoot,startTimers:false)
        let folded=try foldStore.addTodo(title:"折叠这项",now:start)
        let visible=try foldStore.addTodo(title:"这项仍在底部",now:start)
        let unfinished=try foldStore.addTodo(title:"未完成仍在前",now:start)
        foldStore.complete(folded,now:start);foldStore.complete(visible,now:start.addingTimeInterval(1))
        XCTAssertEqual(foldStore.unfoldedCompletedTodos.count,2);XCTAssertTrue(foldStore.foldedCompletedTodos.isEmpty)
        foldStore.setTodoCollapsed(folded,collapsed:true);foldStore.setTodoCollapsed(unfinished,collapsed:true)
        XCTAssertEqual(foldStore.foldedCompletedTodos.map(\.id),[folded])
        XCTAssertEqual(foldStore.unfoldedCompletedTodos.map(\.id),[visible])
        XCTAssertEqual(foldStore.pendingTodos.map(\.id),[unfinished]);XCTAssertEqual(foldStore.todoHistory.count,2)
        let foldReload=WorkspaceStore(root:foldRoot,startTimers:false)
        XCTAssertEqual(foldReload.foldedCompletedTodos.map(\.id),[folded])
        XCTAssertEqual(foldReload.unfoldedCompletedTodos.map(\.id),[visible])
        foldReload.archiveItem(folded);XCTAssertTrue(foldReload.foldedCompletedTodos.isEmpty)
        XCTAssertEqual(foldReload.todoHistory.count,2)
        foldReload.unarchiveItem(folded);XCTAssertEqual(foldReload.unfoldedCompletedTodos.count,2)
        foldReload.setTodoCollapsed(visible,collapsed:true);foldReload.reopenTodo(visible)
        XCTAssertTrue(foldReload.foldedCompletedTodos.isEmpty);XCTAssertEqual(foldReload.todoHistory.count,2)
        foldReload.complete(visible,now:start.addingTimeInterval(3))
        XCTAssertEqual(foldReload.unfoldedCompletedTodos.count,2);XCTAssertEqual(foldReload.todoHistory.count,3)

        let periodic=try historyReload.addTodo(title:"合成三小时任务",now:start)
        XCTAssertTrue(try historyReload.configureTodoReminder(periodic,dates:[start.addingTimeInterval(1800)],repeatMinutes:30,repeatUntil:start.addingTimeInterval(10800),now:start))
        var periodicNotices=0; historyReload.notify={_ in periodicNotices+=1}
        historyReload.tickReminders(now:start.addingTimeInterval(9000))
        XCTAssertEqual(periodicNotices,1); XCTAssertEqual(historyReload.disk.items.first(where:{$0.id==periodic})?.due,start.addingTimeInterval(10800))
        historyReload.tickReminders(now:start.addingTimeInterval(10801)); XCTAssertEqual(periodicNotices,2)
        historyReload.tickReminders(now:start.addingTimeInterval(20000)); XCTAssertEqual(periodicNotices,2)
        let before=historyReload.disk.items.first(where:{$0.id==periodic})
        do { _=try historyReload.configureTodoReminder(periodic,dates:[start.addingTimeInterval(-1)],now:start,title:"错误写入"); XCTAssertTrue(false) }
        catch { XCTAssertEqual(historyReload.disk.items.first(where:{$0.id==periodic}),before) }
        do { _=try historyReload.configureTodoReminder(periodic,dates:[start.addingTimeInterval(100)],now:start,title:" "); XCTAssertTrue(false) }
        catch { XCTAssertEqual(historyReload.disk.items.first(where:{$0.id==periodic}),before) }

        let habit=try historyReload.upsertScreenSchedule(title:"合成喝水",firstFire:start.addingTimeInterval(60),repeatMinutes:30,style:.init(),lightOnly:true)
        var habitScreens=0; historyReload.presentScreenReminder={_ in habitScreens+=1}
        historyReload.tickReminders(now:start.addingTimeInterval(120)); XCTAssertEqual(habitScreens,0)
        XCTAssertTrue(historyReload.screenSchedules.first(where:{$0.id==habit})?.lightOnly == true)
        XCTAssertEqual(historyReload.screenSchedules.first(where:{$0.id==habit})?.fireAt,start.addingTimeInterval(1920))

        let routes=WorkspaceStore(root:root.appendingPathComponent("routes"),startTimers:false)
        var lightRoutes=0, screenRoutes=0, agentRoutes=0
        routes.notify={_ in lightRoutes+=1}; routes.presentScreenReminder={_ in screenRoutes+=1}; routes.agentNotice={_,_,_ in agentRoutes+=1}
        let screenTask=try routes.addTodo(title:"合成冲屏路径",now:start)
        XCTAssertTrue(try routes.configureTodoReminder(screenTask,dates:[start.addingTimeInterval(60)],style:style,completionStyle:style,now:start))
        routes.remindersAreLocked={true}; routes.tickReminders(now:start.addingTimeInterval(61))
        XCTAssertEqual(screenRoutes,0); XCTAssertEqual(lightRoutes,0); XCTAssertFalse(routes.disk.items[0].reminded)
        routes.remindersAreLocked={false}; routes.tickReminders(now:start.addingTimeInterval(62)); routes.tickReminders(now:start.addingTimeInterval(63))
        XCTAssertEqual(screenRoutes,1); XCTAssertEqual(lightRoutes,0); XCTAssertEqual(agentRoutes,0)
        let fallback=try routes.addTodo(title:"合成缺失素材",now:start)
        _=routes.mutate { state in
            guard let index=state.items.firstIndex(where:{$0.id==fallback}) else{return}
            state.items[index].due=start.addingTimeInterval(60); state.items[index].screenReminder = .init(materialID:"missing",durationSeconds:10)
        }
        routes.tickReminders(now:start.addingTimeInterval(64)); routes.tickReminders(now:start.addingTimeInterval(65))
        XCTAssertEqual(lightRoutes,1); XCTAssertEqual(screenRoutes,1); XCTAssertTrue(routes.error.contains("素材"))
        routes.remindersAreLocked={true}; routes.complete(screenTask,now:start.addingTimeInterval(66))
        XCTAssertEqual(screenRoutes,1); XCTAssertEqual(routes.todoHistory.count,1)

        // Legacy human completions have no invented date; all old payloads survive.
        let legacyRoot=root.appendingPathComponent("legacy-workspace")
        try FileManager.default.createDirectory(at:legacyRoot,withIntermediateDirectories:true)
        var legacyDisk=WorkDisk(); var old=WorkItem(title:"旧的已完成任务",input:"旧材料仍保留",instruction:"旧处理要求")
        old.state="done"; old.result="旧结果"; legacyDisk.items=[old]
        try JSONEncoder().encode(legacyDisk).write(to:legacyRoot.appendingPathComponent("workspace.json"))
        let migrated=WorkspaceStore(root:legacyRoot,startTimers:false)
        XCTAssertEqual(migrated.todoHistory.count,1); XCTAssertNil(migrated.todoHistory.first?.completedAt)
        XCTAssertEqual(migrated.todoHistory.first?.source,"legacy_time_unknown")
        XCTAssertEqual(migrated.disk.items[0].result,"旧结果"); XCTAssertEqual(migrated.disk.items[0].instruction,"旧处理要求")
        XCTAssertNil(migrated.disk.items[0].completedCollapsed);XCTAssertEqual(migrated.unfoldedCompletedTodos.count,1)
        XCTAssertEqual(WorkspaceStore(root:legacyRoot,startTimers:false).todoHistory.count,1)

        // Retired Dot leases must not leave an uneditable task when no worker is resumed.
        let retiredRoot=root.appendingPathComponent("retired-dot-workspace")
        try FileManager.default.createDirectory(at:retiredRoot,withIntermediateDirectories:true)
        var retiredDisk=WorkDisk()
        let retainedClaim=DotClaim(grant:UUID(),digest:"synthetic-digest",expires:start.addingTimeInterval(-1))
        var retired=WorkItem(title:"旧 Dot 待办",input:"保留原内容",instruction:"旧指令",service:"dot",dotClaim:retainedClaim,state:"dot_running",result:"保留已有结果")
        retired.dotDispatch=UUID(); retiredDisk.items=[retired]
        try JSONEncoder().encode(retiredDisk).write(to:retiredRoot.appendingPathComponent("workspace.json"))
        let recovered=WorkspaceStore(root:retiredRoot,startTimers:false)
        XCTAssertEqual(recovered.disk.items.first?.state,"interrupted")
        XCTAssertEqual(recovered.disk.items.first?.dotClaim,retainedClaim)
        XCTAssertEqual(recovered.disk.items.first?.result,"保留已有结果")
        XCTAssertEqual(recovered.disk.items.first?.dotDispatch,retired.dotDispatch)
        XCTAssertTrue(WorkspaceStore.canEdit(recovered.disk.items[0]))
        recovered.tick(now:start.addingTimeInterval(3600))
        XCTAssertEqual(recovered.disk.items.first?.state,"interrupted")
        XCTAssertEqual(recovered.disk.items.first?.dotClaim,retainedClaim)
        recovered.complete(retired.id,now:start)
        XCTAssertEqual(recovered.completedTodos.first?.id,retired.id)
        XCTAssertEqual(recovered.todoHistory.first?.completedAt,start)

        // The other app's source remains byte-for-byte unchanged and import is idempotent.
        let source=root.appendingPathComponent("youge-todos")
        try FileManager.default.createDirectory(at:source,withIntermediateDirectories:true)
        let sourceID=UUID().uuidString
        let incompleteSourceID=UUID().uuidString
        let document=TodoDocument(items:[
            TodoItem(id:sourceID,title:"佑哥旧完成任务",text:"合成原文",createdAt:start,completedAt:start.addingTimeInterval(60),archivedAt:start.addingTimeInterval(65)),
            TodoItem(id:incompleteSourceID,title:"佑哥旧未完成归档",text:"仍要保留的未完成内容",createdAt:start,archivedAt:start.addingTimeInterval(70))
        ])
        let bytes=try JSONEncoder().encode(document); try bytes.write(to:source.appendingPathComponent("todos.json"))
        XCTAssertEqual(try migrated.importLegacyTodos(from:source),2)
        XCTAssertEqual(try migrated.importLegacyTodos(from:source),0)
        XCTAssertEqual(try Data(contentsOf:source.appendingPathComponent("todos.json")),bytes)
        XCTAssertEqual(migrated.archivedTodos.count,2); XCTAssertEqual(migrated.todoHistory.count,2)
        XCTAssertEqual(migrated.todoHistory.first?.completedAt,start.addingTimeInterval(60))
        XCTAssertEqual(migrated.archivedIncompleteTodos.count,1)
        let incomplete=migrated.archivedIncompleteTodos[0]
        XCTAssertEqual(incomplete.input,"仍要保留的未完成内容");XCTAssertNil(incomplete.completedAt)
        XCTAssertEqual(incomplete.archivedAt,start.addingTimeInterval(70))
        XCTAssertFalse(migrated.todoHistory.contains(where:{$0.taskID==incomplete.id}))
        let incompleteExport=migrated.todoHistorySnapshot()["archived_incomplete"] as! [[String:Any]]
        XCTAssertEqual(incompleteExport.count,1);XCTAssertEqual(incompleteExport[0]["status"] as? String,"incomplete")
        XCTAssertTrue(incompleteExport[0]["completed_at"] is NSNull)
        let importedReload=WorkspaceStore(root:legacyRoot,startTimers:false)
        XCTAssertEqual(importedReload.archivedIncompleteTodos.first?.id,incomplete.id)
        importedReload.unarchiveItem(incomplete.id)
        XCTAssertTrue(importedReload.archivedIncompleteTodos.isEmpty)
        XCTAssertEqual(importedReload.pendingTodos.first?.id,incomplete.id)
        XCTAssertNil(importedReload.pendingTodos.first?.completedAt);XCTAssertEqual(importedReload.todoHistory.count,2)

        // Render actual unified components in a hidden AppKit window, no screen overlay.
        NSApplication.shared.setActivationPolicy(.prohibited)
        let view=UnifiedTodoPanel(store:historyReload)
        let host=NSHostingView(rootView:view)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:420),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView=host; host.layoutSubtreeIfNeeded()
        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(host.fittingSize.width.isFinite); XCTAssertTrue(host.fittingSize.width <= 420)
        let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)
        XCTAssertTrue(bitmap != nil)
        if let bitmap { host.cacheDisplay(in:host.bounds,to:bitmap) }
        window.orderOut(nil)

        // Settings owns the only scroll view; the expanded noncompact content is natural-height.
        let settingsHost=NSHostingView(rootView:UnifiedTodoSettings(store:historyReload))
        settingsHost.frame=NSRect(x:0,y:0,width:650,height:900); settingsHost.layoutSubtreeIfNeeded()
        XCTAssertTrue(settingsHost.fittingSize.height > 400)
    }
}
