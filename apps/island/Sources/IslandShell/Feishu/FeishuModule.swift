import NookApp
import SwiftUI

@MainActor
final class FeishuModule: NookModule {
    nonisolated static let info: NookModuleDescriptor = {
        var descriptor = NookModuleDescriptor(
        id: IslandHost.feishuID, displayName: "飞书消息", icon: "paperplane.fill",
        backgroundPolicy: .stayResident
        )
        descriptor.loadsAtLaunch = true
        return descriptor
    }()
    var descriptor: NookModuleDescriptor { Self.info }
    let store: FeishuStore
    private let context: NookModuleContext
    init(context: NookModuleContext) {
        self.context = context
        let args = ProcessInfo.processInfo.arguments
        let demo = args.contains("--feishu-demo")
        store = FeishuStore(defaults: demo ? UserDefaults(suiteName: "local.zaizhi.feishu-island.preview.demo." + UUID().uuidString)! : context.defaults,
                            live: Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview" && !args.contains("--self-test") && !demo, receivingDefault: demo, headlessRenderer: false)
        if demo { store.loadDemo() }
        if Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview", !args.contains("--self-test") { SettingsServer.shared.start(store: store) }
    }
    func makeConfiguration() -> NookConfiguration {
        var config = IslandHost.baseConfiguration(title: "飞书消息", symbol: "paperplane.fill")
        config.expandedWidth = 380
        let store = store
        config.setCompactTrailing { FeishuCompactView(store: store) }
        config.setHome { FeishuView(store: store) }
        config.onReady = { [weak self] coordinator in
            guard let self else { return }
            store.canAlert = { [weak coordinator] in coordinator?.appState.isNookVisible == false }
            store.start(activities: self.context.services.resolve(NookLiveActivitiesKey.self))
            RuntimeVerification.startIfRequested(coordinator: coordinator)
        }
        return config
    }
}

struct FeishuCompactView: View {
    @ObservedObject var store: FeishuStore
    @Environment(\.nookResolvedTheme) private var theme
    var body: some View {
        Text(!store.enabled ? "已停止" : store.isMuted ? "静音" : store.waitingCount > 0 ? "\(store.waitingCount)条" : "飞书")
            .font(.system(size: 10, weight: .medium)).foregroundStyle(theme.secondaryLabel)
    }
}
