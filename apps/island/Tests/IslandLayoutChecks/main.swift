import AppKit
import SwiftUI
import NookApp
@testable import IslandShell

MainActor.assumeIsolated {
    let app=NSApplication.shared; app.setActivationPolicy(.accessory)
    let root=URL(fileURLWithPath:CommandLine.arguments[1]); try! FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    Task { @MainActor in
        let defaults=UserDefaults(suiteName:"island.layout."+UUID().uuidString)!
        let agents=AgentStore(defaults:defaults,allowsLiveReads:false,sessionIsLocked:{false})
        var prefs=agents.preferences; prefs.enabled=true; prefs.effectsEnabled=false; prefs.setVisibleIDs(["codex","claude","workbuddy"]);try! agents.update(prefs)
        let now=Date().timeIntervalSince1970
        agents.ingestSnapshots(["codex":AgentSnapshot(sessions:[.init(id:"synthetic",state:.working,updatedAt:now)],quotas:[.init(id:"codex/primary",label:"周额度",remainingPercent:55,resetsAt:now+86400,updatedAt:now)],detail:"已读取官方额度；每3分钟自动刷新。")],now:now)
        let workspace=WorkspaceStore(root:root.appendingPathComponent("workspace"),startTimers:false)
        let fs=FeishuStore(defaults:defaults,live:false,receivingDefault:false,headlessRenderer:true)
        var sizes:[String:Double]=[:]
        @MainActor func render(_ view:AnyView,_ name:String) async {
            let host=NSHostingView(rootView:view.frame(width:400).fixedSize(horizontal:false,vertical:true).preferredColorScheme(.light)
                .environment(\.nookResolvedTheme,NookResolvedTheme.resolve(theme:agents.selectedSkin.theme,preferences:.init(chromePalette:.light),effectiveColorScheme:.light,reduceTransparency:true))
                .background(Color.white))
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:420),styleMask:.borderless,backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;window.contentView=host
            for _ in 0..<4 {host.layoutSubtreeIfNeeded();try? await Task.sleep(for:.milliseconds(150));window.setContentSize(host.fittingSize)}
            sizes[name]=host.fittingSize.height
            precondition(host.fittingSize.height<=401,"Page exceeded scroll cap")
            host.layoutSubtreeIfNeeded();host.displayIfNeeded()
            if let image=host.bitmapImageRepForCachingDisplay(in:host.bounds) {host.cacheDisplay(in:host.bounds,to:image);try! image.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name+".png"))}
            window.close()
        }
        await render(AnyView(AgentPanel(store:agents)),"agent-working")
        await render(AnyView(UnifiedTodoPanel(store:workspace)),"todo-empty")
        await render(AnyView(FeishuView(store:fs)),"messages-empty")
        workspace.hub=HubSnapshot(connected:true,name:"合成",cards:[.init(id:"review",title:"工作周报",kind:"report",text:"本周完成产品交互调整。\n下周核对真实使用体验。",href:"https://virxact.net/")],readAt:Date())
        _=workspace.mutate{$0.selectedCards=["review"]}
        await render(AnyView(UnifiedPlatformPanel(workspace:workspace)),"platform")
        fs.updateSettings(enabled:true,rules:fs.rules,custom:fs.customRules)
        fs.loadDemo()
        await render(AnyView(FeishuView(store:fs)),"messages-content")
        precondition(sizes["agent-working"]!<390,"Agent page retained fixed blank height")
        precondition(sizes["messages-empty"]!<300,"Empty messages retained blank height")
        for i in 0..<20 {_=try! workspace.addTodo(title:"合成任务 \(i)")}
        await render(AnyView(UnifiedTodoPanel(store:workspace)),"todo-many")
        precondition(sizes["todo-many"]! == 400,"Long list must remain scrollable")
        try! JSONSerialization.data(withJSONObject:sizes,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("sizes.json"))
        print(sizes);app.terminate(nil)
    }
    app.run()
}
