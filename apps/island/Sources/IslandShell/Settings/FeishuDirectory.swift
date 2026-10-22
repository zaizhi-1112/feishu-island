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
