import NookApp
import SwiftUI

@MainActor
final class UnifiedPlatformModule: NookModule {
    nonisolated static let info: NookModuleDescriptor = {
        var value = NookModuleDescriptor(id: IslandHost.platformID, displayName: "中台", icon: "square.grid.2x2", backgroundPolicy: .stayResident)
        value.loadsAtLaunch = true
        return value
    }()
    var descriptor: NookModuleDescriptor { Self.info }
    init(context: NookModuleContext) { HubPingLauncher.shared.start() }
    func makeConfiguration() -> NookConfiguration {
        var config = IslandHost.baseConfiguration(title: "中台", symbol: "square.grid.2x2")
        config.setCompactTrailing { Text("虚实中台").font(.system(size: 10, weight: .medium)) }
        config.setHome { UnifiedPlatformPanel(workspace: .shared) }
        return config
    }
}

@MainActor
struct UnifiedPlatformPanel: View {
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var launcher: UnifiedPlatformStore = .shared
    @Environment(\.nookResolvedTheme) private var theme
    @State private var closedCards = Set<String>()
    var body: some View {
        IslandContentScroll {
            VStack(alignment: .leading, spacing: 12) {
                if !workspace.hub.connected {
                    Text("连接后，在这里查看本人中台卡片。")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
                    Button("连接中台") { connect() }.buttonStyle(IslandButtonStyle())
                }
                if !workspace.hub.error.isEmpty {
                    Text(workspace.hub.error).font(.system(size: 12)).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true)
                }
                if workspace.hub.connected && workspace.visibleCards.isEmpty {
                    Text("还没有选择卡片。点右上角齿轮，在“中台”中选择要放在岛里的内容。")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
                }
                if !workspace.visibleCards.isEmpty {
                    HStack {
                        Text("我的卡片").font(.system(size: 18, weight: .semibold)); Spacer()
                        Button { Task { await workspace.refreshHub() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).accessibilityLabel("刷新中台")
                    }
                    ForEach(workspace.visibleCards) { card in
                        DisclosureGroup(isExpanded: Binding(get: { !closedCards.contains(card.id) }, set: { if $0 { closedCards.remove(card.id) } else { closedCards.insert(card.id) } })) {
                            VStack(alignment: .leading, spacing: 10) {
                                HubCardContent(card: card)
                                if let url = card.href.flatMap(HubPingGeometry.safeURL) {
                                    Button("打开中台原页") { _ = launcher.activate(.init(id: 0, title: card.title, url: url)) }.buttonStyle(IslandButtonStyle())
                                }
                            }.padding(.top, 8)
                        } label: { Text(HubCardPresentation.title(card)).font(.system(size: 17, weight: .semibold)) }
                        .padding(13).modifier(IslandCard(radius: 12))
                    }
                }
            }.padding(12)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(theme.primaryLabel)
        .accessibilityIdentifier("island.platform")
    }
    private func connect() {
        guard let address = SettingsServer.shared.address else {
            workspace.error = "本机连接服务尚未就绪，请稍后重试。"
            UnifiedSettingsWindow.shared.open(section: .platform); return
        }
        workspace.connectHub(callback: address + "/oauth/virxact/callback")
    }
}

@MainActor
struct UnifiedPlatformSettings: View {
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var launcher: UnifiedPlatformStore = .shared
    @Environment(\.nookResolvedTheme) private var theme
    @State private var tab = "cards"
    private var orderedCards: [HubCard] {
        workspace.visibleCards + workspace.hub.cards.filter { !workspace.disk.selectedCards.contains($0.id) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("中台设置", selection: $tab) {
                Text("岛内卡片").tag("cards")
                Text("快捷入口").tag("shortcuts")
                Text("连接与状态").tag("connection")
            }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("platform.settings.tabs")
            if tab == "cards" {
                IslandSettingsCard("把常看的内容放在岛上") {
                    Toggle("在灵动岛主栏显示中台", isOn: Binding(get: { launcher.showInMainBar }, set: { _ = launcher.setMainBar($0) }))
                    Text("选择要展示的卡片，用箭头调整顺序。隐藏栏目会保留连接和选择。")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    if workspace.hub.cards.isEmpty {
                        Text(workspace.hub.connected ? "还没有可展示的卡片，可以在“连接与状态”刷新。" : "先在“连接与状态”连接自己的中台。")
                            .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).padding(.vertical, 12)
                    }
                    HubCardOptionsLayout {
                        ForEach(orderedCards) { card in cardOption(card) }
                    }.accessibilityIdentifier("platform.cards.options")
                }
            } else if tab == "shortcuts" {
                HubShortcutSettings(workspace: workspace, launcher: launcher)
            } else {
                IslandSettingsCard("本人中台连接") {
                    Label(workspace.hub.connected ? "已连接本人中台" : "尚未连接中台", systemImage: workspace.hub.connected ? "checkmark.circle.fill" : "link")
                        .foregroundStyle(workspace.hub.connected ? Color.green : theme.secondaryLabel)
                    Text("按本人的权限读取首页与数据卡片，每10分钟更新。正文只在内存中缓存，快捷入口只打开链接。")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(workspace.hub.connected ? "重新连接" : "连接中台") {
                            if let address = SettingsServer.shared.address { workspace.connectHub(callback: address + "/oauth/virxact/callback") }
                            else { workspace.error = "本机连接服务尚未就绪，请稍后重试。" }
                        }.buttonStyle(IslandButtonStyle(prominent: true))
                        Button(workspace.hubBusy ? "刷新中…" : "刷新卡片") { Task { await workspace.refreshHub() } }
                            .disabled(workspace.hubBusy).buttonStyle(IslandButtonStyle())
                    }
                    if !workspace.hub.error.isEmpty { Text(workspace.hub.error).font(.system(size: 12)).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true) }
                    if !workspace.error.isEmpty { Text(workspace.error).font(.system(size: 12)).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true) }
                }
            }
            if !launcher.error.isEmpty { Text(launcher.error).font(.system(size: 12)).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true) }
        }.foregroundStyle(theme.primaryLabel).accessibilityIdentifier("island.platform.settings")
    }
    private func cardOption(_ card: HubCard) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { workspace.disk.selectedCards.contains(card.id) }, set: { selected in
                if selected != workspace.disk.selectedCards.contains(card.id) { workspace.toggleCard(card.id) }
            })) {
                Text(card.title).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch).accessibilityIdentifier("platform.card.\(card.id)")
            if let index = workspace.disk.selectedCards.firstIndex(of: card.id) {
                HStack(spacing: 0) {
                    Button { workspace.moveCard(card.id, direction: -1) } label: { Image(systemName: "arrow.up").frame(width: 24, height: 28) }
                        .disabled(index == 0).accessibilityLabel("上移：" + card.title)
                    Button { workspace.moveCard(card.id, direction: 1) } label: { Image(systemName: "arrow.down").frame(width: 24, height: 28) }
                        .disabled(index == workspace.disk.selectedCards.count - 1).accessibilityLabel("下移：" + card.title)
                }
            }
        }.buttonStyle(.plain).frame(minHeight: 40)
    }
}
