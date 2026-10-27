import AppKit
import NookApp
import SwiftUI
@testable import IslandShell

@main struct UnifiedProductChecks {
    @MainActor static func main() async throws {
        let app=NSApplication.shared
        app.setActivationPolicy(CommandLine.arguments.contains("--interactive") ? .accessory:.prohibited)
        var count=0
        func check(_ value:Bool,_ label:String) { guard value else {fputs("FAIL: \(label)\n",stderr);exit(1)};count += 1 }
        await runPeekTransitionChecks(check: check)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("feibao-product-check-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        var prefs=AgentPreferences()
        let path=root.appendingPathComponent("agent.json")
        let now=Date().timeIntervalSince1970
        var value=CustomAgentReader.example(now:now)
        try JSONEncoder().encode(value).write(to:path)
        let profile=AgentProfile(id:"custom-review",name:"自定义审阅 Agent",kind:"file",dataPath:path.path)
        prefs.profiles.append(profile)
        check(prefs.validationError==nil,"custom profile accepted without overwriting builtins")
        prefs.setVisibleIDs(["workbuddy",profile.id,"codex"])
        check(prefs.visibleProfiles.map(\.id)==["workbuddy",profile.id,"codex"],"display order respected")
        check(prefs.activeMonitorIDs.contains("claude"),"hiding retains monitoring")
        prefs.visibleIDs.append("claude")
        check(prefs.validationError != nil,"fourth visible Agent rejected")
        prefs.setVisibleIDs([])
        check(prefs.validationError==nil && prefs.visibleProfiles.isEmpty,"all Agents can be hidden")
        prefs.monitoredIDs=[profile.id]
        prefs.completionScreenMaterialID="cat"
        let restored=try JSONDecoder().decode(AgentPreferences.self,from:JSONEncoder().encode(prefs))
        check(restored.activeMonitorIDs==[profile.id] && restored.completionScreenMaterialID=="cat","monitoring and reminder selection persist")
        check(try CustomAgentReader.read(profile).sessions.count==1,"authorized file read")
        try Data("{\"sessions\":[],\"source\":\"Only status\"}".utf8).write(to:path)
        check(try CustomAgentReader.read(profile).quotas.isEmpty,"unavailable quota stays missing")
        value.quotas[0].remainingPercent=101;try JSONEncoder().encode(value).write(to:path)
        do {_=try CustomAgentReader.read(profile);check(false,"bad quota rejected")} catch {check(true,"bad quota rejected")}
        try Data(repeating:65,count:262145).write(to:path)
        do {_=try CustomAgentReader.read(profile);check(false,"oversized state rejected")} catch {check(true,"oversized state rejected")}
        let link=root.appendingPathComponent("linked.json");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:path)
        do {_=try CustomAgentReader.read(.init(id:"link",name:"Link",kind:"file",dataPath:link.path));check(false,"symlink rejected")} catch {check(true,"symlink rejected")}
        check(UnifiedSettingsSection.allCases.map(\.title)==["飞书消息","Agent 状态","待办","中台","外观与交互"],"exactly five native settings modules")
        let host=IslandHost.configuration()
        check(host.defaultModule==IslandHost.feishuID,"launch into messages")
        let appState=AppState()
        var appearance=appState.appearancePreferences;appearance.openOnHover = .peekFirst;appearance.peekDwell=0
        check(appearance.hoverIntent.action == .peek && appearance.hoverIntent.dwellToExpand==nil,"preview waits for click")
        appearance.openOnHover = .immediately
        check(appearance.hoverIntent.action == .expand,"full hover expansion")
        let persisted=try JSONDecoder().decode(NookAppearancePreferences.self,from:JSONEncoder().encode(appearance))
        check(persisted.openOnHover == .immediately,"hover preference serializes")
        check(Bundle.main.bundleIdentifier != "local.zaizhi.feishu-island.preview","fixture never has production identity")
        let fs=FeishuStore(defaults:UserDefaults(suiteName:"feibao-product-feishu-"+UUID().uuidString)!,live:false,receivingDefault:false,headlessRenderer:true)
        FeishuStore.active=fs;fs.loadDemo()
        if CommandLine.arguments.contains("--conversation-review") {
            var rules = fs.customRules
            rules.conversations = (0..<200).map {
                .init(target: .init(id: "oc_synthetic_\($0)", name: "合成会话 \($0)", detail: "群聊"), mode: .all)
            }
            fs.updateSettings(enabled: false, rules: fs.rules, custom: rules)
        }
        let server=SettingsServer();server.start(store:fs,listen:false,nativeOnly:true)
        let response=await server.respond(method:"POST",path:"/mcp/dot",headers:["host":"127.0.0.1:18766"],body:Data())
        check(response.status==404 || response.status==403,"legacy task route not exposed")
        if CommandLine.arguments.contains("--render") || CommandLine.arguments.contains("--interactive") {
            guard IslandRuntime.isSkinPreview else {fatalError("Rendering requires --skin-preview isolation")}
            let workspace=WorkspaceStore.shared
            let task=try workspace.add(text:"整理本周完成记录",minutes:0)
            _=try workspace.add(text:"和同事核对新版交互",minutes:30)
            workspace.complete(task)
            workspace.hub=HubSnapshot(connected:true,name:"合成体验",cards:[.init(id:"review",title:"工作周报",kind:"report",text:"仅用于界面验收的合成内容",href:"https://virxact.net/")],readAt:Date())
            _ = workspace.mutate{$0.selectedCards=["review"]}
            let model=UnifiedSettingsModel();model.appState=appState;model.visible=true
            if CommandLine.arguments.contains("--interactive") {
                NookEditMenu.installIfNeeded()
                if CommandLine.arguments.contains("--agent-order-review") {
                    var preferences=AgentStore.shared.preferences
                    preferences.enabled=false;preferences.quotaDisplayEnabled=false
                    preferences.setVisibleIDs(["codex","claude","workbuddy"])
                    try AgentStore.shared.update(preferences)
                }
                UnifiedSettingsWindow.shared.bind(appState:appState)
                UnifiedSettingsWindow.shared.open(section:CommandLine.arguments.contains("--agent-order-review") ? "agents":"messages")
                print("Synthetic native settings window ready; no account reads.")
                app.run(); return
            }
            let index=CommandLine.arguments.firstIndex(of:"--render")!
            let output=URL(fileURLWithPath:CommandLine.arguments[index+1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
            for size in [NSSize(width:1020,height:760), NSSize(width:840,height:620)] {
              for section in UnifiedSettingsSection.allCases {
                model.section=section
                let view=NSHostingView(rootView:UnifiedSettingsRoot(model:model))
                let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.borderless],backing:.buffered,defer:false)
                window.contentView=view;view.layoutSubtreeIfNeeded()
                try await Task.sleep(for:.milliseconds(180))
                guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else {fatalError("No bitmap")}
                view.cacheDisplay(in:view.bounds,to:bitmap)
                try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(section.rawValue+(size.width==840 ? "-narrow":"")+".png"))
                check(!window.isVisible,"rendered hidden "+section.rawValue)
                check(view.bounds.width==size.width && view.fittingSize.width.isFinite,"settings viewport width "+section.rawValue)
                window.orderOut(nil)
              }
            }
        }
        print("PASS \(count) unified product checks; synthetic data only")
    }
}
