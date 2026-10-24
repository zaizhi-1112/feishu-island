import AppKit
import QuartzCore
import SwiftUI
import WebKit
@testable import IslandShell

@MainActor
private func syntheticDeskStore() throws -> WorkspaceStore {
    guard Bundle.main.bundleIdentifier != "local.zaizhi.feishu-island.preview",
          SettingsServer.shared.address == nil else {
        throw WorkError.message("工作台夹具必须在独立检查程序中运行，不能连接日用服务。")
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("workbench-ui-fixture-" + UUID().uuidString)
    let store = WorkspaceStore(root: root, startTimers: false)
    store.draftProject = "工作台合成验收"
    store.draftService = "dot"
    store.draftArchive = WorkArchiveTarget(mode: "off")
    let first = try store.add(text: "合成待办：整理日期筛选与导出进度两项反馈。", minutes: 0)
    _ = try store.add(text: "合成待办：明天检查材料归档说明。", minutes: 0)
    store.selected = first
    try store.upsertScreenSchedule(title: "合成循环提醒", firstFire: Date().addingTimeInterval(86400), repeatMinutes: 30, style: .init())
    store.hub = HubSnapshot(connected: true, name: "合成中台", error: "")
    store.hub.cards = [HubCard(id: "synthetic-plan", title: "合成本周计划", kind: "text", text: "完成反馈整理，再核对归档记录。")]
    store.toggleCard("synthetic-plan")
    store.draftText = "这是合成草稿。切换工作台页面后应完整保留。"
    store.boardTab = 0
    return store
}

extension FusionTests {
    /// Exercises the real sidebar and page composition in never-shown windows.
    /// The account page intentionally has no service to contact; this checks its
    /// native container only, not a real account or the live settings HTML.
    func testWorkspaceDeskLayout() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let store = try syntheticDeskStore()
        let navigation = WorkspaceDeskNavigation()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let originalDisk = try encoder.encode(store.disk)
        let originalText = store.draftText
        let originalSelection = store.selected
        let evidence = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/workbench-layout-check")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let pageNames = ["materials", "tasks", "hub", "processing", "account-container", "reminder-library", "shell-settings-unbound"]

        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        for size in [NSSize(width: 960, height: 680), NSSize(width: 760, height: 540)] {
            let content = WorkspaceDesk(store: store, navigation: navigation)
                .frame(width: size.width, height: size.height)
                .transaction { $0.disablesAnimations = true; $0.animation = nil }
            let host = NSHostingView(rootView: content)
            host.wantsLayer = true
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.close() }
            for page in pageNames.indices {
                navigation.page = page
                host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); CATransaction.flush()
                try await Task.sleep(for: .milliseconds(140))
                host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); CATransaction.flush()
                XCTAssertFalse(window.isVisible)
                XCTAssertEqual(host.bounds.size, size)
                XCTAssertTrue(host.fittingSize.width.isFinite && host.fittingSize.height.isFinite)
                XCTAssertLessThan(host.fittingSize.width, size.width + 1)
                XCTAssertLessThan(host.fittingSize.height, size.height + 1)
                let nativeChildren = descendants(host)
                if page == 0 {
                    let editors = nativeChildren.compactMap { $0 as? NSTextView }
                    XCTAssertTrue(editors.contains { $0.string == originalText })
                    for editor in editors {
                        XCTAssertGreaterThan(editor.bounds.width, 200)
                        XCTAssertLessThan(editor.bounds.width, size.width - 180)
                    }
                }
                if page == 4 {
                    let browsers = nativeChildren.compactMap { $0 as? WKWebView }
                    // No service is started: the page shows its bounded loading
                    // state instead of contacting the user's real 18766 instance.
                    XCTAssertTrue(browsers.isEmpty)
                }
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw WorkError.message("工作台离屏画布未生成。") }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw WorkError.message("工作台离屏图片未生成。") }
                try png.write(to: evidence.appendingPathComponent("\(Int(size.width))x\(Int(size.height))-\(pageNames[page]).png"))
                XCTAssertGreaterThan(bitmap.pixelsWide, 0)
                XCTAssertEqual(try encoder.encode(store.disk), originalDisk)
                XCTAssertEqual(store.draftText, originalText)
                XCTAssertEqual(store.selected, originalSelection)
                XCTAssertEqual(store.boardTab, 0)
                XCTAssertNil(SettingsServer.shared.address)
            }
            window.close()
        }
    }

    /// Explicit human inspection only: a normal, resizable window using temporary
    /// synthetic data. No receiver, local server, helper, scheduler or reminder
    /// renderer is started. The fixture starts on the task page for editing checks.
    func showWorkspaceDeskFixture() async throws {
        let store = try syntheticDeskStore()
        let navigation = WorkspaceDeskNavigation(); navigation.page = 1
        NSApplication.shared.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "飞书工作岛 · 合成工作台验收"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 540)
        window.contentView = NSHostingView(rootView: WorkspaceDesk(store: store, navigation: navigation))
        NSApplication.shared.finishLaunching()
        window.center(); window.makeKeyAndOrderFront(nil); NSApplication.shared.activate()
        print("Synthetic workbench ready: edit/delete/countdown inspection only; no receiver, timers or integration service started.")
        fflush(stdout)
        while window.isVisible {
            while let event = NSApplication.shared.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) { NSApplication.shared.sendEvent(event) }
            NSApplication.shared.updateWindows()
            try await Task.sleep(for: .milliseconds(20))
        }
        window.close()
    }
}
