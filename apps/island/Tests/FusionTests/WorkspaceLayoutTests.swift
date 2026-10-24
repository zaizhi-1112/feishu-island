import AppKit
import QuartzCore
import SwiftUI
import NookApp
@testable import IslandShell

extension FusionTests {
    /// Renders the actual native material/editor/cards views in never-shown AppKit windows.
    /// All data, images and screen sizes are synthetic; no receiver or integration is started.
    func testWorkspaceIslandHeightContract() async throws {
        XCTAssertEqual(WorkspaceLayout.height(), 326)
        XCTAssertEqual(WorkspaceLayout.bodyHeight(for: 326), 260)
        XCTAssertEqual(WorkspaceLayout.height(preferredHeight: 236), 236)
        XCTAssertEqual(WorkspaceLayout.height(preferredHeight: 999), 326)
        XCTAssertEqual(WorkspaceLayout.height(screenHeight: 480, preferredHeight: 236), 176)
        for screen: CGFloat in [2160, 1440, 900, 768, 600, 480, 240] {
            let height = WorkspaceLayout.height(screenHeight: screen)
            XCTAssertLessThan(height + WorkspaceLayout.shellAllowance, screen / 2 + 1)
            XCTAssertLessThan(height, 327)
            XCTAssertGreaterThanOrEqual(WorkspaceLayout.bodyHeight(for: height), 0)
        }
        XCTAssertEqual(WorkspaceLayout.height(screenHeight: .nan), 326)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("island-layout-fixture-" + UUID().uuidString)
        let store = WorkspaceStore(root: root, startTimers: false)
        let evidence = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/workspace-layout-check")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)

        @MainActor func render<V: View>(_ view: V, name: String, expectedHeight: CGFloat, shell: Bool = false) async throws {
            let host = NSHostingView(rootView: view.preferredColorScheme(.dark).background(Color.black).transaction { transaction in
                transaction.disablesAnimations = true
                transaction.animation = nil
            })
            host.wantsLayer = true
            let size = host.fittingSize
            XCTAssertTrue(size.width.isFinite && size.height.isFinite)
            if !shell { XCTAssertEqual(size.width, WorkspaceLayout.islandWidth) }
            XCTAssertLessThan(abs(size.height - expectedHeight), 1)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            // The window is never ordered on screen. Explicitly complete the layer-backed
            // hosting view's display pass before capture, otherwise cached glyph layers can
            // be absent even though the native layout itself is complete.
            host.displayIfNeeded()
            CATransaction.flush()
            try await Task.sleep(for: .milliseconds(120))
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            CATransaction.flush()
            XCTAssertFalse(window.isVisible)
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw WorkError.message("合成布局截图失败") }
                try png.write(to: evidence.appendingPathComponent(name + ".png"))
                XCTAssertGreaterThan(bitmap.pixelsWide, 0)
            } else { XCTAssertTrue(false) }
            window.close()
        }

        store.boardTab = 0
        let selectedRecipe = store.disk.recipes.last!.id
        store.draftRecipe = selectedRecipe
        store.draftReminderMinutes = 47
        try await render(WorkspaceView(store: store).environment(\.workspaceScreenHeight, 1440), name: "materials-empty", expectedHeight: 236)
        XCTAssertEqual(store.draftRecipe, selectedRecipe)
        XCTAssertEqual(store.draftReminderMinutes, 47)
        let desktop = ScrollView { WorkspaceView(store: store, desktop: true) }.frame(width: 760, height: 420)
        try await render(desktop, name: "desktop-shared-draft", expectedHeight: 420, shell: true)
        XCTAssertEqual(store.draftRecipe, selectedRecipe)
        XCTAssertEqual(store.draftReminderMinutes, 47)
        store.draftProject = String(repeating: "合成项目名称", count: 12)
        store.draftText = String(repeating: "合成材料正文，搜索需按日期筛选，导出应显示进度。\n", count: 120)
        store.draftFiles = (0..<20).map { root.appendingPathComponent("合成文件-\($0).txt") }
        store.draftImages = try (0..<6).map { try PendingWorkImage.decode(syntheticWorkImage(), name: "合成截图-\($0)") }
        store.draftArchive = WorkArchiveTarget(mode: "base", url: "https://synthetic.feishu.cn/base/OnlySynthetic?table=tblSynthetic", field: "合成记录")
        store.draftService = "dot"
        store.error = String(repeating: "合成错误说明，应留在岛内滚动。", count: 24)
        try await render(WorkspaceView(store: store).environment(\.workspaceScreenHeight, 1440), name: "materials-overflow", expectedHeight: 326)
        try await render(WorkspaceView(store: store).environment(\.workspaceScreenHeight, 480), name: "materials-small-screen", expectedHeight: WorkspaceLayout.height(screenHeight: 480))

        let id = try store.add(text: String(repeating: "这是待办的合成材料。\n", count: 100), minutes: 0)
        store.boardTab = 1
        store.selected = id
        store.beginEdit(id)
        store.editTitle = String(repeating: "长标题", count: 30)
        store.editInstruction = String(repeating: "合成处理要求。", count: 40)
        try await render(WorkspaceView(store: store).environment(\.workspaceScreenHeight, 1440), name: "task-edit", expectedHeight: 326)
        store.cancelEdit()
        try store.receiveAgentResult(id, text: String(repeating: "合成结果：日期筛选和导出进度。\n", count: 100))
        try await render(WorkspaceView(store: store).environment(\.workspaceScreenHeight, 1440), name: "task-result", expectedHeight: 326)

        store.boardTab = 2
        store.hub.connected = true
        store.hub.name = "合成中台"
        store.hub.cards = [HubCard(id: "synthetic-plan", title: "合成本周计划", kind: "text", text: String(repeating: "完成材料整理和归档。\n", count: 100))]
        store.toggleCard("synthetic-plan")
        try await render(WorkspaceView(store: store).environment(\.workspaceScreenHeight, 1440), name: "cards", expectedHeight: 326)

        // Render the real OpenNook expanded chrome as well as the workspace: an island-only
        // assertion would miss the external top bar/padding that originally hid lower actions.
        let shellState = AppState(preferenceDefaults: IslandHost.configuration().preferenceDefaults)
        var bar = NookTopBarConfiguration.default
        bar.showsStatusBanner = false
        let shell = NookExpandedView(appState: shellState, services: AppServices(), toggleKeepOpen: {}, hide: {}, resetAllSettings: {}, home: { AnyView(WorkspaceView(store: store)) }, topBar: bar, width: 400)
            .padding(.bottom, 8) // NookSurface's default expanded bottom safe-area strip.
            .environment(\.workspaceScreenHeight, 1440)
        let expectedShellHeight = 326 + 16 + 24 + 8 + 8
        try await render(shell, name: "expanded-shell", expectedHeight: CGFloat(expectedShellHeight), shell: true)
        XCTAssertLessThan(expectedShellHeight, 400)
        let integratedBar=IslandHost.baseConfiguration(title:"工作台",symbol:"tray").topBar
        let destinations=IslandHost.configuration().makeRegistry().descriptors.filter{[IslandHost.workspaceID,IslandHost.feishuID,IslandHost.agentID].contains($0.id)}
        let switcher=NookModuleSwitcher(modules:destinations,activeID:IslandHost.workspaceID,attentionIDs:[],switchTo:{_ in})
        let integratedShell=NookExpandedView(appState:shellState,services:AppServices(),toggleKeepOpen:{},hide:{},resetAllSettings:{},home:{AnyView(WorkspaceView(store:store))},topBar:integratedBar,width:400,moduleSwitcher:switcher).padding(.bottom,8).environment(\.workspaceScreenHeight,1440)
        let integratedHeight=NSHostingView(rootView:integratedShell).fittingSize.height
        XCTAssertGreaterThan(integratedHeight,326); XCTAssertLessThan(integratedHeight,400)
        try await render(integratedShell,name:"integrated-shell",expectedHeight:integratedHeight,shell:true)
        let barSwitcher=NookTopBarContext.ModuleSwitcher(modules:destinations,activeID:IslandHost.workspaceID,attentionIDs:[],switchTo:{_ in})
        let standaloneBar=IntegrationTopBar(bar:NookTopBarContext(title:"工作台",moduleSwitcher:barSwitcher)).frame(width:400,height:28)
        try await render(standaloneBar,name:"integration-navigation-bar",expectedHeight:28,shell:true)
    }
}
