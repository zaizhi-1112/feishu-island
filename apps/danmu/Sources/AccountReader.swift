import Foundation

struct AccountChat {
    let id: String
    let name: String
    let kind: String
    let muted: Bool
}
struct AccountFailure: Error { let detail: String }

// Each start owns separate progress. Late workers from a stopped session cannot
// mutate a new session, even while a subprocess is finishing cancellation.
private final class AccountSession {
    let token: Int
    let started: Date
    let ownID: String
    let lock = NSLock()
    var checkpoints: [String: Date] = [:]
    var seen: [String: [String: Date]] = [:]
    var inFlight = Set<String>()
    var windows: [String: Date] = [:]
    var catalogCount = 0
    var selectedCount = 0
    var backgroundFailed = false
    var unreadUnavailable = false
    init(token: Int, ownID: String, started: Date) { self.token = token; self.ownID = ownID; self.started = started }
}

// Official CLI owns credentials. Raw GET avoids shortcut thread/media enrichment
// and preserves the server's millisecond create_time for actual latency measurement.
final class AccountReader {
    var onMessage: ((String, Bool, Date?) -> Void)?
    var onIdentifiedMessage: ((String, Bool, Date?, String) -> Void)?
    var onStatus: ((String) -> Void)?
    private(set) var enabled = false
    private let worker = DispatchQueue(label: "feishu.account.fast")
    private let background = DispatchQueue(label: "feishu.account.backfill", qos: .utility)
    private let lock = NSLock()
    private var generation = 0
    private var processes: [UUID: Process] = [:]
    private var gray: [String] = []
    private var hidden: [String] = []
    private let cli: URL
    private var pollDelay: TimeInterval
    private let pageDelay: TimeInterval
    private let concurrency: Int
    private let catalogInterval: TimeInterval
    private let requestTimeout: TimeInterval
    private let clock: ServerClock
    private let requestSlots = DispatchSemaphore(value: 3)
    func currentTime() -> Date { clock.now() }
    func checkUnread(_ id: String, completion: @escaping (Bool?) -> Void) {
        lock.lock(); let token = generation; lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async {
            var unread: Bool?
            do {
                let states = try self.data(["im", "+messages-read-status", "--message-ids", id], token)
                if let item = (states["items"] as? [[String: Any]])?.first(where: { $0["message_id"] as? String == id }), let read = item["is_read"] as? Bool { unread = !read }
                else { unread = false }
            } catch { unread = nil }
            self.post(token) { completion(unread) }
        }
    }
    init(cli: URL? = nil, pollDelay: TimeInterval = 1, pageDelay: TimeInterval = 0.15, concurrency: Int = 3, catalogInterval: TimeInterval = 60, requestTimeout: TimeInterval = 8, clock: ServerClock = ServerClock()) {
        self.cli = cli ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/lark-cli")
        self.pollDelay = pollDelay; self.pageDelay = pageDelay
        self.concurrency = max(2, concurrency); self.catalogInterval = catalogInterval
        self.requestTimeout = requestTimeout; self.clock = clock
    }
    func setPollDelay(_ delay: TimeInterval) { lock.lock(); pollDelay = max(0.5, delay); lock.unlock() }
    func setRules(gray: [String], hidden: [String]) {
        lock.lock(); self.gray = gray; self.hidden = hidden; lock.unlock()
    }
    private func rules() -> ([String], [String]) { lock.lock(); defer { lock.unlock() }; return (gray, hidden) }
    private func alive(_ token: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return generation == token }
    private func post(_ token: Int, _ action: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in guard self?.alive(token) == true else { return }; action() }
    }
    func start() {
        guard !enabled else { return }
        enabled = true
        lock.lock(); generation += 1; let token = generation; lock.unlock()
        onStatus?("正在连接飞书账号…")
        worker.async { [weak self] in
            guard let self else { return }
            do {
                let auth = try self.call(["auth", "status", "--json"], token)
                guard let identities = auth["identities"] as? [String: Any], let user = identities["user"] as? [String: Any], user["available"] as? Bool == true, let id = user["openId"] as? String else { throw AccountFailure(detail: "账号未授权，请重新连接") }
                try self.clock.refreshIfNeeded()
                guard self.alive(token) else { return }
                let session = AccountSession(token: token, ownID: id, started: self.clock.now())
                self.background.async { self.backfill(session) }
                self.cycle(session)
            } catch {
                self.post(token) { self.onStatus?("连接失败：\(self.reason(error)) · 5 秒后重连") }
                self.worker.asyncAfter(deadline: .now() + 5) {
                    self.post(token) { self.enabled = false; self.start() }
                }
            }
        }
    }
    func stop() {
        enabled = false
        lock.lock(); generation += 1; let running = Array(processes.values); lock.unlock()
        for p in running where p.isRunning { p.terminate() }
        onStatus?("账号接收已停止")
    }
    private func reason(_ error: Error) -> String { (error as? AccountFailure)?.detail ?? "本机连接异常" }
    private func call(_ args: [String], _ token: Int) throws -> [String: Any] {
        requestSlots.wait(); defer { requestSlots.signal() }
        guard alive(token) else { throw AccountFailure(detail: "接收已停止") }
        let p = Process(); p.executableURL = cli
        p.arguments = ["--profile", "feishu-danmu"] + args
        var env = ProcessInfo.processInfo.environment
        env["LARKSUITE_CLI_NO_UPDATE_NOTIFIER"] = "1"; env["LARKSUITE_CLI_NO_SKILLS_NOTIFIER"] = "1"
        p.environment = env; p.standardInput = FileHandle.nullDevice
        let pipe = Pipe(); let errors = Pipe(); p.standardOutput = pipe; p.standardError = errors
        // Foundation Process retains Pipe handles after exit. Close all parent
        // descriptors explicitly; polling otherwise exhausts the GUI process.
        defer {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
            try? errors.fileHandleForReading.close()
            try? errors.fileHandleForWriting.close()
        }
        let errorGroup = DispatchGroup()
        var errorBytes = Data()
        let processID = UUID()
        lock.lock()
        guard generation == token else { lock.unlock(); throw AccountFailure(detail: "接收已停止") }
        processes[processID] = p
        do { try p.run(); lock.unlock() } catch { processes[processID] = nil; lock.unlock(); throw error }
        defer { lock.lock(); processes[processID] = nil; lock.unlock() }
        errorGroup.enter()
        DispatchQueue.global().async { errorBytes = errors.fileHandleForReading.readDataToEndOfFile(); errorGroup.leave() }
        let timeout = DispatchWorkItem {
            if p.isRunning {
                p.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if p.isRunning { kill(p.processIdentifier, SIGKILL) }
                }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + requestTimeout, execute: timeout)
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); timeout.cancel(); errorGroup.wait()
        guard alive(token) else { throw AccountFailure(detail: "接收已停止") }
        let payload = bytes.isEmpty ? errorBytes : bytes
        guard let result = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { throw AccountFailure(detail: "接口未有效返回（退出码 \(p.terminationStatus)，返回 \(payload.count) 字节）") }
        if p.terminationStatus != 0 || result["ok"] as? Bool == false {
            let error = result["error"] as? [String: Any] ?? [:]
            let code = (error["code"] as? NSNumber)?.stringValue ?? "未知"
            throw AccountFailure(detail: "飞书接口错误 \(code)，请检查账号授权或网络")
        }
        return result
    }
    private func data(_ args: [String], _ token: Int) throws -> [String: Any] {
        let result = try call(args + ["--as", "user", "--format", "json"], token)
        guard result["identity"] as? String == "user", let body = result["data"] as? [String: Any] else { throw AccountFailure(detail: "账号身份或接口结构异常") }
        return body
    }
    private func chats(_ token: Int, excludeMuted: Bool, full: Bool) throws -> [[String: Any]] {
        var args = ["im", "+chat-list", "--types=p2p,group", "--sort", "active_time", "--page-size", full ? "100" : "12"]
        if full { args += ["--page-all", "--page-limit", "1000"] }
        if excludeMuted { args.append("--exclude-muted") }
        let result = try data(args, token)
        guard (!full || result["has_more"] as? Bool != true), let chats = result["chats"] as? [[String: Any]] else { throw AccountFailure(detail: "会话列表未完整返回") }
        return chats
    }
    private func catalog(_ rows: [[String: Any]], unmuted: Set<String>) -> [AccountChat] {
        var ids = Set<String>()
        return rows.compactMap { row in
            guard let id = row["chat_id"] as? String, let kind = row["chat_mode"] as? String,
                  ["p2p", "group", "topic"].contains(kind), ids.insert(id).inserted else { return nil }
            return AccountChat(id: id, name: row["name"] as? String ?? "飞书会话", kind: kind, muted: !unmuted.contains(id))
        }
    }
    private func allowed(_ chat: AccountChat) -> Bool {
        let (gray, hidden) = rules()
        return !hidden.contains { chat.name.localizedCaseInsensitiveContains($0) } && (!chat.muted || gray.contains { chat.name.localizedCaseInsensitiveContains($0) })
    }
    // Foreground discovery never waits for the full catalog or backfill worker.
    private func cycle(_ session: AccountSession) {
        guard alive(session.token) else { return }
        let began = ProcessInfo.processInfo.systemUptime
        var retryDelay: TimeInterval = 0
        do {
            try clock.refreshIfNeeded()
            let unmuted = try chats(session.token, excludeMuted: true, full: false)
            let allowedIDs = Set(unmuted.compactMap { $0["chat_id"] as? String })
            // Only fetch muted candidates when a gray exception actually needs them.
            let rows = rules().0.isEmpty ? unmuted : try chats(session.token, excludeMuted: false, full: false)
            let selected = catalog(rows, unmuted: allowedIDs).filter { allowed($0) }
            let group = DispatchGroup(); let slots = DispatchSemaphore(value: concurrency - 1)
            let failureLock = NSLock(); var failed = 0
            for chat in selected.prefix(6) {
                guard alive(session.token) else { break }
                slots.wait(); group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    defer { slots.signal(); group.leave() }
                    do { try self.receive(chat, session, fast: true) }
                    catch { failureLock.lock(); failed += 1; failureLock.unlock() }
                }
            }
            group.wait()
            guard alive(session.token) else { return }
            session.lock.lock(); let count = session.selectedCount; let total = session.catalogCount; let backFailed = session.backgroundFailed; let unknownRead = session.unreadUnavailable; session.lock.unlock()
            if failed > 0 { retryDelay = 5 }
            let scope = total == 0 ? "会话发现中" : "\(count)/\(total) 个会话"
            let suffix = (failed > 0 ? " · \(failed) 个快查读取失败，将重试" : backFailed ? " · 后台补读重试中" : "") + (unknownRead ? " · 部分消息未读状态不可用，已跳过" : "")
            let seconds = ProcessInfo.processInfo.systemUptime - began
            let correction = abs(clock.offset) >= 2 ? String(format:" · 时间校准 %+.0f 秒",clock.offset) : ""
            let state = failed > 0 || backFailed ? "接收异常，重试中" : "账号接收中"
            post(session.token) { self.onStatus?("\(state) · \(scope) · 快查 \(String(format:"%.1f",seconds)) 秒\(correction)\(suffix)") }
        } catch { retryDelay = 5; post(session.token) { self.onStatus?("快查暂缓：\(self.reason(error)) · 自动重试中") } }
        guard alive(session.token) else { return }
        lock.lock(); let delay = max(pollDelay, retryDelay); lock.unlock()
        worker.asyncAfter(deadline: .now() + delay) { [weak self] in self?.cycle(session) }
    }
    private func backfill(_ session: AccountSession) {
        var list: [AccountChat] = []; var cursor = 0; var refreshed = -Double.infinity
        while alive(session.token) {
            do {
                if ProcessInfo.processInfo.systemUptime - refreshed >= catalogInterval {
                    let rows = try chats(session.token, excludeMuted: false, full: true)
                    let ids = Set(try chats(session.token, excludeMuted: true, full: true).compactMap { $0["chat_id"] as? String })
                    list = catalog(rows, unmuted: ids); refreshed = ProcessInfo.processInfo.systemUptime
                    session.lock.lock(); session.catalogCount = list.count; session.selectedCount = list.filter { allowed($0) }.count; session.lock.unlock()
                }
                if !list.isEmpty {
                    let chat = list[cursor % list.count]; cursor += 1
                    if allowed(chat) { try receive(chat, session) }
                    else { session.lock.lock(); session.checkpoints[chat.id] = clock.now(); session.lock.unlock() }
                }
                session.lock.lock(); session.backgroundFailed = false; session.lock.unlock()
                Thread.sleep(forTimeInterval: max(pageDelay, list.isEmpty ? 1 : 0))
            } catch {
                session.lock.lock(); session.backgroundFailed = true; session.lock.unlock()
                // A slow or rate-limited backfill never holds the quick-check queue.
                for _ in 0..<50 { if !alive(session.token) { return }; Thread.sleep(forTimeInterval:0.1) }
            }
        }
    }
    private func receive(_ chat: AccountChat, _ session: AccountSession, fast: Bool = false) throws {
        guard alive(session.token), allowed(chat) else { return }
        session.lock.lock()
        let flightKey = chat.id + (fast ? ":fast" : ":background")
        guard session.inFlight.insert(flightKey).inserted else { session.lock.unlock(); return }
        let checkpoint = session.checkpoints[chat.id] ?? session.started
        let start = max(session.started, checkpoint.addingTimeInterval(-120))
        session.windows[flightKey] = start
        session.lock.unlock()
        defer { session.lock.lock(); session.inFlight.remove(flightKey); session.windows.removeValue(forKey: flightKey); session.lock.unlock() }
        try clock.refreshIfNeeded()
        let end = clock.now()
        // Allow late API visibility without replaying pre-start history. IDs dedupe.
        var pageToken: String?; var pageCount = 0
        repeat {
            var params = ["container_id_type":"chat", "container_id":chat.id,
                          "start_time":String(Int(start.timeIntervalSince1970)), "end_time":String(Int(end.timeIntervalSince1970)),
                          "sort_type":"ByCreateTimeDesc", "page_size":"50", "with_sender_name":"true", "only_thread_root_messages":"false"]
            if let cursor = pageToken { params["page_token"] = cursor }
            let json = String(data: try JSONSerialization.data(withJSONObject:params),encoding:.utf8)!
            let result = try data(["api", "GET", "/open-apis/im/v1/messages", "--params", json], session.token)
            guard let messages = result["items"] as? [[String: Any]] else { throw AccountFailure(detail:"消息结构异常") }
            session.lock.lock()
            // An older concurrent page can still return previously seen IDs.
            // Keep its replay range until that request has fully completed.
            let retainedFrom = session.windows.filter { $0.key.hasPrefix(chat.id + ":") }.values.min() ?? start
            session.seen[chat.id] = (session.seen[chat.id] ?? [:]).filter { $0.value >= retainedFrom }
            let known = session.seen[chat.id] ?? [:]
            session.lock.unlock()
            let candidates = messages.reversed().filter { message in
                guard let id = message["message_id"] as? String, known[id] == nil,
                      message["deleted"] as? Bool != true,
                      (message["sender"] as? [String: Any])?["id"] as? String != session.ownID,
                      let created = accountMessageDate(message["create_time"]), created >= session.started else { return false }
                return true
            }
            let ids = candidates.compactMap { $0["message_id"] as? String }
            var unread = Set<String>()
            if !ids.isEmpty {
                let states = try data(["im", "+messages-read-status", "--message-ids", ids.joined(separator: ",")], session.token)
                guard let items = states["items"] as? [[String: Any]] else { throw AccountFailure(detail:"未读状态无法确认，暂停该批消息") }
                if items.count < ids.count { session.lock.lock(); session.unreadUnavailable = true; session.lock.unlock() }
                unread = Set(items.compactMap { item in
                    guard item["is_read"] as? Bool == false else { return nil }
                    return item["message_id"] as? String
                })
            }
            for message in candidates {
                guard let id = message["message_id"] as? String else { continue }
                let created = accountMessageDate(message["create_time"])
                if let created, created < session.started { continue }
                session.lock.lock()
                let isNew = session.seen[chat.id]?[id] == nil
                if isNew { session.seen[chat.id, default: [:]][id] = created ?? end }
                session.lock.unlock()
                guard isNew, unread.contains(id) else { continue }
                let sender = message["sender"] as? [String: Any] ?? [:]
                guard sender["id"] as? String != session.ownID else { continue }
                let name = sender["sender_name"] as? String ?? "飞书消息"
                let text = accountMessageText(message)
                let title = chat.kind != "p2p" ? "\(chat.name) · \(name)" : name
                let gray = chat.muted || rules().0.contains { chat.name.localizedCaseInsensitiveContains($0) }
                post(session.token) {
                    guard self.allowed(chat) else { return }
                    self.onMessage?("\(title)：\(text)", gray, created)
                    self.onIdentifiedMessage?("\(title)：\(text)", gray, created, id)
                }
            }
            if result["has_more"] as? Bool == true {
                guard let next = result["page_token"] as? String, !next.isEmpty, next != pageToken else { throw AccountFailure(detail:"消息分页异常") }
                pageToken = next
            } else { pageToken = nil }
            pageCount += 1
            // Limit catch-up work on the hot path. The independent backfill
            // finishes remaining pages; do not advance the checkpoint here.
            if fast && pageCount >= 2 && pageToken != nil { return }
            if pageCount >= 1000 && pageToken != nil { throw AccountFailure(detail:"消息补读尚未完成") }
        } while pageToken != nil
        session.lock.lock(); session.checkpoints[chat.id] = max(session.checkpoints[chat.id] ?? session.started, end); session.lock.unlock()
    }
}

