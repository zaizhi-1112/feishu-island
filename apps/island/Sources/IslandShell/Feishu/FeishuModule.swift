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
        let preview = IslandRuntime.isSkinPreview
        store = FeishuStore(defaults: preview ? UserDefaults(suiteName:"local.zaizhi.feishu-island.skin-preview."+UUID().uuidString)! : demo ? UserDefaults(suiteName: "local.zaizhi.feishu-island.preview.demo." + UUID().uuidString)! : context.defaults,
                            live: Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview" && !args.contains("--self-test") && !demo && !preview, receivingDefault: demo, headlessRenderer: false)
        FeishuStore.active = store
        if demo { store.loadDemo() }
        if Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview", !args.contains("--self-test"), !preview { SettingsServer.shared.start(store: store, nativeOnly: true) }
    }
    func makeConfiguration() -> NookConfiguration {
        var config = IslandHost.baseConfiguration(title: "飞书消息", symbol: "paperplane.fill")
        config.expandedWidth = 400
        let store = store
        config.setCompactLeading { IslandCompactGlyph(symbol: "paperplane.fill") }
        config.setCompactTrailing { FeishuCompactView(store: store) }
        config.setHome { FeishuView(store:store) }
        config.onReady = { [weak self] coordinator in
            guard let self else { return }
            IslandModuleNavigation.shared.bind(coordinator: coordinator)
            if !self.context.defaults.bool(forKey: "hoverAutoCollapseV1") {
                if coordinator.appState.keepNookOpen { coordinator.toggleKeepNookOpen() }
                self.context.defaults.set(true, forKey: "hoverAutoCollapseV1")
            }
            store.canAlert = { [weak coordinator] in coordinator?.appState.isNookVisible == false }
            store.onOpenReader = { [weak coordinator, weak store] in
                coordinator?.switchModule(to: IslandHost.feishuID)
                store?.presentReadingActivity()
            }
            store.onCloseReader = { [weak coordinator] in coordinator?.hideNook() }
            store.start(activities: self.context.services.resolve(NookLiveActivitiesKey.self))
            store.beginAutomaticConnectionIfNeeded()
            if ProcessInfo.processInfo.arguments.contains("--feishu-demo"), store.readingID != nil { store.onOpenReader() }
            RuntimeVerification.startIfRequested(coordinator: coordinator)
            SkinVerification.startIfRequested(coordinator: coordinator)
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
