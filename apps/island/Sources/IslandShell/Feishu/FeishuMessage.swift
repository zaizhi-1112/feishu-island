import Foundation

public struct FeishuReminderRules: Codable, Equatable, Sendable {
    public var mentionsMe = true
    public var mentionsAll = true
    public var directMessages = true
    public var followedChats = true
    public init() {}
}

public enum FeishuReminderMode: String, Codable, Sendable {
    case all, mentions, quiet
}

public struct FeishuRuleTarget: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var detail: String
    public init(id: String, name: String, detail: String = "") {
        self.id = id; self.name = name; self.detail = detail
    }
}

public struct FeishuTargetRule: Codable, Equatable, Sendable, Identifiable {
    public var target: FeishuRuleTarget
    public var mode: FeishuReminderMode
    public var id: String { target.id }
    public init(target: FeishuRuleTarget, mode: FeishuReminderMode) { self.target = target; self.mode = mode }
}

public struct FeishuCustomRules: Codable, Equatable, Sendable {
    /// Both private and group conversations use the stable chat ID.
    public var conversations: [FeishuTargetRule] = []
    public var people: [FeishuTargetRule] = []
    public var groups: [FeishuTargetRule] = []
    public var blockedPeople: [FeishuRuleTarget] = []
    public var blockedGroups: [FeishuRuleTarget] = []
    public init() {}
    private enum CodingKeys: String, CodingKey { case conversations, people, groups, blockedPeople, blockedGroups }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        conversations = try c.decodeIfPresent([FeishuTargetRule].self, forKey: .conversations) ?? []
        people = try c.decodeIfPresent([FeishuTargetRule].self, forKey: .people) ?? []
        groups = try c.decodeIfPresent([FeishuTargetRule].self, forKey: .groups) ?? []
        blockedPeople = try c.decodeIfPresent([FeishuRuleTarget].self, forKey: .blockedPeople) ?? []
        blockedGroups = try c.decodeIfPresent([FeishuRuleTarget].self, forKey: .blockedGroups) ?? []
    }
    /// Old blocked targets become quiet rules; their notification preference is not lost.
    public mutating func consolidate(followed: Set<String>) {
        for target in blockedPeople {
            people.removeAll { $0.id == target.id }
            people.append(.init(target: target, mode: .quiet))
        }
        for target in blockedGroups {
            groups.removeAll { $0.id == target.id }
            conversations.removeAll { $0.id == target.id }
            conversations.append(.init(target: target, mode: .quiet))
        }
        blockedPeople.removeAll(); blockedGroups.removeAll()
        for item in groups where !conversations.contains(where: { $0.id == item.id }) { conversations.append(item) }
        groups.removeAll()
        for id in followed.sorted() where !conversations.contains(where: { $0.id == id }) && id.hasPrefix("oc_") {
            conversations.append(.init(target: .init(id: id, name: "原会话提醒", detail: "刷新会话列表后显示名称"), mode: .all))
        }
    }
    public func blocks(_ message: FeishuMessage) -> Bool {
        blockedGroups.contains { $0.id == message.chatID }
            || (!message.senderID.isEmpty && blockedPeople.contains { $0.id == message.senderID })
    }
    public var validationError: String? {
        let buckets = [(conversations.map(\.target), "oc_"), (people.map(\.target), "ou_"), (groups.map(\.target), "oc_"),
                       (blockedPeople, "ou_"), (blockedGroups, "oc_")]
        guard buckets.reduce(0, { $0 + $1.0.count }) <= 500 else { return "最多保存500项会话提醒设置。" }
        for (targets, prefix) in buckets {
            guard Set(targets.map(\.id)).count == targets.count else { return "同一对象存在重复规则。" }
            for target in targets {
                guard target.id.hasPrefix(prefix), target.id.count > prefix.count, target.id.count <= 128,
                      target.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }),
                      !target.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, target.name.count <= 120,
                      target.detail.count <= 200 else { return "联系人或群聊信息不完整，请重新从飞书选择。" }
            }
        }
        return nil
    }
}

public struct FeishuMessage: Identifiable, Equatable, Sendable {
    public let id: String
    public let chatID: String
    public let chatName: String
    public let chatKind: String
    public let senderName: String
    public let senderID: String
    public let text: String
    public let created: Date
    public let mentionsMe: Bool
    public let mentionsAll: Bool
    public var viewed = false
    public var remindAt: Date?
    public var reminded = false

