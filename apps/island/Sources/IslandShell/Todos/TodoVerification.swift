import AppKit
import NookApp

@MainActor
enum TodoVerification {
    private static var started = false
    static func startIfRequested(coordinator: AppCoordinator) {
        let args = ProcessInfo.processInfo.arguments
        guard IslandRuntime.isTodoPreview, !started else { return }
        started = true
        coordinator.appState.keepNookOpen = true
        coordinator.showNook()
        guard let i = args.firstIndex(of: "--todo-capture"), args.indices.contains(i + 1), args.contains("--todo-test-root") else { return }
        let folder = URL(fileURLWithPath: args[i + 1])
        Task { @MainActor in
            let store = TodoStore.shared
            var checks: [String: Bool] = [:]
            var sounds = 0
            TodoBridge.shared.playSound = { sounds += 1 }
            let center = coordinator.moduleHost.registry.liveActivities
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try await Task.sleep(for: .seconds(1))
                checks["threeModules"] = Set(coordinator.moduleHost.descriptors.map(\.id)) == [IslandHost.feishuID, IslandHost.agentID, IslandHost.todoID]
                checks["isolatedStorage"] = store.directory.path == args[args.firstIndex(of: "--todo-test-root")! + 1]
                let initial = store.document.items.count
                for (name, module, payload) in [
                    ("feishu", IslandHost.feishuID, NookDropPayload.text("跟进客户反馈\n确认修改后的封面和交付时间")),
                    ("agents", IslandHost.agentID, NookDropPayload.link(URL(string: "https://example.com/reference")!)),
                    ("todos", IslandHost.todoID, NookDropPayload.text("整理今天的临时材料"))
                ] {
                    coordinator.switchModule(to: module)
                    try await Task.sleep(for: .milliseconds(500))
                    checks["\(name).switch"] = coordinator.activeModuleID == module
                    checks["\(name).dropAccepted"] = coordinator.configuration.onDrop?(payload) == true
                    try await Task.sleep(for: .milliseconds(400))
                    checks["\(name).capture"] = capture(coordinator, to: folder.appendingPathComponent("\(name)-capture.png"))
                }
                checks["allModulesSave"] = store.document.items.count == initial + 3
                coordinator.switchModule(to: IslandHost.todoID)
                try await Task.sleep(for: .milliseconds(400))
                if let item = store.pending.first {
                    store.selectedID = item.id
                    try await Task.sleep(for: .milliseconds(500))
                    checks["detailsCapture"] = capture(coordinator, to: folder.appendingPathComponent("todo-detail.png"))
                    checks["viewDoesNotComplete"] = store.item(item.id)?.completedAt == nil
                    store.selectedID = nil
                }
                coordinator.showSettings()
                try await Task.sleep(for: .milliseconds(400))
                checks["settingsCapture"] = capture(coordinator, to: folder.appendingPathComponent("todo-settings.png"))
                coordinator.showHome()
                // Arrival while the person is in Feishu must leave its content in place.
                coordinator.switchModule(to: IslandHost.feishuID)
                try await Task.sleep(for: .milliseconds(400))
                let due = await store.capture(.text("到时间了：确认交付反馈"))!
                _ = store.update(due, title: "到时间了：确认交付反馈", dueAt: Date().addingTimeInterval(-1))
                TodoBridge.shared.tick()
                checks["noTakeoverWhileExpanded"] = coordinator.activeModuleID == IslandHost.feishuID && coordinator.appState.isNookVisible
                checks["singleSound"] = sounds == 1
                TodoBridge.shared.tick()
                checks["timerDoesNotRepeatSound"] = sounds == 1
                store.savedID = nil
                if coordinator.appState.keepNookOpen { coordinator.toggleKeepNookOpen() }
                coordinator.hideNook()
                try await Task.sleep(for: .milliseconds(700))
                TodoBridge.shared.tick()
                try await Task.sleep(for: .milliseconds(800))
                checks["compactOnly"] = !coordinator.appState.isNookVisible && center.entry(moduleID: IslandHost.todoID, id: "todo-reminder")?.activity.alert == .compact(.seconds(5))
                checks["reminderCapture"] = capture(coordinator, to: folder.appendingPathComponent("todo-reminder.png"))
                coordinator.showNook()
                try await Task.sleep(for: .milliseconds(700))
                checks["clickReminderEntersTodos"] = coordinator.activeModuleID == IslandHost.todoID && coordinator.appState.isNookVisible
                coordinator.hideNook()
                try await Task.sleep(for: .milliseconds(400))
                // Agent completion retains its own activity, instead of being overwritten.
                AgentStore.shared.previewNotification("codex")
                checks["competingAlertWaits"] = center.primary?.moduleID == IslandHost.todoID
                checks["separateActivityIDs"] = center.entry(moduleID: IslandHost.todoID, id: "todo-reminder") != nil && center.entry(moduleID: IslandHost.agentID, id: "agent-status") != nil
                try await Task.sleep(for: .seconds(6))
                TodoBridge.shared.tick()
                checks["reminderRetracted"] = !coordinator.appState.isNookVisible && center.entry(moduleID: IslandHost.todoID, id: "todo-reminder") == nil
                checks["overdueBadgePersists"] = store.overdueCount == 1
                NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
                try await Task.sleep(for: .milliseconds(500))
                checks["wakeDoesNotRepeatSound"] = sounds == 1
                coordinator.appState.keepNookOpen = true
                coordinator.switchModule(to: IslandHost.todoID); coordinator.showNook()
                try await Task.sleep(for: .milliseconds(700))
                checks["listCapture"] = capture(coordinator, to: folder.appendingPathComponent("todo-list.png"))
                // Both hardware layouts on the attached screens, using the real surface.
                let originalDisplay = coordinator.appState.displayPreference
                for (name, preference) in [("built-in", NookDisplayPreference.builtIn), ("automatic", .automatic)] {
                    coordinator.appState.displayPreference = preference
                    NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                    try await Task.sleep(for: .seconds(1))
                    checks["\(name).capture"] = capture(coordinator, to: folder.appendingPathComponent("todo-\(name).png"))
                }
                coordinator.hideNook()
                try await Task.sleep(for: .milliseconds(700))
                var appearance = coordinator.appState.appearancePreferences
                appearance.presentation = .notch
                coordinator.appState.replaceAppearancePreferences(appearance)
                coordinator.appState.keepNookOpen = true
                coordinator.showNook()
                try await Task.sleep(for: .milliseconds(1400))
                checks["forcedNotchExpanded"] = coordinator.appState.isNookVisible
                checks["forcedNotchCapture"] = capture(coordinator, to: folder.appendingPathComponent("todo-forced-notch.png"))
                appearance.presentation = .auto
                coordinator.appState.replaceAppearancePreferences(appearance)
                coordinator.appState.displayPreference = originalDisplay
            } catch { checks["exception"] = false; fputs("Todo runtime: \(error)\n", stderr) }
            let screens: [[String: Any]] = NSScreen.screens.map { ["name": $0.localizedName, "safeAreaTop": $0.safeAreaInsets.top, "frame": NSStringFromRect($0.frame)] }
            let report: [String: Any] = ["checks": checks, "screens": screens, "soundCalls": sounds,
                "syntheticEvents": true, "physicalSleepTested": false, "passed": !checks.isEmpty && checks.values.allSatisfy { $0 }]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: folder.appendingPathComponent("runtime-checks.json"))
                FileHandle.standardOutput.write(data)
            }
            exit(!checks.isEmpty && checks.values.allSatisfy { $0 } ? 0 : 1)
        }
    }

    private static func capture(_ coordinator: AppCoordinator, to url: URL) -> Bool {
        guard let view = coordinator.nookWindow?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: url); return true } catch { return false }
    }
}
