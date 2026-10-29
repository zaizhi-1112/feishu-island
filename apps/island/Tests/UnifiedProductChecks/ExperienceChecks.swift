import AppKit
import Foundation
import NookApp
@testable import IslandShell

@MainActor
func runExperienceChecks(check: (Bool, String) -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("island-experience-" + UUID().uuidString)
    let store = WorkspaceStore(root: root, startTimers: false)
    let now = Date()
    let first = try store.addTodo(title: "较早任务", details: "需要保留的完整说明", now: now)
    let second = try store.addTodo(title: "同时创建的第二条", now: now)
    let third = try store.addTodo(title: "较晚但更紧急", now: now.addingTimeInterval(1))
    check(store.disk.items.first{$0.id==first}?.due == now.addingTimeInterval(1200), "new todo defaults to a reminder in twenty minutes")
    check(store.disk.items.first{$0.id==first}?.todoReminder?.pendingDates == [now.addingTimeInterval(1200)], "default reminder uses the existing scheduler")
    _ = store.mutate { state in
        let index = state.items.firstIndex { $0.id == third }!
        state.items[index].due = now.addingTimeInterval(60)
    }
    check(store.pendingTodos.map(\.id) == [third, second, first], "newest tasks lead, ties use insertion order rather than reminder time")
    store.complete(first, now: now.addingTimeInterval(2))
    store.complete(second, now: now.addingTimeInterval(3))
    let history = store.todoHistory
    _ = store.mutate { state in
        let index = state.items.firstIndex { $0.id == second }!
        state.items[index].archive = WorkArchiveReceipt(target: .init(), digest: "synthetic", state: "running")
    }
    store.archiveCompletedTodos(now: now.addingTimeInterval(4))
    check(store.archivedTodos.isEmpty, "busy batch archive fails without partially moving tasks")
    _ = store.mutate { state in
        let index = state.items.firstIndex { $0.id == second }!
        state.items[index].archive = nil
    }
    let archivedAt = now.addingTimeInterval(5)
    store.archiveCompletedTodos(now: archivedAt)
    check(Set(store.archivedTodos.map(\.id)) == Set([first, second]), "batch archive moves only completed tasks")
    check(store.pendingTodos.map(\.id) == [third], "archiving leaves unfinished work intact")
    check(store.todoHistory == history, "archiving preserves completion events")
    check(store.archivedTodos.allSatisfy { $0.archivedAt == archivedAt }, "one batch uses one persisted archive time")
    let reload = WorkspaceStore(root: root, startTimers: false)
    check(reload.archivedTodos.count == 2 && reload.todoHistory == history, "archive and completion history survive restart")
    reload.unarchiveItem(first)
    check(reload.completedTodos.contains { $0.id == first }, "restoring an archive preserves completed status")
    check(!reload.pendingTodos.contains { $0.id == first }, "restoring an archive does not silently reopen it")
    check(reload.disk.items.first { $0.id == first }?.input == "需要保留的完整说明", "restore retains original task content")
    reload.reopenTodo(first)
    check(reload.pendingTodos.contains { $0.id == first }, "explicit reopen returns a task to unfinished work")
    check(reload.todoHistory == history, "reopening does not erase previous completed work")
    reload.deleteItem(third)
    check(!reload.pendingTodos.contains { $0.id == third } && reload.disk.trash?.contains { $0.id == third } == true, "delete is distinct and recoverable")
    let again = WorkspaceStore(root: root, startTimers: false)
    again.restoreItem(third)
    check(again.pendingTodos.contains { $0.id == third }, "recoverable delete survives restart")
    check(IslandHost.panelHeight == 336 && IslandHost.panelWidth == 400, "all panels use the reviewed compact viewport")
    let platformRoot = root.appendingPathComponent("platform")
    let platform = UnifiedPlatformStore(root: platformRoot)
    let oldKey = platform.hotkey
    let newKey = NookHotkey(keyCode: 40, carbonModifiers: 4096, keySymbol: "K")
    check(UnifiedPlatformStore.validHotkey(newKey), "modified global shortcut is valid")
    platform.registerHotkey = { _ in false }
    check(!platform.setHotkey(newKey) && platform.hotkey == oldKey, "shortcut conflicts preserve the previous binding")
    platform.registerHotkey = { _ in true }
    check(platform.setHotkey(newKey), "available global shortcut is saved")
    check(UnifiedPlatformStore(root: platformRoot).hotkey == newKey, "custom global shortcut survives restart")
    check(platform.setHotkey(.init(keyCode: 40, carbonModifiers: 0, keySymbol: "K")), "user-selected single key is saved")
    check(FeishuEmptyStatePresentation(enabled: false, connecting: false, status: "旧状态", showAll: false).title == "接收已停止", "stopped receiving has one unambiguous state")
    check(FeishuEmptyStatePresentation(enabled: false, connecting: true, status: "接收已停止", showAll: false).title == "等待你完成飞书授权", "authorization progress takes priority over the stopped receiver")
    check(FeishuEmptyStatePresentation(enabled: true, connecting: false, status: "账号接收中 · 合成", showAll: false).title == "暂时没有重要消息", "healthy empty inbox is distinct from connection failures")
    let failedConnection = FeishuEmptyStatePresentation(enabled: true, connecting: false, status: "账号授权已过期", showAll: true)
    check(failedConnection.title == "连接需要检查" && failedConnection.detail.contains("过期"), "empty inbox does not hide an expired authorization")

}
