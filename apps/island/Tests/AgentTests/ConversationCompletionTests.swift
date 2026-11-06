import AppKit
import Foundation
import NookApp
@testable import IslandShell

private final class LifecycleFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("island-conversation-check-" + UUID().uuidString)
    let date = Date()
    private let formatter: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return value
    }()
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    func file(_ name: String, id: String, extra: [String: Any] = [:]) throws -> URL {
        let url = root.appendingPathComponent(name + ".jsonl")
        var metadata: [String: Any] = ["id": id, "source": "vscode"]
        for (key, value) in extra { metadata[key] = value }
        try Data().write(to: url)
        try append(url, kind: "session_meta", payload: metadata)
        return url
    }
    func append(_ url: URL, kind: String = "event_msg", payload: [String: Any], at offset: Double = 0) throws {
        var bytes = try JSONSerialization.data(withJSONObject: ["type": kind, "timestamp": formatter.string(from: date.addingTimeInterval(offset)), "payload": payload])
        bytes.append(10)
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: bytes)
    }
    func event(_ url: URL, _ type: String, turn: String = "root-turn", at offset: Double = 0) throws {
        try append(url, payload: ["type": type, "turn_id": turn], at: offset)
    }
}

extension AgentTests {
    func testCodexRootConversationCompletions() async throws {
        let fixture = try LifecycleFixture()
        let root = try fixture.file("parent", id: "user-chat")
        try fixture.event(root, "task_started")
        // This is a legitimate user fork, not a subordinate agent.
        let fork = try fixture.file("user-fork", id: "user-fork", extra: ["forked_from_id": "another-chat"])
        try fixture.event(fork, "task_started")
        for index in 0..<85 {
            let child = try fixture.file("child-\(index)", id: "child-\(index)", extra: ["source": ["subagent": ["thread_spawn": ["parent_thread_id": "user-chat"]]]])
            try fixture.event(child, "task_started", turn: "child-turn")
            try fixture.event(child, "task_complete", turn: "child-turn", at: 1)
        }
        // Older variants can identify the hierarchy without the nested source.
        for metadata: [String: Any] in [["parent_thread_id": "user-chat"], ["agent_path": "/root/review"], ["source": "subagent"]] {
            let child = try fixture.file(UUID().uuidString, id: UUID().uuidString, extra: metadata)
            try fixture.event(child, "task_complete", at: 1)
        }
        let reader = CodexReader(root: fixture.root)
        var sessions = await reader.sessions(now: fixture.date.addingTimeInterval(1))
        XCTAssertEqual(Set(sessions.map(\.id)), Set(["user-chat", "user-fork"]))
        XCTAssertTrue(sessions.allSatisfy { $0.state == .working })
        var tracker = AgentAlertTracker()
        XCTAssertEqual(tracker.completions(sessions, now: fixture.date.timeIntervalSince1970 + 1), 0)
        try fixture.append(root, payload: ["type": "item_completed", "turn_id": "root-turn", "item": ["type": "tool_call", "text": "PRIVATE_SYNTHETIC_CONTENT"]], at: 2)
        try fixture.event(root, "task_complete", turn: "another-turn", at: 2)
        sessions = await reader.sessions(now: fixture.date.addingTimeInterval(2))
        XCTAssertEqual(sessions.first { $0.id == "user-chat" }?.state, .working)
        XCTAssertEqual(tracker.completions(sessions, now: fixture.date.timeIntervalSince1970 + 2), 0)
        try fixture.event(root, "task_complete", at: 3)
        sessions = await reader.sessions(now: fixture.date.addingTimeInterval(3))
        let completed = tracker.completionEvents(sessions, now: fixture.date.timeIntervalSince1970 + 3)
        XCTAssertEqual(completed.map(\.id), ["user-chat"])
        XCTAssertEqual(completed.first?.completionID, "root-turn")
        XCTAssertEqual(completed.first?.startID, "root-turn")
        XCTAssertEqual(tracker.completions(sessions, now: fixture.date.timeIntervalSince1970 + 4), 0)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(sessions), as: UTF8.self).contains("PRIVATE_SYNTHETIC_CONTENT"))
    }

    func testCodexLongSubagentAndResumedRollouts() async throws {
        let fixture = try LifecycleFixture()
        let child = try fixture.file("long-child", id: "subagent", extra: ["source": ["subagent": ["thread_spawn": ["parent_thread_id": "long-root"]]]])
        let root = try fixture.file("long-root", id: "long-root")
        for file in [root, child] {
            try fixture.event(file, "task_started")
            try fixture.append(file, kind: "response_item", payload: ["type": "message", "content": String(repeating: "SYNTHETIC ", count: 450_000)], at: 1)
            try fixture.event(file, "task_complete", at: 2)
        }
        let reader = CodexReader(root: fixture.root)
        var sessions = await reader.sessions(now: fixture.date.addingTimeInterval(3))
        XCTAssertEqual(sessions.map(\.id), ["long-root"])
        XCTAssertEqual(sessions.first?.state, .completed)
        // A resumed chat can have more than one rollout. The new running turn wins.
        let resumed = try fixture.file("resumed-root", id: "long-root")
        try fixture.event(resumed, "task_started", turn: "next-turn", at: 4)
        sessions = await reader.sessions(now: fixture.date.addingTimeInterval(14))
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.state, .working)
        XCTAssertEqual(sessions.first?.startID, "next-turn")
        try fixture.event(resumed, "task_complete", turn: "next-turn", at: 15)
        sessions = await reader.sessions(now: fixture.date.addingTimeInterval(15))
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.completionID, "next-turn")
    }

    func testCompletionCancelsWhenTheSameChatContinues() {
        let completed = AgentSession(id: "chat", state: .completed, updatedAt: now, completionID: "turn-1")
        let running = AgentSession(id: "chat", state: .working, updatedAt: now + 1, startID: "turn-2")
        let other = AgentSession(id: "another-chat", state: .working, updatedAt: now + 1)
        var batch = AgentCompletionBatch()
        XCTAssertTrue(batch.ingest(completions: [completed], sessions: [completed, other], now: now).isEmpty)
        XCTAssertTrue(batch.ingest(completions: [], sessions: [running, other], now: now + 1).isEmpty)
        XCTAssertTrue(batch.ingest(completions: [], sessions: [running, other], now: now + 4).isEmpty)
        let next = AgentSession(id: "chat", state: .completed, updatedAt: now + 5, completionID: "turn-2")
        XCTAssertTrue(batch.ingest(completions: [next], sessions: [next, other], now: now + 5).isEmpty)
        XCTAssertEqual(batch.ingest(completions: [], sessions: [next, other], now: now + 7), [next])
        XCTAssertTrue(batch.ingest(completions: [], sessions: [next, other], now: now + 9).isEmpty)
        let notice = AgentCompletionNotice(profileID: "codex", name: "Codex", count: 1, stillWorking: false, completedSessions: [next])
        XCTAssertTrue(notice.isCurrentCompletion(in: [next, other]))
        XCTAssertFalse(notice.isCurrentCompletion(in: [running, other]))
        XCTAssertFalse(notice.isCurrentCompletion(in: [completed, other]))
        XCTAssertFalse(notice.isCurrentCompletion(in: []))
        var missing = AgentCompletionBatch()
        _ = missing.ingest(completions: [completed], sessions: [completed], now: now)
        XCTAssertTrue(missing.ingest(completions: [], sessions: [], now: now + 2).isEmpty)
        XCTAssertTrue(missing.ingest(completions: [], sessions: [completed], now: now + 61).isEmpty)
    }

    @MainActor func testStoreSuppressesSupersededCompletions() throws {
        let suite = "local.island.completion-check." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let store = AgentStore(defaults: defaults, allowsLiveReads: false, sessionIsLocked: { false })
        let center = NookActivityCenter(); store.start(activities: center.activities(for: "completion-check"))
        var prefs = store.preferences; prefs.enabled = true; prefs.monitoredIDs = ["codex"]
        prefs.startAlerts = false; prefs.attentionAlerts = false; prefs.completionAlerts = true; prefs.quotaAlerts = false
        try store.update(prefs)
        func ingest(_ state: AgentState, _ offset: Double, turn: String) {
            let value = AgentSession(id: "chat", state: state, updatedAt: now + offset, completionID: state == .completed ? turn : nil, startID: turn)
            store.ingestSnapshots(["codex": .init(sessions: [value])], now: now + offset)
        }
        ingest(.working, 0, turn: "first")
        ingest(.completed, 1, turn: "first")
        ingest(.working, 2, turn: "second")
        ingest(.working, 4, turn: "second")
        XCTAssertNil(store.completionNotice)
        ingest(.completed, 5, turn: "second")
        store.ingestSnapshots(["codex": store.snapshots["codex"]!], now: now + 7)
        XCTAssertEqual(store.completionNotice?.completedSessions.first?.completionID, "second")
        XCTAssertEqual(center.primary?.activity.alert, .compact(.seconds(6)))
        ingest(.working, 8, turn: "third")
        XCTAssertNil(store.completionNotice)
        XCTAssertFalse(store.lastAlert.isEmpty)
    }

    @MainActor func testQueuedScreenCompletionRechecksConversation() throws {
        let presenter = ScreenReminderPresenter(displaysWindows: false, sessionIsLocked: { false })
        let material = ScreenReminderMaterial.builtins.first { $0.id == "cat" }!
        let request = ScreenReminderRequest(title: "合成完成提醒", style: .init(durationSeconds: 5), material: material, videoURL: ScreenReminderMedia.bundledURL("cat"))
        let frame = CGRect(x: 0, y: 0, width: 900, height: 700)
        var complete = true
        try presenter.present(request, testFrame: frame)
        try presenter.present(request, testFrame: frame, shouldPresent: { complete })
        XCTAssertEqual(presenter.pendingCount, 1)
        complete = false
        presenter.dismiss()
        XCTAssertEqual(presenter.pendingCount, 0)
        XCTAssertTrue(presenter.verificationWindows.isEmpty)
        XCTAssertEqual(presenter.deliveredTitles.count, 1)
        try presenter.present(request, testFrame: frame, shouldPresent: { complete })
        XCTAssertTrue(presenter.verificationWindows.isEmpty)
        complete = true
        try presenter.present(request, testFrame: frame, shouldPresent: { complete })
        XCTAssertEqual(presenter.verificationWindows.count, 2)
        complete = false
        presenter.refreshCountdown()
        XCTAssertTrue(presenter.verificationWindows.isEmpty)
        complete = true
        try presenter.present(request, testFrame: frame, shouldPresent: { complete })
        presenter.suspendForLock(); complete = false; presenter.resumePending()
        XCTAssertTrue(presenter.verificationWindows.isEmpty)
        presenter.dismissAll()
    }
}
