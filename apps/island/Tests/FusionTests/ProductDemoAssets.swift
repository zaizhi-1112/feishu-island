@testable import IslandLegacyFixtures
import AppKit
import QuartzCore
import SwiftUI
@testable import IslandShell

extension FusionTests {
    /// Website assets are the product's own views with synthetic stores, never a capture of personal data.
    func exportProductDemoAssets() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("island-product-demo-"+UUID().uuidString)
        let workspace=WorkspaceStore(root:root,startTimers:false)
        workspace.draftProject="合成演示项目"
        workspace.draftText="整理两条反馈：搜索支持日期筛选；导出时显示进度。"
        workspace.draftArchive=WorkArchiveTarget(mode:"off")
        let defaults=UserDefaults(suiteName:"island.product-demo."+UUID().uuidString)!
        let agents=AgentStore(defaults:defaults)
        let catalog=AgentCatalogStore(defaults:defaults)
        let feishu=FeishuStore(defaults:defaults,live:false,receivingDefault:true,headlessRenderer:true)
        feishu.receive(fixture("product-demo-message",text:"合成演示：讨论改到下午3点，方便时确认。"))
        feishu.openReader("product-demo-message")
        let output=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/product-demo-assets")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var sizes:[String:[Int]]=[:]
        func render<V:View>(_ name:String,_ view:V) async throws {
            let host=NSHostingView(rootView:view.preferredColorScheme(.dark).transaction{$0.disablesAnimations=true})
            host.wantsLayer=true;host.appearance=NSAppearance(named:.darkAqua)
            let size=host.fittingSize
            let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;window.contentView=host;window.appearance=NSAppearance(named:.darkAqua)
            host.layoutSubtreeIfNeeded();host.displayIfNeeded();CATransaction.flush()
            try await Task.sleep(for:.milliseconds(120))
            host.layoutSubtreeIfNeeded();host.displayIfNeeded();CATransaction.flush()
            XCTAssertFalse(window.isVisible)
            if name == "demo-result" {
                func descendants(_ view:NSView)->[NSView] { view.subviews.flatMap { [$0]+descendants($0) } }
                if let scroll=descendants(host).compactMap({$0 as? NSScrollView}).first,let document=scroll.documentView {
                    scroll.contentView.scroll(to:NSPoint(x:0,y:max(0,document.bounds.height-scroll.contentView.bounds.height)))
                    scroll.reflectScrolledClipView(scroll.contentView);host.displayIfNeeded();CATransaction.flush()
                }
            }
            guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else {throw WorkError.message("Native product demo rendering failed")}
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
            sizes[name]=[Int(size.width),Int(size.height)]
            window.close()
        }
        func compact<L:View,R:View>(@ViewBuilder leading:()->L,@ViewBuilder trailing:()->R)->some View {
            HStack(spacing:0) {
                leading().frame(maxWidth:.infinity)
                Color.black.frame(width:179,height:32)
                trailing().frame(maxWidth:.infinity)
            }.frame(width:390,height:32).background(Color.black,in:UnevenRoundedRectangle(bottomLeadingRadius:14,bottomTrailingRadius:14))
        }
        try await render("demo-feishu-compact",compact { IslandCompactGlyph(symbol:"paperplane.fill") } trailing: { Text("1条").font(.system(size:10)) })
        let now=Date().timeIntervalSince1970
        let quota=AgentQuota(id:"codex/primary",label:"周额度",remainingPercent:93,resetsAt:now+86400,updatedAt:now)
        let summary=AgentQuotaCompactSummary(quotas:[quota],refreshing:false,now:now)
        try await render("demo-agent-idle",compact { AgentQuotaCompactBadge(summary:summary,leading:true) } trailing: { AgentQuotaCompactBadge(summary:summary,leading:false) })
        for (state,attention) in [("working",Optional("running")),("waiting",Optional("approval")),("completed",nil)] {
            let notice=AgentCompletionNotice(profileID:"codex",name:"Codex",count:1,stillWorking:false,attention:attention)
            try await render("demo-agent-"+state,compact { AgentIdentityIcon(id:"codex",size:22) } trailing: { AgentCompletionStatus(notice:notice,motion:false) })
        }
        try await render("demo-materials",AgentWorkspaceSurface(agents:agents,workspace:workspace,catalog:catalog).environment(\.workspaceScreenHeight,1440).background(Color.black))
        try await render("demo-feishu-expanded",FeishuView(store:feishu).environment(\.workspaceScreenHeight,1440).background(Color.black))
        let taskID=try workspace.add(text:"合成演示：整理两条客户反馈",minutes:0,service:"codex")
        try workspace.receiveAgentResult(taskID,text:"1. 搜索需要支持日期筛选。\n2. 导出时需要显示进度。")
        workspace.selected=taskID
        try await render("demo-result",WorkspaceView(store:workspace,desktop:false,pageOverride:1).environment(\.workspaceScreenHeight,1440).background(Color.black))
        XCTAssertFalse(agents.preferences.enabled)
        XCTAssertFalse(feishu.allowsDirectoryLookup)
        let manifest:[String:Any]=["source":"Native SwiftUI product views with synthetic stores","cameraGapPoints":179,"compactHeightPoints":32,"dimensionsPoints":sizes,"windowsShown":false,"realAccountsRead":false]
        try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("manifest.json"))
    }
}
