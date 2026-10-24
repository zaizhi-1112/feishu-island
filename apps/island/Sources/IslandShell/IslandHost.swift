import NookApp
import SwiftUI

public enum IslandHost {
    public static let feishuID = "local.youzi.island.feishu"
    public static let todoID = "local.youzi.island.todos"
    public static let agentID = "local.youzi.island.agents"
    static let panelWidth: CGFloat = 400
    static let panelHeight: CGFloat = 400

    public static func configuration() -> NookHostConfiguration {
        var host = NookHostConfiguration()
        host.branding = NookHostBranding(
            hostName: "柚子岛", hostTagline: "常用功能，抬手即达。",
            mark: NookHostBranding.symbol("capsule.fill"),
            menuBarIcon: NookHostBranding.symbol("capsule")
        )
        host.preferenceDefaults = NookPreferenceDefaults(
            appearance: NookAppearancePreferences(
                chromePalette: .dark, presentation: .auto, soundsEnabled: false,
                hoverDelay: 0.15, externalDisplayHoverDelay: 0.2
            ),
            display: .automatic
        )
        host.chromeTheme = IslandDesign.chrome
        host.chromeThemeSource = MainActor.assumeIsolated { AgentStore.shared.themeSource }
        host.chromeBehavior.backdrop = { context in
            .custom(.init(id: "island.skin.\(context.colorScheme).\(context.state).\(context.form)") { _ in
                IslandSkinBackdrop(store: .shared, dark: context.colorScheme == .dark, compact: context.isCompact, notched: context.form == .notch)
            })
        }
        host.chromeBehavior.showsLaunchShimmer = false
        host.chromeBehavior.edgeDocked = true
        // Hide the framework's conflicting "hover to fully expand" settings.
        host.chromeBehavior.hoverIntent = NookHoverIntent(action: .none)
        host.moduleSwitcherPlacement = .leadingCluster
        host.register(FeishuModule.info) { FeishuModule(context: $0) }
        host.register(AgentModule.info) { AgentModule(context: $0) }
        host.register(TodoModule.info) { TodoModule(context: $0) }
        host.defaultModule = IslandRuntime.isTodoPreview ? todoID : feishuID
        return host
    }

    @MainActor
    static func baseConfiguration(title: String, symbol: String) -> NookConfiguration {
        var config = NookConfiguration()
        config.expandedWidth = panelWidth
        config.allowsHorizontalModuleSwipe = true
        config.labels = IslandLabels.chinese
        config.settingsGroups = [.appearance, .display, .shortcut, .about]
        config.setSettings { IslandSettingsView() }
        config.topBar.leadingTitle = { _ in title }
        config.topBar.leadingIcon = symbol
        config.setTopBar { IslandTopBar(bar: $0) }
        config.onDrop = { payload in
            Task { @MainActor in _ = await TodoStore.shared.capture(payload) }
            return true
        }
        config.onReady = { TodoBridge.shared.attach($0) }
        config.setCompactLeading {
            AgentCompanionGlyph(store: .shared)
        }
        config.setCompactTrailing {
            Text(title)
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.8))
        }
        return config
    }
}
