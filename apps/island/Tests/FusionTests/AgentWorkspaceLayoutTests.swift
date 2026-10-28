@testable import IslandLegacyFixtures
import AppKit
import QuartzCore
import SwiftUI
@testable import IslandShell

extension FusionTests {
    func testAgentWorkspaceComposition() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("agent-compose-fixture-"+UUID().uuidString)
        let workspace=WorkspaceStore(root:root,startTimers:false)
        workspace.draftProject="合成共用项目"
        workspace.draftText="合成材料：整理日期筛选与导出进度。"
        workspace.draftArchive=WorkArchiveTarget(mode:"off")
        let suite="agent.compose.check."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        let agents=AgentStore(defaults:defaults)
        let catalog=AgentCatalogStore(defaults:defaults)
        let initialRevision=agents.preferences.revision
        let evidence=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/agent-workspace-layout")
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        XCTAssertEqual(AgentWorkProvider.allCases.map(\.rawValue),["codex","dot","doubao","workbuddy"])
        XCTAssertEqual(IslandHost.configuration().defaultModule,IslandHost.feishuID)
        func descendants(_ view:NSView)->[NSView] { view.subviews.flatMap{[$0]+descendants($0)} }
        XCTAssertEqual(catalog.entries.map(\.id),["codex","claude","workbuddy","dot","doubao"])
        XCTAssertNil(catalog.add(name:"合成助手",url:"https://example.com/assistant"))
        let customID=catalog.custom[0].id
        XCTAssertTrue(catalog.entries.first{$0.id=="claude"}?.taskProvider == nil)
        XCTAssertEqual(catalog.entries.first{$0.id=="workbuddy"}?.taskProvider, .workbuddy)
        for entry in catalog.entries {
            let previousService=workspace.draftService
            catalog.select(entry.id,in:workspace)
            if let provider=entry.taskProvider { XCTAssertEqual(workspace.draftService,provider.rawValue) }
            else { XCTAssertEqual(workspace.draftService,previousService) }
            XCTAssertEqual(catalog.selected(in:workspace).id,entry.id)
            XCTAssertEqual(workspace.draftText,"合成材料：整理日期筛选与导出进度。")
            XCTAssertEqual(workspace.draftProject,"合成共用项目")
            XCTAssertFalse(agents.preferences.enabled)
            XCTAssertEqual(agents.preferences.revision,initialRevision)
            for height:CGFloat in [1440,480] {
                // Before this integration WorkBuddy was only a catalog selection,
                // so an upgrade may restore it beside the old Codex destination.
                if entry.id == "workbuddy", height == 1440 { workspace.draftService="codex" }
                let view=AgentWorkspaceSurface(agents:agents,workspace:workspace,catalog:catalog)
                    .environment(\.workspaceScreenHeight,height)
                    .preferredColorScheme(.dark)
                    .background(Color.black)
                    .transaction{$0.disablesAnimations=true}
                let host=NSHostingView(rootView:view);host.wantsLayer=true;host.appearance=NSAppearance(named:.darkAqua)
                let size=host.fittingSize
                XCTAssertEqual(size.width,WorkspaceLayout.islandWidth)
                XCTAssertEqual(size.height,WorkspaceLayout.height(screenHeight:height))
                let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
                window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:.darkAqua);window.contentView=host
                host.layoutSubtreeIfNeeded();host.displayIfNeeded();CATransaction.flush()
                try await Task.sleep(for:.milliseconds(120))
                host.layoutSubtreeIfNeeded();host.displayIfNeeded()
                if entry.id == "workbuddy" { XCTAssertEqual(workspace.draftService,"workbuddy") }
                XCTAssertFalse(window.isVisible)
                let editors=descendants(host).compactMap{$0 as? NSTextView}
                if entry.taskProvider != nil { XCTAssertTrue(editors.contains{$0.string==workspace.draftText}) }
                else { XCTAssertFalse(editors.contains{$0.string==workspace.draftText}) }
                guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw WorkError.message("合成Agent画布未生成") }
                host.cacheDisplay(in:host.bounds,to:bitmap)
                try bitmap.representation(using:.png,properties:[:])!.write(to:evidence.appendingPathComponent(entry.id+"-\(Int(height)).png"))
                window.close()
            }
        }
        let reloaded=AgentCatalogStore(defaults:defaults)
        XCTAssertEqual(reloaded.custom,catalog.custom)
        XCTAssertEqual(reloaded.selected(in:workspace).id,customID)
        XCTAssertTrue(reloaded.add(name:"Codex",url:"") != nil)
        XCTAssertTrue(reloaded.add(name:"合成助手",url:"") != nil)
        for address in ["javascript:alert(1)","file:///tmp/fixture","http://example.com", "https://user:secret@example.com", "https://example.com/?token=secret", "https://example.com/#secret"] {
            XCTAssertTrue(reloaded.add(name:"拒绝危险入口",url:address) != nil)
        }
        reloaded.remove("codex"); XCTAssertEqual(reloaded.entries.count,6)
        reloaded.remove(customID); XCTAssertEqual(reloaded.entries.count,5)
        XCTAssertNil(reloaded.selectedID)
        XCTAssertTrue(workspace.disk.items.isEmpty)
        XCTAssertFalse(agents.preferences.enabled)
    }
}
