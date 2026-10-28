import Foundation
import CryptoKit
import Darwin
import SQLite3

enum AgentReadError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case .unavailable(let message) = self { return message }; return nil }
}

enum WorkBuddyReader {
    static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".workbuddy")
    static func sessions(now: Double, root: URL = WorkBuddyReader.root, observedEvents: [AgentSession]? = nil) throws -> [AgentSession] {
        let events = observedEvents ?? (root == WorkBuddyReader.root ? AgentStatusConnection.sessions(provider: "workbuddy", now: now) : [])
        let accountURL = root.appendingPathComponent("storage/skeleton/account-snapshot.json")
        let raw = (try? Data(contentsOf: accountURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let uid = (raw?["primary"] as? [String: Any])?["uid"] as? String
        // Older clients lack the account snapshot. They may only refine sessions
        // already observed through a recent local Hook; never load arbitrary tasks.
        let observed = Dictionary(events.filter { now - $0.updatedAt < 900 && $0.updatedAt <= now + 60 }
            .map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        if uid == nil && observed.isEmpty { return events }
        var db: OpaquePointer?
        guard sqlite3_open_v2(root.appendingPathComponent("workbuddy.db").path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }
            if uid == nil { return events }
            throw AgentReadError.unavailable("请先打开并登录WorkBuddy。")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 300)
        var statement: OpaquePointer?
        let sql = uid != nil
            ? "SELECT id,status,updated_at FROM sessions WHERE deleted_at IS NULL AND user_id=? ORDER BY updated_at DESC LIMIT 100"
            : "SELECT id,status,updated_at FROM sessions WHERE deleted_at IS NULL AND updated_at>=? ORDER BY updated_at DESC LIMIT 100"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            if uid == nil { return events }
            throw AgentReadError.unavailable("WorkBuddy的任务格式已变化，需更新接入。")
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        if let uid { sqlite3_bind_text(statement, 1, uid, -1, transient) }
        else { sqlite3_bind_double(statement, 1, (now - 900) * 1000) }
        var result: [AgentSession] = []
        var hints: [String: WorkBuddyPendingTool.Hint] = [:]
        var historyBudget = 8
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idRaw = sqlite3_column_text(statement, 0), let stateRaw = sqlite3_column_text(statement, 1) else { continue }
            let id = String(cString: idRaw), value = String(cString: stateRaw).lowercased()
            let timestamp = sqlite3_column_double(statement, 2) / 1000
            let digest = AgentHookRecord.digest(id)
            if uid == nil && observed[digest] == nil { continue }
            var state: AgentState
            switch value {
            case "running", "in_progress", "working", "planning": state = .working
            case "completed": state = .completed
            case "error", "failed", "cancelled", "interrupted", "terminated": state = .failed
            case "waiting_for_input", "awaiting_input", "waiting_input", "waiting_user_input": state = .waiting
            case "waiting_for_approval", "waiting_for_permission": state = .waiting
            // WorkBuddy also uses pending for a brand-new, unstarted turn. Hooks disambiguate.
            case "pending", "waiting": state = .unknown
            default: continue
            }
            // The database is authoritative. Old rows remain historical and do not light up the island.
            var reason = state == .waiting ? (value.contains("permission") || value.contains("approval") ? "approval" : "input") : nil
            var attentionID = reason.map { _ in value }
            if historyBudget > 0, (state == .waiting || value == "pending" || value == "waiting"), now - timestamp < 900, timestamp <= now + 60 {
                historyBudget -= 1
                // pending also describes a new, unstarted task. The unresolved tool
                // and the client's awaiting-input state must agree. A newer Hook
                // resuming/finishing the task wins over a delayed database update.
                let nativePending = value == "pending" || value == "waiting"
                let newerEvent = observed[digest].map { $0.updatedAt > timestamp } ?? false
                if !newerEvent, let hint = WorkBuddyPendingTool.hint(sessionID: id, root: root, awaitingNativePermission: nativePending) {
                    state = .waiting; reason = hint.reason; attentionID = hint.id; hints[digest] = hint
                }
            }
            result.append(AgentSession(id: digest, state: state, updatedAt: timestamp, attentionID: attentionID, attentionReason: reason))
        }
        return AgentStatusConnection.merge(database: result, events: events, now: now).map { item in
            var item = item
            if item.state == .waiting, let hint = hints[item.id] { item.attentionReason = hint.reason; item.attentionID = hint.id }
            return item
        }
    }
    static func quotas(now: Double) throws -> [AgentQuota] {
        let client = try WorkBuddyIPC(discovery: root.appendingPathComponent("wbipc/endpoint.json"))
        let data = try client.resourceSummary()
        return try parseQuotas(data, now: now)
    }
    static func parseQuotas(_ data: [String: Any], now: Double) throws -> [AgentQuota] {
        func number(_ value: Any?) -> Double? { if let v = value as? Double { return v }; return (value as? String).flatMap(Double.init) }
        guard let left = number(data["TotalCredits"]), let groups = data["CreditGroups"] as? [[String: Any]],
              left.isFinite, left >= 0 else { throw AgentReadError.unavailable("WorkBuddy未返回可用积分数据。") }
        let capacities = groups.compactMap { number($0["CycleTotalCapacity"]) }
        guard capacities.count == groups.count, capacities.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw AgentReadError.unavailable("WorkBuddy积分数据不完整。") }
        let total = capacities.reduce(0, +)
        guard total > 0, left <= total else { throw AgentReadError.unavailable("WorkBuddy暂无可计算比例的积分额度。") }
        var quota = AgentQuota(id: "credits", label: "可用积分", remainingPercent: 100 * left / total, resetsAt: nil, updatedAt: now)
        quota.remainingUnits = left; quota.totalUnits = total
        return [quota]
    }
}

