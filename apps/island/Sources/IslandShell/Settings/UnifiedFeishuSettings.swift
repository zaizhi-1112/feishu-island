import AppKit
import NookApp
import SwiftUI

/// One vertical native page, backed by the same receiver as the island.
/// The containing settings window owns scrolling and navigation.
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

private struct UnifiedFeishuSettingsContent: View {
    @ObservedObject var store: FeishuStore
    @State private var query = ""
    @State private var conversations: [FeishuRuleTarget] = []
    @State private var pageToken = ""
    @State private var more = false
    @State private var loading = false
    @State private var directoryError: String?
    @State private var appearanceError: String?
    @State private var requestGeneration = UUID()
    @State private var preview = false
    @State private var previewStarted = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var items: [FeishuRuleTarget] {
        var result = store.conversationRules.map(\.target)
        var ids = Set(result.map(\.id))
        result += conversations.filter { ids.insert($0.id).inserted }
        let names = Dictionary(conversations.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        return result.map { names[$0.id] ?? $0 }.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            section("连接飞书", subtitle: "首次完成本人授权，之后启动自动恢复。消息内容只在本机内存中停留。") {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: store.enabled ? "checkmark.circle.fill" : "paperplane.circle")
                        .font(.system(size: 28)).foregroundStyle(store.enabled ? Color.green : Color.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.enabled ? store.account : "连接你的飞书").font(.system(size: 16, weight: .semibold))
                        Text(store.status).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if store.connecting {
                        Button("暂停连接") { store.cancelConnection() }
                    } else {
                        Button(store.enabled ? "管理授权" : "连接飞书") { store.beginCompanyConnection() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if let hint = store.connectionHint { Text(hint).font(.system(size: 12)).foregroundStyle(.secondary) }
                if store.hasSavedConnection {
                    Button("更换账号…") { store.requestCompanyAccountSwitch() }
                        .buttonStyle(.link).font(.system(size: 12)).disabled(store.connecting || !store.rulesConfigurationReadable)
                }
                Toggle("接收新的飞书消息", isOn: Binding(get: { store.enabled }, set: { value in
                    if value && !store.canResumeSavedConnection { store.beginCompanyConnection() }
                    else if value != store.enabled { store.toggleReceiving() }
                })).toggleStyle(.switch).disabled(store.connecting)
                Text("保留飞书免打扰与未读校验，不修改已读状态，不读取启动前的历史消息。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            section("默认提醒", subtitle: "没有单独设置的会话使用下面的规则。") {
                Toggle("私聊消息", isOn: rule(\.directMessages)).toggleStyle(.switch)
                Toggle("有人 @我", isOn: rule(\.mentionsMe)).toggleStyle(.switch)
                Toggle("有人 @所有人", isOn: rule(\.mentionsAll)).toggleStyle(.switch)
                Text("普通群消息会保留在最近消息中；需要每条提醒的群，可在下面单独设置。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            section("会话管理", subtitle: "私聊和群聊在同一处管理；单独设置的会话优先显示。") {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索已加载的联系人或群聊", text: $query).textFieldStyle(.plain)
                    Button(loading ? "正在加载…" : "刷新会话") { loadConversations(reset: true) }
                        .disabled(loading || !store.allowsDirectoryLookup || !store.hasSavedConnection)
                }.padding(10).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                if let error = directoryError { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
                if items.isEmpty {
                    Text(query.isEmpty ? "点击刷新会话，从你最近的私聊和群聊中选择。" : "当前已加载的会话中没有匹配项，可继续加载更早的会话。")
                        .font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 12)
                } else {
                    ForEach(items) { target in conversationRow(target) }
                }
                if more {
                    Button(loading ? "正在加载…" : "加载更多会话") { loadConversations(reset: false) }.disabled(loading)
                }
                Text("“静音”仅停止本应用提醒；“跟随默认”会移除该会话的单独设置。飞书中的免打扰始终优先。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            section("桌面弹幕", subtitle: "灵动岛始终保留完整消息，桌面弹幕只展示短消息。") {
                Toggle("同时显示桌面弹幕", isOn: Binding(get: { store.danmu.enabled }, set: { value in
                    var next = store.danmu; next.enabled = value; store.updateDanmu(next)
                })).toggleStyle(.switch)
                HStack {
                    Text("字号")
                    Slider(value: number("fontSize", fallback: 28), in: 22...44, step: 1)
                    Text("\(intValue("fontSize", fallback: 28)) pt").monospacedDigit().frame(width: 54, alignment: .trailing)
                }
                HStack {
                    Text("速度")
                    Slider(value: number("speed", fallback: 100), in: 40...240, step: 10)
                    Text("\(intValue("speed", fallback: 100)) pt/s").monospacedDigit().frame(width: 70, alignment: .trailing)
                }
                HStack(alignment: .center) {
                    Picker("气泡皮肤", selection: Binding(get: { store.appearance["bubble"] as? String ?? "none" }, set: setBubble)) {
                        Text("纯文字").tag("none"); Text("墨色气泡").tag("dark"); Text("浅色气泡").tag("light"); Text("自选配色").tag("custom")
                    }.frame(maxWidth: 340)
                    Spacer()
                    ColorPicker("文字", selection: colorBinding("foreground", fallback: foreground), supportsOpacity: false)
                        .fixedSize()
                }
                if store.appearance["bubble"] as? String == "custom" {
                    HStack {
                        ColorPicker("气泡底色", selection: colorBinding("background", fallback: background), supportsOpacity: false)
                        Spacer()
                        ColorPicker("气泡边线", selection: colorBinding("border", fallback: background), supportsOpacity: false)
                    }
                }
                if let error = appearanceError { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
                previewSurface
                HStack {
                    Text("合成消息预览 · 只在这里播放").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button(preview ? "停止预览" : "播放预览") { previewStarted = Date(); preview.toggle() }
                }
            }
            if let error = store.actionError { Text(error).foregroundStyle(.orange).font(.system(size: 12)) }
        }
        .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("unified.feishu.settings")
        .onChange(of: store.connection) { _, _ in requestGeneration = UUID(); conversations = []; pageToken = ""; more = false; loading = false }
        .onDisappear { preview = false; requestGeneration = UUID(); loading = false }
        .task(id: preview) {
            if preview { try? await Task.sleep(for: .seconds(12)); if !Task.isCancelled { preview = false } }
        }
    }
    private func section<Content: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            content()
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.07), lineWidth: 0.7))
    }
    private func conversationRow(_ target: FeishuRuleTarget) -> some View {
        HStack(spacing: 10) {
            Image(systemName: target.detail == "私聊" || target.id.hasPrefix("ou_") ? "person.crop.circle" : "person.2.circle")
                .font(.system(size: 23)).foregroundStyle(.secondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(target.name).font(.system(size: 13, weight: .medium)).lineLimit(2)
                if !target.detail.isEmpty { Text(target.detail).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            Picker("提醒方式", selection: Binding(get: {
                store.conversationRules.first { $0.id == target.id }?.mode.rawValue ?? "default"
            }, set: { store.setConversation(target, mode: FeishuReminderMode(rawValue: $0)) })) {
                Text("跟随默认").tag("default")
                Text("每条提醒").tag("all")
                Text("仅 @ 时提醒").tag("mentions")
                Text("静音").tag("quiet")
            }.labelsHidden().frame(width: 138).accessibilityLabel("\(target.name)的提醒方式")
        }.padding(.vertical, 6)
    }
    private func rule(_ key: WritableKeyPath<FeishuReminderRules, Bool>) -> Binding<Bool> {
        Binding(get: { store.rules[keyPath: key] }, set: { value in
            var next = store.rules; next[keyPath: key] = value; store.updateSettings(enabled: store.enabled, rules: next)
        })
    }
    private func loadConversations(reset: Bool) {
        guard !loading, store.allowsDirectoryLookup else { return }
        loading = true; directoryError = nil
        let generation = UUID(); requestGeneration = generation
        let connection = store.connection, token = reset ? "" : pageToken
        Task {
            do {
                let page = try await FeishuDirectory(connection: connection).conversations(pageToken: token)
                guard requestGeneration == generation, store.connection == connection else { return }
                if !reset, page.hasMore, page.pageToken == token { throw AccountFailure(detail: "会话列表分页未前进，请重新刷新。") }
                let combined = (reset ? [] : conversations) + page.items
                var ids = Set<String>()
                conversations = Array(combined.filter { ids.insert($0.id).inserted }.prefix(5000))
                pageToken = page.pageToken; more = page.hasMore && conversations.count < 5000
            } catch {
                if requestGeneration == generation { directoryError = (error as? AccountFailure)?.detail ?? "会话加载失败，请检查连接后重试。" }
            }
            if requestGeneration == generation { loading = false }
        }
    }
    private func intValue(_ key: String, fallback: Int) -> Int { (store.appearance[key] as? NSNumber)?.intValue ?? fallback }
    private func number(_ key: String, fallback: Double) -> Binding<Double> {
        Binding(get: { (store.appearance[key] as? NSNumber)?.doubleValue ?? fallback }, set: { saveAppearance([key: Int($0.rounded())]) })
    }
    private func setBubble(_ value: String) {
        let light = value == "light"
        saveAppearance(["bubble": value, "foreground": light ? "#18202A" : "#FFFFFF", "background": light ? "#FFFFFF" : "#15171C", "border": light ? "#D9DEE5" : "#414753"])
    }
    private func saveAppearance(_ patch: [String: Any]) {
        appearanceError = store.updateAppearance(store.appearance.merging(patch) { _, new in new }) ? nil : "这个配色对比度不足，请让文字与背景更容易区分。"
    }
    private func color(_ key: String, fallback: Color) -> Color {
        guard let hex = store.appearance[key] as? String, let value = UInt32(hex.dropFirst(), radix: 16) else { return fallback }
        return Color(red: Double((value >> 16) & 255)/255, green: Double((value >> 8) & 255)/255, blue: Double(value & 255)/255)
    }
    private var foreground: Color { color("foreground", fallback: .white) }
    private var background: Color { color("background", fallback: Color(red: 0.08, green: 0.09, blue: 0.11)) }
    private func colorBinding(_ key: String, fallback: Color) -> Binding<Color> {
        Binding(get: { color(key, fallback: fallback) }, set: { value in
            guard let rgb = NSColor(value).usingColorSpace(.sRGB) else { return }
            let hex = String(format: "#%02X%02X%02X", Int((rgb.redComponent*255).rounded()), Int((rgb.greenComponent*255).rounded()), Int((rgb.blueComponent*255).rounded()))
            var patch: [String: Any] = [key: hex]
            if key == "foreground", store.appearance["background"] is NSNull { patch["background"] = "#15171C" }
            if key == "background", store.appearance["foreground"] is NSNull { patch["foreground"] = "#FFFFFF" }
            saveAppearance(patch)
        })
    }
    private var previewSurface: some View {
        TimelineView(.animation(minimumInterval: 1.0/30, paused: !preview || reduceMotion)) { context in
            GeometryReader { geometry in
                let size = CGFloat(intValue("fontSize", fallback: 28))
                let text = "飞书 · 新消息到了，继续专注。"
                let width = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium)]).width + 28
                let span = geometry.size.width + width
                let travel = CGFloat(context.date.timeIntervalSince(previewStarted)) * CGFloat(intValue("speed", fallback: 100))
                let offset = preview && !reduceMotion ? geometry.size.width - travel.truncatingRemainder(dividingBy: max(1, span)) : 16
                let bubble = store.appearance["bubble"] as? String ?? "none"
                Text(text).font(.system(size: size, weight: .medium)).fixedSize().foregroundStyle(foreground)
                    .shadow(color: bubble == "none" ? .black : .clear, radius: 1, x: 0, y: 1)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(bubble == "none" ? Color.clear : background, in: RoundedRectangle(cornerRadius: CGFloat(intValue("corner", fallback: 12))))
                    .offset(x: offset, y: (geometry.size.height-size-24)/2)
            }
        }.frame(height: 96).background(Color(red: 0.15, green: 0.19, blue: 0.24), in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel("合成弹幕预览")
    }
}
