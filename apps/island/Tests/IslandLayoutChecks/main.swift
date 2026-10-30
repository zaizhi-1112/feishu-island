import AppKit
import SwiftUI
import NookApp
@testable import IslandShell

MainActor.assumeIsolated {
    precondition(IslandHost.panelHeight == 336, "The reviewed compact viewport must remain 336pt")
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
        var scrolling:[String:Bool]=[:]
        var shellSizes:[String:[Double]]=[:]
        let shellState=AppState()
        let destinations=IslandHost.configuration().makeRegistry().descriptors.filter {
            [IslandHost.feishuID,IslandHost.agentID,IslandHost.todoID,IslandHost.platformID].contains($0.id)
        }
        @MainActor func scrollViews(_ view:NSView)->[NSScrollView] {
            if let scroll=view as? NSScrollView { return [scroll] }
            return view.subviews.flatMap(scrollViews)
        }
        @MainActor func render(_ view:AnyView,_ name:String, overflow:Bool = false) async {
            let host=NSHostingView(rootView:view.frame(width:400).fixedSize(horizontal:false,vertical:true).preferredColorScheme(.light)
                .environment(\.nookResolvedTheme,NookResolvedTheme.resolve(theme:agents.selectedSkin.theme,preferences:.init(chromePalette:.light),effectiveColorScheme:.light,reduceTransparency:true))
                .background(Color.white))
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:420),styleMask:.borderless,backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;window.contentView=host
            for _ in 0..<4 {host.layoutSubtreeIfNeeded();try? await Task.sleep(for:.milliseconds(150));window.setContentSize(host.fittingSize)}
            sizes[name]=host.fittingSize.height
            precondition(abs(host.fittingSize.height-IslandHost.panelHeight)<0.5,"\(name) must match the shared 336pt viewport")
            precondition(abs(host.fittingSize.width-400)<0.5,"\(name) changed the shared width")
            if overflow {
                guard let scroll=scrollViews(host).first(where:{ ($0.documentView?.frame.height ?? 0)>$0.contentView.bounds.height+1 }) else {
                    preconditionFailure("\(name) needs a scrollable overflow viewport")
                }
                precondition(scroll.hasVerticalScroller,"\(name) must offer a draggable vertical scrollbar")
                let before=scroll.contentView.bounds.origin.y
                scroll.contentView.scroll(to:NSPoint(x:0,y:before+100));scroll.reflectScrolledClipView(scroll.contentView)
                scrolling[name]=scroll.contentView.bounds.origin.y>before
                precondition(scrolling[name] == true,"\(name) must reach content below the viewport")
                scroll.contentView.scroll(to:.zero);scroll.reflectScrolledClipView(scroll.contentView)
            }
            host.layoutSubtreeIfNeeded();host.displayIfNeeded()
            if let image=host.bitmapImageRepForCachingDisplay(in:host.bounds) {host.cacheDisplay(in:host.bounds,to:image);try! image.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name+".png"))}
            window.close()
            let switcher=NookModuleSwitcher(modules:destinations,activeID:IslandHost.feishuID,attentionIDs:[],switchTo:{_ in})
            let bar=IslandHost.baseConfiguration(title:"消息",symbol:"paperplane").topBar
            let shell=NookExpandedView(appState:shellState,services:AppServices(),toggleKeepOpen:{},hide:{},resetAllSettings:{},home:{view},topBar:bar,width:400,moduleSwitcher:switcher)
                .padding(.bottom,8)
                .preferredColorScheme(.light)
            let shellHost=NSHostingView(rootView:shell)
            let shellSize=shellHost.fittingSize
            // The Youzi Island chrome adds 16pt padding, a 27pt navigation row,
            // an 8pt column gap and the surface's 8pt bottom inset to its fixed body.
            precondition(abs(shellSize.width-416)<0.5 && abs(shellSize.height-(IslandHost.panelHeight+59))<0.5,"\(name) must match the complete Youzi Island expanded chrome")
            shellSizes[name]=[shellSize.width,shellSize.height]
        }
        await render(AnyView(AgentPanel(store:agents)),"agent-working")
        var credits = AgentQuota(id: "workbuddy/credits", label: "可用积分", remainingPercent: 29.16, resetsAt: nil, updatedAt: now)
        credits.remainingUnits = 939.55; credits.totalUnits = 3222
        agents.ingestSnapshots(["workbuddy": .init(quotas: [credits], source: "合成客户端积分", detail: "合成数据，仅验证积分显示。")], now: now)
        agents.selectPrimary("workbuddy")
        await render(AnyView(AgentPanel(store:agents)),"workbuddy-credits")
        credits.updatedAt = now - 3600
        agents.ingestSnapshots(["workbuddy": .init(quotas: [credits], source: "合成客户端积分", detail: "合成过期数据，仅验证上次记录。")], now: now)
        await render(AnyView(AgentPanel(store:agents)),"workbuddy-stale")
        agents.selectPrimary("codex")
        prefs=agents.preferences;prefs.setVisibleIDs([]);try! agents.update(prefs)
        await render(AnyView(UnifiedAgentIslandView(store:agents)),"agent-empty")
        prefs=agents.preferences;prefs.setVisibleIDs(["codex","claude","workbuddy"]);try! agents.update(prefs)
        let longSnapshot=AgentSnapshot(sessions:[.init(id:"synthetic",state:.working,updatedAt:now)],detail:String(repeating:"合成长状态说明，用于检查固定尺寸与滚动。\n",count:30))
        precondition(longSnapshot.validationError == nil,"Long state fixture must use valid input")
        agents.ingestSnapshots(["codex":longSnapshot],now:now)
        await render(AnyView(UnifiedAgentIslandView(store:agents)),"agent-long",overflow:true)
        await render(AnyView(UnifiedTodoPanel(store:workspace)),"todo-empty")
        await render(AnyView(FeishuView(store:fs)),"messages-empty")
        workspace.hub=HubSnapshot(connected:true,name:"合成",cards:[.init(id:"review",title:"工作周报",kind:"report",text:"本周完成产品交互调整。\n下周核对真实使用体验。",href:"https://hub.example.invalid/")],readAt:Date())
        _=workspace.mutate{$0.selectedCards=["review"]}
        await render(AnyView(UnifiedPlatformPanel(workspace:workspace)),"platform")
        workspace.hub=HubSnapshot(connected:true,name:"合成",cards:[.init(id:"review",title:"长卡片",kind:"report",text:String(repeating:"合成卡片完整正文，向下滚动查看。\n",count:80),href:"https://hub.example.invalid/")],readAt:Date())
        await render(AnyView(UnifiedPlatformPanel(workspace:workspace)),"platform-long",overflow:true)
        fs.updateSettings(enabled:true,rules:fs.rules,custom:fs.customRules)
        fs.loadDemo()
        fs.closeReader()
        await render(AnyView(FeishuView(store:fs)),"messages-content",overflow:true)
        if let message=fs.visibleMessages.first {
            fs.openReader(message.id)
            precondition(fs.readingID == message.id,"Detail fixture must open the actual message reader")
            await render(AnyView(FeishuView(store:fs)),"message-detail")
            fs.closeReader()
        }
        for i in 0..<20 {_=try! workspace.addTodo(title:"合成任务 \(i)")}
        await render(AnyView(UnifiedTodoPanel(store:workspace)),"todo-many",overflow:true)
        precondition(sizes["todo-many"]! == IslandHost.panelHeight,"Long list must remain scrollable")
        try! JSONSerialization.data(withJSONObject:sizes,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("sizes.json"))
        try! JSONSerialization.data(withJSONObject:scrolling,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("scrolling.json"))
        try! JSONSerialization.data(withJSONObject:shellSizes,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("shell-sizes.json"))
        print(sizes);app.terminate(nil)
    }
    app.run()
}