/// WorkBuddy 5.9's authenticated local IPC. Uses the client's own auth proxy, never its cloud token.
private final class WorkBuddyIPC {
    private let fd: Int32
    private var buffer = Data()
    private var requestID = 0
    init(discovery: URL) throws {
        guard FileManager.default.fileExists(atPath: discovery.path) else {
            throw AgentReadError.unavailable("当前WorkBuddy版本未提供本机积分接口；状态提醒仍可使用。")
        }
        var info = stat()
        guard lstat(discovery.path, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              info.st_mode & S_IFMT == S_IFREG,
              let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: discovery)) as? [String: Any],
              let endpoint = raw["endpoint"] as? String, let ticket = raw["ticket"] as? String,
              endpoint.utf8.count < 104, endpoint.hasPrefix("/"), ticket.count >= 32 else {
            throw AgentReadError.unavailable("请打开并登录WorkBuddy，再刷新额度。")
        }
        var socketInfo = stat()
        guard lstat(endpoint, &socketInfo) == 0, socketInfo.st_uid == getuid(), socketInfo.st_mode & S_IFMT == S_IFSOCK else {
            throw AgentReadError.unavailable("WorkBuddy本机连接不可用。")
        }
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentReadError.unavailable("无法连接WorkBuddy。") }
        var timeout = timeval(tv_sec: 8, tv_usec: 0), noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        do {
            var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            withUnsafeMutableBytes(of: &address.sun_path) { target in
                _ = endpoint.utf8CString.withUnsafeBytes { source in memcpy(target.baseAddress!, source.baseAddress!, source.count) }
            }
            let connected = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard connected == 0 else { throw AgentReadError.unavailable("WorkBuddy未运行，打开后即可读取积分。") }
            let nonce = UUID().uuidString
            let ticketID = SHA256.hash(data: Data(ticket.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16)
            try send(["type": "session_hello", "protocol_min": 1, "protocol_max": 1, "ticket_id": String(ticketID), "client_nonce": nonce,
                      "client": ["kind": "integration", "id": "youzi-island", "version": "0.5.1"]])
            let challenge = try read()
            guard challenge["type"] as? String == "session_challenge", let serverNonce = challenge["server_nonce"] as? String else { throw AgentReadError.unavailable("WorkBuddy拒绝了本机连接，请重新打开客户端。") }
            func proof(_ role: String) -> String {
                var transcript = Data()
                for value in [role, "1", endpoint, nonce, serverNonce] {
                    let bytes = Data(value.utf8); var length = UInt32(bytes.count).bigEndian
                    withUnsafeBytes(of: &length) { transcript.append(contentsOf: $0) }; transcript.append(bytes)
                }
                let signature = HMAC<SHA256>.authenticationCode(for: transcript, using: SymmetricKey(data: Data(ticket.utf8)))
                return Data(signature).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            }
            guard challenge["server_proof"] as? String == proof("wbipc-s") else { throw AgentReadError.unavailable("WorkBuddy连接身份校验失败。") }
            try send(["type": "session_prove", "client_proof": proof("wbipc-c")])
            guard try read()["type"] as? String == "session_hello_ack" else { throw AgentReadError.unavailable("WorkBuddy连接未授权。") }
        } catch { close(fd); throw error }
    }
    deinit { close(fd) }
    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object); data.append(10)
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), data.count - offset) }
            guard written > 0 else { throw AgentReadError.unavailable("WorkBuddy连接中断。") }; offset += written
        }
    }
    private func read() throws -> [String: Any] {
        while buffer.count < 1048576 {
            if let newline = buffer.firstIndex(of: 10) {
                let line = buffer[..<newline]; buffer.removeSubrange(...newline)
                guard let json = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { break }; return json
            }
            var chunk = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(fd, &chunk, chunk.count)
            guard count > 0 else { throw AgentReadError.unavailable("WorkBuddy读取超时，请稍后刷新。") }
            buffer.append(contentsOf: chunk.prefix(count))
        }
        throw AgentReadError.unavailable("WorkBuddy返回了无法识别的数据。")
    }
    private func request(_ method: String, params: [String: Any], mode: String? = nil) throws -> [String: Any] {
        requestID += 1
        var message: [String: Any] = ["jsonrpc": "2.0", "id": requestID, "method": method, "params": params]
        if let mode { message["mode"] = mode }; try send(message)
        let reply = try read()
        guard reply["id"] as? Int == requestID, reply["error"] == nil, let result = reply["result"] as? [String: Any] else { throw AgentReadError.unavailable("WorkBuddy暂未允许读取积分。") }
        return result
    }
    func resourceSummary() throws -> [String: Any] {
        let pipe = try request("broker/GetPipe", params: ["pipe": "wb.request"])
        guard let channel = pipe["channel"] as? String else { throw AgentReadError.unavailable("WorkBuddy积分接口不可用。") }
        let result = try request("\(channel)/http.fetch", params: ["method": "POST", "path": "/billing/meter/get-user-resource-summary", "headers": ["content-type": "application/json"], "body_b64": "e30="], mode: "call")
        guard result["status"] as? Int == 200, let encoded = result["body_b64"] as? String, let bytes = Data(base64Encoded: encoded),
              let response = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], response["code"] as? Int == 0,
              let data = response["data"] as? [String: Any] else { throw AgentReadError.unavailable("积分未能刷新，请确认WorkBuddy仍处于登录状态。") }
        return data
    }
}
