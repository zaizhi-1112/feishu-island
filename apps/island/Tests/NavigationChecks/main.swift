import AppKit
import NookApp
@testable import NookKit
@testable import IslandShell

var passed = 0
func check(_ value: Bool, _ label: String, line: Int = #line) {
    guard value else { fputs("FAIL \(line): \(label)\n", stderr); exit(1) }
    passed += 1
}

// The view receives real NSEvent fields; fixtures make phase, axis and region
// isolation reproducible without claiming that physical fingers were exercised.
final class ScrollFixture: NSEvent {
    var target: NSWindow?
    var point = NSPoint(x: 100, y: 100)
    var dx: CGFloat = -60
    var dy: CGFloat = 0
    var gesturePhase: NSEvent.Phase = .began
    var inertia: NSEvent.Phase = []
    override var window: NSWindow? { target }
    override var locationInWindow: NSPoint { point }
    override var scrollingDeltaX: CGFloat { dx }
    override var scrollingDeltaY: CGFloat { dy }
    override var phase: NSEvent.Phase { gesturePhase }
    override var momentumPhase: NSEvent.Phase { inertia }
    override var hasPreciseScrollingDeltas: Bool { true }
    override var isDirectionInvertedFromDevice: Bool { true }
}

Task { @MainActor in
    check(IslandRuntime.isSkinPreview, "run with --skin-preview to isolate readers")
    var swipe = NookModuleSwipeTracker()
    check(swipe.update(dx: -15, dy: 1, phase: .began) == nil && swipe.consumesEvent, "horizontal axis claims scroll")
    check(swipe.update(dx: -34, dy: 2, phase: .changed) == 1, "left swipe advances")
    check(swipe.update(dx: -200, dy: 0, phase: .changed) == nil, "long gesture advances once")
    check(swipe.update(dx: 0, dy: 0, phase: .ended) == nil, "end does not advance")
    check(swipe.update(dx: -200, dy: 0, phase: [], momentum: .began) == nil && swipe.consumesEvent, "inertia consumed without second switch")
    check(swipe.update(dx: 60, dy: 0, phase: .began) == -1, "next independent right swipe goes back")
    check(swipe.update(dx: -60, dy: 0, phase: .began, inverted: false) == -1, "natural scroll preference compensated")
    check(swipe.update(dx: 2, dy: 18, phase: .began) == nil && !swipe.consumesEvent, "vertical list scroll passes through")
    check(swipe.update(dx: -100, dy: 0, phase: .changed) == nil && !swipe.consumesEvent, "vertical gesture cannot turn into navigation")
    check(swipe.update(dx: -30, dy: 0, phase: .began) == nil, "short swipe does not switch")
    check(swipe.update(dx: -80, dy: 0, phase: .cancelled) == nil, "cancelled swipe does not switch")
    check(swipe.update(dx: -80, dy: 0, phase: []) == nil, "phase-less mouse wheel does not switch")
    check(swipe.update(dx: -80, dy: 0, phase: .began, precise: false) == nil, "ordinary wheel does not switch")
    let modules = [IslandHost.feishuID, IslandHost.agentID, IslandHost.todoID]
    check(NookModuleSwipeTracker.destination(modules: modules, activeID: modules[0], step: 1) == modules[1], "module order forward")
    check(NookModuleSwipeTracker.destination(modules: modules, activeID: modules[2], step: -1) == modules[1], "module order backward")
    check(NookModuleSwipeTracker.destination(modules: modules, activeID: modules[0], step: -1) == nil, "first page has no wrap")
    check(NookModuleSwipeTracker.destination(modules: modules, activeID: modules[2], step: 1) == nil, "last page has no wrap")

    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let window = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 400, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
    let region = NookModuleSwipeRegion.SwipeView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
    window.contentView!.addSubview(region)
    region.canNavigate = { true }
    var steps = [Int]()
    region.switchPage = { steps.append($0) }
    let event = ScrollFixture(); event.target = window
    check(region.handle(event) == nil && steps == [1], "expanded region handles trackpad gesture")
    event.point = NSPoint(x: 350, y: 350)
    check(region.handle(event) != nil && steps == [1], "transparent window area cannot navigate")
    event.point = NSPoint(x: 100, y: 100); event.target = nil
    check(region.handle(event) != nil && steps == [1], "other window cannot navigate")
    event.target = window; region.canNavigate = { false }
    check(region.handle(event) != nil && steps == [1], "collapsed or settings region ignores gestures")
    region.stop()

    let suite = "local.youzi.island.navigation-check.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let feishu = FeishuStore(defaults: defaults)
    let agents = AgentStore(defaults: defaults)
    var monitoring = agents.preferences; monitoring.enabled = true; try! agents.update(monitoring)
    let todos = TodoStore(directory: root)
    @MainActor func hints() -> [String: String] { IslandModuleAttention.hints(feishu: feishu, agents: agents, todos: todos) }
    check(hints().isEmpty, "no spurious initial badges")
    let message = FeishuMessage(raw: ["message_id": "fixture", "create_time": "1", "msg_type": "text", "sender": ["sender_name": "测试"], "body": ["content": "{\"text\":\"提醒测试\"}"]], chatID: "oc_fixture", chatName: "测试", chatKind: "p2p", ownID: "ou_me")
    feishu.receive(message)
    check(hints()[modules[0]] != nil, "new Feishu message has a dot even without capsule")
    feishu.toggleMute()
    check(hints()[modules[0]] != nil, "mute keeps pending message visible")
    feishu.remindLater(message.id)
    check(hints()[modules[0]] == nil, "snoozed message clears pending dot")
    feishu.tick(now: Date().addingTimeInterval(601))
    check(hints()[modules[0]] != nil, "manual reminder restores pending dot")
    feishu.markViewed(message.id)
    check(hints()[modules[0]] == nil, "viewed messages clear dot")
    agents.previewNotification("codex")
    check(hints()[modules[1]] != nil, "completion retains pending dot")
    agents.acknowledgeCompletions()
    check(hints()[modules[1]] == nil, "reading Agent clears completion dot")
    func quota(_ left: Double, age: Double = 0) -> AgentQuota { .init(id: "test", label: "测试额度", remainingPercent: left, resetsAt: nil, updatedAt: Date().timeIntervalSince1970 - age) }
    agents.previewQuotas([quota(20)])
    check(hints()[modules[1]] == nil, "exactly twenty is not low")
    agents.previewQuotas([quota(19.9)])
    check(hints()[modules[1]]?.contains("20%") == true, "below twenty shows persistent warning")
    agents.acknowledgeCompletions()
    check(hints()[modules[1]] != nil, "reading cannot clear outstanding quota warning")
    agents.previewQuotas([quota(10, age: 901)])
    check(hints()[modules[1]] == nil, "stale quota cannot show warning")
    agents.previewQuotas([quota(10)], profileID: "workbuddy")
    check(hints()[modules[1]] != nil, "nonprimary visible Agent also warns")
    var prefs = agents.preferences; prefs.setVisibleIDs(["codex"]); try! agents.update(prefs)
    check(hints()[modules[1]] == nil, "hidden Agent no longer warns")
    agents.previewQuotas([quota(9)])
    prefs = agents.preferences; prefs.quotaAlerts = false; try! agents.update(prefs)
    check(hints()[modules[1]] == nil, "warning preference respected")
    prefs = agents.preferences; prefs.quotaAlerts = true; prefs.setVisibleIDs(["codex", "workbuddy"]); try! agents.update(prefs)
    let attention = IslandModuleAttention(agents: agents, todos: todos, feishu: feishu)
    attention.refresh()
    check(attention.hints[modules[1]]?.contains("WorkBuddy") == true, "hint names actual low-quota Agent")
    attention.acknowledge(modules[1])
    check(attention.hints[modules[1]] == nil && agents.hasLowQuota, "visit clears navigation hint while source warning remains")
    attention.refresh()
    check(attention.hints[modules[1]] == nil, "timer does not restore acknowledged quota")
    agents.previewNotification("codex"); attention.refresh()
    check(attention.hints[modules[1]]?.contains("Codex") == true, "new completion after acknowledgment raises hint")
    attention.acknowledge(modules[1])
    check(attention.hints[modules[1]] == nil && agents.unviewedCompletionProfiles.isEmpty, "completion and quota acknowledgment clear together")
    agents.previewQuotas([quota(50)]); agents.previewQuotas([quota(50)], profileID: "workbuddy"); attention.refresh()
    agents.previewQuotas([quota(19)]); attention.refresh()
    check(attention.hints[modules[1]] != nil, "new threshold crossing raises quota hint again")
    let id = await todos.capture(.text("待办提醒测试"))!
    _ = todos.update(id, title: "待办提醒测试", dueAt: Date().addingTimeInterval(-1))
    check(hints()[modules[2]] != nil, "due todo shows badge")
    _ = todos.checkDue()
    check(hints()[modules[2]] != nil, "delivered reminder keeps badge")
    attention.refresh(); attention.acknowledge(modules[2])
    check(attention.hints[modules[2]] == nil && todos.overdueCount == 1, "viewing todo clears hint without completing item")
    attention.refresh()
    check(attention.hints[modules[2]] == nil, "overdue timer does not resurrect seen hint")
    todos.snooze(id, minutes: 10)
    check(hints()[modules[2]] == nil, "snooze clears overdue badge")
    _ = todos.update(id, title: "待办提醒测试", dueAt: Date().addingTimeInterval(-1))
    todos.complete(id)
    check(hints()[modules[2]] == nil, "completed todo clears overdue badge")
    if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "--window-check") {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[i + 1])
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var runtime: [String: Bool] = [:]
        let config = IslandHost.configuration()
        let host = ModuleHost(registry: config.makeRegistry())
        let coordinator = AppCoordinator(appState: AppState(preferenceDefaults: config.preferenceDefaults), moduleHost: host)
        coordinator.start()
        coordinator.appState.keepNookOpen = true
        coordinator.showNook()
        TodoBridge.shared.playSound = {}
        @MainActor func settle() async {
            await coordinator.drainLifecycleForTesting()
            try? await Task.sleep(for: .milliseconds(500))
        }
        @MainActor func verify(_ value: Bool, _ label: String) { runtime[label] = value; check(value, label) }
        @MainActor func region(in view: NSView?) -> NookModuleSwipeRegion.SwipeView? {
            guard let view else { return nil }
            if let swipe = view as? NookModuleSwipeRegion.SwipeView { return swipe }
            return view.subviews.compactMap { region(in: $0) }.first
        }
        @MainActor func capture(_ name: String) {
            let view = coordinator.nookWindow!.contentView!
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + ".png"))
        }
        @MainActor func swipe(_ dx: CGFloat, dy: CGFloat = 0, phase: NSEvent.Phase = .began, momentum: NSEvent.Phase = []) -> Bool {
            guard let view = region(in: coordinator.nookWindow?.contentView) else { return false }
            let event = ScrollFixture(); event.target = view.window
            event.point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            event.dx = dx; event.dy = dy; event.gesturePhase = phase; event.inertia = momentum
            return view.handle(event) == nil
        }
        await settle()
        verify(coordinator.appState.isNookVisible && region(in: coordinator.nookWindow?.contentView)?.enabled == true, "nativeSwipeRegionMounted")
        let nativeFeishu = (host.registry.module(for: modules[0]) as! FeishuModule).store
        nativeFeishu.receive(message)
        AgentStore.shared.previewNotification("codex")
        AgentStore.shared.previewQuotas([quota(19)])
        let dueID = await TodoStore.shared.capture(.text("验收待办：确认消息"))!
        _ = TodoStore.shared.update(dueID, title: "验收待办：确认消息", dueAt: Date().addingTimeInterval(-1))
        TodoStore.shared.savedID = nil
        await settle()
        verify(IslandModuleAttention.shared.hints[modules[0]] == nil && IslandModuleAttention.shared.hints[modules[1]] != nil && IslandModuleAttention.shared.hints[modules[2]] != nil, "nativeOnlyBackgroundModulesHaveHints")
        verify(nativeFeishu.waitingCount == 1, "visitDoesNotMarkFeishuMessagesRead")
        verify(!AgentStore.shared.unviewedCompletionProfiles.isEmpty, "backgroundCompletionNotAcknowledged")
        capture("three-badges")
        // Let the capsule event expire: completion still needs a visit.
        try? await Task.sleep(for: .seconds(6))
        verify(AgentStore.shared.completionNotice == nil && IslandModuleAttention.shared.hints[modules[1]] != nil, "badgeOutlivesCapsule")
        let originalRegion = region(in: coordinator.nookWindow?.contentView)
        verify(swipe(-65), "nativeLeftGestureConsumed")
        await settle()
        verify(host.activeModuleID == modules[1], "nativeSwipeFeishuToAgent")
        verify(region(in: coordinator.nookWindow?.contentView) === originalRegion, "gestureStateSurvivesPageReplacement")
        verify(AgentStore.shared.unviewedCompletionProfiles.isEmpty && AgentStore.shared.hasLowQuota, "visitAcknowledgesCompletionButKeepsQuota")
        verify(IslandModuleAttention.shared.hints[modules[1]] == nil, "visitClearsAgentHintEvenWhenAnotherAgentQuotaLow")
        capture("agent-quota")
        verify(swipe(-200, phase: .changed), "remainingGestureConsumed")
        verify(swipe(-200, phase: [], momentum: .began), "nativeMomentumConsumed")
        await settle()
        verify(host.activeModuleID == modules[1], "longSwipeCannotSkipTwoPanels")
        AgentStore.shared.previewQuotas([quota(50)])
        await settle()
        verify(IslandModuleAttention.shared.hints[modules[1]] == nil, "quotaRecoveryClearsBadge")
        verify(swipe(-65), "secondGestureConsumed")
        await settle()
        verify(host.activeModuleID == modules[2], "nativeSwipeAgentToTodo")
        verify(IslandModuleAttention.shared.hints[modules[2]] == nil && TodoStore.shared.overdueCount == 1, "visitClearsTodoHintWithoutCompleting")
        capture("todo-badge")
        _ = swipe(-65); await settle()
        verify(host.activeModuleID == modules[2], "nativeEndDoesNotWrap")
        _ = swipe(65); await settle()
        verify(host.activeModuleID == modules[1], "nativeRightGestureToAgent")
        _ = swipe(65); await settle()
        verify(host.activeModuleID == modules[0], "nativeRightGestureToFeishu")
        nativeFeishu.markViewed(message.id)
        await settle()
        verify(IslandModuleAttention.shared.hints[modules[0]] == nil, "nativeViewedMessageClearsBadge")
        verify(!swipe(1, dy: -65), "verticalScrollNotConsumed")
        await settle()
        verify(host.activeModuleID == modules[0], "verticalScrollKeepsPanel")
        coordinator.showSettings(); await settle()
        AgentStore.shared.previewNotification("codex"); await settle()
        verify(IslandModuleAttention.shared.hints[modules[1]] != nil, "settingsDoesNotAcknowledgeBackgroundCompletion")
        verify(!swipe(-65), "settingsGestureNotConsumed")
        await settle()
        verify(host.activeModuleID == modules[0] && coordinator.appState.viewMode == .settings, "settingsKeepsPanel")
        coordinator.showHome(); await settle()
        coordinator.switchModule(to: modules[2]); await settle()
        coordinator.switchModule(to: modules[1]); await settle()
        verify(IslandModuleAttention.shared.hints[modules[1]] == nil, "returningFromSettingsAcknowledgesCompletion")
        AgentStore.shared.previewNotification("codex"); await settle()
        verify(IslandModuleAttention.shared.hints[modules[1]] == nil, "visibleAgentAcknowledgesNewCompletion")
        coordinator.switchModule(to: modules[2]); await settle()
        TodoStore.shared.complete(dueID); await settle()
        verify(IslandModuleAttention.shared.hints.isEmpty, "nativeResolvedBadgesClear")
        capture("cleared-badges")
        var geometry: [String: [String: String]] = [:]
        let originalSkin = AgentStore.shared.preferences.skinID
        for skin in AgentSkin.allCases {
            AgentStore.shared.selectSkin(skin.rawValue)
            coordinator.switchModule(to: modules[0]); await settle()
            AgentStore.shared.previewNotification("codex")
            AgentStore.shared.previewQuotas([quota(19)], profileID: "workbuddy")
            await settle()
            verify(IslandModuleAttention.shared.hints[modules[1]] != nil, "\(skin.rawValue).newCompletionHint")
            var sizes: [NSSize] = []
            for (name, moduleID) in zip(["feishu", "agent", "todo"], modules) {
                coordinator.switchModule(to: moduleID); await settle()
                let size = region(in: coordinator.nookWindow?.contentView)!.bounds.size
                sizes.append(size)
                geometry[skin.rawValue, default: [:]][name] = NSStringFromSize(size)
                capture("\(skin.rawValue)-\(name)")
            }
            verify(sizes.allSatisfy { abs($0.width - sizes[0].width) < 0.5 && abs($0.height - sizes[0].height) < 0.5 }, "\(skin.rawValue).samePanelDimensions")
            verify(IslandModuleAttention.shared.hints[modules[1]] == nil && AgentStore.shared.hasLowQuota, "\(skin.rawValue).seenQuotaStaysInPanelOnly")
        }
        // Long lists may scroll, but never resize the outer panel.
        let emptySize = region(in: coordinator.nookWindow?.contentView)!.bounds.size
        for index in 1...12 { _ = await TodoStore.shared.capture(.text("长列表验收\(index)")) }
        TodoStore.shared.savedID = nil; await settle()
        verify(region(in: coordinator.nookWindow?.contentView)!.bounds.size == emptySize, "longTodoListKeepsPanelDimensions")
        capture("long-todo-list")
        AgentStore.shared.selectSkin(originalSkin)
        try! JSONSerialization.data(withJSONObject: geometry, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("panel-geometry.json"))
        let report: [String: Any] = ["checks": runtime, "passed": runtime.values.allSatisfy { $0 }, "syntheticGestureEvents": true, "physicalTrackpadTested": false]
        try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("runtime-checks.json"))
    }
    print("\(passed) navigation and attention checks passed.")
    exit(0)
}
NSApplication.shared.run()
