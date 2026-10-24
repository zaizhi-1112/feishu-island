import AppKit
import QuartzCore
import SwiftUI
@testable import IslandShell

extension FusionTests {
    func testQuotaCompactLayout() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let now=Date().timeIntervalSince1970
        let week=AgentQuota(id:"codex/primary",label:"周额度",remainingPercent:93,resetsAt:now+86400,updatedAt:now)
        let evidence=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/quota-compact-layout")
        try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
        for (name,quotas,stamp) in [("weekly",[week],now),("unknown",[],now),("stale",[week],now+901)] {
            let summary=AgentQuotaCompactSummary(quotas:quotas,refreshing:false,now:stamp)
            for camera:CGFloat in [179,0] {
                let view=HStack(spacing:0) {
                    AgentQuotaCompactBadge(summary:summary,leading:true).padding(.horizontal,10)
                    Color.black.frame(width:camera == 0 ? 8:camera,height:32)
                    AgentQuotaCompactBadge(summary:summary,leading:false).padding(.horizontal,10)
                }.frame(height:32).background(Color.black,in:UnevenRoundedRectangle(bottomLeadingRadius:14,bottomTrailingRadius:14)).preferredColorScheme(.dark)
                let host=NSHostingView(rootView:view);host.wantsLayer=true;host.appearance=NSAppearance(named:.darkAqua)
                let size=host.fittingSize
                XCTAssertEqual(size.height,32)
                XCTAssertLessThan(size.width,400)
                XCTAssertGreaterThan(size.width,camera+90)
                let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
                window.isReleasedWhenClosed=false;window.contentView=host
                host.layoutSubtreeIfNeeded();host.displayIfNeeded();CATransaction.flush()
                try await Task.sleep(for:.milliseconds(80))
                XCTAssertFalse(window.isVisible)
                guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw WorkError.message("额度合成视图生成失败") }
                host.cacheDisplay(in:host.bounds,to:bitmap)
                try bitmap.representation(using:.png,properties:[:])!.write(to:evidence.appendingPathComponent(name+"-\(Int(camera)).png"))
                window.close()
            }
        }
        for id in ["codex","claude","workbuddy","dot","doubao"] {
            for state in [AgentState.working,.waiting,.completed] {
                let name=AgentCatalogStore.builtins.first{$0.id==id}!.name
                let notice=AgentCompletionNotice(profileID:id,name:name,count:1,stillWorking:state == .working,attention:state == .waiting ? "approval":nil)
                let view=HStack(spacing:10) { AgentIdentityIcon(id:id,size:22);AgentCompletionStatus(notice:notice,motion:false) }.padding(10).background(Color.black).preferredColorScheme(.dark)
                let host=NSHostingView(rootView:view);host.wantsLayer=true;host.appearance=NSAppearance(named:.darkAqua)
                let size=host.fittingSize
                XCTAssertLessThan(size.width,400);XCTAssertLessThan(size.height,60)
                let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
                window.isReleasedWhenClosed=false;window.contentView=host;host.layoutSubtreeIfNeeded();host.displayIfNeeded();CATransaction.flush()
                XCTAssertFalse(window.isVisible)
                if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) {
                    host.cacheDisplay(in:host.bounds,to:bitmap)
                    try bitmap.representation(using:.png,properties:[:])!.write(to:evidence.appendingPathComponent(id+"-"+state.rawValue+".png"))
                }
                window.close()
            }
        }

    }
}
