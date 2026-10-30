import Foundation
@testable import IslandShell

@MainActor func checkTodoOrder() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("todo-order-" + UUID().uuidString)
    let store = WorkspaceStore(root: root, startTimers: false)
    let a = try! store.addTodo(title: "A")
    let b = try! store.addTodo(title: "B")
    let c = try! store.addTodo(title: "C")
    let original = store.disk.items
    check(store.pendingTodos.map(\.id) == [c,b,a], "unconfigured order remains newest first")
    check(store.moveTodo(a, by: -1), "move todo up")
    check(store.pendingTodos.map(\.id) == [c,a,b], "up moves one step")
    check(store.moveTodo(b, before: c), "drop todo before target")
    check(store.pendingTodos.map(\.id) == [b,c,a], "drop persists complete order")
    check(store.disk.items == original, "reorder preserves all task content and reminder fields")
    check(!store.moveTodo(b, by: -1) && !store.moveTodo(UUID(), before: a), "invalid moves rejected")
    let restored = WorkspaceStore(root: root, startTimers: false)
    check(restored.pendingTodos.map(\.id) == [b,c,a], "manual todo order survives restart")
    let d = try! restored.addTodo(title: "D")
    check(restored.pendingTodos.map(\.id) == [d,b,c,a], "new todo prepends without disturbing manual order")
    restored.complete(c)
    check(restored.pendingTodos.map(\.id) == [d,b,a], "completion preserves remaining order")
    restored.reopenTodo(c)
    check(restored.pendingTodos.map(\.id) == [d,b,c,a], "undo completion restores prior position")
}
