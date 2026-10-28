import AppKit
import NookApp

/// Opt-in real-window check; never runs during ordinary use.
@MainActor
enum RuntimeVerification {
    private static var started = false
    static func startIfRequested(coordinator: AppCoordinator) {
        guard ProcessInfo.processInfo.arguments.contains("--self-test"), !started else { return }
        started = true
        Task { @MainActor in
            var checks: [String: Bool] = [:]
            var placement: [String: [String: String]] = [:]
            checks["expandCollapse"] = await coordinator.runLaunchSmokeTest(timeout: 10)
            coordinator.showNook()
            checks["expanded"] = await wait { coordinator.appState.isNookVisible }
            let hostView = coordinator.nookWindow?.contentView?.subviews.first
            checks["firstMouseAccepted"] = hostView?.acceptsFirstMouse(for: nil) == true
            coordinator.switchModule(to: IslandHost.feishuID)
            checks["switchToFeishu"] = await wait { coordinator.activeModuleID == IslandHost.feishuID }
            coordinator.switchModule(to: IslandHost.agentID)
            checks["switchToAgents"] = await wait { coordinator.activeModuleID == IslandHost.agentID }

            coordinator.switchModule(to: IslandHost.todoID)
            checks["switchToTodos"] = await wait { coordinator.activeModuleID == IslandHost.todoID }
            coordinator.switchModule(to: IslandHost.platformID)
            checks["switchToPlatform"] = await wait { coordinator.activeModuleID == IslandHost.platformID }
            checks["onlyUsefulModules"] = Set(coordinator.moduleHost.descriptors.map(\.id)) == [IslandHost.feishuID, IslandHost.agentID, IslandHost.todoID, IslandHost.platformID]
            coordinator.switchModule(to: IslandHost.feishuID)
            checks["switchBackToFeishu"] = await wait { coordinator.activeModuleID == IslandHost.feishuID }
            UnifiedSettingsWindow.shared.open()
            checks["settings"] = await wait { UnifiedSettingsWindow.shared.model.visible }
            checks["noIslandSettingsPage"] = coordinator.appState.viewMode == .home
            for section in UnifiedSettingsSection.allCases {
                UnifiedSettingsWindow.shared.open(section: section)
                checks["settings."+section.rawValue] = UnifiedSettingsWindow.shared.model.section == section
            }
            NSApp.windows.first { $0.identifier?.rawValue == "feibao.settings" }?.close()
            coordinator.showHome()
            // Exercise the actual screen/wake observer and window rebuild on the live display.
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            try? await Task.sleep(for: .seconds(1))
            checks["screenRebuild"] = visibleOnTarget(coordinator)
            placement["screenRebuild"] = placementDetails(coordinator)
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            try? await Task.sleep(for: .seconds(1))
            checks["wakeRebuild"] = visibleOnTarget(coordinator)
            placement["wakeRebuild"] = placementDetails(coordinator)
            checks["hotkeyRegistered"] = coordinator.appState.hotkeyRegistrationFailures.isEmpty
            coordinator.hideNook()
            checks["finalCollapse"] = await wait { !coordinator.appState.isNookVisible }
            let screens: [[String: Any]] = NSScreen.screens.map {
                ["name": $0.localizedName, "frame": NSStringFromRect($0.frame), "safeAreaTop": $0.safeAreaInsets.top]
            }
            let report: [String: Any] = ["checks": checks, "screens": screens, "placement": placement,
                "physicalHotPlugTested": false, "passed": checks.values.allSatisfy { $0 }]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            exit(checks.values.allSatisfy { $0 } ? 0 : 1)
        }
    }

    private static func visibleOnTarget(_ coordinator: AppCoordinator) -> Bool {
        guard let window = coordinator.nookWindow, window.isVisible,
              let screen = NookScreenLocator.screen(matching: coordinator.appState.displayPreference)
        else { return false }
        return abs(window.frame.midX - screen.frame.midX) < 2
            && abs(window.frame.maxY - screen.frame.maxY) < 2
            // AppKit can report a different screen object when displays have
            // identical desktop bounds. Geometry is still the same visible target.
            && (window.screen == screen || window.screen?.frame == screen.frame)
    }

    private static func placementDetails(_ coordinator: AppCoordinator) -> [String: String] {
        let target = NookScreenLocator.screen(matching: coordinator.appState.displayPreference)
        let window = coordinator.nookWindow
        return ["target": target?.localizedName ?? "none", "actual": window?.screen?.localizedName ?? "none",
                "targetFrame": target.map { NSStringFromRect($0.frame) } ?? "none",
                "actualScreenFrame": window?.screen.map { NSStringFromRect($0.frame) } ?? "none",
                "windowFrame": window.map { NSStringFromRect($0.frame) } ?? "none",
                "visible": String(window?.isVisible ?? false)]
    }

    private static func wait(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}
