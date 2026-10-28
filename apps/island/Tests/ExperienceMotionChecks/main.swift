import AppKit
import SwiftUI
@testable import NookSurface
@testable import NookKit
@testable import IslandShell

MainActor.assumeIsolated {
    precondition(IslandRuntime.isSkinPreview, "Motion evidence must use isolated stores")
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let output = URL(fileURLWithPath: CommandLine.arguments[1])
    try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let defaults = UserDefaults(suiteName: "experience-motion-" + UUID().uuidString)!
    NookPreferenceStorage.defaults = defaults
    let agents = AgentStore(defaults: defaults, allowsLiveReads: false, sessionIsLocked: { false })
    var preferences = agents.preferences
    preferences.enabled = true; preferences.effectsEnabled = false
    preferences.setVisibleIDs(["codex", "claude", "workbuddy"])
    try! agents.update(preferences); agents.selectSkin("codex")
    let now = Date().timeIntervalSince1970
    agents.ingestSnapshots(["codex": .init(quotas: [.init(id: "week", label: "周额度", remainingPercent: 60, resetsAt: now + 86400, updatedAt: now)], detail: "合成额度 · 用于展开动画检查")], now: now)
    let state = AppState()
    state.appearancePreferences = .init(chromePalette: .dark, openOnHover: .immediately)
    state.keepNookOpen = true
    var configuration = IslandHost.baseConfiguration(title: "Agent", symbol: "sparkles")
    configuration.chromeTheme = agents.selectedSkin.theme
    configuration.chromeBehavior.edgeDocked = true
    let modules = IslandHost.configuration().makeRegistry().descriptors.filter { IslandHost.moduleIDs.contains($0.id) }
    let switcher = NookModuleSwitcher(modules: modules, activeID: IslandHost.agentID, attentionIDs: [], switchTo: { _ in })
    let theme = NookResolvedTheme.resolve(theme: agents.selectedSkin.theme, preferences: state.appearancePreferences, effectiveColorScheme: .dark, reduceTransparency: true)
    var trace: [[String: Any]] = []
    Task { @MainActor in
        let screen = NSScreen.main!
        for baseline in [true, false] {
            let name = baseline ? "before" : "after"
            let folder = output.appendingPathComponent(name)
            try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let nook = Nook(hoverBehavior: []) {
                NookExpandedView(appState: state, services: AppServices(), toggleKeepOpen: {}, hide: {}, resetAllSettings: {}, theme: { _ in theme },
                                 home: { AnyView(AgentPanel(store: agents)) }, topBar: configuration.topBar, labels: configuration.labels, metrics: configuration.effectiveMetrics,
                                 motion: configuration.effectiveMotion, typography: configuration.effectiveTypography,
                                 width: IslandHost.panelWidth, moduleSwitcher: switcher, chromeTheme: agents.selectedSkin.theme, themeTokens: configuration.effectiveThemeTokens)
                    .environment(\.nookResolvedTheme, theme).preferredColorScheme(.dark)
            } compactLeading: {
                AgentPortrait(id: "codex", size: 25, avatar: true, motion: false, tapFeedback: false)
            } compactTrailing: { Text("Codex").font(.system(size: 10)).foregroundStyle(.white) }
            nook.edgeDocked = true; nook.presentation = .floating
            nook.hoverIntent = .init(action: .none)
            nook.backdrop = .solid(Color(red: 0.07, green: 0.08, blue: 0.10))
            nook.pointerLocation = { [weak nook] in
                guard let window = nook?.window else { return .zero }
                return .init(x: window.frame.midX, y: window.frame.maxY - 15)
            }
            let coordinator = AppCoordinator(appState: state, moduleHost: ModuleHost(configuration: configuration), surface: nook)
            coordinator.applySurfaceLook()
            nook.transitionConfiguration = baseline ? AppCoordinator.defaultTransitions : configuration.transitions!
            await nook.compact(on: screen)
            nook.configureWindow {
                $0.appearance = NSAppearance(named: .darkAqua)
                if !CommandLine.arguments.contains("--visible-motion") { $0.orderOut(nil) }
            }
            nook.setHoveringWithoutTransition(true)
            try? await Task.sleep(for: .milliseconds(700))
            // Warm both view trees before sampling. Their first SwiftUI layout
            // can otherwise consume the entire start of the capture interval.
            await nook.expand(on: screen)
            try? await Task.sleep(for: .milliseconds(700))
            nook.window?.contentView?.displayIfNeeded()
            await nook.compact(on: screen)
            try? await Task.sleep(for: .milliseconds(700))
            for closing in [false, true] {
                let action = closing ? "close" : "open"
                let initialView = nook.window!.contentView!
                let initialRect = NSRect(x: initialView.bounds.midX - 255, y: initialView.bounds.maxY - 425, width: 510, height: 425)
                let initial = initialView.bitmapImageRepForCachingDisplay(in: initialRect)!
                initialView.cacheDisplay(in: initialRect, to: initial)
                let start = Date()
                var captured: [(Int, NSBitmapImageRep)] = [(0, initial)]
                trace.append(["mode": name, "action": action, "frame": 0, "elapsed": 0,
                              "geometry": NSStringFromRect(nook.chromeFrameInWindow), "state": String(describing: nook.state)])
                let transition = Task { @MainActor in
                    if closing { await nook.compact(on: screen) } else { await nook.expand(on: screen) }
                }
                for frame in 1...32 {
                    try? await Task.sleep(for: .milliseconds(16))
                    guard let view = nook.window?.contentView else { fatalError("Missing motion window") }
                    view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
                    let rect = NSRect(x: view.bounds.midX - 255, y: view.bounds.maxY - 425, width: 510, height: 425)
                    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: rect) else { fatalError("Missing frame bitmap") }
                    let timestamp = Date().timeIntervalSince(start)
                    view.cacheDisplay(in: rect, to: bitmap)
                    captured.append((frame, bitmap))
                    trace.append(["mode": name, "action": action, "frame": frame, "elapsed": timestamp, "geometry": NSStringFromRect(nook.chromeFrameInWindow), "state": String(describing: nook.state)])
                }
                await transition.value
                // PNG compression runs only after motion, so evidence capture does
                // not stall the main actor during the transition being measured.
                for (frame, bitmap) in captured {
                    try! bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(String(format: "%@-%03d.png", action, frame)))
                }
                precondition(nook.state == (closing ? .compact : .expanded), "Transition must finish at the requested state")
                if !closing { precondition(nook.chromeFrameInWindow.height >= IslandHost.panelHeight, "Expanded content must remain accessible") }
            }
            // The two comparison runs get fresh view trees, so the outgoing
            // compact transition cannot retain the previous strategy's animation.
            let compact = Task { @MainActor in await nook.compact(on: screen) }
            try? await Task.sleep(for: .milliseconds(70))
            let reopen = Task { @MainActor in await nook.expand(on: screen) }
            await compact.value; await reopen.value
            precondition(nook.state == .expanded, "Quick reversal must finish at the last requested state")
            precondition(state.keepNookOpen, "Motion must preserve the lock selection")
            await nook.hide()
            _ = coordinator
        }
        try! JSONSerialization.data(withJSONObject: trace, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("trace.json"))
        print("PASS motion capture and reversal; real product views, synthetic accounts; visible=\(CommandLine.arguments.contains("--visible-motion"))")
        app.terminate(nil)
    }
    app.run()
}
