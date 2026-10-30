import AppKit
import SwiftUI
import Carbon
import NookApp
@testable import IslandShell

var passed = 0
func check(_ result: @autoclosure () -> Bool, _ label: String, line: Int = #line) {
    guard result() else { fputs("FAIL \(line): \(label)\n", stderr); exit(1) }
    passed += 1
}

Task { @MainActor in
    checkTodoOrder()
    let customIcon = checkShortcutIcons()
    checkHubPingGestures()
    for index in 0..<8 {
        let angle = (Double(index) * 45 - 90) * Double.pi / 180
        check(HubPingGeometry.slice(dx: cos(angle) * 100, dy: sin(angle) * 100) == index, "compass direction \(index)")
    }
    check(HubPingGeometry.slice(dx: 0, dy: 0) == nil, "center cancels")
    check(HubPingGeometry.slice(dx: 0, dy: -54.9) == nil, "inside dead zone cancels")
    check(HubPingGeometry.slice(dx: 0, dy: -55) == 0, "dead zone edge selects")
    check(HubPingGeometry.slice(dx: 0, dy: -161, outerLimit: 160) == nil, "release outside wheel cancels")
    check(HubPingGeometry.slice(dx: .nan, dy: 0) == nil, "NaN rejected")
    check(HubPingGeometry.slice(dx: 0, dy: .infinity) == nil, "infinity rejected")
    for (angle, expected) in [(22.4, 0), (22.6, 1), (-22.4, 0), (-22.6, 7), (359.9, 0)] {
        let radians = (angle - 90) * Double.pi / 180
        check(HubPingGeometry.slice(dx: cos(radians) * 100, dy: sin(radians) * 100) == expected, "boundary \(angle)")
    }
    for url in ["https://virxact.net/", "https://example.com/dashboard?tab=weekly#summary"] {
        check(HubPingGeometry.safeURL(url) != nil, "safe navigation accepted")
    }
    for url in ["javascript:alert(1)", "file:///tmp/secret", "https://user:pass@example.com", "http://example.com", "https://example.com?access_token=private", "https://example.com?code=private", "https://example.com\n/path", "", "https://"] {
        check(HubPingGeometry.safeURL(url) == nil, "unsafe navigation rejected")
    }

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("feibao-platform-checks-" + UUID().uuidString)
    let store = UnifiedPlatformStore(root: root)
    let cards = [
        HubCard(id: "one", title: "周报", kind: "report", text: "合成周报", href: "https://example.com/weekly"),
        HubCard(id: "two", title: "日程", kind: "calendar", text: "合成日程", href: "https://example.com/calendar"),
        HubCard(id: "three", title: "无链接", kind: "text", text: "仅内容", href: nil)
    ]
    var destinations = store.destinations(cards: cards, selectedIDs: ["two"])
    check(destinations.count == 8, "exactly eight slots")
    check(destinations[0].url?.host == "virxact.net", "home is explicit URL")
    check(destinations.map(\.title) == ["首页", "OKR", "资料", "数据", "异常项", "应用", "Skill", "审批"], "defaults match eight hub destinations")
    check(destinations[7].url?.host == "applink.feishu.cn", "approval follows the real hub link")
    check(destinations.allSatisfy(\.available), "default wheel works without a connected card account")
    check(store.setSlot(3, .init(source: .custom, title: "我的入口", address: "https://example.com/tools")), "save custom slot")
    check(store.setSlot(4, .init(source: .card, cardID: "two")), "save fixed card")
    check(store.setSlot(5, .init(source: .empty)), "save explicit empty slot")
    check(!store.setSlot(8, .init()), "out of range slot rejected")
    check(!store.setSlot(6, .init(source: .custom, title: "注入", address: "javascript:alert(1)")), "unsafe custom write rejected")
    check(store.setMainBar(false), "hide main bar")
    check(store.setSound(true), "enable sound")
    let restored = UnifiedPlatformStore(root: root)
    check(!restored.showInMainBar, "main bar persisted")
    check(restored.preferences.soundEnabled, "sound persisted")
    check(restored.preferences.slots == store.preferences.slots, "all slots persisted")
    check(restored.preferences.slots[3].title == "我的入口", "hiding does not clear custom entry")
    destinations = restored.destinations(cards: cards, selectedIDs: ["one"])
    check(destinations[4].title == "日程", "fixed card ignores new automatic order")
    check(!restored.destinations(cards: [], selectedIDs: [])[4].available, "missing saved card never guesses another URL")
    check(!destinations[5].available, "empty slot has no action")
    let apps = HubHomeApplication.decode(["top":[["key":"favorite","name":"合成常用应用","url":"https://example.com/favorite"]],"all":[["key":"favorite","name":"重复应用","url":"https://example.com/duplicate"],["key":"other","name":"其他应用","url":"https://example.com/other"],["key":"unsafe","name":"不安全链接","url":"javascript:alert(1)"]]])
    check(apps.count == 2 && apps[0].frequent && !apps[1].frequent && apps[0].url.hasSuffix("favorite"), "home applications preserve favorite order, deduplicate, and reject unsafe URLs")
    check(restored.setSlot(1,.init(source:.application,cardID:"favorite")), "bind a homepage application")
    check(restored.destinations(cards:cards,selectedIDs:[],applications:apps)[1].title == "合成常用应用", "application resolves from current personal catalog")
    check(!restored.destinations(cards:cards,selectedIDs:[],applications:[])[1].available, "missing app never silently substitutes another destination")
    check(restored.swapSlots(0,2), "dragging slots swaps entries")
    let swapped = restored.destinations(cards:cards,selectedIDs:[])
    check(swapped[0].title == "资料" && swapped[2].title == "首页", "automatic defaults resolve before swapping positions")
    var settingsOpened = 0
    restored.openSettings = { settingsOpened += 1 }
    check(restored.setSlot(6,.init(source:.settings)), "native settings can be bound")
    check(restored.activate(restored.destinations(cards:[],selectedIDs:[])[6]) && settingsOpened == 1, "settings destination invokes native settings exactly once")
    check(!restored.setSlot(1,.init(source:.builtin,cardID:"unknown")), "unknown built-in destination rejected")
    check(UnifiedPlatformStore(root:root).preferences.slots == restored.preferences.slots, "new application and settings bindings survive restart")
    let legacySnapshot = try! JSONDecoder().decode(HubSnapshot.self,from:Data("{\"connected\":true,\"name\":\"合成\",\"cards\":[],\"error\":\"\"}".utf8))
    check(legacySnapshot.connected && legacySnapshot.applications == nil, "older helper snapshots remain decodable")
    var opened: [URL] = []; var sounds = 0
    restored.openURL = { opened.append($0); return true }
    restored.playSound = { sounds += 1 }
    check(restored.activate(destinations[3]), "explicit activation works")
    check(opened.count == 1 && opened[0].path == "/tools", "single activation opens once")
    check(sounds == 1, "enabled sound once")
    check(!restored.activate(destinations[5]) && opened.count == 1, "empty slot does not launch")
    restored.openURL = { _ in false }
    check(!restored.activate(destinations[0]) && !restored.error.isEmpty, "browser failure surfaced")
    let attributes = try! FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("preferences.json").path)
    check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "preferences private permissions")
    let corrupt = root.appendingPathComponent("corrupt")
    try! FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
    let original = Data("{\"version\":999,\"unknown\":\"must retain\"}".utf8)
    try! original.write(to: corrupt.appendingPathComponent("preferences.json"))
    let damaged = UnifiedPlatformStore(root: corrupt)
    check(!damaged.error.isEmpty && !damaged.setMainBar(false), "malformed settings stop overwrite")
    check(try! Data(contentsOf: corrupt.appendingPathComponent("preferences.json")) == original, "malformed source retained")

    if let index = CommandLine.arguments.firstIndex(of: "--render"), CommandLine.arguments.indices.contains(index + 1) {
        let output = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let previewDefaults = UnifiedPlatformStore(root: root.appendingPathComponent("default-preview"))
        _ = previewDefaults.setSlot(0, .init(source: .custom, title: "我的入口", address: "https://example.com", iconPNG: customIcon))
        let view = NSHostingView(rootView: HubPingWheel(destinations: previewDefaults.destinations(cards:[],selectedIDs:[]), gesture: HubPingGesture(), activate: { _ in true })
            .frame(width: 400, height: 400).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 400, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("render bitmap unavailable") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: output)
        check(!window.isVisible, "render window never displayed")
        check((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) == 0, "wheel corners are genuinely transparent")
        let workspace = WorkspaceStore(root: root.appendingPathComponent("render-workspace"), startTimers: false)
        workspace.hub = HubSnapshot(connected: true, name: "合成中台", cards: cards)
        workspace.toggleCard("one")
        let panelView = NSHostingView(rootView: UnifiedPlatformPanel(workspace: workspace, launcher: restored)
            .frame(width: 400, height: IslandHost.panelHeight).background(Color.black).preferredColorScheme(.dark)
            .environment(\.nookResolvedTheme, NookResolvedTheme.resolve(theme: AgentStore.shared.selectedSkin.theme, preferences: .init(chromePalette: .dark), effectiveColorScheme: .dark, reduceTransparency: true)))
        let panelWindow = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 400, height: IslandHost.panelHeight), styleMask: [.borderless], backing: .buffered, defer: false)
        panelWindow.appearance = NSAppearance(named: .darkAqua)
        panelWindow.contentView = panelView
        panelView.layoutSubtreeIfNeeded()
        guard let panelBitmap = panelView.bitmapImageRepForCachingDisplay(in: panelView.bounds) else { fatalError("panel render bitmap unavailable") }
        panelView.cacheDisplay(in: panelView.bounds, to: panelBitmap)
        let panelOutput = output.deletingPathExtension().appendingPathExtension("panel.png")
        try! panelBitmap.representation(using: .png, properties: [:])!.write(to: panelOutput)
        check(!panelWindow.isVisible, "panel window never displayed")
        workspace.hub.applications = apps
        let board = NSHostingView(rootView:HubShortcutSettings(workspace:workspace,launcher:previewDefaults).frame(width:680).padding(20).background(Color.white).preferredColorScheme(.light))
        let boardWindow = NSWindow(contentRect:NSRect(x:-2000,y:-2000,width:720,height:700),styleMask:[.borderless],backing:.buffered,defer:false)
        boardWindow.contentView = board; board.layoutSubtreeIfNeeded()
        check(board.fittingSize.width <= 725 && board.fittingSize.height <= 710, "shortcut board fits narrow settings without horizontal overflow")
        if let bitmap = board.bitmapImageRepForCachingDisplay(in:board.bounds) {
            board.cacheDisplay(in:board.bounds,to:bitmap)
            try! bitmap.representation(using:.png,properties:[:])!.write(to:output.deletingPathExtension().appendingPathExtension("settings.png"))
        }
        check(!boardWindow.isVisible, "shortcut settings fixture never displays a desktop window")

    }
    if CommandLine.arguments.contains("--register-shortcut-check") {
        precondition(IslandRuntime.isSkinPreview && CommandLine.arguments.contains("--shortcut-preview"))
        HubPingLauncher.shared.start()
        let launcher = UnifiedPlatformStore.shared
        check(launcher.registerHotkey != nil, "real Carbon callback is installed in an explicitly isolated fixture")
        let key = NookHotkey(keyCode: UInt32(kVK_F19), carbonModifiers: UInt32(controlKey | optionKey | shiftKey), keySymbol: "F19")
        check(launcher.setHotkey(key), "real OS registers a temporary custom global shortcut")
        HubPingLauncher.shared.suspendForRecording()
        print("Real shortcut registered and removed; no keyboard event was synthesized. Wheel invocation still requires an unlocked Mac.")
    }
    print("PASS \(passed) platform checks")
    if CommandLine.arguments.contains("--editor-preview") {
        precondition(IslandRuntime.isSkinPreview)
        NSApplication.shared.setActivationPolicy(.regular)
        let preview = UnifiedPlatformStore(root: root.appendingPathComponent("editor-preview"))
        let workspace = WorkspaceStore(root: root.appendingPathComponent("editor-workspace"), startTimers: false)
        let window = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 780, height: 720), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "快捷入口图片验收（合成数据）"
        window.isReleasedWhenClosed = false
        _ = try! workspace.addTodo(title: "第一件事")
        _ = try! workspace.addTodo(title: "第二件事")
        _ = try! workspace.addTodo(title: "第三件事")
        window.contentView = NSHostingView(rootView: TabView {
            HubShortcutSettings(workspace: workspace, launcher: preview).padding(20).tabItem { Text("快捷入口") }
            UnifiedTodoPanel(store: workspace).frame(width: 420).environment(\.nookResolvedTheme, NookResolvedTheme.resolve(theme: AgentStore.shared.selectedSkin.theme, preferences: .init(chromePalette: .light), effectiveColorScheme: .light, reduceTransparency: true)).tabItem { Text("待办排序") }
        })
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        return
    }
    exit(0)
}
if CommandLine.arguments.contains("--editor-preview") { NSApplication.shared.run() } else { RunLoop.main.run() }
