import AppKit
import Sparkle
@testable import IslandShell

@MainActor final class DriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    let presenter = UpdateWindowPresenter()
    nonisolated func standardUserDriverWillShowModalAlert() { MainActor.assumeIsolated { presenter.expectModalAlert() } }
    nonisolated func standardUserDriverDidShowModalAlert() { MainActor.assumeIsolated { presenter.didCloseModalAlert() } }
    nonisolated func standardUserDriverWillFinishUpdateSession() { MainActor.assumeIsolated { presenter.endSession() } }
}

// Exercises Sparkle's real progress and modal windows using synthetic data only.
// No receiver, credentials, update download, or installation is started.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let output = URL(fileURLWithPath: CommandLine.arguments[1])
    try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    var checks: [String: Bool] = [:]
    func check(_ value: Bool, _ name: String) { checks[name] = value; print("\(value ? "PASS" : "FAIL"): \(name)"); fflush(stdout) }
    func windowRows() -> [[String: Any]] {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    }
    let island = NSPanel(contentRect: NSRect(x: 50, y: 50, width: 300, height: 80), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    island.identifier = .init("opennook.panel")
    island.level = .init(rawValue: 33)
    island.isOpaque = false; island.backgroundColor = .clear; island.ignoresMouseEvents = true
    island.isReleasedWhenClosed = false; island.orderFrontRegardless()
    let settings = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 260, height: 160), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    settings.title = "合成设置窗口"; settings.isReleasedWhenClosed = false; settings.makeKeyAndOrderFront(nil)
    let delegate = DriverDelegate()
    let driver = SPUStandardUserDriver(hostBundle: Bundle.main, delegate: delegate)
    Task { @MainActor in
        driver.showUserInitiatedUpdateCheck(cancellation: {})
        try? await Task.sleep(for: .milliseconds(1600))
        let progress = NSApp.windows.first { UpdateWindowPresenter.isSparkleWindow($0) && $0.isVisible }
        check(progress != nil, "real Sparkle progress window is recognized")
        guard let progress else { exit(1) }
        let originalLevel = progress.level
        check(originalLevel.rawValue < island.level.rawValue, "reproduces legacy prompt below the island")
        delegate.presenter.beginManualSession()
        try? await Task.sleep(for: .milliseconds(250))
        check(progress.isVisible && progress.level.rawValue > island.level.rawValue, "manual update prompt is above the island")
        check(progress.isKeyWindow && NSApp.isActive, "manual update prompt receives foreground keyboard focus")
        check(settings.level == .normal, "ordinary settings keeps normal window level")
        check(progress.collectionBehavior.contains(.moveToActiveSpace) && progress.collectionBehavior.contains(.fullScreenAuxiliary), "update prompt follows active Space and supports fullscreen applications")
        let rows = windowRows()
        let updateIndex = rows.firstIndex { ($0[kCGWindowNumber as String] as? Int) == progress.windowNumber }
        let islandIndex = rows.firstIndex { ($0[kCGWindowNumber as String] as? Int) == island.windowNumber }
        check(updateIndex != nil && islandIndex != nil && updateIndex! < islandIndex!, "WindowServer confirms update is ordered before island")
        progress.setFrameOrigin(NSPoint(x: 100_000, y: 100_000))
        delegate.presenter.presentExistingWindows()
        check(NSScreen.screens.contains { $0.visibleFrame.intersects(progress.frame) }, "offscreen update prompt is returned to a visible screen")
        progress.styleMask.insert(.miniaturizable)
        progress.miniaturize(nil)
        try? await Task.sleep(for: .milliseconds(200))
        delegate.presenter.beginManualSession()
        try? await Task.sleep(for: .milliseconds(200))
        check(!progress.isMiniaturized && progress.isVisible, "repeated check restores minimized update prompt")
        delegate.presenter.endSession()
        check(progress.level == originalLevel && !delegate.presenter.active, "session completion restores update window level")
        driver.dismissUpdateInstallation()
        try? await Task.sleep(for: .milliseconds(150))

        delegate.presenter.beginManualSession()
        let timer = Timer(timeInterval: 0.35, repeats: false) { _ in
            MainActor.assumeIsolated {
                if let modal = NSApp.modalWindow {
                    check(modal.level.rawValue > island.level.rawValue, "real Sparkle modal error is above the island")
                    check(modal.isKeyWindow, "real Sparkle modal error is directly operable")
                    NSApp.abortModal(); modal.orderOut(nil)
                } else { check(false, "real Sparkle modal error is available") }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .modalPanel)
        let error = NSError(domain: "UpdateWindowChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "合成更新错误提示", NSLocalizedRecoverySuggestionErrorKey: "本机窗口检查，不会下载或安装更新。"])
        await driver.showUpdaterError(error)
        delegate.presenter.endSession()
        check(settings.level == .normal && island.level.rawValue == 33, "update cleanup preserves settings and island levels")
        let passed = !checks.isEmpty && checks.values.allSatisfy { $0 }
        let result: [String: Any] = ["passed": passed, "checks": checks]
        try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("update-window-result.json"))
        for window in NSApp.windows { window.orderOut(nil) }
        print("\(passed ? "PASS" : "FAIL"): \(checks.count) update window checks")
        exit(passed ? 0 : 1)
    }
    app.run()
}
