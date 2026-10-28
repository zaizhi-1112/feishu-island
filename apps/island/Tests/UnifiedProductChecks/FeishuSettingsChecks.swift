import AppKit
import Foundation
import NookApp
import SwiftUI
@testable import IslandShell

@MainActor func runFeishuSettingsChecks(check: (Bool, String) -> Void, renderTo: URL?) async throws {
    func status(bound: Bool = true, enabled: Bool = true, readable: Bool = true, raw: String = "", checking: Bool = false, verified: Bool = false, failure: String? = nil) -> FeishuSettingsConnectionState {
        .resolve(bound: bound, enabled: enabled, readable: readable, status: raw, checking: checking, verified: verified, failure: failure)
    }
    check(status(bound: false, raw: "账号接收中").kind == .unconnected, "unsaved profile never inherits stale receiver success")
    check(status(raw: "连接配置已保存").kind == .checking, "saved configuration does not claim connectivity")
    check(status(raw: "账号接收中 · 42/42 个会话").kind == .receiving, "working receiver explicitly reports success")
    check(status(enabled: false, verified: false).title == "已停止接收新消息", "paused saved account does not invent authorization success")
    check(status(enabled: false, verified: true).title.contains("连接成功"), "verified paused account distinguishes connection from receiving")
    check(status(raw: "本机飞书账号尚未通过验证，请先完成本机CLI登录。").action == "重新授权", "invalid authorization has an actionable recovery")
    check(status(failure: "本机账号缺少所选用途的权限，请先授权：x").kind == .permission, "missing scopes distinct from network failure")
    check(status(failure: "本机CLI账号已变化，已停止读取。").action == "核对账号", "identity changes require verification")
    check(status(raw: "连接失败：飞书接口错误，请检查账号授权或网络").kind == .failed, "ambiguous failures are not falsely diagnosed as expired auth")
    check(status(raw: "接收异常，重试中 · 后台补读重试中").kind == .degraded, "partially failing receiver is not shown as healthy")
    check(status(readable: false, raw: "账号接收中").kind == .blocked, "corrupt preferences cannot be masked by previous success")

    let suite = "feishu-settings-check-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = LocalFeishuAccount(appID: "cli_fixture", openID: "ou_fixture", userName: "合成账号")
    let connection = FeishuConnection(cliPath: "/synthetic/never-run", profile: "fixture", localAccount: account)
    defaults.set(try JSONEncoder().encode(connection), forKey: "connection")
    defaults.set(false, forKey: "enabled")
    let store = FeishuStore(defaults: defaults, live: false, headlessRenderer: true)
    let personal = FeishuRuleTarget(id: "oc_person", name: "小林", detail: "私聊")
    let group = FeishuRuleTarget(id: "oc_group", name: "产品项目群", detail: "群聊")
    let muted = FeishuRuleTarget(id: "oc_muted", name: "工作通知群", detail: "群聊")
    store.setConversation(group, mode: .mentions)
    let original = store.customRules
    var rule = store.rules; rule.directMessages = false; rule.mentionsMe = true; rule.mentionsAll = false
    check(FeishuSettingsRuleText.defaultSummary(personal, rules: rule) == "仅@我时提醒", "private default describes the existing mention precedence")
    check(FeishuSettingsRuleText.defaultSummary(group, rules: rule) == "仅@我时提醒", "default summary updates with rule switches")
    let model = FeishuSettingsModel(store: store) { _, token, exclude in
        if exclude { return .init(items: token.isEmpty ? [personal] : [group], hasMore: token.isEmpty, pageToken: token.isEmpty ? "unmuted-next" : "") }
        return .init(items: [personal, group, muted], hasMore: false, pageToken: "")
    }
    func settle(_ model: FeishuSettingsModel) async throws {
        for _ in 0..<200 where model.loading { try await Task.sleep(for: .milliseconds(10)) }
        check(!model.loading, "directory request reaches final state")
    }
    model.load(reset: true); try await settle(model)
    check(model.items(query: "").first?.id == group.id, "explicit rules precede automatically loaded recent conversations")
    check(model.items(query: "小林").map(\.id) == [personal.id], "search matches conversation names")
    check(model.isMuted(group) == false && model.isMuted(muted) == true, "mute inference waits for every unmuted page")
    check(model.verified && model.connectionState.kind == .paused && !store.enabled, "read-only connection checks never enable paused receiving")
    check(store.customRules == original, "loading or checking preserves conversation preferences")
    let failedMute = FeishuSettingsModel(store: store) { _, _, excluded in
        if excluded { throw AccountFailure(detail: "Network") }
        return .init(items: [muted], hasMore: false, pageToken: "")
    }
    failedMute.load(reset: true); try await settle(failedMute)
    check(failedMute.isMuted(muted) == nil && failedMute.verified && failedMute.muteError != nil, "incomplete mute catalog never classifies every chat as muted")
    let repeating = FeishuSettingsModel(store: store) { _, token, excluded in
        .init(items: [group], hasMore: !excluded, pageToken: excluded ? "" : "repeated")
    }
    repeating.load(reset: true); try await settle(repeating)
    repeating.load(reset: false); try await settle(repeating)
    check(repeating.directoryError?.contains("未前进") == true, "pagination cycle produces a recoverable error")
    let slow = FeishuSettingsModel(store: store) { _, _, _ in
        try? await Task.sleep(for: .milliseconds(100))
        return .init(items: [personal], hasMore: false, pageToken: "")
    }
    slow.load(reset: true); slow.stop(); try await Task.sleep(for: .milliseconds(150))
    check(slow.conversations.isEmpty && !slow.verified && !slow.loading, "closed page ignores late read-only results")
    let expired = FeishuSettingsModel(store: store) { _, _, _ in throw AccountFailure(detail: "本机飞书账号尚未通过验证，请先完成本机CLI登录。") }
    expired.load(reset: true); try await settle(expired)
    check(expired.connectionState.action == "重新授权" && !expired.verified, "failed verification renders a real reauthorization action")

    let preview = FeishuDanmuPreviewView(frame: NSRect(x: 0, y: 0, width: 560, height: 118))
    var appearance = AppearanceMCP.defaults
    appearance["bubble"] = "light"; appearance["foreground"] = "#18202A"; appearance["background"] = "#FFFFFF"; appearance["border"] = "#D9DEE5"; appearance["fontSize"] = 36
    preview.configure(appearance, playing: false, started: Date())
    check(preview.text.backdrop && preview.text.fillColor?.usingColorSpace(.sRGB)?.redComponent == 1, "preview uses real desktop fill and renderer")
    check((preview.text.content.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 36, "preview uses the actual saved font size")
    check(preview.window == nil, "preview never opens a desktop overlay")
    preview.stop()

    if let output = renderTo {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let agents = AgentStore.shared
        for dark in [false, true] {
            let theme = NookResolvedTheme.resolve(theme: agents.selectedSkin.theme, preferences: .init(chromePalette: dark ? .dark : .light), effectiveColorScheme: dark ? .dark : .light, reduceTransparency: true)
            for width in [780.0, 576.0] {
                for (label, current) in [("connected-paused", model), ("authorization", expired), ("danmu", model)] {
                    store.updateDanmu(.init(enabled: label == "danmu"))
                    let root = UnifiedFeishuSettingsContent(store: store, model: current)
                        .padding(24).frame(width: width).environment(\.nookResolvedTheme, theme).tint(theme.accent)
                        .preferredColorScheme(dark ? .dark : .light)
                        .background(dark ? Color(skinHex: "#14251D") : Color(skinHex: "#F3F8F5"))
                    let view = NSHostingView(rootView: root)
                    let size = NSSize(width: width, height: 1650)
                    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua); window.contentView = view
                    view.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(150))
                    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(label)-\(Int(width))\(dark ? "-dark" : "").png"))
                    check(!window.isVisible && view.fittingSize.width <= width + 1, "new message settings fit desktop content width \(width)")
                    window.close()
                }
            }
        }
    }
}
