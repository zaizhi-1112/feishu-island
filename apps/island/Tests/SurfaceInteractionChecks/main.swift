import AppKit
import SwiftUI
import Combine
@testable import NookSurface
@testable import NookKit
@testable import IslandShell

// Native, synthetic-only fixture. Never opens an account store or starts a reader.
MainActor.assumeIsolated {
    let preferenceSuite = "surface-keep-open-check." + UUID().uuidString
    let previousDefaults = NookPreferenceStorage.defaults
    NookPreferenceStorage.defaults = UserDefaults(suiteName: preferenceSuite)!
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let output = URL(fileURLWithPath: CommandLine.arguments[1])
    try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let screen = NSScreen.main!
    let nook = Nook {
        VStack(alignment: .leading, spacing: 18) {
            Text("消息     Agent     待办     中台").font(.system(size: 12))
            Divider()
            Text("待办").font(.title2)
            TextField("接下来要做的事", text: .constant("合成输入"))
            Text("合成内容 · 固定内容区与内部滚动保持原样")
            Spacer()
        }.padding(16).frame(width: 416, height: 459).foregroundStyle(.white)
    } compactLeading: {
        AgentPortrait(id: "codex", size: 25, avatar: true, state: .working, motion: false, tapFeedback: false)
            .overlay(alignment: .bottomTrailing) { Circle().fill(.red).frame(width: 5, height: 5) }
    } compactTrailing: {
        Text("WorkBuddy · 正在处理你的任务").font(.system(size: 10)).foregroundStyle(.white)
    }
    nook.pointerLocation = { [weak nook] in
        guard let nook, let window = nook.window else { return .zero }
        return nook.isHovering
            ? NSPoint(x: window.frame.midX, y: window.frame.maxY - nook.physicalNotchHeight - 2)
            : NSPoint(x: window.frame.minX - 100, y: window.frame.minY - 100)
    }
    nook.edgeDocked = true
    nook.presentation = .floating
    nook.hoverIntent = NookHoverIntent(action: .none)
    nook.backdrop = .solid(Color(red: 0.08, green: 0.1, blue: 0.12))
    // The dock must stay shadow-free even if a theme supplies a shadow.
    nook.chromeShadow = .soft
    nook.peekContent = AnyView(Text("点击展开").frame(width: 200, height: 90))
    var checks: [String: Bool] = [:]
    var measurements: [String: String] = [:]
    var blockedChecks: [String] = []
    @MainActor func check(_ value: Bool, _ name: String) {
        checks[name] = value
        precondition(value, name)
    }
    @MainActor func checkCompleteStartup() async {
        let bootState = AppState()
        bootState.keepNookOpen = true
        let boot = AppCoordinator(appState: bootState, moduleHost: ModuleHost(registry: IslandHost.configuration().makeRegistry()))
        print("BOOT: starting full coordinator"); fflush(stdout)
        boot.start()
        print("BOOT: startup queued"); fflush(stdout)
        await boot.drainLifecycleForTesting()
        print("BOOT: lifecycle drained"); fflush(stdout)
        try? await Task.sleep(for: .milliseconds(800))
        check(bootState.keepNookOpen && bootState.isNookVisible, "complete preview startup finishes locked and expanded")
        try? await Task.sleep(for: .seconds(2))
        check(bootState.isNookVisible, "complete preview startup stays expanded with the real pointer")
        UnifiedSettingsWindow.shared.open(section: .platform)
        await boot.drainLifecycleForTesting()
        print("BOOT: lifecycle drained"); fflush(stdout)
        try? await Task.sleep(for: .milliseconds(800))
        check(boot.nookWindow?.isVisible == true && bootState.isNookVisible, "complete startup keeps island visible with settings open")
        let liveSettings = NSApp.windows.first { $0.identifier?.rawValue == "feibao.settings" }!
        check(liveSettings.styleMask.contains(.nonactivatingPanel) && liveSettings.collectionBehavior.contains(.moveToActiveSpace), "live settings uses current-Space nonactivating policy")
        check(liveSettings.collectionBehavior.contains(.canJoinAllApplications) && liveSettings.collectionBehavior.contains(.fullScreenAuxiliary), "live settings is eligible for other fullscreen apps")
        let liveField = NSTextField(frame: NSRect(x: 24, y: 24, width: 180, height: 24))
        liveSettings.contentView!.addSubview(liveField)
        liveSettings.makeKeyAndOrderFront(nil)
        check(liveSettings.makeFirstResponder(liveField), "live settings accepts text editor focus")
        try? await Task.sleep(for: .milliseconds(100))
        check(liveSettings.isKeyWindow && NookPanel.acceptsTyping(liveSettings.firstResponder), "live settings owns actual text input")
        liveSettings.makeFirstResponder(nil); liveSettings.endEditing(for: nil); liveField.removeFromSuperview()
        liveSettings.miniaturize(nil)
        try? await Task.sleep(for: .milliseconds(800))
        check(boot.nookWindow?.isVisible == true, "minimizing live settings leaves island visible")
        UnifiedSettingsWindow.shared.open(section: .agents)
        try? await Task.sleep(for: .milliseconds(800))
        check(liveSettings.isVisible && !liveSettings.isMiniaturized, "opening minimized settings restores a usable panel")
        boot.switchModule(to: IslandHost.agentID)
        await boot.drainSwitchTailsForTesting()
        await boot.drainLifecycleForTesting()
        UnifiedSettingsWindow.shared.open(section: .agents)
        let store = AgentStore.shared
        let saved = store.preferences
        var quotaPrefs = store.preferences
        quotaPrefs.enabled = false; quotaPrefs.quotaDisplayEnabled = true
        try! store.update(quotaPrefs)
        try? await Task.sleep(for: .milliseconds(100))
        let quotaActivity = boot.liveActivities.activities.first { $0.activity.id == "agent-status" }
        check(quotaActivity != nil && quotaActivity?.activity.keepsCompactVisible == false, "enabled quota stays available without holding the capsule open")
        let bootSurface = boot.surface as! Nook<AnyView, AnyView, AnyView>
        check(!bootSurface.compactRevealActive, "real coordinator does not force reveal for persistent quota")
        boot.toggleKeepNookOpen()
        bootSurface.pointerLocation = { .zero }
        bootSurface.setHoveringWithoutTransition(false)
        await bootSurface.compact(on: screen)
        try? await Task.sleep(for: .milliseconds(800))
        check(bootSurface.state == .compact && !bootSurface.isHovering && !bootSurface.isPeeking && !bootSurface.compactRevealActive, "quota-enabled island retracts after the pointer leaves")
        let quotaView = boot.nookWindow!.contentView!
        quotaView.layoutSubtreeIfNeeded()
        let quotaBitmap = quotaView.bitmapImageRepForCachingDisplay(in: quotaView.bounds)!
        quotaView.cacheDisplay(in: quotaView.bounds, to: quotaBitmap)
        try! quotaBitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("quota-enabled-retracted.png"))
        var switchPrefs=store.preferences;switchPrefs.setVisibleIDs(["codex","claude","workbuddy"]);try! store.update(switchPrefs)
        for id in ["workbuddy","claude","codex"] {
            store.selectPrimary(id)
            try? await Task.sleep(for:.milliseconds(850))
            check(bootSurface.compactRevealActive && bootSurface.state == .compact,"primary selection reveals second stage: "+id)
            check(store.primarySwitchNotice?.profileID==id,"revealed identity matches selected Agent: "+id)
            let host=boot.nookWindow!.contentView!;host.layoutSubtreeIfNeeded()
            let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
            try! bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("switch-"+id+".png"))
        }
        try? await Task.sleep(for:.milliseconds(3400))
        check(!bootSurface.compactRevealActive && bootSurface.state == .compact,"selection feedback expires and island retracts")
        boot.toggleKeepNookOpen()
        boot.showNook()
        await boot.drainLifecycleForTesting()
        for (name, ids) in [("both", ["codex", "workbuddy"]), ("without-codex", ["workbuddy"]), ("without-workbuddy", ["codex"]), ("restored-both", ["codex", "workbuddy"]), ("none", [])] {
            var prefs = store.preferences
            prefs.enabled = false; prefs.quotaDisplayEnabled = false
            prefs.setVisibleIDs(ids)
            try! store.update(prefs)
            try? await Task.sleep(for: .milliseconds(800))
            check(boot.nookWindow?.isVisible == true && bootState.isNookVisible && UnifiedSettingsWindow.shared.model.visible, "live Agent change preserves both windows: \(name)")
            let view = boot.nookWindow!.contentView!
            view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("live-agent-" + name + ".png"))
        }
        var restored = saved; restored.revision = store.preferences.revision
        try! store.update(restored)
        NSApp.windows.first { $0.identifier?.rawValue == "feibao.settings" }!.close()
        await boot.drainLifecycleForTesting()
        print("BOOT: lifecycle drained"); fflush(stdout)
        try? await Task.sleep(for: .milliseconds(800))
        check(bootState.isNookVisible && bootState.keepNookOpen, "complete startup preserves the locked island after settings close")
    }
    Task { @MainActor in
        if CommandLine.arguments.contains("--space-review") { await runSettingsSpaceChecks(output: output); return }
        if CommandLine.arguments.contains("--startup-only") {
            await checkCompleteStartup()
            let report: [String: Any] = ["checks": checks, "passed": checks.values.allSatisfy { $0 }]
            try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("startup-result.json"))
            print("PASS: \(checks.count) complete startup and settings checks")
            exit(0)
        }
        @MainActor func settle() async { try? await Task.sleep(for: .milliseconds(800)) }
        @MainActor func capture(_ name: String) {
            guard let view = nook.window?.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Missing fixture window") }
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            measurements[name] = NSStringFromRect(nook.chromeFrameInWindow)
        }
        await nook.compact(on: screen)
        check(nook.window?.hasShadow == false, "native panel never casts a rectangular shadow")
        nook.configureWindow { $0.orderOut(nil) }
        await settle()
        capture("stage-1")
        nook.setHoveringWithoutTransition(true)
        for (name, delay) in [("reveal-080", 80), ("reveal-180", 100), ("reveal-360", 180), ("reveal-680", 320)] {
            try? await Task.sleep(for: .milliseconds(delay))
            capture(name)
        }
        await settle()
        capture("stage-2")
        let compact = nook.chromeFrameInWindow.size
        await nook.peek(on: screen)
        await settle()
        capture("stage-2-peek")
        check(nook.chromeFrameInWindow.size == compact, "peek keeps the second stage a single capsule")
        check(compact.height < 50, "second stage stays shorter than 50pt")
        await nook.expand(on: screen)
        nook.configureWindow { $0.orderOut(nil) }
        await settle()
        capture("stage-3")
        check(nook.chromeFrameInWindow.height >= 459, "third stage preserves the full viewport")

        // Empty measured bounds make the native pointer query follow the injected
        // hover state, so the user's real pointer cannot influence timing assertions.
        @MainActor func leave() {
            nook.chromeFrameInWindow = .zero
            nook.setHoveringWithoutTransition(true)
            nook.updateHoverState(false)
        }
        leave()
        try? await Task.sleep(for: .milliseconds(80))
        check(nook.state == .compact, "idle mouse exit begins collapse within 80ms")
        capture("collapse-080")
        try? await Task.sleep(for: .milliseconds(100))
        capture("collapse-180")
        try? await Task.sleep(for: .milliseconds(180))
        capture("collapse-360")
        await settle()
        capture("collapsed-settled")
        await nook.expand(on: screen)
        leave()
        nook.updateHoverState(true)
        try? await Task.sleep(for: .milliseconds(100))
        check(nook.state == .expanded, "rapid pointer return cancels an older collapse")
        leave()
        try? await Task.sleep(for: .milliseconds(80))
        check(nook.state == .compact, "another pointer exit after returning still collapses")
        await nook.expand(on: screen)
        nook.beginLayoutGrace()
        leave()
        try? await Task.sleep(for: .milliseconds(80))
        check(nook.state == .compact, "layout grace cannot delay a real pointer exit")

        await nook.expand(on: screen)
        nook.staysExpandedOnHoverExit = true
        leave()
        try? await Task.sleep(for: .milliseconds(750))
        check(nook.state == .expanded, "active editing or presentation pin survives pointer exit")
        nook.staysExpandedOnHoverExit = false
        try? await Task.sleep(for: .milliseconds(80))
        check(nook.state == .compact, "ending the task releases a deferred pointer exit")

        await nook.expand(on: screen)
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: nil)
        await Task.yield()
        leave()
        try? await Task.sleep(for: .milliseconds(100))
        check(nook.state == .expanded, "native menus keep the panel open")
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(80))
        check(nook.state == .compact, "closing a menu releases the deferred exit")

        let text = NSTextView()
        check(NookPanel.acceptsTyping(text), "native editable text is recognized")
        text.isEditable = false
        check(!NookPanel.acceptsTyping(text), "read-only text is not an editing hold")
        check(!NookPanel.acceptsTyping(NSButton()), "a clicked button is not an editing hold")
        if !ScreenReminderSession.isLocked {
        // Establish input while the controlled pointer is inside. Moving the
        // fixture window with an outside pointer can legitimately collapse it
        // before AppKit has handed the field its editor.
        nook.setHoveringWithoutTransition(true)
        await nook.expand(on: screen)
        let panel = nook.window as! NookPanel
        let originalOrigin = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 20, y: screen.visibleFrame.minY + 20))
        let field = NSTextField(frame: NSRect(x: 20, y: 20, width: 180, height: 24))
        panel.contentView!.addSubview(field)
        NSApp.activate(ignoringOtherApps: true)
        await Task.yield()
        panel.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(200))
        panel.makeKey()
        let acquiredField = panel.makeFirstResponder(field)
        check(acquiredField, "AppKit accepts the native field editor")
        print("READY: native keyboard focus fixture"); fflush(stdout)
        for _ in 0..<100 where !panel.isKeyWindow {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKey()
            panel.makeFirstResponder(field)
            try? await Task.sleep(for: .milliseconds(100))
        }
        check(panel.isKeyWindow && NookPanel.acceptsTyping(panel.firstResponder), "native text field actually owns keyboard focus")
        check(nook.state == .expanded, "typing fixture begins on an expanded panel")
        leave()
        try? await Task.sleep(for: .milliseconds(750))
        check(nook.state == .expanded, "editing text survives pointer exit without a presentation pin")
        panel.makeFirstResponder(nil)
        try? await Task.sleep(for: .milliseconds(100))
        check(nook.state == .compact, "ending native text editing collapses after the pointer left")
        field.removeFromSuperview()
        panel.orderOut(nil)
        panel.setFrameOrigin(originalOrigin)
        } else {
            blockedChecks.append("Native keyboard focus, typing hold and ending-edit collapse require an unlocked Mac")
        }

        for physical in [CGFloat(0), CGFloat(32)] {
            var capsuleSizes: [CGSize] = []
            var panelSizes: [CGSize] = []
            for mode in [NookPresentation.floating, .notch] {
                nook.presentation = mode
                await nook.compact(on: screen)
                nook.configureWindow { $0.orderOut(nil) }
                nook.updateScreenGeometry(notch: CGSize(width: physical > 0 ? 180 : 300, height: physical > 0 ? 32 : 30),
                                          physicalHeight: physical, menuHeight: physical > 0 ? 32 : 30)
                nook.setHoveringWithoutTransition(false)
                await settle()
                check(nook.layoutForm == .floating,
                      "first stage honors real hardware in \(mode.rawValue)-\(physical)")
                capture("\(mode.rawValue)-\(Int(physical))-stage-1")
                nook.setHoveringWithoutTransition(true)
                await settle()
                check(nook.layoutForm == .floating, "second stage floats in \(mode.rawValue)-\(physical)")
                capsuleSizes.append(nook.chromeFrameInWindow.size)
                capture("\(mode.rawValue)-\(Int(physical))-stage-2")
                await nook.expand(on: screen)
                await settle()
                check(nook.layoutForm == .floating, "third stage floats in \(mode.rawValue)-\(physical)")
                panelSizes.append(nook.chromeFrameInWindow.size)
                capture("\(mode.rawValue)-\(Int(physical))-stage-3")
            }
            check(capsuleSizes[0] == capsuleSizes[1], "second-stage sizes match on physical notch \(physical)")
            check(capsuleSizes[0].height == 30, "second-stage capsule always measures 30pt")
            if physical > 0 { check(capsuleSizes[0].width <= 180, "long WorkBuddy status fits the physical notch width") }
            check(panelSizes[0] == panelSizes[1], "third-stage sizes match on physical notch \(physical)")
        }
        check(SkinManifest.shared.agents["codex"]?.avatar == "avatar-codex.png"
              && SkinResources.images["avatar-codex.png"] != nil, "unified blue robot asset exists and is selected")
        let defaults = UserDefaults(suiteName: "surface-palette-check." + UUID().uuidString)!
        let agents = AgentStore(defaults: defaults, allowsLiveReads: false)
        agents.selectSkin("workbuddy")
        agents.setEffectsEnabled(false)
        let state = AppState()
        for (name, form, dark) in [("capsule-light", NookChromeForm.floating, false), ("capsule-dark", .floating, true)] {
            let host = NookCompactHost(appState: state, theme: { _ in
                .resolve(theme: agents.selectedSkin.theme, preferences: .init(chromePalette: dark ? .dark : .light),
                         effectiveColorScheme: dark ? .dark : .light, reduceTransparency: true)
            }, services: AppServices(), labels: .default, metrics: .default, motion: .default,
               typography: .default, branding: .default, chromeActions: .inert,
               chromeTheme: agents.selectedSkin.theme) {
                IslandCompactTitle(title: "Codex · 工作中")
            }
            .frame(width: 240, height: 32)
            .background { IslandSkinBackdrop(store: agents, dark: dark, compact: true, notched: form == .notch) }
            .environment(\.nookChromeShape, NookShape(form: form, topCornerRadius: 6, bottomCornerRadius: 14))
            let view = NSHostingView(rootView: host)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 32),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            await settle()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            let sample = bitmap.colorAt(x: 4, y: 4)!.usingColorSpace(.deviceRGB)!
            let brightness = (sample.redComponent + sample.greenComponent + sample.blueComponent) / 3
            check(form == .notch ? brightness < 0.01 : (dark ? brightness < 0.3 : brightness > 0.7),
                  "palette background matches \(name)")
            window.close()
        }
        var fullConfiguration = NookConfiguration()
        fullConfiguration.chromeBehavior.edgeDocked = true
        fullConfiguration.chromeBehavior.backdrop = { _ in .solid(Color(red: 0.08, green: 0.1, blue: 0.12)) }
        fullConfiguration.setPeek { Text("合成胶囊预览") }
        let fullState = AppState()
        fullState.appearancePreferences = .init(openOnHover: .immediately, hoverDelay: 0.15, externalDisplayHoverDelay: 0.2)
        let fullCoordinator = AppCoordinator(appState: fullState, moduleHost: ModuleHost(configuration: fullConfiguration), surface: nook)
        fullCoordinator.applyHoverIntent()
        nook.transitionConfiguration = AppCoordinator.defaultTransitions
        check(nook.hoverIntent.delay(onBuiltInDisplay: true) == .zero, "full expansion has no built-in display dwell")
        check(nook.hoverIntent.delay(onBuiltInDisplay: false) == .zero, "full expansion has no external display dwell")
        nook.setHoveringWithoutTransition(false)
        await nook.compact(on: screen)
        nook.configureWindow { $0.orderOut(nil) }
        await settle()
        capture("full-rest")
        nook.updateHoverState(true)
        try? await Task.sleep(for: .milliseconds(20))
        check(nook.state == .expanded, "full expansion starts within 20ms without stopping at compact")
        capture("full-020")
        for (name, delay) in [("full-080", 60), ("full-180", 100), ("full-360", 180), ("full-680", 320)] {
            try? await Task.sleep(for: .milliseconds(delay))
            check(nook.state == .expanded, "full expansion never returns to compact at \(name)")
            capture(name)
        }
        fullState.appearancePreferences.openOnHover = .peekFirst
        fullCoordinator.applyHoverIntent()
        check(nook.hoverIntent.action == .peek, "switching settings live restores the click-to-expand route")
        nook.setHoveringWithoutTransition(false)
        await nook.compact(on: screen)
        nook.configureWindow { $0.orderOut(nil) }
        await settle()
        nook.updateHoverState(true)
        try? await Task.sleep(for: .milliseconds(900))
        check(nook.state == .compact, "preview mode still waits at the capsule for a click")
        nook.handleChromeClick()
        try? await Task.sleep(for: .milliseconds(20))
        check(nook.state == .expanded, "preview capsule opens immediately when clicked")
        await settle()
        for physical in [CGFloat(0), CGFloat(32)] {
            nook.setHoveringWithoutTransition(false)
            await nook.compact(on: screen)
            nook.configureWindow { $0.orderOut(nil) }
            nook.updateScreenGeometry(notch: CGSize(width: 180, height: 32), physicalHeight: physical, menuHeight: 32)
            await settle()
            let window = nook.window!
            var cursor = NSPoint(x: window.frame.midX, y: window.frame.maxY - physical - 2)
            nook.pointerLocation = { cursor }
            var expansions = 0
            nook.onExpand = { expansions += 1 }
            fullState.appearancePreferences.openOnHover = .immediately
            fullCoordinator.applyHoverIntent()
            nook.updateChromeHoverState(true)
            try? await Task.sleep(for: .milliseconds(40))
            for _ in 0..<12 {
                // A real window/layout event reports exit; the physical cursor is unchanged.
                nook.updateChromeHoverState(false)
                try? await Task.sleep(for: .milliseconds(60))
                check(nook.state == .expanded && nook.isHovering, "stationary entry pointer stays engaged on screen \(physical)")
                nook.updateChromeHoverState(true)
            }
            check(expansions == 1, "stationary pointer expands exactly once on screen \(physical)")
            cursor = NSPoint(x: window.frame.maxX + 100, y: window.frame.minY - 100)
            // No second SwiftUI exit is needed after an ignored layout exit.
            // Poll the asynchronous outcome rather than assuming a fixed sleep
            // also drained the monitor's separately scheduled transition task.
            let exitStart = Date()
            while nook.state != .compact && Date().timeIntervalSince(exitStart) < 0.25 {
                try? await Task.sleep(for: .milliseconds(5))
            }
            measurements["pointer-exit-\(Int(physical))-seconds"] = String(format: "%.4f", Date().timeIntervalSince(exitStart))
            if nook.state != .compact {
                print("DIAG pointer exit: state=\(nook.state) hovering=\(nook.isHovering) hold=\(nook.staysExpandedOnHoverExit) keyboard=\(nook.hasKeyboardFocus) deferred=\(nook.hasDeferredHoverExit) suppressed=\(nook.suppressesHoverExitCompact) drag=\(nook.isDragInFlight)")
                fflush(stdout)
            }
            check(nook.state == .compact, "real pointer exit collapses even after a layout exit was ignored on screen \(physical)")
        }
        let lockConfiguration = IslandHost.baseConfiguration(title: "消息", symbol: "paperplane")
        @MainActor func lockBar() -> NookTopBarContext {
            .live(appState: fullState, topBar: lockConfiguration.topBar, motion: .default,
                  moduleSwitcher: nil, toggleKeepOpen: { fullCoordinator.toggleKeepNookOpen() })
        }
        let lockModules = IslandHost.configuration().makeRegistry().descriptors.filter { IslandHost.moduleIDs.contains($0.id) }
        let lockSwitcher = NookModuleSwitcher(modules: lockModules, activeID: IslandHost.todoID, attentionIDs: [], switchTo: { _ in })
        let lockShell = NookExpandedView(appState: fullState, services: AppServices(),
            toggleKeepOpen: { fullCoordinator.toggleKeepNookOpen() }, hide: {}, resetAllSettings: {},
            home: { AnyView(Color.clear.frame(height: 40)) }, topBar: lockConfiguration.topBar,
            width: 400, moduleSwitcher: lockSwitcher).preferredColorScheme(.light).background(Color.white)
        let lockHost = NSHostingView(rootView: lockShell)
        let lockWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 416, height: 110), styleMask: .borderless, backing: .buffered, defer: false)
        lockWindow.isReleasedWhenClosed = false
        lockWindow.contentView = lockHost
        @MainActor func captureLock(_ name: String) async {
            lockHost.layoutSubtreeIfNeeded()
            lockWindow.setContentSize(lockHost.fittingSize)
            await settle()
            let bitmap = lockHost.bitmapImageRepForCachingDisplay(in: lockHost.bounds)!
            lockHost.cacheDisplay(in: lockHost.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            check(abs(lockHost.fittingSize.width - 416) < 0.5 && lockHost.fittingSize.height < 120,
                  "lock and gear fit the existing single-row navigation in \(name)")
        }
        await captureLock("topbar-unlocked")
        let existingPresentation = await fullCoordinator.beginTransientPresentation(.init(moduleID: fullCoordinator.activeModuleID, presentation: .expanded))
        check(existingPresentation != nil, "an unlocked automatic presentation can expand before locking")
        var lockedCursor = NSPoint(x: nook.window!.frame.midX, y: nook.window!.frame.maxY - nook.physicalNotchHeight - 2)
        nook.pointerLocation = { lockedCursor }
        nook.updateChromeHoverState(true)
        try? await Task.sleep(for: .milliseconds(40))
        lockBar().toggleKeepOpen()
        check(fullState.keepNookOpen && nook.staysExpandedOnHoverExit, "top-bar lock action reaches the real coordinator and surface")
        check(AppState().keepNookOpen, "lock choice survives preference reload")
        lockedCursor = NSPoint(x: nook.window!.frame.maxX + 100, y: nook.window!.frame.minY - 100)
        nook.updateChromeHoverState(false)
        await captureLock("topbar-locked")
        check(nook.state == .expanded && !nook.isHovering, "locked panel stays open with no input and cursor outside")
        check(fullCoordinator.isUserEngaged, "locked panel remains protected after hover and layout grace end")
        var engagementEvent = false
        let engagementSubscription = fullCoordinator.userEngagementChanges.sink { engagementEvent = $0 }
        check(engagementEvent, "engagement publisher reports the keep-open lock")
        let compactClaim = await fullCoordinator.beginTransientPresentation(.init(moduleID: fullCoordinator.activeModuleID, priority: .urgent, presentation: .compact))
        check(compactClaim == nil && nook.state == .expanded, "automatic compact presentation cannot take a locked panel")
        if let existingPresentation { await fullCoordinator.endTransientPresentation(existingPresentation) }
        check(nook.state == .expanded && fullState.keepNookOpen, "ending an earlier presentation cannot restore a locked panel to compact")
        lockBar().toggleKeepOpen()
        try? await Task.sleep(for: .milliseconds(100))
        check(!fullState.keepNookOpen && nook.state == .compact, "unlocking outside resumes automatic collapse")
        check(!engagementEvent && !AppState().keepNookOpen, "unlock is published and saved")
        engagementSubscription.cancel()

        if !ScreenReminderSession.isLocked {
        lockedCursor = NSPoint(x: nook.window!.frame.midX, y: nook.window!.frame.maxY - nook.physicalNotchHeight - 2)
        nook.setHoveringWithoutTransition(true)
        await nook.expand(on: screen)
        let editingPanel = nook.window as! NookPanel
        let editingOrigin = editingPanel.frame.origin
        editingPanel.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 20, y: screen.visibleFrame.minY + 20))
        lockedCursor = NSPoint(x: editingPanel.frame.midX, y: editingPanel.frame.maxY - nook.physicalNotchHeight - 2)
        let lockedField = NSTextField(frame: NSRect(x: 20, y: 20, width: 180, height: 24))
        editingPanel.contentView!.addSubview(lockedField)
        editingPanel.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(200))
        editingPanel.makeKey(); editingPanel.makeFirstResponder(lockedField)
        check(editingPanel.isKeyWindow && NookPanel.acceptsTyping(editingPanel.firstResponder), "lock interaction fixture owns a real text editor")
        check(nook.state == .expanded, "lock editing fixture begins on an expanded panel")
        lockBar().toggleKeepOpen()
        lockedCursor = NSPoint(x: editingPanel.frame.maxX + 100, y: editingPanel.frame.minY - 100)
        try? await Task.sleep(for: .milliseconds(100))
        lockBar().toggleKeepOpen()
        try? await Task.sleep(for: .milliseconds(100))
        check(!fullState.keepNookOpen && nook.state == .expanded, "unlocking while typing retains input protection")
        editingPanel.makeFirstResponder(nil)
        try? await Task.sleep(for: .milliseconds(100))
        check(nook.state == .compact, "finishing input after unlocking restores pointer-exit collapse")
        lockedField.removeFromSuperview(); editingPanel.orderOut(nil); editingPanel.setFrameOrigin(editingOrigin)
        } else {
            blockedChecks.append("Unlocking the island while a real text editor has focus requires an unlocked Mac")
        }
        lockWindow.close()
        // Settings must leave the live island visible and interactive, including while locked.
        lockedCursor = NSPoint(x: nook.window!.frame.midX, y: nook.window!.frame.maxY - nook.physicalNotchHeight - 2)
        nook.setHoveringWithoutTransition(true)
        await nook.expand(on: screen)
        nook.configureWindow { $0.orderFrontRegardless() }
        fullCoordinator.toggleKeepNookOpen()
        let savedDraft = WorkspaceStore.shared.todoDraft
        WorkspaceStore.shared.todoDraft = "设置切换时保留的合成草稿"
        UnifiedSettingsWindow.shared.bind(appState: fullState)
        UnifiedSettingsWindow.shared.open(section: .todos)
        await fullCoordinator.drainLifecycleForTesting()
        await settle()
        let settingsWindow = NSApp.windows.first { $0.identifier?.rawValue == "feibao.settings" }!
        check(settingsWindow.styleMask.contains(.nonactivatingPanel), "settings accepts focus without activating another Space")
        check(settingsWindow.collectionBehavior.contains(.moveToActiveSpace) && !settingsWindow.collectionBehavior.contains(.canJoinAllSpaces), "settings follows the active Space rather than sticking to an old desktop")
        check(settingsWindow.collectionBehavior.contains(.fullScreenAuxiliary) && settingsWindow.collectionBehavior.contains(.canJoinAllApplications), "settings can join another app fullscreen Space")
        let settingsField = NSTextField(frame: NSRect(x: 30, y: 30, width: 180, height: 24))
        settingsWindow.contentView!.addSubview(settingsField)
        settingsWindow.makeKeyAndOrderFront(nil)
        check(settingsWindow.makeFirstResponder(settingsField), "nonactivating settings accepts native text input")
        await settle()
        check(settingsWindow.isKeyWindow && NookPanel.acceptsTyping(settingsWindow.firstResponder), "settings field owns keyboard focus without app activation")
        settingsWindow.makeFirstResponder(nil); settingsWindow.endEditing(for: nil); settingsField.removeFromSuperview()
        check(settingsWindow.isVisible && nook.window?.isVisible == true && nook.state == .expanded, "opening settings preserves the visible expanded island")
        check(fullState.keepNookOpen && WorkspaceStore.shared.todoDraft == "设置切换时保留的合成草稿", "settings preserves the lock choice and unsubmitted draft")
        UnifiedSettingsWindow.shared.open(section: .agents)
        check(nook.window?.isVisible == true && nook.state == .expanded, "changing settings sections keeps live island visible")
        settingsWindow.miniaturize(nil)
        await settle()
        check(nook.window?.isVisible == true && nook.state == .expanded, "minimizing settings preserves island state")
        UnifiedSettingsWindow.shared.open(section: .agents)
        await settle()
        check(nook.window?.isVisible == true && nook.state == .expanded, "restoring settings preserves island state")
        fullCoordinator.toggleKeepNookOpen()
        nook.setHoveringWithoutTransition(true)
        lockedCursor = NSPoint(x: nook.window!.frame.minX - 100, y: nook.window!.frame.minY - 100)
        // Send the actual hover-exit event; setting the stored flag alone deliberately
        // bypasses the transition and cannot verify the user's pointer interaction.
        nook.updateHoverState(false)
        await settle()
        check(nook.state == .compact && settingsWindow.isVisible, "island collapses normally while settings stays open")
        lockedCursor = NSPoint(x: nook.window!.frame.midX, y: nook.window!.frame.maxY - nook.physicalNotchHeight - 2)
        nook.setHoveringWithoutTransition(true)
        fullCoordinator.showNook()
        await fullCoordinator.drainLifecycleForTesting()
        fullCoordinator.toggleKeepNookOpen()
        await settle()
        check(nook.state == .expanded && settingsWindow.isVisible, "island opens normally while settings stays open")
        settingsWindow.close()
        await fullCoordinator.drainLifecycleForTesting()
        await settle()
        check(nook.window?.isVisible == true && nook.state == .expanded && fullState.keepNookOpen, "closing settings preserves the current locked expanded island across section changes")
        WorkspaceStore.shared.todoDraft = savedDraft
        let appearanceHost = NSHostingView(rootView: VStack(alignment: .leading, spacing: 20) {
            UnifiedAppearanceControls(appState: fullState)
        }.padding(24).frame(width: 650).fixedSize(horizontal: false, vertical: true).preferredColorScheme(.light).background(Color.white))
        let appearanceWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 320), styleMask: .borderless, backing: .buffered, defer: false)
        appearanceWindow.isReleasedWhenClosed = false
        appearanceWindow.contentView = appearanceHost
        appearanceHost.layoutSubtreeIfNeeded()
        appearanceWindow.setContentSize(appearanceHost.fittingSize)
        await settle()
        let appearanceBitmap = appearanceHost.bitmapImageRepForCachingDisplay(in: appearanceHost.bounds)!
        appearanceHost.cacheDisplay(in: appearanceHost.bounds, to: appearanceBitmap)
        try! appearanceBitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("settings-floating-only.png"))
        appearanceWindow.close()
        nook.window?.orderOut(nil)
        await checkCompleteStartup()
        let report: [String: Any] = ["checks": checks, "frames": measurements, "blocked": blockedChecks, "passed": blockedChecks.isEmpty]
        try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("result.json"))
        print("\(blockedChecks.isEmpty ? "PASS" : "PARTIAL"): \(checks.count) native surface checks; \(blockedChecks.count) keyboard scenarios blocked")
        NookPreferenceStorage.defaults = previousDefaults
        UserDefaults.standard.removePersistentDomain(forName: preferenceSuite)
        app.terminate(nil)
    }
    app.run()
}