    public init(raw: [String: Any], chatID: String, chatName: String, chatKind: String, ownID: String) {
        id = raw["message_id"] as? String ?? UUID().uuidString
        self.chatID = chatID; self.chatName = chatName; self.chatKind = chatKind
        let sender = raw["sender"] as? [String: Any] ?? [:]
        let senderType = sender["id_type"] as? String ?? "open_id"
        if let ids = sender["id"] as? [String: Any] { senderID = ids["open_id"] as? String ?? "" }
        else { senderID = senderType == "open_id" ? sender["id"] as? String ?? "" : "" }
        senderName = sender["sender_name"] as? String ?? (chatKind == "p2p" ? chatName : "群成员")
        created = accountMessageDate(raw["create_time"]) ?? Date()
        let mentions = raw["mentions"] as? [[String: Any]] ?? []
        mentionsMe = !ownID.isEmpty && mentions.contains {
            if let ids = $0["id"] as? [String: Any] { return ids["open_id"] as? String == ownID }
            return $0["id"] as? String == ownID && ($0["id_type"] as? String ?? "open_id") == "open_id"
        }
        let allToken = #"(?<![A-Za-z0-9_@])@_all(?![A-Za-z0-9_])"#
        var body = accountMessageText(raw)
        let structuredAll = mentions.contains { mention in
            if let ids = mention["id"] as? [String: Any] {
                return ["open_id", "user_id", "union_id"].contains { ids[$0] as? String == "all" }
            }
            return mention["id"] as? String == "all"
        }
        func hasAllTag(_ value: Any) -> Bool {
            if let rows = value as? [Any] { return rows.contains(where: hasAllTag) }
            guard let item = value as? [String: Any] else { return false }
            if item["tag"] as? String == "at", item["user_id"] as? String == "all" { return true }
            return item.values.contains(where: hasAllTag)
        }
        let contentString = (raw["body"] as? [String: Any])?["content"] as? String ?? ""
        let postContent = (raw["msg_type"] as? String == "post") ? contentString.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) } : nil
        // Feishu sometimes omits `mentions` for @all text messages. Match its exact API token.
        mentionsAll = structuredAll || postContent.map(hasAllTag) == true
            || body.range(of: allToken, options: .regularExpression) != nil
        body = body.replacingOccurrences(of: allToken, with: "@所有人", options: .regularExpression)
        for mention in mentions {
            if let key = mention["key"] as? String, !key.isEmpty, let name = mention["name"] as? String {
                body = body.replacingOccurrences(of: key, with: "@" + name)
            }
        }
        text = body
    }

    public func importanceReason(followed: Set<String>, rules: FeishuReminderRules = .init(), custom: FeishuCustomRules = .init()) -> String? {
        if custom.blocks(self) { return nil }
        if reminded || remindAt != nil { return "稍后" }
        let person = senderID.isEmpty ? nil : custom.people.first { $0.id == senderID }
        let group = custom.groups.first { $0.id == chatID }
        let conversation = custom.conversations.first { $0.id == chatID }
        // Explicit quiet rules prevent an old blocked target from being re-enabled.
        if person?.mode == .quiet || conversation?.mode == .quiet || group?.mode == .quiet { return nil }
        if let selected = conversation ?? person ?? group {
            switch selected.mode {
            case .all: return conversation != nil ? "会话提醒" : person != nil ? "联系人" : "群规则"
            case .mentions: return mentionsMe ? "@我" : mentionsAll ? "@所有人" : nil
            case .quiet: return nil
            }
        }
        if mentionsMe && rules.mentionsMe { return "@我" }
        if mentionsAll && rules.mentionsAll { return "@所有人" }
        if chatKind == "p2p" && rules.directMessages { return "私聊" }
        if followed.contains(chatID) && rules.followedChats { return "关注" }
        return nil
    }
    public func isImportant(followed: Set<String>, rules: FeishuReminderRules = .init(), custom: FeishuCustomRules = .init()) -> Bool {
        importanceReason(followed: followed, rules: rules, custom: custom) != nil
    }
    public var chatURL: URL? {
        guard chatID.hasPrefix("oc_"), chatID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { return nil }
        var components = URLComponents(string: "https://applink.feishu.cn/client/chat/open")!
        components.queryItems = [URLQueryItem(name: "chatId", value: chatID)]
        return components.url
    }
    public var source: String { chatKind == "p2p" ? senderName : chatName }
    var danmuText: String {
        let chat = chatName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sender = senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = chatKind == "p2p" || chat == sender || chat.isEmpty ? sender : sender.isEmpty ? chat : "\(chat) · \(sender)"
        return label.isEmpty ? text : "\(label)：\(text)"
    }
    public var reason: String { importanceReason(followed: [chatID]) ?? "关注" }
}
