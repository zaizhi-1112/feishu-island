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
    init(context: NookModuleContext) {}
    func makeConfiguration() -> NookConfiguration {
        var config = IslandHost.baseConfiguration(title: "中台", symbol: "square.grid.2x2")
        config.setCompactTrailing { Text("中台快捷入口").font(.system(size: 10, weight: .medium)) }
        config.setHome { UnifiedPlatformPanel(workspace: .shared) }
        return config
    }
}

@MainActor
struct UnifiedPlatformPanel: View {
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var launcher: UnifiedPlatformStore = .shared
    @Environment(\.nookResolvedTheme) private var theme
    @State private var openCards = Set<String>()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("快捷入口").font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Button { WorkspaceWindow.shared.openHub(store: workspace) } label: { Image(systemName: "slider.horizontal.3").frame(width: 28, height: 28) }
                        .buttonStyle(.plain).accessibilityLabel("中台设置")
                }
                HubPingWheel(destinations: launcher.destinations(cards: workspace.hub.cards, selectedIDs: workspace.disk.selectedCards), diameter: 300, activate: launcher.activate)
                    .frame(maxWidth: .infinity)
                if !launcher.error.isEmpty { Text(launcher.error).font(.system(size: 12)).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true) }
                if !workspace.hub.connected {
                    Text("连接中台后，可把本人卡片放进快捷轮盘；自定义入口随时可用。")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
                    Button("连接中台") { connect() }.buttonStyle(IslandButtonStyle())
                }
                if !workspace.hub.error.isEmpty {
                    Text(workspace.hub.error).font(.system(size: 12)).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true)
                }
                if !workspace.visibleCards.isEmpty {
                    HStack {
                        Text("我的卡片").font(.system(size: 15, weight: .semibold)); Spacer()
                        Button { Task { await workspace.refreshHub() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).accessibilityLabel("刷新中台")
                    }
                    ForEach(workspace.visibleCards) { card in
                        DisclosureGroup(isExpanded: Binding(get: { openCards.contains(card.id) }, set: { if $0 { openCards.insert(card.id) } else { openCards.remove(card.id) } })) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(HubCardPresentation.displayText(card.text)).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                if let url = card.href.flatMap(HubPingGeometry.safeURL) {
                                    Button("打开中台原页") { _ = launcher.activate(.init(id: 0, title: card.title, url: url)) }.buttonStyle(IslandButtonStyle())
                                }
                            }.padding(.top, 8)
                        } label: { Text(card.title).font(.system(size: 13, weight: .medium)) }
                        .padding(13).modifier(IslandCard(radius: 12))
                    }
                }
            }.padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: IslandHost.panelHeight)
        .foregroundStyle(theme.primaryLabel)
        .accessibilityIdentifier("island.platform")
    }
    private func connect() {
        guard let address = SettingsServer.shared.address else {
            workspace.error = "本机连接服务尚未就绪，请稍后重试。"
            WorkspaceWindow.shared.openHub(store: workspace); return
        }
        workspace.connectHub(callback: address + "/oauth/virxact/callback")
    }
}

