import Foundation
import SwiftUI

/// Presentation only. A saved profile is never evidence of a working connection.
struct FeishuSettingsConnectionState: Equatable {
    enum Kind { case unconnected, checking, receiving, paused, authorization, permission, identity, failed, degraded, blocked }
    let kind: Kind
    let title: String
    let detail: String
    var action: String {
        switch kind {
        case .unconnected: "连接飞书"
        case .authorization, .permission: "重新授权"
        case .identity: "核对账号"
        case .failed, .degraded: "重试连接"
        case .checking: "正在检测…"
        case .receiving, .paused: "检测连接"
        case .blocked: "查看详情"
        }
    }
    var warning: Bool { [.authorization, .permission, .identity, .failed, .degraded, .blocked].contains(kind) }
    static func resolve(bound: Bool, enabled: Bool, readable: Bool, status: String, checking: Bool,
                        verified: Bool, failure: String?) -> Self {
        if !readable { return .init(kind: .blocked, title: "消息设置需要检查", detail: "原消息规则无法读取，接收已暂停。原设置已保留。") }
        if !bound { return .init(kind: .unconnected, title: "尚未连接飞书", detail: "连接后，在岛上接收与你有关的新消息。") }
        if checking { return .init(kind: .checking, title: "正在检测飞书连接…", detail: "正在核对账号授权与会话读取，不会更改消息已读状态。") }
        let reason = failure ?? status
        if reason.contains("账号已变化") { return .init(kind: .identity, title: "账号发生变化 · 接收已暂停", detail: "请核对要使用的账号，原账号的提醒设置会保留。") }
        if reason.contains("缺少所选用途") || reason.contains("缺少消息") {
            return .init(kind: .permission, title: "授权不完整 · 无法接收消息", detail: "请完成消息读取授权，已有提醒规则会保留。")
        }
        if ["未授权", "授权已过期", "授权已失效", "尚未通过验证", "先完成本机CLI登录"].contains(where: reason.contains) {
            return .init(kind: .authorization, title: "账号授权需要更新", detail: "请重新授权飞书，完成后继续使用已有提醒设置。")
        }
        if failure != nil { return .init(kind: .failed, title: "连接检测未通过", detail: "暂时无法确认消息连接，请重试；仍有问题可重新授权。") }
        if !enabled {
            return verified
                ? .init(kind: .paused, title: "连接成功 · 已停止接收新消息", detail: "账号授权与会话读取正常。打开接收开关即可恢复。")
                : .init(kind: .paused, title: "已停止接收新消息", detail: "账号配置与提醒规则已保留，点击“检测连接”核对授权。")
        }
        if status.hasPrefix("账号接收中") {
            return .init(kind: .receiving, title: "连接成功 · 正在接收消息", detail: "已完成账号授权，消息接收正常。")
        }
        if status.hasPrefix("接收异常") || status.hasPrefix("快查暂缓") {
            return .init(kind: .degraded, title: "消息接收暂时异常 · 正在重试", detail: "部分消息可能延迟，可重试连接或查看详情。")
        }
        if status.contains("失败") || status.contains("异常") || status.contains("旧弹幕") {
            return .init(kind: .failed, title: "暂时无法接收消息", detail: "请重试连接；如果授权已失效，可以重新授权。")
        }
        return .init(kind: .checking, title: "正在连接飞书…", detail: verified ? "账号授权与会话读取已通过，正在等待消息接收就绪。" : "正在核对连接，已有设置保持不变。")
    }
}

enum FeishuSettingsRuleText {
    static func isPerson(_ target: FeishuRuleTarget) -> Bool { target.detail == "私聊" || target.id.hasPrefix("ou_") }
    static func defaultSummary(_ target: FeishuRuleTarget, rules: FeishuReminderRules) -> String {
        // @ rules also apply to private messages in the existing receiver.
        if isPerson(target), rules.directMessages { return "私聊会提醒" }
        switch (rules.mentionsMe, rules.mentionsAll) {
        case (true, true): return "@我或@所有人时提醒"
        case (true, false): return "仅@我时提醒"
        case (false, true): return "仅@所有人时提醒"
        default: return "不提醒"
        }
    }
}

@MainActor final class FeishuSettingsModel: ObservableObject {
    typealias Fetch = (FeishuConnection, String, Bool) async throws -> FeishuDirectoryPage
    @Published private(set) var conversations: [FeishuRuleTarget] = []
    @Published private(set) var more = false
    @Published private(set) var loading = false
    @Published private(set) var checking = false
    @Published private(set) var verified = false
    @Published private(set) var failure: String?
    @Published private(set) var directoryError: String?
    @Published private(set) var muteError: String?
    @Published private(set) var unmutedIDs: Set<String>?
    @Published private(set) var checkedAt: Date?
    private var pageToken = ""
    private var visitedPages = Set<String>()
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private let fetch: Fetch
    private let allowsSyntheticLookup: Bool
    let store: FeishuStore