func accountMessageDate(_ value: Any?) -> Date? {
    if let value = value as? String, let number = Double(value) { return Date(timeIntervalSince1970: number > 100_000_000_000 ? number / 1000 : number) }
    if let number = value as? NSNumber { let v = number.doubleValue; return Date(timeIntervalSince1970:v > 100_000_000_000 ? v / 1000 : v) }
    return nil
}
func accountMessageText(_ message: [String: Any]) -> String {
    let kind = message["msg_type"] as? String ?? "消息"
    let body = message["body"] as? [String: Any] ?? [:]
    guard let raw = body["content"] as? String, let bytes = raw.data(using:.utf8),
          let content = try? JSONSerialization.jsonObject(with:bytes) as? [String: Any] else { return "[\(kind)]" }
    if kind == "text" { return content["text"] as? String ?? "[文字]" }
    if kind == "post" {
        let localized = content["zh_cn"] as? [String: Any] ?? content["en_us"] as? [String: Any] ?? content
        let title = localized["title"] as? String ?? ""
        let rows = localized["content"] as? [[[String: Any]]] ?? []
        let lines = rows.map { row in row.map { element -> String in
            if let text = element["text"] as? String { return text }
            switch element["tag"] as? String {
            case "at": return "@" + (element["user_name"] as? String ?? "成员")
            case "img": return "[图片]"
            case "media": return "[视频]"
            default: return ""
            }
        }.joined() }
        return ([title] + lines).filter { !$0.isEmpty }.joined(separator:" ")
    }
    if kind == "interactive" {
        // Preserve inline card copy without fetching linked content/resources.
        func copy(_ value: Any) -> [String] {
            if let list = value as? [Any] { return list.flatMap { copy($0) } }
            guard let object = value as? [String: Any] else { return [] }
            var parts: [String] = []
            for key in ["header", "title", "text", "content", "elements", "fields", "columns", "items", "body"] {
                guard let value = object[key] else { continue }
                if let text = value as? String, !text.isEmpty { parts.append(text) }
                else { parts += copy(value) }
            }
            return parts
        }
        let parts = copy(content)
        if !parts.isEmpty { return parts.joined(separator:" ") }
    }
    let labels = ["image":"图片", "file":"文件", "audio":"语音", "media":"视频", "video":"视频", "sticker":"表情", "interactive":"卡片", "merge_forward":"合并转发", "share_chat":"分享会话", "share_user":"分享联系人"]
    let label = labels[kind] ?? kind
    if let name = content["file_name"] as? String { return "[\(label)] \(name)" }
    // No additional API expansion on the hot path; avoid raw JSON/resource keys.
    return "[\(label)]"
}
