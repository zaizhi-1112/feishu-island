import NookApp
import SwiftUI

public enum IslandHost {
    public static let workspaceID = "local.zaizhi.feishu-island.preview.workspace"
    public static let homeID = "local.zaizhi.feishu-island.preview.home"
    public static let feishuID = "local.zaizhi.feishu-island.preview.feishu"
    public static let sampleID = "local.zaizhi.feishu-island.preview.sample"

    public static func configuration() -> NookHostConfiguration {
        var host = NookHostConfiguration()
        host.branding = NookHostBranding(
            hostName: "飞书工作岛", hostTagline: "常用功能，抬手即达。",
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
        host.chromeBehavior.showsLaunchShimmer = false
        host.chromeBehavior.edgeDocked = true
        host.chromeBehavior.hoverIntent = NookHoverIntent(action: .expand, delay: .milliseconds(150), externalDisplayDelay: .milliseconds(200))
        host.moduleSwitcherPlacement = .leadingCluster
        host.register(FeishuModule.info) { FeishuModule(context: $0) }
        host.register(WorkspaceModule.info) { WorkspaceModule(context: $0) }
        if ProcessInfo.processInfo.arguments.contains("--self-test") || Bundle.main.bundleIdentifier != "local.zaizhi.feishu-island.preview" {
            host.register(HomeModule.info) { HomeModule(context: $0) }
            host.register(SampleModule.info) { SampleModule(context: $0) }
        }
        host.defaultModule = workspaceID
        return host
    }

    @MainActor
    static func baseConfiguration(title: String, symbol: String) -> NookConfiguration {
        var config = NookConfiguration()
        config.expandedWidth = 320
        config.labels = IslandLabels.chinese
        config.settingsGroups = [.appearance, .display, .shortcut, .about]
        config.addSettingsSection(id: "island.webSettings", title: "设置面板") {
            WebSettingsButton()
        }
        config.topBar.leadingTitle = { _ in title }
        config.topBar.leadingIcon = symbol
        config.setCompactLeading {
            IslandCompactGlyph(symbol: symbol)
        }
        config.setCompactTrailing {
            Text(title == "首页" ? "就绪" : "示例")
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
        Button("打开网页版设置") { SettingsServer.shared.open() }
            .buttonStyle(.bordered).accessibilityIdentifier("island.webSettings")
    }
}
