import AppKit
import NookApp

/// Isolated visual preview. This process uses a separate bundle and preference suites;
/// it never starts Agent readers or the Feishu receiver.
@MainActor
enum SkinVerification {
    private static var started = false
    static func startIfRequested(coordinator: AppCoordinator) {
        let args = ProcessInfo.processInfo.arguments
        guard IslandRuntime.isSkinPreview, !started else { return }
        started = true
        coordinator.appState.keepNookOpen = true
        coordinator.showNook()
        if let index = args.firstIndex(of: "--skin-notification-test"), args.indices.contains(index+1) {
            notificationCheck(coordinator, folder:URL(fileURLWithPath:args[index+1],isDirectory:true)); return
        }
        guard let index = args.firstIndex(of: "--skin-capture"), args.indices.contains(index + 1) else { return }
        let folder = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        Task { @MainActor in
            var checks: [String: Bool] = [:]
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try await Task.sleep(for: .seconds(1))
                let store = AgentStore.shared
                store.selectPrimary("codex")
                for skin in AgentSkin.allCases {
                    store.selectSkin(skin.rawValue)
                    checks["\(skin.rawValue).independent"] = store.primary.id == "codex" && store.selectedSkin == skin
                    checks["\(skin.rawValue).theme"] = store.themeSource.theme.name == skin.theme.name
                    for palette in [NookChromePalette.dark, .light] {
                      var appearance = coordinator.appState.appearancePreferences
                      appearance.chromePalette = palette
                      coordinator.appState.replaceAppearancePreferences(appearance)
                      let mode = palette == .dark ? "dark" : "light"
                      for (name, module) in [("feishu", IslandHost.feishuID), ("agent", IslandHost.agentID)] {
                        coordinator.switchModule(to: module)
                        coordinator.showHome(); coordinator.showNook()
                        try await Task.sleep(for: .milliseconds(700))
                        checks["\(skin.rawValue).\(mode).\(name)"] = capture(coordinator, to: folder.appendingPathComponent("\(skin.rawValue)-\(mode)-\(name).png"))
                      }
                      coordinator.showSettings()
                      try await Task.sleep(for: .milliseconds(700))
                      checks["\(skin.rawValue).\(mode).settings"] = capture(coordinator, to: folder.appendingPathComponent("\(skin.rawValue)-\(mode)-settings.png"))
                    }
                }
                store.selectSkin("workbuddy"); store.selectPrimary("claude")
                checks["manualSurvivesAgentChange"] = store.selectedSkin == .workbuddy
                store.selectSkin("auto")
                checks["autoFollowsAgent"] = store.selectedSkin == .claude
                store.selectPrimary("codex"); store.selectSkin("codex")
                var restored=coordinator.appState.appearancePreferences;restored.chromePalette = .dark
                coordinator.appState.replaceAppearancePreferences(restored)
            } catch { fputs("Skin capture: \(error)\n", stderr) }
            let report: [String: Any] = ["checks": checks, "passed": checks.count == 34 && checks.values.allSatisfy { $0 }]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: folder.appendingPathComponent("native-checks.json"))
                FileHandle.standardOutput.write(data)
            }
            exit(checks.count == 34 && checks.values.allSatisfy { $0 } ? 0 : 1)
        }
    }
    private static func notificationCheck(_ coordinator: AppCoordinator, folder: URL) {
        Task { @MainActor in
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let store = AgentStore.shared
            store.selectPrimary("codex"); store.selectSkin("codex")
            coordinator.switchModule(to: IslandHost.feishuID)
            if coordinator.appState.keepNookOpen { coordinator.toggleKeepNookOpen() }
            var appearance = coordinator.appState.appearancePreferences
            appearance.chromePalette = .dark
            coordinator.appState.replaceAppearancePreferences(appearance)
            try? await Task.sleep(for: .seconds(2))
            var checks: [String: Bool] = [:]
            let center = coordinator.moduleHost.registry.liveActivities
            for id in ["codex", "workbuddy", "claude"] {
                coordinator.hideNook()
                try? await Task.sleep(for: .milliseconds(700))
                store.previewNotification(id)
                for (frame, delay) in [("arrival", 100), ("check", 250), ("settled", 800)] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    checks["\(id).\(frame)Capture"] = capture(coordinator, to: folder.appendingPathComponent("\(id)-\(frame).png"))
                }
                let entry = center.entry(moduleID: IslandHost.agentID, id: "agent-status")
                checks["\(id).secondStageOnly"] = !coordinator.appState.isNookVisible && entry?.activity.alert == .compact(.seconds(5)) && entry?.activity.peek == nil
                checks["\(id).oneStatusActivity"] = center.activities.filter { $0.moduleID == IslandHost.agentID }.count == 1
                checks["\(id).keepsThemeAndPrimary"] = store.selectedSkin == .codex && store.primary.id == "codex"
                checks["\(id).completionIdentity"] = store.completionNotice?.profileID == id && store.completionNotice?.stillWorking == false
                if id == "workbuddy" {
                    coordinator.showNook()
                    try? await Task.sleep(for: .milliseconds(700))
                    checks["openingShowsCompletionDetails"] = coordinator.appState.moduleBreadcrumb == entry?.activity.accessibilityLabel && coordinator.appState.isNookVisible
                    checks["detailCapture"] = capture(coordinator, to: folder.appendingPathComponent("workbuddy-details.png"))
                }
                try? await Task.sleep(for: .seconds(6))
                checks["\(id).restoresStatus"] = store.completionNotice == nil && center.entry(moduleID: IslandHost.agentID, id: "agent-status")?.activity.priority == .low
                if id != "workbuddy" {
                    checks["\(id).retractedCapture"] = capture(coordinator, to: folder.appendingPathComponent("\(id)-retracted.png"))
                    checks["\(id).remainsCollapsed"] = !coordinator.appState.isNookVisible
                } else {
                    checks["userOpenedPanelStaysOpen"] = coordinator.appState.isNookVisible
                    checks["userOpenedDetailsKeepTheirModule"] = coordinator.appState.moduleBreadcrumb == entry?.activity.accessibilityLabel
                    checks["detailAfterDwellCapture"] = capture(coordinator, to: folder.appendingPathComponent("workbuddy-details-after-dwell.png"))
                }
            }
            coordinator.hideNook()
            try? await Task.sleep(for: .milliseconds(700))
            store.setEffectsEnabled(false)
            store.previewNotification("codex", stillWorking: true)
            try? await Task.sleep(for: .milliseconds(900))
            checks["concurrentTaskKeepsWorking"] = store.completionNotice?.stillWorking == true && store.completionNotice?.status.contains("仍在工作") == true
            checks["effectsOffCapture"] = capture(coordinator, to: folder.appendingPathComponent("codex-still-working-effects-off.png"))
            checks["effectsOffStillReveals"] = !coordinator.appState.isNookVisible && center.primary?.activity.alert == .compact(.seconds(5))
            try? await Task.sleep(for: .seconds(6))
            store.setEffectsEnabled(true)
            store.previewNotification("codex")
            try? await Task.sleep(for: .seconds(3))
            store.previewNotification("workbuddy")
            try? await Task.sleep(for: .seconds(3))
            checks["consecutiveCompletionIdentity"] = store.completionNotice?.profileID == "workbuddy"
            checks["renewedDwellCapture"] = capture(coordinator, to: folder.appendingPathComponent("renewed-dwell.png"))
            try? await Task.sleep(for: .seconds(4))
            checks["consecutiveCompletionRestores"] = store.completionNotice == nil && !coordinator.appState.isNookVisible
            checks["renewedRetractionCapture"] = capture(coordinator, to: folder.appendingPathComponent("renewed-retracted.png"))
            let report: [String: Any] = ["checks": checks, "synthetic": true, "passed": !checks.isEmpty && checks.values.allSatisfy { $0 }]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: folder.appendingPathComponent("notification-checks.json"))
                FileHandle.standardOutput.write(data)
            }
            exit(checks.values.allSatisfy { $0 } ? 0 : 1)
        }
    }
    private static func capture(_ coordinator: AppCoordinator, to url: URL) -> Bool {
        guard let view = coordinator.nookWindow?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: url); return true } catch { return false }
    }
}
