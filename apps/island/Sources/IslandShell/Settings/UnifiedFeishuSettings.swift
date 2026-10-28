import AppKit
import NookApp
import SwiftUI

struct UnifiedFeishuSettings: View {
    private let suppliedStore: FeishuStore?
    init(store: FeishuStore? = nil) { suppliedStore = store }
    var body: some View {
        if let store = suppliedStore ?? FeishuStore.active {
            UnifiedFeishuSettingsContent(store: store)
        } else {
            ContentUnavailableView("飞书正在准备", systemImage: "paperplane", description: Text("应用启动后会自动准备连接。"))
        }
    }
}

struct UnifiedFeishuSettingsContent: View {
    @ObservedObject var store: FeishuStore
    @StateObject private var model: FeishuSettingsModel
    @State private var query = ""
    @State private var expanded = false
    @State private var connectionSheet = false
    @State private var connectionDetails = false
    @State private var customColors = false
    @State private var preview = false
    @State private var previewStarted = Date()
    @State private var feedback: String?
    @State private var undoAction: (() -> Void)?
    @State private var undoRevision = -1
    @State private var appearanceError: String?
    @State private var colorDraft: [String: Any]?
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    init(store: FeishuStore, model: FeishuSettingsModel? = nil) {
        self.store = store
        _model = StateObject(wrappedValue: model ?? FeishuSettingsModel(store: store))
    }
    private var connectionState: FeishuSettingsConnectionState { model.connectionState }
    private var canReceive: Bool { store.canResumeSavedConnection && store.rulesConfigurationReadable }
    private var bubble: String { store.appearance["bubble"] as? String ?? "none" }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            accountCard
            reminderSection
            displaySection
            HStack(spacing: 5) {
                Image(systemName: "checkmark").font(.system(size: 11))
                Text("设置自动保存在这台 Mac；自定义配色点「应用配色」后生效。").font(.system(size: 12))
            }.foregroundStyle(theme.secondaryLabel).frame(maxWidth: .infinity)
        }
        .font(.system(size: 14)).foregroundStyle(theme.primaryLabel)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("unified.feishu.settings")
        .overlay(alignment: .topTrailing) {
            if let feedback {
                HStack(spacing: 12) {
                    Text(feedback).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    if undoAction != nil, undoRevision == store.settingsRevision {
                        Button("撤销") { undoAction?(); clearFeedback() }.font(.system(size: 12, weight: .semibold))
                            .accessibilityIdentifier("unified.feishu.undo")
                    }
                    Button { clearFeedback() } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).accessibilityLabel("关闭操作提示")
                }.padding(12).background(theme.subtleFill, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.subtleStroke))
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 4).padding(8)
                    .accessibilityIdentifier("unified.feishu.feedback")
            }
        }
        .sheet(isPresented: $connectionSheet) {
            FeishuMessageConnectionSheet(store: store) { connectionSheet = false; model.connectionChanged() }
        }
        .onAppear { model.load(reset: true) }
        .onChange(of: store.connection) { _, _ in clearFeedback(); model.connectionChanged() }
        .onChange(of: store.status) { _, _ in model.receiverChanged() }
        .onChange(of: store.settingsRevision) { _, revision in
            if undoRevision != revision { clearFeedback() }
        }
        .onChange(of: query) { _, value in if !value.isEmpty { expanded = true } }
        .onDisappear { preview = false; model.stop() }
        .task(id: feedback) { if feedback != nil { try? await Task.sleep(for: .seconds(6)); if !Task.isCancelled { clearFeedback() } } }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { accountIdentity; Spacer(minLength: 12); accountControls }
                VStack(alignment: .leading, spacing: 10) { accountIdentity; HStack { Spacer(); accountControls } }
            }
            Divider().overlay(theme.subtleStroke)
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Circle().fill(connectionState.warning ? theme.warning : theme.accent).frame(width: 7, height: 7)
                        Text(connectionState.title).font(.system(size: 14, weight: .semibold))
                            .accessibilityIdentifier("unified.feishu.connectionStatus")
                    }
                    Text(connectionState.detail).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true).padding(.leading, 14)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if connectionState.kind == .unconnected || [.authorization, .permission, .identity].contains(connectionState.kind) {
                    Button(connectionState.action) { connectionSheet = true }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(!store.rulesConfigurationReadable).accessibilityIdentifier("unified.feishu.reconnect")
                } else {
                    Button(connectionState.action) { performConnectionAction() }.buttonStyle(.plain).foregroundStyle(theme.accent)
                        .disabled(model.loading || connectionState.kind == .checking).padding(.vertical, 10)
                        .accessibilityIdentifier("unified.feishu.checkConnection")
                }
            }
            if connectionState.warning || connectionDetails || store.actionError != nil {
                DisclosureGroup("连接详情", isExpanded: $connectionDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.failure ?? store.actionError ?? store.status).textSelection(.enabled)
                        if let at = model.checkedAt { Text("最近检测：\(at.formatted(date: .omitted, time: .shortened))") }
                        if connectionState.warning && store.rulesConfigurationReadable {
                            Button("重新授权飞书") { connectionSheet = true }.buttonStyle(.link)
                        }
                    }.font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true).padding(.top, 7)
                }.font(.system(size: 12)).tint(theme.secondaryLabel)
            }
            if store.isMuted {
                HStack {
                    Label(store.enabled ? "消息仍在接收，岛上提醒已暂停。" : "岛上提醒也处于暂停状态。", systemImage: "moon").font(.system(size: 12)).foregroundStyle(theme.warning)
                    Spacer()
                    Button("恢复提醒") { store.toggleMute() }.font(.system(size: 12)).buttonStyle(.link)
                }
            }
        }.padding(22).modifier(FeishuSettingsSurface())
    }
    private var accountIdentity: some View {
        HStack(spacing: 12) {
            Image(systemName: "paperplane.fill").font(.system(size: 21)).foregroundStyle(theme.accent)
                .frame(width: 43, height: 43).background(theme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(store.connection.localAccount?.userName ?? (store.canResumeSavedConnection ? store.account : "连接自己的飞书")).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                Text(store.canResumeSavedConnection ? "个人飞书账号" : "在岛上查看你的新消息").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
        }
    }
    private var accountControls: some View {
        HStack(spacing: 16) {
            if store.canResumeSavedConnection {
                Button("管理账号") { connectionSheet = true }.buttonStyle(.plain).foregroundStyle(theme.accent)
                    .accessibilityIdentifier("unified.feishu.manageAccount")
            }
            Toggle("接收新消息", isOn: Binding(get: { store.enabled }, set: { value in
                if value != store.enabled { store.toggleReceiving() }
            })).toggleStyle(.switch).fixedSize().disabled(!canReceive)
                .accessibilityIdentifier("unified.feishu.receiving")
        }.font(.system(size: 12))
    }
    private func performConnectionAction() {
        if connectionState.kind == .blocked { connectionDetails.toggle(); return }
        connectionDetails = true
        model.load(reset: true, retryReceiver: [.failed, .degraded].contains(connectionState.kind))
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("哪些消息提醒我", trailing: "默认规则")
            if !store.enabled || connectionState.warning {
                Text(!store.enabled ? "当前已停止接收新消息，下面的规则会在恢复接收后生效。" : "当前连接需要检查。已有提醒规则会保留。").font(.system(size: 12))
                    .foregroundStyle(theme.warning).padding(11).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.warning.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    ruleRow("私聊消息", key: \.directMessages)
                    Divider()
                    ruleRow("群聊中有人 @我", key: \.mentionsMe)
                    Divider()
                    ruleRow("群聊中有人 @所有人", key: \.mentionsAll)
                }.padding(.horizontal, 22)
                Text("普通群消息仍可在岛内查看。需要每条提醒的群，在下面单独设置。")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).padding(.horizontal, 22).padding(.bottom, 16)
                Divider().overlay(theme.subtleStroke)
                conversationsSection.padding(22)
            }.modifier(FeishuSettingsSurface())
            Label(model.muteError ?? "遵循飞书免打扰；只控制一切在岛的提醒，不修改飞书设置和已读状态。", systemImage: "moon")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func heading(_ title: String, trailing: String) -> some View {
        HStack { Text(title).font(.system(size: 18, weight: .semibold)); Spacer(); Text(trailing).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel) }
    }
    private func ruleRow(_ title: String, key: WritableKeyPath<FeishuReminderRules, Bool>) -> some View {
        HStack {
        Text(title)
        Spacer()
        Toggle(title, isOn: Binding(get: { store.rules[keyPath: key] }, set: { value in
            let before = store.rules; var next = before; next[keyPath: key] = value
            store.updateSettings(enabled: store.enabled, rules: next)
            if store.rules == next { remember("默认提醒已更新", undo: { store.updateSettings(enabled: store.enabled, rules: before) }) }
        })).labelsHidden().toggleStyle(.switch).disabled(!store.rulesConfigurationReadable).accessibilityLabel(title)
        }.frame(minHeight: 54)
    }
    private var conversationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("单独设置某个人或群").font(.system(size: 14, weight: .semibold))
            Text("已单独设置的会话优先展示，其余会话使用上方默认规则。").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryLabel)
                TextField("搜索联系人或群聊", text: $query).textFieldStyle(.plain)
                    .accessibilityIdentifier("unified.feishu.search")
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("清空搜索") }
                if model.loading { ProgressView().controlSize(.small) }
                else { Button { model.load(reset: true) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(theme.accent).disabled(!canReceive).accessibilityLabel("刷新会话") }
            }.padding(11).background(theme.subtleFill, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.subtleStroke))
            let items = model.items(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
            if items.isEmpty {
                Text(emptyDirectoryText).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel).padding(.vertical, 12)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                UnifiedConversationList(items: items, isExpanded: $expanded, previewCount: 3) { conversationRow($0) }
            }
            if let error = model.directoryError {
                HStack(alignment: .top) {
                    Text(error).font(.system(size: 12)).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("重试") { model.load(reset: true) }.buttonStyle(.link).disabled(model.loading)
                }
            }
            if model.more {
                HStack {
                    Text("当前搜索范围：已加载的\(model.conversations.count)个会话").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    Spacer()
                    Button(model.loading ? "正在加载…" : "查找更早的会话") { model.load(reset: false); expanded = true }
                        .buttonStyle(.link).disabled(model.loading).font(.system(size: 12))
                }
            }
        }
    }
    private var emptyDirectoryText: String {
        if model.loading { return "正在读取你的最近会话…" }
        if !store.canResumeSavedConnection { return "连接飞书后，会自动显示你的最近联系人和群聊。" }
        if !query.isEmpty { return model.more ? "已加载的会话中没有匹配项，可以继续查找更早的会话。" : "没有找到匹配的会话，试试其他名称。" }
        return model.directoryError == nil ? "暂时没有可显示的会话。" : "会话尚未加载成功，已有规则保持不变。"
    }
    private func conversationRow(_ target: FeishuRuleTarget) -> some View {
        let mode = store.conversationRules.first { $0.id == target.id }?.mode
        let person = FeishuSettingsRuleText.isPerson(target)
        let muted = model.isMuted(target) == true
        return HStack(spacing: 11) {
            Image(systemName: person ? "person" : "person.2").font(.system(size: 15)).foregroundStyle(theme.secondaryLabel)
                .frame(width: 32, height: 32).background(theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 4) {
                Text(target.name).font(.system(size: 13, weight: .medium)).lineLimit(2)
                Text(muted ? "飞书已免打扰，岛上不弹出提醒" : mode == nil ? "默认：" + FeishuSettingsRuleText.defaultSummary(target, rules: store.rules) : target.detail + " · 已单独设置")
                    .font(.system(size: 11)).foregroundStyle(muted ? theme.warning : theme.secondaryLabel).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                ForEach([("default", "跟随默认"), ("all", person ? "提醒新消息" : "每条都提醒"), ("mentions", "@我或@所有人"), ("quiet", "不提醒")].filter { !person || $0.0 != "mentions" || mode == .mentions }, id: \.0) { raw, title in
                    Button {
                let previous = store.customRules
                store.setConversation(target, mode: FeishuReminderMode(rawValue: raw))
                if store.customRules != previous { remember("会话提醒已更新", undo: { store.updateSettings(enabled: store.enabled, rules: store.rules, custom: previous) }) }
                    } label: { if (mode?.rawValue ?? "default") == raw { Label(title, systemImage: "checkmark") } else { Text(title) } }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(mode == nil ? "跟随默认" : mode == .quiet ? "不提醒" : mode == .mentions ? "@我或@所有人" : person ? "提醒新消息" : "每条都提醒")
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }.font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 7)
                    .background(theme.subtleFill, in: RoundedRectangle(cornerRadius: 7))
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .disabled(!store.rulesConfigurationReadable).accessibilityLabel("\(target.name)的提醒方式")
        }.padding(.vertical, 11).overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("消息怎样显示", trailing: "效果预览")
            VStack(alignment: .leading, spacing: 18) {
                Text("岛内消息 · 示例预览").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                islandPreview
                HStack(spacing: 15) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("同时显示桌面弹幕").font(.system(size: 14, weight: .medium))
                        Text("短消息从桌面划过，长消息分页显示。").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    }
                    Spacer()
                    Toggle("同时显示桌面弹幕", isOn: Binding(get: { store.danmu.enabled }, set: { value in
                        let before = store.danmu; var next = before; next.enabled = value; store.updateDanmu(next)
                        remember(value ? "已开启桌面弹幕" : "已关闭桌面弹幕", undo: { store.updateDanmu(before) })
                        if value { playPreview() } else { preview = false }
                    })).labelsHidden().toggleStyle(.switch).accessibilityLabel("同时显示桌面弹幕")
                        .accessibilityIdentifier("unified.feishu.danmuEnabled")
                }
                if store.danmu.enabled {
                    Divider()
                    if store.danmu.paused {
                        HStack { Text("桌面弹幕已暂停，样式调整仍会保存。").font(.system(size: 12)).foregroundStyle(theme.warning); Spacer()
                            Button("恢复弹幕") { var next = store.danmu; next.paused = false; store.updateDanmu(next) }.buttonStyle(.link) }
                    }
                    HStack {
                        Text("弹幕效果 · 只在下方预览").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        Spacer()
                        Button(preview ? "停止预览" : "重播") { if preview { preview = false } else { playPreview() } }.buttonStyle(.link)
                            .accessibilityIdentifier("unified.feishu.preview")
                    }
                    FeishuDanmuPreview(appearance: colorDraft ?? store.appearance, playing: colorDraft == nil && preview && !reduceMotion, started: previewStarted, onFinished: { preview = false })
                        .frame(height: 118).background(Color(red: 0.19, green: 0.24, blue: 0.23), in: RoundedRectangle(cornerRadius: 10))
                        .clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityLabel("合成弹幕预览")
                    HStack(spacing: 10) { styleChoice("none", "纯文字"); styleChoice("dark", "深色气泡"); styleChoice("light", "浅色气泡") }
                    HStack(spacing: 12) {
                        Text("字号").frame(width: 34, alignment: .leading); Text("小").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        Slider(value: number("fontSize", fallback: 28), in: 22...44, step: 1).accessibilityLabel("弹幕字号")
                        Text("大").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        Text("\(intValue("fontSize", fallback: 28)) pt").font(.system(size: 12)).monospacedDigit().frame(width: 45, alignment: .trailing)
                    }
                    HStack(spacing: 12) {
                        Text("速度").frame(width: 34, alignment: .leading); Text("慢").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        Slider(value: number("speed", fallback: 100), in: 40...240, step: 10).accessibilityLabel("弹幕速度")
                        Text("快").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        Text(intValue("speed", fallback: 100) < 80 ? "舒缓" : intValue("speed", fallback: 100) > 150 ? "轻快" : "适中").font(.system(size: 12)).frame(width: 45, alignment: .trailing)
                    }
                    Divider()
                    DisclosureGroup("自定义配色", isExpanded: $customColors) {
                        DanmuPaletteEditor(appearance: store.appearance, preview: { colorDraft = $0 }, apply: { value in
                            saveAppearance(value); colorDraft = nil
                        }).padding(.top, 12)
                            .onDisappear { colorDraft = nil }
                    }.font(.system(size: 13)).tint(theme.accent)
                    if let appearanceError { Text(appearanceError).font(.system(size: 12)).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true) }
                    if bubble == "custom" { Text("当前使用自定义配色。点击上方任一样式可以恢复预设。").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel) }
                }
            }.padding(22).modifier(FeishuSettingsSurface())
        }
    }
    private var islandPreview: some View {
        VStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Label("飞书消息", systemImage: "paperplane"); Spacer(); Text("现在") }.font(.system(size: 10)).foregroundStyle(theme.secondaryLabel)
                HStack(spacing: 10) {
                    Text("林").font(.system(size: 12)).frame(width: 30, height: 30).background(theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("小林").font(.system(size: 12, weight: .semibold))
                        Text("今天的方案已更新，有空帮我看看。").font(.system(size: 12))
                    }
                }
            }.padding(15).frame(maxWidth: 320).modifier(FeishuSettingsSurface())
                .shadow(color: theme.accent.opacity(0.08), radius: 10, y: 5)
            Text("示例消息 · 不会发送到飞书或桌面").font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
        }.padding(20).frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [theme.accent.opacity(0.10), theme.accent.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 10))
    }
    private func styleChoice(_ value: String, _ label: String) -> some View {
        Button { setBubble(value) } label: {
            VStack(spacing: 12) {
                Text("今天的方案已更新").font(.system(size: 11)).lineLimit(1)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .foregroundStyle(value == "dark" ? Color.white : value == "light" ? Color(skinHex: "#18202A") : theme.primaryLabel)
                    .background(value == "dark" ? Color(skinHex: "#15171C") : value == "light" ? Color.white : .clear, in: Capsule())
                Text(label).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }.frame(maxWidth: .infinity).frame(height: 86)
                .background(bubble == value ? theme.accent.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(bubble == value ? theme.accent : theme.subtleStroke, lineWidth: bubble == value ? 1.8 : 1))
                .overlay(alignment: .topTrailing) { if bubble == value { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent).font(.system(size: 12)).padding(6) } }
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityLabel(label).accessibilityAddTraits(bubble == value ? .isSelected : [])
    }
    private func intValue(_ key: String, fallback: Int) -> Int { (store.appearance[key] as? NSNumber)?.intValue ?? fallback }
    private func number(_ key: String, fallback: Double) -> Binding<Double> {
        Binding(get: { (store.appearance[key] as? NSNumber)?.doubleValue ?? fallback }, set: { value in
            clearFeedback(); saveAppearance([key: Int(value.rounded())], announce: false)
            if key == "speed" { playPreview() }
        })
    }
    private func setBubble(_ value: String) {
        colorDraft = nil; customColors = false
        let light = value == "light"
        saveAppearance(["bubble": value, "backgroundEnabled": value != "none", "borderEnabled": value != "none", "foreground": light ? "#18202A" : "#FFFFFF", "background": light ? "#FFFFFF" : "#15171C", "border": light ? "#D9DEE5" : "#414753"])
        playPreview()
    }
    private func saveAppearance(_ patch: [String: Any], announce: Bool = true) {
        let previous = store.appearance
        guard store.updateAppearance(previous.merging(patch) { _, new in new }) else {
            appearanceError = "配色对比度不足，尚未保存。请调整文字或背景颜色，让消息更容易看清。"; return
        }
        appearanceError = nil
        if announce { remember("弹幕样式已更新", undo: { _ = store.updateAppearance(previous) }) }
    }
    private func playPreview() { preview = true; previewStarted = Date() }
    private func remember(_ message: String, undo: @escaping () -> Void) { feedback = message; undoAction = undo; undoRevision = store.settingsRevision }
    private func clearFeedback() { feedback = nil; undoAction = nil; undoRevision = -1 }
}

struct FeishuSettingsSurface: ViewModifier {
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.background(scheme == .dark ? theme.subtleFill : Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.subtleStroke, lineWidth: 1))
    }
}

/// Keep even a large directory bounded inside the settings page; collapsing it
/// only changes presentation and never touches the saved conversation rules.
struct UnifiedConversationList<Row: View>: View {
    let items: [FeishuRuleTarget]
    @Binding var isExpanded: Bool
    var previewCount = 0
    @ViewBuilder let row: (FeishuRuleTarget) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isExpanded && previewCount > 0 {
                ForEach(Array(items.prefix(previewCount))) { row($0) }
            }
            if items.count > previewCount || isExpanded {
            Button { isExpanded.toggle() } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isExpanded ? "收起会话列表" : "查看全部\(items.count)个会话")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("\(items.count) 个会话").font(.system(size: 12)).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("unified.feishu.conversations.toggle")
            }
            if isExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { target in row(target) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: min(CGFloat(items.count) * 64, 256))
                .accessibilityIdentifier("unified.feishu.conversations.list")
            }
        }
    }
}