@MainActor
struct UnifiedPlatformSettings: View {
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var launcher: UnifiedPlatformStore = .shared
    @Environment(\.nookResolvedTheme) private var theme
    @State private var refreshing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("在灵动岛主栏显示中台", isOn: Binding(get: { launcher.showInMainBar }, set: { _ = launcher.setMainBar($0) })).toggleStyle(.switch)
                Text("关闭只隐藏主栏入口，连接、轮盘和卡片设置都会保留。")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                HStack(spacing: 10) {
                    Label(workspace.hub.connected ? "已连接本人中台" : "尚未连接中台", systemImage: workspace.hub.connected ? "checkmark.circle.fill" : "link")
                        .foregroundStyle(workspace.hub.connected ? Color.green : theme.secondaryLabel)
                    Spacer()
                    Button(workspace.hub.connected ? "重新连接" : "连接中台") {
                        if let address = SettingsServer.shared.address { workspace.connectHub(callback: address + "/oauth/virxact/callback") }
                        else { workspace.error = "本机连接服务尚未就绪，请稍后重试。" }
                    }.buttonStyle(IslandButtonStyle())
                    Button(refreshing ? "刷新中…" : "刷新") {
                        refreshing = true
                        Task { await workspace.refreshHub(); refreshing = false }
                    }.disabled(refreshing).buttonStyle(IslandButtonStyle())
                }
                if !workspace.hub.error.isEmpty { Text(workspace.hub.error).font(.system(size: 12)).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true) }
                if !workspace.error.isEmpty { Text(workspace.error).font(.system(size: 12)).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true) }
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("快捷信号轮盘").font(.system(size: 18, weight: .semibold))
                Text("八个方向对应八个入口。自动分配会跟随已选卡片；也可以固定某张卡片，或填写自己的 HTTPS 入口。")
                    .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
                Toggle("打开入口时播放信号音效", isOn: Binding(get: { launcher.preferences.soundEnabled }, set: { _ = launcher.setSound($0) })).toggleStyle(.switch)
                ForEach(0..<8, id: \.self) { index in
                    HubPingSlotEditor(index: index, launcher: launcher, cards: workspace.hub.cards)
                }
                if !launcher.error.isEmpty { Text(launcher.error).font(.system(size: 12)).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true) }
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("显示在中台的卡片").font(.system(size: 18, weight: .semibold))
                if workspace.hub.cards.isEmpty { Text("连接后会在这里列出本人可读取的卡片。") .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel) }
                ForEach(workspace.hub.cards) { card in
                    HStack(spacing: 10) {
                        Toggle(card.title, isOn: Binding(get: { workspace.disk.selectedCards.contains(card.id) }, set: { selected in
                            if selected != workspace.disk.selectedCards.contains(card.id) { workspace.toggleCard(card.id) }
                        })).toggleStyle(.switch)
                        if workspace.disk.selectedCards.contains(card.id) {
                            Button { workspace.moveCard(card.id, direction: -1) } label: { Image(systemName: "arrow.up") }.accessibilityLabel("上移：" + card.title)
                            Button { workspace.moveCard(card.id, direction: 1) } label: { Image(systemName: "arrow.down") }.accessibilityLabel("下移：" + card.title)
                        }
                    }.buttonStyle(.plain).padding(.vertical, 4)
                }
                Text("沿用独立中台授权，只读本人卡片；正文仅在内存中缓存。快捷轮盘只打开链接，不调用 Agent 或业务写入接口。")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
            }
        }.foregroundStyle(theme.primaryLabel).accessibilityIdentifier("island.platform.settings")
    }
}

@MainActor
private struct HubPingSlotEditor: View {
    let index: Int
    @ObservedObject var launcher: UnifiedPlatformStore
    let cards: [HubCard]
    @State private var editingCustom = false
    @State private var title = ""
    @State private var address = ""
    private var saved: HubPingShortcut { launcher.preferences.slots[index] }
    private var selection: String {
        switch saved.source {
        case .automatic: return "automatic"
        case .empty: return "empty"
        case .custom: return "custom"
        case .card: return "card:" + saved.cardID
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Text(["上", "右上", "右", "右下", "下", "左下", "左", "左上"][index]).font(.system(size: 12, weight: .semibold)).frame(width: 36, alignment: .leading)
                Picker("第\(index + 1)个入口", selection: Binding(get: { editingCustom ? "custom" : selection }, set: { choose($0) })) {
                    Text("自动分配").tag("automatic")
                    Text("留空").tag("empty")
                    Text("自定义入口").tag("custom")
                    if saved.source == .card, !cards.contains(where: { $0.id == saved.cardID }) { Text("已保存的卡片（暂不可用）").tag("card:" + saved.cardID) }
                    ForEach(cards.filter { $0.href.flatMap(HubPingGeometry.safeURL) != nil }) { card in Text(card.title).tag("card:" + card.id) }
                }.labelsHidden().frame(maxWidth: .infinity)
            }
            if editingCustom || saved.source == .custom {
                HStack {
                    TextField("入口名称", text: $title).frame(width: 135)
                    TextField("https://…", text: $address)
                    Button("保存") {
                        if launcher.setSlot(index, .init(source: .custom, title: title.trimmingCharacters(in: .whitespacesAndNewlines), address: address.trimmingCharacters(in: .whitespacesAndNewlines))) { editingCustom = false }
                    }.buttonStyle(IslandButtonStyle())
                }.textFieldStyle(.roundedBorder)
            }
        }.padding(12).modifier(IslandCard(radius: 12))
        .onAppear { title = saved.title; address = saved.address }
    }
    private func choose(_ value: String) {
        if value == "custom" { editingCustom = true; title = saved.title; address = saved.address; return }
        editingCustom = false
        if value == "automatic" { _ = launcher.setSlot(index, .init()) }
        else if value == "empty" { _ = launcher.setSlot(index, .init(source: .empty)) }
        else if value.hasPrefix("card:") { _ = launcher.setSlot(index, .init(source: .card, cardID: String(value.dropFirst(5)))) }
    }
}
