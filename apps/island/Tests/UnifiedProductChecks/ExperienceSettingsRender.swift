import AppKit
import SwiftUI
import NookApp
@testable import IslandShell

@MainActor
func renderExperienceSettingsComponents(output: URL, appState: AppState) async throws {
    precondition(IslandRuntime.isSkinPreview)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let workspace = WorkspaceStore.shared
    let agents = AgentStore.shared
    var prefs=agents.preferences;prefs.enabled=true;prefs.setVisibleIDs(["codex","claude","workbuddy"]);try agents.update(prefs)
    let now=Date().timeIntervalSince1970
    var credits=AgentQuota(id:"workbuddy/credits",label:"账户积分",remainingPercent:64,resetsAt:nil,updatedAt:now);credits.remainingUnits=128.5
    agents.ingestSnapshots(["codex":.init(sessions:[.init(id:"demo",state:.working,updatedAt:now)],quotas:[.init(id:"codex/primary",label:"Codex · 5小时额度",remainingPercent:77,resetsAt:now+3600,updatedAt:now),.init(id:"codex/weekly",label:"Codex · 周额度",remainingPercent:42,resetsAt:now+86400,updatedAt:now)]),"workbuddy":.init(quotas:[credits])],now:now)
    let components: [(String, AnyView)] = [
        ("agent-tools",AnyView(UnifiedAgentSettings(store:agents))),
        ("agent-setup", AnyView(AgentSetupSheet(store:agents))),
        ("display", AnyView(IslandSettingsCard("灵动岛显示在哪里") { UnifiedDisplaySettings(appState: appState) })),
        ("materials", AnyView(IslandSettingsCard("到时间，用喜欢的方式提醒") { WorkspaceReminderLibrary(store: workspace) })),
        ("calendar", AnyView(IslandSettingsCard("飞书日历") { UnifiedCalendarSettings(store: workspace) })),
        ("agent-details", AnyView(IslandSettingsCard("当前状态") { UnifiedAgentSnapshotView(store: agents, profileID: "workbuddy") }))
    ]
    for dark in [false, true] {
        let theme = NookResolvedTheme.resolve(theme: agents.selectedSkin.theme, preferences: .init(chromePalette: dark ? .dark : .light), effectiveColorScheme: dark ? .dark : .light, reduceTransparency: true)
        for (name, content) in components {
            let root = ScrollView { content.padding(28) }
                .frame(width: 632, height: 620).environmentObject(appState)
                .environment(\.nookResolvedTheme, theme)
                .environment(\.nookTheme, agents.selectedSkin.theme)
                .environment(\.nookSurfaceAnimationActive, false)
                .foregroundStyle(theme.primaryLabel).tint(theme.accent)
                .background(Color(skinHex: agents.selectedSkin.palette(dark: dark).bg))
                .preferredColorScheme(dark ? .dark : .light)
            let view = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 632, height: 620), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua); window.contentView = view
            view.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(120))
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw WorkError.message("No component bitmap") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + (dark ? "-dark" : "") + ".png"))
            window.close()
        }
    }
}
