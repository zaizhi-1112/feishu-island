import AppKit
import SwiftUI
import NookApp
@testable import NookSurface
@testable import IslandShell

// A real window using the product's actual compact glyph and expanded controls.
// Only hover is held synthetically; clicks must come through the UI automation.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let suite = "local.youzi.island.compact-click-check.data"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = AgentStore(defaults: defaults)
    let nook = Nook {
        AgentPanel(store: store)
    } compactLeading: {
        AgentCompanionGlyph(store: store)
    } compactTrailing: {
        Text("点击展开验收").font(.system(size: 10)).foregroundStyle(.white)
    }
    nook.edgeDocked = true
    nook.presentation = .floating
    nook.hoverIntent = NookHoverIntent(action: .none)
    nook.staysExpandedOnHoverExit = true
    let reportPath = ProcessInfo.processInfo.arguments.dropFirst().first
    Task { @MainActor in
        await nook.compact(on: nil)
        nook.configureWindow { $0.setAccessibilityIdentifier("island.compactClickCheck") }
        while true {
            if nook.state == .compact { nook.setHoveringWithoutTransition(true) }
            let report: [String: Any] = [
                "state": String(describing: nook.state), "expanded": nook.state == .expanded,
                "primaryID": store.primary.id, "syntheticHover": true,
                "mouse": NSStringFromPoint(NSEvent.mouseLocation),
                "window": nook.window.map { NSStringFromRect($0.frame) } ?? "none"
            ]
            if let reportPath, let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: reportPath), options: .atomic)
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
    application.run()
}
