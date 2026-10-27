import NookApp
import SwiftUI

public enum IslandHost {
    public static let todoID = "local.zaizhi.feishu-island.preview.todos"
    public static let platformID = "local.zaizhi.feishu-island.preview.platform"
    public static let agentID = "local.zaizhi.feishu-island.preview.agents"
    static let panelWidth: CGFloat = 400
    static let panelHeight: CGFloat = 400
    public static let workspaceID = "local.zaizhi.feishu-island.preview.workspace"
    public static let homeID = "local.zaizhi.feishu-island.preview.home"
    public static let feishuID = "local.zaizhi.feishu-island.preview.feishu"
    public static let sampleID = "local.zaizhi.feishu-island.preview.sample"

    public static func configuration() -> NookHostConfiguration {
        var host = NookHostConfiguration()
        host.branding = NookHostBranding(
            hostName: "一切在岛", hostTagline: "常用功能，抬手即达。",
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
        // User preferences own both hover modes and persist through AppState.
        host.chromeBehavior.hoverIntent = nil
        host.moduleSwitcherPlacement = .leadingCluster
        host.register(FeishuModule.info) { FeishuModule(context: $0) }
        host.register(AgentModule.info) { AgentModule(context: $0) }
        host.register(TodoModule.info) { TodoModule(context: $0) }
        host.register(UnifiedPlatformModule.info) { UnifiedPlatformModule(context: $0) }
        if ProcessInfo.processInfo.arguments.contains("--self-test") || Bundle.main.bundleIdentifier != "local.zaizhi.feishu-island.preview" {
            host.register(HomeModule.info) { HomeModule(context: $0) }
            host.register(SampleModule.info) { SampleModule(context: $0) }
        }
        host.defaultModule = feishuID
        return host
    }

    @MainActor
    static func baseConfiguration(title: String, symbol: String) -> NookConfiguration {
        var config = NookConfiguration()
        config.expandedWidth = panelWidth
        config.allowsHorizontalModuleSwipe = true
        config.labels = IslandLabels.chinese
        config.settingsGroups = [.appearance, .display, .about]
        config.setSettings { IslandSettingsView() }
        config.topBar.leadingTitle = { _ in title }
        config.topBar.leadingIcon = symbol
        // The island is a quick surface; the ordinary workbench owns all settings.
        config.topBar.showsSettings = false
        config.setTopBar { IntegrationTopBar(bar: $0) }
        config.setPeek { UnifiedIslandPeek(title: title, symbol: symbol) }
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

@MainActor
final class HomeModule: NookModule {
    nonisolated static let info = NookModuleDescriptor(
        id: IslandHost.homeID, displayName: "首页", icon: "capsule.fill",
        backgroundPolicy: .stayResident
    )
    var descriptor: NookModuleDescriptor { Self.info }
    init(context: NookModuleContext) {}
    func makeConfiguration() -> NookConfiguration {
        var config = IslandHost.baseConfiguration(title: "首页", symbol: "capsule.fill")
        config.setHome { IslandHomeView() }
        config.onReady = { RuntimeVerification.startIfRequested(coordinator: $0) }
        return config
    }
}

@MainActor
final class SampleModule: NookModule {
    nonisolated static let info = NookModuleDescriptor(
        id: IslandHost.sampleID, displayName: "交互示例", icon: "square.stack.3d.up",
        backgroundPolicy: .unloadOnSwitchAway
    )
    var descriptor: NookModuleDescriptor { Self.info }
    private let state: SampleState
    init(context: NookModuleContext) { state = SampleState(defaults: context.defaults) }
    func makeConfiguration() -> NookConfiguration {
        var config = IslandHost.baseConfiguration(title: "交互示例", symbol: "square.stack.3d.up")
        let state = state
        config.setHome { SampleView(state: state) }
        return config
    }
}

@MainActor
public final class SampleState: ObservableObject {
    @Published public private(set) var count: Int
    private let defaults: UserDefaults
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        count = defaults.integer(forKey: "sample.count")
    }
    public func increment() {
        count += 1
        defaults.set(count, forKey: "sample.count")
    }
}

private struct WebSettingsButton: View, Sendable {
    var body: some View {
        Button("打开工作台设置") { WorkspaceWindow.shared.openSettings(store: .shared) }
            .buttonStyle(.bordered).accessibilityIdentifier("island.webSettings")
    }
}

private struct IslandToolbarActions: View {
    let title: String
    @Environment(\.nookResolvedTheme) private var theme
    var body: some View {
        HStack(spacing: 10) {
            if title == "飞书消息" || title == "工作台" {
                Button {
                    if title == "飞书消息" { IslandModuleNavigation.shared.openWorkspace() }
                    else { IslandModuleNavigation.shared.openFeishu() }
                } label: {
                    Label(title == "飞书消息" ? "工作台" : "消息",
                          systemImage: title == "飞书消息" ? "tray.and.arrow.down" : "paperplane")
                        .font(.system(size: 10, weight: .medium))
                }.buttonStyle(.plain).help(title == "飞书消息" ? "切换到工作台" : "切换到飞书消息")
                    .accessibilityIdentifier("island.switchModule")
            }
            Button { WorkspaceWindow.shared.openSettings(store: .shared) } label: {
                Image(systemName: "gearshape").font(.system(size: 12))
            }.buttonStyle(.plain).help("工作台设置").accessibilityLabel("工作台设置")
                .accessibilityIdentifier("island.settings")
        }.foregroundStyle(theme.secondaryLabel)
    }
}
