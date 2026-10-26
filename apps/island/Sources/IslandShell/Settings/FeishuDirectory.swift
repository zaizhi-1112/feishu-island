import Foundation

struct FeishuDirectoryPage: Sendable {
    let items: [FeishuRuleTarget]
    let hasMore: Bool
    let pageToken: String
}

/// On-demand, read-only lookup. Credentials stay owned by the existing CLI.
final class FeishuDirectory: @unchecked Sendable {
    private let cli: URL
    private let profile: String
    private let queue = DispatchQueue(label: "island.settings.directory", qos: .userInitiated, attributes: .concurrent)
    private let slots = DispatchSemaphore(value: 2)
    init(connection: FeishuConnection = .init()) { self.cli = URL(fileURLWithPath: connection.cliPath); self.profile = connection.profile }

    func search(kind: String, query: String, pageToken: String) async throws -> FeishuDirectoryPage {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard self.slots.wait(timeout: .now() + 1) == .success else { throw AccountFailure(detail: "正在查询飞书，请稍后重试。") }
                    defer { self.slots.signal() }
                    var args: [String]
                    if kind == "people" {
                        if self.profile == CompanyConnection.profile { throw AccountFailure(detail:"公司消息连接未申请通讯录搜索权限；请按会话名称设置规则。") }
                        args = ["contact", "+search-user", "--page-size", "30"]
                        args += query.isEmpty ? ["--has-chatted"] : ["--query", query]
                    } else if query.isEmpty {
                        args = ["im", "+chat-list", "--types=group", "--sort", "active_time", "--page-size", "50"]
                    } else {
                        args = ["im", "+chat-search", "--query", query, "--disable-search-by-user",
                                "--search-types", "private,public_joined,external", "--page-size", "50"]
                    }
                    if kind == "groups", !pageToken.isEmpty { args += ["--page-token", pageToken] }
                    let data = try self.call(args + ["--as", "user", "--format", "json"])
                    let key = kind == "people" ? "users" : "chats"
                    guard let rows = data[key] as? [[String: Any]] else { throw AccountFailure(detail: "飞书返回的列表格式不完整，请重试。") }
                    var seen = Set<String>()
                    let items = rows.compactMap { row -> FeishuRuleTarget? in
                        let id = row[kind == "people" ? "open_id" : "chat_id"] as? String ?? ""
                        guard id.hasPrefix(kind == "people" ? "ou_" : "oc_"), seen.insert(id).inserted else { return nil }
                        if kind == "groups", let status = row["chat_status"] as? String, status != "normal" { return nil }
                        let name = row[kind == "people" ? "localized_name" : "name"] as? String ?? ""
                        let external = row[kind == "people" ? "is_cross_tenant" : "external"] as? Bool == true
                        let detail = kind == "people" ? (row["department"] as? String ?? "") : (external ? "外部群聊" : "飞书群聊")
                        return FeishuRuleTarget(id: id, name: String((name.isEmpty ? "未命名" : name).prefix(120)),
                                                detail: String((detail.isEmpty && external ? "外部联系人" : detail).prefix(200)))
                    }
                    let more = data["has_more"] as? Bool ?? false
                    let next = data["page_token"] as? String ?? ""
                    if kind == "groups", more && next.isEmpty { throw AccountFailure(detail: "飞书没有返回下一页信息，请缩小群名查询范围。") }
                    continuation.resume(returning: FeishuDirectoryPage(items: items, hasMore: more, pageToken: next))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    /// Private chats and groups share one picker and one stable chat-ID rule model.
    /// This uses only the already granted chat-list permission, not the directory API.
    func conversations(pageToken: String = "") async throws -> FeishuDirectoryPage {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard self.slots.wait(timeout: .now() + 1) == .success else { throw AccountFailure(detail: "会话列表正在加载，请稍候。") }
                    defer { self.slots.signal() }
                    var args = ["im", "+chat-list", "--types=p2p,group", "--sort", "active_time", "--page-size", "100"]
                    if !pageToken.isEmpty { args += ["--page-token", pageToken] }
                    let data = try self.call(args + ["--as", "user", "--format", "json"])
                    continuation.resume(returning: try Self.conversationPage(data))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    static func conversationPage(_ data: [String: Any]) throws -> FeishuDirectoryPage {
        guard let rows = data["chats"] as? [[String: Any]] else { throw AccountFailure(detail: "飞书返回的会话列表不完整。") }
        var seen = Set<String>()
        let items = rows.compactMap { row -> FeishuRuleTarget? in
            guard let id = row["chat_id"] as? String, id.hasPrefix("oc_"), id.count > 3,
                  id.count <= 128, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }),
                  let kind = row["chat_mode"] as? String, ["p2p", "group", "topic"].contains(kind),
                  seen.insert(id).inserted else { return nil }
            let name = String((row["name"] as? String ?? "未命名会话").prefix(120))
            return .init(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名会话" : name,
                         detail: kind == "p2p" ? "私聊" : kind == "topic" ? "话题群" : "群聊")
        }
        let more = data["has_more"] as? Bool ?? false, next = data["page_token"] as? String ?? ""
        guard !more || !next.isEmpty else { throw AccountFailure(detail: "飞书没有返回下一页信息，请稍后重试。") }
        return FeishuDirectoryPage(items: items, hasMore: more, pageToken: next)
    }
    private func call(_ args: [String]) throws -> [String: Any] {
        let company = profile == CompanyConnection.profile
        let credential = company ? try CompanyConnection.shared.credential(.receive) : nil
        let process = Process(); process.executableURL = cli; process.arguments = (profile.isEmpty || company ? [] : ["--profile",profile]) + args
        var env = credential?.environment(ProcessInfo.processInfo.environment) ?? ProcessInfo.processInfo.environment
        env["LARKSUITE_CLI_NO_UPDATE_NOTIFIER"] = "1"; env["LARKSUITE_CLI_NO_SKILLS_NOTIFIER"] = "1"
        process.environment = FeishuTransport.shared.environment(env); process.standardInput = FileHandle.nullDevice
        // Both streams are JSON for CLI success/failure. A single pipe also avoids stderr backpressure.
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        defer { try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
        do { try process.run() } catch { throw AccountFailure(detail: "未找到可用的飞书连接工具，请检查本机lark-cli。") }
        let timeout = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: timeout)
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); timeout.cancel()
        guard let envelope = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw AccountFailure(detail: "飞书查询未完成，请检查连接后重试。")
        }
        guard process.terminationStatus == 0, envelope["ok"] as? Bool == true, envelope["identity"] as? String == "user",
              let data = envelope["data"] as? [String: Any] else {
            let error = envelope["error"] as? [String: Any] ?? [:]
            let code = (error["code"] as? NSNumber)?.stringValue ?? "未知"
            throw AccountFailure(detail: "飞书查询失败（\(code)），请检查当前账号的读取授权或网络。")
        }
        return data
    }
}
