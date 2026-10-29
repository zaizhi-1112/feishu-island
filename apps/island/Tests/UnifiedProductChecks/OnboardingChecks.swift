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
    let isolated = UserDefaults(suiteName: "island.onboarding.check." + UUID().uuidString)!
    IslandOnboardingPolicy.finish(defaults: isolated, skipped: true)
    check(isolated.string(forKey: IslandOnboardingPolicy.key) == "skipped", "close persists skipped")
    IslandOnboardingPolicy.finish(defaults: isolated, skipped: false)
    check(isolated.string(forKey: IslandOnboardingPolicy.key) == "complete", "finish persists complete")
    var preferences = AgentPreferences(); preferences.skinID = "deepseek"
    let empty = IslandOnboardingPolicy.unselectedAgents(preferences)
    check(empty.validationError == nil && empty.activeMonitorIDs.isEmpty && empty.visibleIDs.isEmpty && !empty.enabled && !empty.quotaDisplayEnabled, "fresh user has no implicit Agent reads")
    check(empty.profiles == preferences.profiles && empty.skinID == "deepseek", "unselected state preserves profiles and theme")
    let reloaded = try JSONDecoder().decode(AgentPreferences.self, from: JSONEncoder().encode(empty))
    check(reloaded.activeMonitorIDs.isEmpty && !reloaded.enabled && !reloaded.quotaDisplayEnabled, "skip survives preference reload")
    check(IslandOnboardingStep.allCases.count == 6, "all six requested choices present")
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
