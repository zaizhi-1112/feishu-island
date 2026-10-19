import NookApp
import SwiftUI

struct FeishuView: View {
    @ObservedObject var store: FeishuStore
    @Environment(\.nookResolvedTheme) private var theme
    @State private var showAll = false
    @State private var selectedID: String?
    @State private var showConnection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let id = selectedID, let message = store.visibleMessages.first(where: { $0.id == id }) {
                detail(message)
            } else {
                header
                if showConnection { connection }
                let list = showAll ? store.visibleMessages : store.important
                if list.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(list) { message in
                                Button {
                                    selectedID = message.id
                                    store.markViewed(message.id)
                                } label: { row(message) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("feishu.message.\(message.id)")
                            }
                        }
                    }.frame(height: min(CGFloat(list.count) * 88, 256))
                }
                footer
                if !store.status.hasPrefix("账号接收中") && !store.status.hasPrefix("演示模式") {
                    Button { showConnection = true } label: {
                        Text(store.status).font(.system(size: 10)).lineLimit(2)
                            .foregroundStyle(store.status.contains("失败") || store.status.contains("异常") || store.status.contains("暂缓") ? theme.warning : theme.tertiaryLabel)
                    }.buttonStyle(.plain)
                }
            }
            if let error = store.actionError {
                Text(error).font(.system(size: 11)).foregroundStyle(theme.warning)
                    .onTapGesture { store.actionError = nil }
            }
        }
        .padding(.horizontal, 12).padding(.top, 7).padding(.bottom, 10)
        .accessibilityIdentifier("feishu.home")
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
            Button { showConnection.toggle() } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 27)
                    .foregroundStyle(showConnection ? theme.accent : theme.secondaryLabel)
                    .background(showConnection ? theme.accent.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain).help("连接与接收设置").accessibilityLabel("连接与接收设置")
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
            Text(!store.enabled ? "在连接设置中，可以重新开始接收。" : "按你的规则筛选，继续遵守免打扰。")
                .font(.system(size: 10)).foregroundStyle(theme.tertiaryLabel)
        }
        .frame(maxWidth: .infinity).frame(height: 157).modifier(IslandCard())
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Circle().fill(store.enabled ? theme.accent : theme.tertiaryLabel).frame(width: 5, height: 5)
                Text("\(store.account) · 本机连接").font(.system(size: 12, weight: .medium))
            }
            Text(store.status).font(.system(size: 10)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(store.enabled ? "停止接收" : "开始接收") { store.toggleReceiving() }.buttonStyle(IslandButtonStyle())
                if store.enabled { Button("重新连接") { store.reconnect() }.buttonStyle(IslandButtonStyle(prominent: true)) }
            }
            Text("使用本机已有飞书授权；授权失效时请在终端完成lark-cli auth login，再点重新连接。")
                .font(.system(size: 10)).foregroundStyle(theme.tertiaryLabel)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(theme.primaryLabel).modifier(IslandCard())
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
            Button { SettingsServer.shared.open() } label: { Label("设置面板", systemImage: "slider.horizontal.3") }
                .buttonStyle(.plain).foregroundStyle(theme.secondaryLabel).accessibilityIdentifier("feishu.webSettings")
        }
        .font(.system(size: 10, weight: .medium)).padding(.top, 10)
        .overlay(alignment: .top) { Rectangle().fill(theme.subtleStroke).frame(height: 0.5) }
    }

    private func detail(_ message: FeishuMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { selectedID = nil; store.actionError = nil } label: { Label("返回", systemImage: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(theme.secondaryLabel)
                Spacer()
                Button { store.toggleFollow(message.chatID) } label: {
                    Image(systemName: store.followed.contains(message.chatID) ? "star.fill" : "star")
                }.buttonStyle(.plain).foregroundStyle(theme.accent)
                    .help("关注此会话的新消息").accessibilityLabel(store.followed.contains(message.chatID) ? "取消关注" : "关注会话")
            }.font(.system(size: 11))
            VStack(alignment: .leading, spacing: 7) {
                Text(message.source).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.primaryLabel)
                HStack(spacing: 7) {
                    Text(message.senderName)
                    Text("·")
                    Text(message.created, style: .time)
                }.font(.system(size: 10)).foregroundStyle(theme.tertiaryLabel)
            }
            ScrollView {
                Text(message.text).font(.system(size: 12)).lineSpacing(6)
                    .foregroundStyle(theme.primaryLabel).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }.frame(height: 154).modifier(IslandCard())
            HStack(spacing: 8) {
                Button("10分钟后提醒") { store.remindLater(message.id); selectedID = nil }
                    .buttonStyle(IslandButtonStyle())
                Spacer()
                Button("打开会话") { store.open(message) }.buttonStyle(IslandButtonStyle(prominent: true))
                    .disabled(message.chatURL == nil).accessibilityIdentifier("feishu.openChat")
            }
            Text("岛内查看不改变飞书已读 · 稍后提醒仅本次运行有效")
                .font(.system(size: 9)).foregroundStyle(theme.tertiaryLabel)
        }
    }
}
