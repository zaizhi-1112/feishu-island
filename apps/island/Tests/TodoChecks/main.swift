import AppKit
import SwiftUI
import NookApp
@testable import NookSurface
@testable import IslandShell

@MainActor
func runChecks() async throws {
    var passed = 0
    func expect(_ value: Bool, _ name: String) {
        guard value else { fputs("FAIL: \(name)\n", stderr); exit(1) }
        passed += 1; print("PASS: \(name)")
    }
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("youzi-todo-check-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    let store = TodoStore(directory: root.appendingPathComponent("store"), now: { clock })
    let id = await store.capture(.text("跟进客户反馈\n带上原始材料"))!
    expect(store.item(id)?.title == "跟进客户反馈", "first line names a text todo")
    expect(store.item(id)?.text.contains("原始材料") == true, "full text retained")
    expect(store.item(id)?.dueAt == clock.addingTimeInterval(1200), "default reminder is 20 minutes")
    store.selectedID = id
    expect(store.pending.count == 1 && store.item(id)?.completedAt == nil, "viewing does not complete or acknowledge a todo")
    let linkID = await store.capture(.link(URL(string: "https://example.com/path?q=1")!))!
    expect(store.item(linkID)?.link?.host == "example.com", "link retained")
    let revision = store.preferences.revision
    try store.updatePreferences(TodoPreferences(revision: revision, defaultMinutes: 35, soundEnabled: false))
    expect(store.item(id)?.dueAt == clock.addingTimeInterval(1200), "default changes leave existing due dates unchanged")
    let later = await store.capture(.text("稍后处理"))!
    expect(store.item(later)?.dueAt == clock.addingTimeInterval(2100), "new default applied")
    do { try store.updatePreferences(TodoPreferences(revision: revision, defaultMinutes: 10)); expect(false, "stale preference revision rejected") }
    catch { expect(true, "stale preference revision rejected") }
    do { try store.updatePreferences(TodoPreferences(revision: store.preferences.revision, defaultMinutes: 0)); expect(false, "invalid minutes rejected") }
    catch { expect(true, "invalid minutes rejected") }
    let restored = TodoStore(directory: store.directory, now: { clock })
    expect(restored.document == store.document, "items and preferences persist across restart")

    var batches = 0
    store.onDue = { items in batches += 1; expect(items.count == 2, "simultaneous reminders combined in one batch") }
    clock = clock.addingTimeInterval(1201)
    expect(store.checkDue().count == 2 && batches == 1, "due checks emit once")
    expect(store.checkDue().isEmpty && batches == 1, "repeated timer and wake checks do not repeat reminders")
    let afterReminder = TodoStore(directory: store.directory, now: { clock })
    expect(afterReminder.checkDue().isEmpty, "restart does not repeat delivered reminders")
    expect(afterReminder.overdueCount == 2, "delivered reminders keep overdue badges")
    store.onDue = nil
    store.snooze(id, minutes: 10)
    expect(store.item(id)?.notifiedAt == nil && store.overdueCount == 1, "snooze resets delivery and clears badge")
    clock = clock.addingTimeInterval(601)
    expect(store.checkDue().map(\.id) == [id], "snoozed reminder fires at its new time")
    store.complete(id)
    expect(store.completed.contains(where: { $0.id == id }) && store.overdueCount == 1, "complete removes pending item and due badge")
    store.restore(id)
    expect(store.item(id)?.completedAt == nil && store.checkDue().isEmpty, "restore does not repeat a delivered reminder")
    expect(store.update(id, title: "更改名称", dueAt: nil), "rename and disable reminder")
    expect(store.overdueCount == 1 && store.item(id)?.dueAt == nil, "disabled reminder removes its due badge")
    expect(!store.update(id, title: " \n", dueAt: nil), "empty title rejected")

    let sourceA = root.appendingPathComponent("a/同名.txt"), sourceB = root.appendingPathComponent("b/同名.txt")
    try fm.createDirectory(at: sourceA.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fm.createDirectory(at: sourceB.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("first".utf8).write(to: sourceA); try Data("second".utf8).write(to: sourceB)
    let filesID = await store.capture(.files([sourceA, sourceB]))!
    let files = store.item(filesID)!.attachments
    expect(files.count == 2 && Set(files.map(\.relativePath)).count == 2, "one drop creates one todo with collision-safe attachments")
    try fm.removeItem(at: sourceA); try fm.removeItem(at: sourceB)
    let copyA = store.attachmentURL(files[0])!
    let copyB = store.attachmentURL(files[1])!
    expect(try String(contentsOf: copyA) == "first", "first copied file survives source removal")
    expect(try String(contentsOf: copyB) == "second", "second copied file survives source removal")
    let count = store.document.items.count
    expect(await store.capture(.files([root])) == nil, "directory import rejected")
    expect(store.document.items.count == count, "failed import creates no todo")
    expect(await store.capture(.files([copyA, root.appendingPathComponent("missing.txt")])) == nil, "partial copy failure rejects entire import")
    expect(store.document.items.count == count, "partial import never reported as saved")
    let staging = store.directory.appendingPathComponent("staging")
    expect((try fm.contentsOfDirectory(atPath: staging.path)).isEmpty, "failed import cleans only its own staging files")
    let malicious = TodoAttachment(id: "bad", name: "bad", relativePath: "../outside")
    expect(store.attachmentURL(malicious) == nil, "attachment cannot escape its container")
    store.savedID = filesID; store.undoCapture()
    expect(store.item(filesID) == nil && !fm.fileExists(atPath: copyA.path), "undo removes newly captured todo and its owned copies")

    // Exercise actual persistence with a controlled clock, including the exact 30-day boundary.
    var archiveClock = clock
    let archiveRoot = root.appendingPathComponent("archive")
    let archives = TodoStore(directory: archiveRoot, now: { archiveClock })
    let completedID = await archives.capture(.text("已完成的归档任务"))!
    archives.complete(completedID)
    let completedAt = archives.item(completedID)!.completedAt
    archives.selectedID = completedID
    expect(archives.archive(completedID), "completed item can be archived")
    expect(archives.completed.isEmpty && archives.pending.isEmpty && archives.archived.count == 1,
           "archive hides item from both normal lists")
    expect(archives.selectedID == nil && archives.savedID == nil, "archive clears detail and capture undo")
    expect(archives.item(completedID)?.archiveExpiresAt == nil, "archives have no automatic expiration")
    let reopenArchive = TodoStore(directory: archiveRoot, now: { archiveClock })
    expect(reopenArchive.archived.count == 1 && reopenArchive.item(completedID)?.completedAt == completedAt,
           "archive and completion survive restart")
    expect(archives.unarchive(completedID) && archives.completed.count == 1 && archives.pending.isEmpty,
           "unarchive returns completed item to completed list")
    let pendingID = await archives.capture(.text("归档期间不提醒"))!
    expect(archives.archive(pendingID), "pending item can be archived")
    let archivedAt = archives.item(pendingID)!.archivedAt
    expect(!archives.archive(pendingID) && archives.item(pendingID)?.archivedAt == archivedAt,
           "duplicate archive cannot extend retention")
    archiveClock = archiveClock.addingTimeInterval(1201)
    expect(archives.checkDue().isEmpty && archives.overdueCount == 0, "archived pending item never alerts or shows overdue")
    expect(!archives.update(pendingID, title: "cannot edit archive", dueAt: nil), "archived item cannot be edited as an active todo")
    expect(archives.unarchive(pendingID) && archives.pending.count == 1 && archives.checkDue().count == 1,
           "unarchive restores unfinished item and its reminder")
    expect(archives.archive(pendingID), "restored item can be archived again")
    expect(archives.item(pendingID)?.archivedAt == archiveClock, "explicit rearchive starts a fresh retention period")

    let original = root.appendingPathComponent("保留原文件.txt")
    try Data("source stays intact".utf8).write(to: original)
    let archivedFileID = await archives.capture(.files([original]))!
    let archivedCopy = archives.attachmentURL(archives.item(archivedFileID)!.attachments[0])!
    expect(archives.archive(archivedFileID), "file todo archived")
    let retainedID = await archives.capture(.text("未归档的已完成任务"))!
    archives.complete(retainedID)
    archiveClock = archiveClock.addingTimeInterval(30 * 86400 - 1)
    archives.checkDue()
    expect(archives.item(archivedFileID) != nil && fm.fileExists(atPath: archivedCopy.path),
           "one second before expiry keeps record and attachment")
    expect(archives.item(archivedFileID)?.archiveExpiresAt == nil, "archive retention stays indefinite")
    let at29Days = TodoStore(directory: archiveRoot, now: { archiveClock })
    expect(at29Days.archived.count == 2, "restart before expiry preserves all archives")
    archiveClock = archiveClock.addingTimeInterval(1)
    archives.checkDue()
    expect(archives.item(archivedFileID) != nil && archives.item(pendingID) != nil && archives.archived.count == 2,
           "timer retains archives across the former 30-day boundary")
    expect(fm.fileExists(atPath: archivedCopy.path) && fm.fileExists(atPath: original.path),
           "long-term history retains both original and copied attachments")
    expect(archives.unarchive(archivedFileID), "old history can still be restored")
    expect(archives.item(retainedID)?.completedAt != nil && archives.item(completedID) != nil,
           "age alone never purges unarchived tasks")
    expect(TodoStore(directory: archiveRoot, now: { archiveClock }).document == archives.document,
           "long-term retention persists after restart")
    let startupID = await archives.capture(.files([original]))!
    let startupCopy = archives.attachmentURL(archives.item(startupID)!.attachments[0])!
    expect(archives.archive(startupID), "prepare archive expiring while app is closed")
    archiveClock = archiveClock.addingTimeInterval(30 * 86400)
    let afterExpiry = TodoStore(directory: archiveRoot, now: { archiveClock })
    expect(afterExpiry.item(startupID) != nil && fm.fileExists(atPath: startupCopy.path),
           "launch preserves old archives and their attachments")

    // Missing optional fields in the original schema remain readable without a migration write.
    var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(archives.document)) as! [String: Any]
    legacyJSON.removeValue(forKey: "attachmentCleanupIDs")
    legacyJSON["items"] = (legacyJSON["items"] as! [[String: Any]]).map { item in
        var item = item; item.removeValue(forKey: "archivedAt"); return item
    }
    let legacyRoot = root.appendingPathComponent("legacy")
    try fm.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
    let legacyBytes = try JSONSerialization.data(withJSONObject: legacyJSON)
    try legacyBytes.write(to: legacyRoot.appendingPathComponent("todos.json"))
    let legacy = TodoStore(directory: legacyRoot, now: { archiveClock })
    expect(!legacy.loadFailed && legacy.document.items.count == archives.document.items.count && legacy.archived.isEmpty,
           "existing schema-1 data loads with no archive fields")
    expect(try Data(contentsOf: legacyRoot.appendingPathComponent("todos.json")) == legacyBytes,
           "loading legacy data does not rewrite it")

    let failedID = await afterExpiry.capture(.files([original]))!
    let failedCopy = afterExpiry.attachmentURL(afterExpiry.item(failedID)!.attachments[0])!
    let liveFile = archiveRoot.appendingPathComponent("todos.json")
    let heldFile = archiveRoot.appendingPathComponent("held.json")
    try fm.moveItem(at: liveFile, to: heldFile)
    try fm.createDirectory(at: liveFile, withIntermediateDirectories: false)
    expect(!afterExpiry.archive(failedID) && afterExpiry.item(failedID)?.archivedAt == nil,
           "failed archive write leaves item active")
    try fm.removeItem(at: liveFile); try fm.moveItem(at: heldFile, to: liveFile)
    expect(afterExpiry.archive(failedID), "archive succeeds once storage is available")
    archiveClock = archiveClock.addingTimeInterval(30 * 86400)
    try fm.moveItem(at: liveFile, to: heldFile)
    try fm.createDirectory(at: liveFile, withIntermediateDirectories: false)
    afterExpiry.purgeExpiredArchives()
    expect(afterExpiry.item(failedID) != nil && fm.fileExists(atPath: failedCopy.path),
           "failed purge commit keeps record and attachment intact")
    expect(!afterExpiry.unarchive(failedID), "expired archive cannot bypass expiry after a purge write failure")
    try fm.removeItem(at: liveFile); try fm.moveItem(at: heldFile, to: liveFile)
    afterExpiry.purgeExpiredArchives()
    expect(afterExpiry.item(failedID) != nil && fm.fileExists(atPath: failedCopy.path),
           "retention never resumes destructive cleanup when storage recovers")

    let failureRoot = root.appendingPathComponent("unwritable")
    let failure = TodoStore(directory: failureRoot)
    try Data("occupied".utf8).write(to: failureRoot)
    expect(await failure.capture(.text("不能存入")) == nil && failure.document.items.isEmpty, "write failure cannot produce success or phantom item")
    let corruptRoot = root.appendingPathComponent("corrupt")
    try fm.createDirectory(at: corruptRoot, withIntermediateDirectories: true)
    let badData = Data("invalid json".utf8); try badData.write(to: corruptRoot.appendingPathComponent("todos.json"))
    let corrupt = TodoStore(directory: corruptRoot)
    expect(corrupt.loadFailed, "corrupt storage surfaces a load failure")
    expect(await corrupt.capture(.text("不能覆盖")) == nil, "corrupt original cannot be silently overwritten")
    expect(try Data(contentsOf: corruptRoot.appendingPathComponent("todos.json")) == badData, "corrupt source preserved byte-for-byte")

    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("一段文字", forType: .string)
    expect(NookDropPayload.read(from: pasteboard) == .text("一段文字"), "plain text pasteboard accepted")
    pasteboard.clearContents(); pasteboard.setString("https://example.com", forType: .string)
    expect(NookDropPayload.read(from: pasteboard) == .link(URL(string: "https://example.com")!), "URL text recognized as link")
    pasteboard.clearContents(); pasteboard.setString("https://example.com/page", forType: .URL)
    expect(NookDropPayload.read(from: pasteboard) == .link(URL(string: "https://example.com/page")!), "browser URL pasteboard accepted")
    pasteboard.clearContents(); pasteboard.writeObjects([copyB as NSURL]); pasteboard.setString("duplicate", forType: .string)
    expect(NookDropPayload.read(from: pasteboard) == .files([copyB]), "file URL takes precedence over duplicate text")
    expect(NookDropPayload.webURL("javascript:alert(1)") == nil, "unsafe URL scheme not opened")
    pasteboard.clearContents()
    expect(NookDropPayload.read(from: pasteboard) == nil, "unsupported or empty pasteboard rejected")
    let offlineRoot = root.appendingPathComponent("offline")
    let offline = TodoStore(directory: offlineRoot, now: { clock })
    _ = await offline.capture(.text("退出期间到期"))
    clock = clock.addingTimeInterval(1201)
    let reopened = TodoStore(directory: offlineRoot, now: { clock })
    expect(reopened.checkDue().count == 1, "missed deadline delivered once after reopening")
    expect(reopened.checkDue().isEmpty, "missed deadline delivery remains deduplicated")

    let surface = Nook { Text("legacy") } compactLeading: { Text("L") } compactTrailing: { Text("R") }
    var legacyCalls = 0, typedCalls = 0
    surface.onFileDrop = { _ in legacyCalls += 1; return true }
    expect(surface.nookPanelPerformDrop(.files([copyB])), "legacy file callback remains supported")
    expect(legacyCalls == 1 && !surface.nookPanelPerformDrop(.text("unsupported")), "legacy file handler never receives text")
    surface.onDrop = { _ in typedCalls += 1; return true }
    expect(surface.nookPanelPerformDrop(.text("typed")) && typedCalls == 1 && legacyCalls == 1, "typed drop routes once without duplicate legacy capture")

    let beforeDrag = surface.state
    expect(surface.nookPanelDraggingEntered(.text("取消拖入")) == .copy && surface.isDragInFlight, "drag entry exposes receiving state")
    surface.nookPanelDraggingExited()
    expect(!surface.isDragInFlight && surface.state == beforeDrag && typedCalls == 1, "canceled drag restores state and creates no todo")
    surface.nookPanelDraggingExited()
    expect(!surface.isDragInFlight, "duplicate drag exit is harmless")

    let center = NookActivityCenter()
    let todoScope = center.activities(for: "test.todo"), agentScope = center.activities(for: "test.agent")
    func activity(_ id: String) -> NookLiveActivity {
        NookLiveActivity(id: id, priority: .high, alert: .compact(.milliseconds(180)), accessibilityLabel: id) {
            Text(id)
        } compactTrailing: { Text(id) } minimal: { Text(id) }
    }
    todoScope.start(activity("due")); agentScope.start(activity("complete"))
    expect(center.primary?.moduleID == "test.todo", "second alert cannot steal current reminder")
    expect(center.activities.filter(\.isAlerting).count == 1, "only one activity alerts at a time")
    try await Task.sleep(for: .milliseconds(240))
    expect(center.primary?.moduleID == "test.agent" && center.primary?.isAlerting == true, "queued completion shows after reminder")
    agentScope.end("complete"); todoScope.end("due")
    expect(center.activities.isEmpty, "ending queued activities leaves no stale alert")
    print("TodoChecks: \(passed) passed")
}

Task { @MainActor in
    do { try await runChecks(); exit(0) }
    catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
dispatchMain()
