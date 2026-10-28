import AppKit
@testable import IslandShell
@testable import NookKit

/// Desktop changes are performed through the UI. Marker files only tell this
/// isolated harness when to reopen its own settings, never move a system Space.
@MainActor func runSettingsSpaceChecks(output: URL) async {
    let state = AppState()
    UnifiedSettingsWindow.shared.bind(appState: state)
    UnifiedSettingsWindow.shared.open(section: .agents)
    let window = NSApp.windows.first { $0.identifier?.rawValue == "feibao.settings" }!
    var reports: [[String: Any]] = []
    for scenario in ["other-desktop", "fullscreen"] {
        print("SPACE READY: \(scenario)"); fflush(stdout)
        let marker = output.appendingPathComponent("open-" + scenario)
        let start = Date()
        while !FileManager.default.fileExists(atPath: marker.path) && Date().timeIntervalSince(start) < 180 {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard FileManager.default.fileExists(atPath: marker.path) else { print("SPACE BLOCKED: UI marker missing"); exit(2) }
        let wasOnActiveSpace = window.isOnActiveSpace
        let appBefore = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        var changes = 0
        let observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { changes += 1 }
        }
        UnifiedSettingsWindow.shared.open(section: .agents)
        try? await Task.sleep(for: .seconds(2))
        NSWorkspace.shared.notificationCenter.removeObserver(observer)
        let appAfter = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let result: [String: Any] = ["scenario": scenario, "wasOnActiveSpace": wasOnActiveSpace, "isOnActiveSpace": window.isOnActiveSpace, "visible": window.isVisible, "isKey": window.isKeyWindow, "spaceChangesDuringOpen": changes, "frontmostUnchanged": appBefore == appAfter, "frontmostBefore": appBefore, "frontmostAfter": appAfter]
        reports.append(result)
        try! JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("spaces.json"))
        print("SPACE RESULT: \(result)"); fflush(stdout)
    }
    window.close()
    exit(0)
}
