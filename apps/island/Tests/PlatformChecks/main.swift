import AppKit
import SwiftUI
@testable import IslandShell

var passed = 0
func check(_ result: @autoclosure () -> Bool, _ label: String, line: Int = #line) {
    guard result() else { fputs("FAIL \(line): \(label)\n", stderr); exit(1) }
    passed += 1
}

Task { @MainActor in
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
    check(destinations[1].title == "日程", "selected cards first")
    check(destinations[2].title == "周报", "remaining linked cards follow")
    check(!destinations[3].available, "missing link remains unavailable")
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
        let view = NSHostingView(rootView: HubPingWheel(destinations: destinations, diameter: 344, activate: { _ in true })
            .padding(24).frame(width: 392, height: 426).background(Color.black).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 392, height: 426), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("render bitmap unavailable") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: output)
        check(!window.isVisible, "render window never displayed")
        let workspace = WorkspaceStore(root: root.appendingPathComponent("render-workspace"), startTimers: false)
        workspace.hub = HubSnapshot(connected: true, name: "合成中台", cards: cards)
        workspace.toggleCard("one")
        let panelView = NSHostingView(rootView: UnifiedPlatformPanel(workspace: workspace, launcher: restored)
            .frame(width: 400, height: 400).background(Color.black).preferredColorScheme(.dark))
        let panelWindow = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 400, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        panelWindow.contentView = panelView
        panelView.layoutSubtreeIfNeeded()
        guard let panelBitmap = panelView.bitmapImageRepForCachingDisplay(in: panelView.bounds) else { fatalError("panel render bitmap unavailable") }
        panelView.cacheDisplay(in: panelView.bounds, to: panelBitmap)
        let panelOutput = output.deletingPathExtension().appendingPathExtension("panel.png")
        try! panelBitmap.representation(using: .png, properties: [:])!.write(to: panelOutput)
        check(!panelWindow.isVisible, "panel window never displayed")
    }
    print("PASS \(passed) platform checks")
    exit(0)
}
RunLoop.main.run()