    init(store: FeishuStore, fetch: Fetch? = nil) {
        self.store = store
        allowsSyntheticLookup = fetch != nil
        self.fetch = fetch ?? { connection, token, excluding in
            try await FeishuDirectory(connection: connection).conversations(pageToken: token, excludeMuted: excluding)
        }
    }
    var connectionState: FeishuSettingsConnectionState {
        .resolve(bound: store.canResumeSavedConnection, enabled: store.enabled, readable: store.rulesConfigurationReadable,
                 status: store.status, checking: checking, verified: verified || store.status.hasPrefix("账号接收中"), failure: failure)
    }
    func items(query: String) -> [FeishuRuleTarget] {
        var seen = Set<String>()
        let names = Dictionary(conversations.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        return (store.conversationRules.map(\.target) + conversations)
            .filter { seen.insert($0.id).inserted }.map { names[$0.id] ?? $0 }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }
    func isMuted(_ target: FeishuRuleTarget) -> Bool? {
        guard conversations.contains(where: { $0.id == target.id }), let unmutedIDs else { return nil }
        return !unmutedIDs.contains(target.id)
    }
    func receiverChanged() {
        if store.status.hasPrefix("账号接收中") { verified = true; failure = nil }
    }
    func connectionChanged() {
        stop(); conversations = []; pageToken = ""; visitedPages = []; more = false
        verified = false; failure = nil; directoryError = nil; muteError = nil; unmutedIDs = nil; checkedAt = nil
        load(reset: true)
    }
    func stop() { generation = UUID(); task?.cancel(); task = nil; loading = false; checking = false }
    func load(reset: Bool, retryReceiver: Bool = false) {
        guard !loading, (store.allowsDirectoryLookup || allowsSyntheticLookup), store.canResumeSavedConnection else { return }
        if retryReceiver && store.enabled { store.reconnect() }
        let epoch = UUID(), connection = store.connection, token = reset ? "" : pageToken
        generation = epoch; loading = true; checking = reset; directoryError = nil
        if reset { failure = nil; muteError = nil; unmutedIDs = nil }
        task = Task {
            do {
                let page = try await fetch(connection, token, false)
                guard current(epoch, connection) else { return }
                if page.hasMore && (page.pageToken.isEmpty || page.pageToken == token || !reset && visitedPages.contains(page.pageToken)) {
                    throw AccountFailure(detail: "会话列表分页未前进，请刷新后重试。")
                }
                var ids = Set<String>()
                conversations = Array(((reset ? [] : conversations) + page.items).filter { ids.insert($0.id).inserted }.prefix(5000))
                pageToken = page.pageToken; more = page.hasMore && conversations.count < 5000
                if reset { visitedPages = [] }; visitedPages.insert(page.pageToken)
                verified = true; failure = nil; checkedAt = Date(); checking = false
                // chat-list does not provide per-row mute metadata. Only infer a
                // muted chat after a complete exclude-muted catalog was obtained.
                if reset {
                    do {
                        var unmuted = Set<String>(), next = "", visited = Set<String>()
                        repeat {
                            let p = try await fetch(connection, next, true)
                            guard current(epoch, connection) else { return }
                            unmuted.formUnion(p.items.map(\.id))
                            if !p.hasMore { break }
                            guard !p.pageToken.isEmpty, visited.insert(p.pageToken).inserted, visited.count < 50 else {
                                throw AccountFailure(detail: "免打扰状态未完整返回，稍后可刷新。")
                            }
                            next = p.pageToken
                        } while true
                        unmutedIDs = unmuted
                    } catch {
                        guard current(epoch, connection) else { return }
                        muteError = "免打扰状态暂未更新，实际提醒仍遵循飞书设置。"
                    }
                }
            } catch {
                guard current(epoch, connection) else { return }
                let reason = (error as? AccountFailure)?.detail ?? "会话加载失败，请检查连接后重试。"
                directoryError = reason
                if reset { failure = reason; verified = false }
            }
            if current(epoch, connection) { loading = false; checking = false }
        }
    }
    private func current(_ epoch: UUID, _ connection: FeishuConnection) -> Bool {
        !Task.isCancelled && generation == epoch && store.connection == connection
    }
}
