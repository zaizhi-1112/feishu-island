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
        let initialRevision=agents.preferences.revision
        let evidence=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/agent-workspace-layout")
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        XCTAssertEqual(AgentWorkProvider.allCases.map(\.rawValue),["codex","dot","doubao"])
        XCTAssertEqual(IslandHost.configuration().defaultModule,IslandHost.agentID)
        func descendants(_ view:NSView)->[NSView] { view.subviews.flatMap{[$0]+descendants($0)} }
        for provider in AgentWorkProvider.allCases {
            provider.select(in:workspace)
            XCTAssertEqual(workspace.draftService,provider.rawValue)
            XCTAssertEqual(workspace.draftText,"合成材料：整理日期筛选与导出进度。")
            XCTAssertEqual(workspace.draftProject,"合成共用项目")
            XCTAssertFalse(agents.preferences.enabled)
            XCTAssertEqual(agents.preferences.revision,initialRevision)
            for height:CGFloat in [1440,480] {
                let view=AgentWorkspaceSurface(agents:agents,workspace:workspace)
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
                XCTAssertFalse(window.isVisible)
                XCTAssertTrue(descendants(host).compactMap{$0 as? NSTextView}.contains{$0.string==workspace.draftText})
                guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw WorkError.message("合成Agent画布未生成") }
                host.cacheDisplay(in:host.bounds,to:bitmap)
                try bitmap.representation(using:.png,properties:[:])!.write(to:evidence.appendingPathComponent(provider.rawValue+"-\(Int(height)).png"))
                window.close()
            }
        }
        XCTAssertTrue(workspace.disk.items.isEmpty)
        XCTAssertFalse(agents.preferences.enabled)
    }
}
