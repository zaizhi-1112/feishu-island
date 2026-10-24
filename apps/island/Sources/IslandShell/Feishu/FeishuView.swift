import NookApp
import SwiftUI

struct FeishuView: View {
    @ObservedObject var store: FeishuStore
    @Environment(\.nookResolvedTheme) private var theme
    @State private var showAll = false

    var body: some View {
        WorkspaceIslandFrame { bodyHeight in
            VStack(alignment: .leading, spacing: 10) {
                if let id = store.readingID, let message = store.visibleMessages.first(where: { $0.id == id }) {
                    ScrollView {
                        detail(message)
                        errorBanner
                    }.frame(height: bodyHeight + WorkspaceLayout.headerHeight + WorkspaceLayout.sectionSpacing)
                } else {
                    header.frame(height: 28)
                    ScrollView {
                        let list = showAll ? store.visibleMessages : store.important
                        if list.isEmpty { emptyState }
                        else {
                            LazyVStack(spacing: 8) {
                                ForEach(list) { message in
                                    Button { store.openReader(message.id) } label: { row(message) }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("feishu.message.\(message.id)")
                                }
                            }
                        }
                        if !store.status.hasPrefix("账号接收中") && !store.status.hasPrefix("演示模式") {
                            Button { WorkspaceWindow.shared.openSettings(store: .shared) } label: {
                                Text(store.status).font(.system(size: 10)).lineLimit(2)
                                    .foregroundStyle(store.status.contains("失败") || store.status.contains("异常") || store.status.contains("暂缓") ? theme.warning : theme.tertiaryLabel)
                            }.buttonStyle(.plain)
                        }
                        errorBanner
                    }.frame(height: max(0, bodyHeight - 30))
                    footer.frame(height: 24)
                }
            }.padding(WorkspaceLayout.padding)
        }
        .accessibilityIdentifier("feishu.home")
        .modifier(IslandReadingModule(moduleID:IslandHost.feishuID))
    }

    @ViewBuilder private var errorBanner: some View {
        if let error = store.actionError {
            Text(error).font(.system(size: 11)).foregroundStyle(theme.warning)
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
                Text(title).font(.system(size: 11, weight: active ? .semibold : .medium))
                if let count {
                    Text("\(count)").font(.system(size: 9, weight: .medium)).monospacedDigit()
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
        VStack(spacing: 10) {
            Image(systemName: !store.enabled ? "pause" : showAll ? "tray" : "checkmark")
                .font(.system(size: 19, weight: .regular)).foregroundStyle(theme.accent)
                .frame(width: 40, height: 40)
                .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
            Text(!store.enabled ? "接收已停止" : showAll ? "等待新的消息" : "暂时没有重要消息")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(theme.primaryLabel)
            Text(!store.enabled ? "在工作台设置中，可以重新开始接收。" : "按你的规则筛选，继续遵守免打扰。")
                .font(.system(size: 10)).foregroundStyle(theme.tertiaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).modifier(IslandCard())
    }

    private func row(_ message: FeishuMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(String(message.source.prefix(1))).font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.accent).frame(width: 29, height: 29)
                .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .overlay(alignment: .topTrailing) {
                    if !message.viewed { Circle().fill(theme.accent).frame(width: 5, height: 5).offset(x: 2, y: -2) }
                }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(message.source).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(message.created, style: .time).font(.system(size: 9)).foregroundStyle(theme.tertiaryLabel)
                }
                Text(message.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 11)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    if let reason = message.importanceReason(followed: store.followed, rules: store.rules, custom: store.customRules) {
                        Text(reason).font(.system(size: 8, weight: .medium))
                            .foregroundStyle(theme.accent).padding(.horizontal, 5).padding(.vertical, 2)
                            .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    }
                    if message.remindAt != nil {
                        Label("稍后提醒已设", systemImage: "clock").font(.system(size: 8)).foregroundStyle(theme.tertiaryLabel)
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
            Button { WorkspaceWindow.shared.openSettings(store: .shared) } label: { Label("工作台设置", systemImage: "slider.horizontal.3") }
                .buttonStyle(.plain).foregroundStyle(theme.secondaryLabel).accessibilityIdentifier("feishu.webSettings")
        }
        .font(.system(size: 10, weight: .medium)).padding(.top, 10)
        .overlay(alignment: .top) { Rectangle().fill(theme.subtleStroke).frame(height: 0.5) }
    }

    private func detail(_ message: FeishuMessage) -> some View {
        IslandMessageReader(message: message, followed: store.followed.contains(message.chatID),
                            pending: store.readingQueue.count,
                            onBack: { store.closeReader() },
                            onFollow: { store.toggleFollow(message.chatID) },
                            onDone: { store.finishReading() },
                            onRemind: { store.remindLater(message.id); store.finishReading() },
                            onOpen: { store.open(message) }, appearance: store.appearance,
                            initialPage: store.readingPages[message.id] ?? 0,
                            onPageChange: { store.rememberReadingPage($0, for: message.id) })
            .id(message.id)
    }
}
