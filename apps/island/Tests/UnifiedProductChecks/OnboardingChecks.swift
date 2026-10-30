import AppKit
import SwiftUI
import NookApp
@testable import IslandShell

@MainActor func runOnboardingChecks(check: (Bool, String) -> Void) async throws {
    check(IslandOnboardingPolicy.initialState(saved: nil, hasExistingData: false) == "pending", "new installation gets guide")
    check(IslandOnboardingPolicy.initialState(saved: nil, hasExistingData: true) == "existing", "upgrade never interrupts existing preferences")
    for state in ["complete", "skipped", "existing"] {
        check(IslandOnboardingPolicy.initialState(saved: state, hasExistingData: false) == state, "dismissal persists even when preferences are empty")
    }
    check(IslandOnboardingPolicy.initialState(saved: "pending", hasExistingData: true) == "pending", "interrupted first run resumes despite partial saves")
    check(IslandInstaller.isInstallSource(URL(fileURLWithPath:"/Volumes/一切在岛/一切在岛.app")), "DMG opens installation action")
    check(IslandInstaller.isInstallSource(URL(fileURLWithPath:"/private/var/folders/test/AppTranslocation/id/d/一切在岛.app")), "Gatekeeper translocation still opens installer")
    check(!IslandInstaller.shouldStartInstaller(source:URL(fileURLWithPath:"/private/var/folders/test/AppTranslocation/id/d/一切在岛.app"),arguments:["--onboarding"]), "installed copy never re-enters installer when Gatekeeper translocates it")
    check(!IslandInstaller.isInstallSource(URL(fileURLWithPath:"/Applications/一切在岛.app")), "installed launch never copies itself")
    let isolated = UserDefaults(suiteName: "island.onboarding.check." + UUID().uuidString)!
    IslandOnboardingPolicy.finish(defaults: isolated, skipped: true)
    check(isolated.string(forKey: IslandOnboardingPolicy.key) == "skipped", "legacy skipped state persists")
    IslandOnboardingPolicy.finish(defaults: isolated, skipped: false)
    check(isolated.string(forKey: IslandOnboardingPolicy.key) == "complete", "finish persists complete")
    var preferences = AgentPreferences(); preferences.skinID = "deepseek"
    let empty = IslandOnboardingPolicy.unselectedAgents(preferences)
    check(empty.validationError == nil && empty.activeMonitorIDs.isEmpty && empty.visibleIDs.isEmpty && !empty.enabled && !empty.quotaDisplayEnabled, "fresh user has no implicit Agent reads")
    check(empty.profiles == preferences.profiles && empty.skinID == "deepseek", "unselected state preserves profiles and theme")
    let reloaded = try JSONDecoder().decode(AgentPreferences.self, from: JSONEncoder().encode(empty))
    check(reloaded.activeMonitorIDs.isEmpty && !reloaded.enabled && !reloaded.quotaDisplayEnabled, "skip survives preference reload")
    check(IslandOnboardingStep.allCases.count == 7, "all seven choices including keyboard recording present")
    let noConsent = AgentStore(defaults: isolated, allowsLiveReads: true)
    check(noConsent.preferences.activeMonitorIDs.isEmpty && noConsent.preferences.visibleIDs.isEmpty, "missing preferences never imply consent even outside onboarding")
    check(!ScreenReminderRules.canDismiss(elapsed: 2.99) && ScreenReminderRules.canDismiss(elapsed: 3), "all reminder dismissal waits three seconds")
    let content: [String:Any] = ["items": [["name":"合成人物", "contract":"全约", "level":"S", "platforms":[["name":"公众号","followers":183287],["name":"小红书","followers":396]], "tags":"人工智能"]], "ownerAvatar":"https://example.com/private", "key":"internal-record"]
    let sections=HubStructured.sections(content)
    let bytes=try JSONEncoder().encode(sections), text=String(decoding:bytes,as:UTF8.self)
    check(text.contains("合成人物") && text.contains("18.3 万") && text.contains("公众号") && text.contains("小红书"), "nested platform and talent data preserve grouping and numbers")
    check(!text.contains("internal-record") && !text.contains("https:") && !text.contains("followers"), "hub cards exclude machine metadata and raw links")
    check(HubStructured.sections(["entries":[["name":"运营资料","href":"https://example.com","key":"secret","kindLabel":"看板"]]]) == [.init(title:"运营资料")], "resource directory keeps useful titles only")
    guard CommandLine.arguments.contains("--onboarding-only"), let flag = CommandLine.arguments.firstIndex(of: "--render"), flag+1 < CommandLine.arguments.count else { return }
    precondition(IslandRuntime.isSkinPreview)
    let output = URL(fileURLWithPath: CommandLine.arguments[flag+1]); try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let feishu = FeishuStore(defaults: isolated, live: false, headlessRenderer: true)
    let agents = AgentStore(defaults: isolated, allowsLiveReads: false)
    let workspace = WorkspaceStore(root: output.appendingPathComponent("synthetic-workspace"))
    let state = AppState()
    for dark in [false,true] {
        state.replaceAppearancePreferences(.init(chromePalette: dark ? .dark : .light))
        for step in IslandOnboardingStep.allCases {
            let view = NSHostingView(rootView: IslandOnboardingView(appState: state, feishu: feishu, agents: agents, workspace: workspace, complete: { _ in }, step: step))
            let window = NSWindow(contentRect: NSRect(x:0,y:0,width:850,height:640),styleMask:.borderless,backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false; window.contentView=view
            view.layoutSubtreeIfNeeded(); try await Task.sleep(for:.milliseconds(100))
            guard let image=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { throw WorkError.message("No guide render") }
            view.cacheDisplay(in:view.bounds,to:image)
            try image.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("step-\(step.rawValue+1)-\(dark ? "dark" : "light").png"))
            check(view.bounds.width == 850 && view.bounds.height == 640, "guide fits native window")
            window.close()
        }
    }
}

@MainActor private var guideReviewWindow: NSWindow?
@MainActor func showGuideReview() {
    precondition(IslandRuntime.isSkinPreview)
    let isolated=UserDefaults(suiteName:"island.guide.review."+UUID().uuidString)!
    let agents=AgentStore(defaults:isolated,allowsLiveReads:false)
    try? agents.update(IslandOnboardingPolicy.unselectedAgents(agents.preferences))
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("island-guide-review-"+UUID().uuidString)
    let content=IslandOnboardingView(appState:AppState(),feishu:FeishuStore(defaults:isolated,live:false,headlessRenderer:true),agents:agents,workspace:WorkspaceStore(root:root,startTimers:false),complete:{_ in NSApp.terminate(nil)})
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:850,height:640),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    window.title="一切在岛 · 合成安装引导验收";window.isReleasedWhenClosed=false;window.contentView=NSHostingView(rootView:content);window.center()
    guideReviewWindow=window;window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
}
