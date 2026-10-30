import NookApp
import SwiftUI

struct FeishuEmptyStatePresentation {
    let title: String
    let detail: String
    let symbol: String
    init(enabled: Bool, connecting: Bool, status: String, showAll: Bool) {
        if connecting {
            title = "等待你完成飞书授权"; symbol = "arrow.triangle.2.circlepath"
            detail = "在授权窗口确认后，Mac会自动核对连接。"
        } else if !enabled {
            title = "接收已停止"; symbol = "pause"
            detail = "点右上角齿轮，在“飞书消息”中开启接收。"
        } else if status.hasPrefix("账号接收中") || status.hasPrefix("演示模式") || status.hasPrefix("皮肤预览") {
            title = showAll ? "等待新的消息" : "暂时没有重要消息"; symbol = showAll ? "tray" : "checkmark"
            detail = "按你的规则筛选，继续遵守免打扰。"
        } else {
            let failed = ["失败", "异常", "过期", "未登录", "无法", "错误", "暂缓"].contains { status.contains($0) }
            title = failed ? "连接需要检查" : "正在连接飞书"
            symbol = failed ? "exclamationmark.circle" : "arrow.triangle.2.circlepath"
            detail = status.isEmpty ? "正在核对连接，请稍候。" : status
        }
    }
}

struct FeishuView: View {
    @ObservedObject var store: FeishuStore
    @Environment(\.nookResolvedTheme) private var theme
    @State private var showAll = false

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 10) {
                if let id = store.readingID, let message = store.visibleMessages.first(where: { $0.id == id }) {
                    IslandContentScroll(height: IslandHost.panelHeight - 2 * IslandHost.panelPadding) {
                        detail(message)
                        errorBanner
                    }
                } else {
                    header.frame(height: 28)
                    let list = showAll ? store.visibleMessages : store.important
                    Group {
                        if list.isEmpty {
                            emptyState
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            IslandContentScroll(height: IslandHost.panelHeight - 2 * IslandHost.panelPadding - 28 - 24 - 20) {
                            LazyVStack(spacing: 8) {
                                ForEach(list) { message in
                                    VStack(spacing: 5) {
                                    Button { store.openReader(message.id) } label: { row(message) }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("feishu.message.\(message.id)")
                                    if message.hasImageContent {
                                        FeishuImageGallery(message: message, connection: store.connection, compact: true)
                                            .padding(.horizontal, 8).padding(.bottom, 5)
                                    }
                                    }
                                }
                            }
                            if !store.status.hasPrefix("账号接收中") && !store.status.hasPrefix("演示模式") {
                                Text(store.status).islandFont(size: 12).fixedSize(horizontal:false,vertical:true)
                                    .foregroundStyle(store.status.contains("失败") || store.status.contains("异常") || store.status.contains("暂缓") ? theme.warning : theme.tertiaryLabel)
                            }
                            errorBanner
                            }
                        }
                    }
                    footer.frame(height: 24)
                }
            }.padding(IslandHost.panelPadding)
                .frame(height: IslandHost.panelHeight, alignment: .top)
        }
        .accessibilityIdentifier("feishu.home")
        .modifier(IslandReadingModule(moduleID:IslandHost.feishuID))
    }

    @ViewBuilder private var errorBanner: some View {
        if let error = store.actionError {
            Text(error).islandFont(size: 11).foregroundStyle(theme.warning)
                .onTapGesture { store.actionError = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                tab("重要", count: store.waitingCount, active: !showAll) { showAll = false }
                    .accessibilityIdentifier("feishu.important")
                tab("最近", count: nil, active: showAll) { showAll = true }
                    .accessibilityIdentifier("feishu.recent")
            }
            .padding(3).background(theme.subtleFill, in: RoundedRectangle(cornerRadius: 8))
            Spacer()
        }
    }

    private func tab(_ title: String, count: Int?, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).islandFont(size: 11, weight: active ? .semibold : .medium)
                if let count {
                    Text("\(count)").islandFont(size: 9, weight: .medium).monospacedDigit()
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(theme.accent.opacity(active ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 3))
                }
            }
            .foregroundStyle(active ? theme.accent : theme.secondaryLabel)
            .padding(.horizontal, 10).frame(height: 24)
            .background(active ? theme.accent.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain)
    }

    private var emptyState: some View {
        let presentation = FeishuEmptyStatePresentation(enabled: store.enabled, connecting: store.connecting, status: store.status, showAll: showAll)
        return VStack(spacing: 10) {
            Image(systemName: presentation.symbol)
                .islandFont(size: 19, weight: .regular).foregroundStyle(theme.accent)
                .frame(width: 40, height: 40)
                .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
            Text(presentation.title)
                .islandFont(size: 13, weight: .medium).foregroundStyle(theme.primaryLabel)
            Text(presentation.detail)
                .islandFont(size: 10).foregroundStyle(theme.tertiaryLabel)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            errorBanner
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(16)
        .accessibilityIdentifier("feishu.emptyState")
    }

    private func row(_ message: FeishuMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(String(message.source.prefix(1))).islandFont(size: 12, weight: .medium)
                .foregroundStyle(theme.accent).frame(width: 29, height: 29)
                .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .overlay(alignment: .topTrailing) {
                    if !message.viewed { Circle().fill(theme.accent).frame(width: 5, height: 5).offset(x: 2, y: -2) }
                }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(message.source).islandFont(size: 12, weight: .semibold).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(message.created, style: .time).islandFont(size: 9).foregroundStyle(theme.tertiaryLabel)
                }
                Text(message.displayText)
                    .islandFont(size: 14).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal:false,vertical:true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    if let reason = message.importanceReason(followed: store.followed, rules: store.rules, custom: store.customRules) {
                        Text(reason).islandFont(size: 8, weight: .medium)
                            .foregroundStyle(theme.accent).padding(.horizontal, 5).padding(.vertical, 2)
                            .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    }
                    if message.remindAt != nil {
                        Label("稍后提醒已设", systemImage: "clock").islandFont(size: 8).foregroundStyle(theme.tertiaryLabel)
                    }
                }
            }
        }
        .padding(11).foregroundStyle(theme.primaryLabel)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(IslandCard(highlighted: !message.viewed))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack {
            Button { store.toggleMute() } label: {
                Label(store.isMuted ? "恢复提醒" : "静音1小时", systemImage: store.isMuted ? "bell.slash" : "bell")
            }.buttonStyle(.plain).foregroundStyle(store.isMuted ? theme.accent : theme.secondaryLabel)
                .accessibilityIdentifier("feishu.mute")
            Spacer()
        }
        .islandFont(size: 10, weight: .medium).padding(.top, 10)
        .overlay(alignment: .top) { Rectangle().fill(theme.subtleStroke).frame(height: 0.5) }
    }

    private func detail(_ message: FeishuMessage) -> some View {
        IslandMessageReader(message: message, followed: store.followed.contains(message.chatID),
                            pending: store.readingQueue.count,
                            onBack: { store.closeReader() },
                            onFollow: { store.toggleFollow(message.chatID) },
                            onDone: { store.finishReading() },
                            onRemind: { store.remindLater(message.id); store.finishReading() },
                            onOpen: { store.open(message) },
                            initialPage: store.readingPages[message.id] ?? 0,
                            onPageChange: { store.rememberReadingPage($0, for: message.id) }, connection: store.connection)
            .id(message.id)
    }
}
