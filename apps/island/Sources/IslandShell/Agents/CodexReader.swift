import Foundation

actor CodexReader {
    struct Cursor {
        var offset: UInt64 = 0
        var tail = Data()
        var session: AgentSession?
        var turnID: String?
    }
    private var cursors: [String: Cursor] = [:]
    private var lastDiscovery = Date.distantPast
    private var files: [URL] = []
    private let root: URL
    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")) { self.root = root }
    private let dateParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return formatter
    }()
    func sessions(now: Date) -> [AgentSession] {
        if now.timeIntervalSince(lastDiscovery) >= 10 {
            lastDiscovery = now
            var candidates: [(URL, Date)] = []
            // A resumed chat keeps its original date directory. Discover by modification time.
            if let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let file as URL in entries where file.pathExtension == "jsonl" {
                    guard let metadata = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                          metadata.isRegularFile == true, let modified = metadata.contentModificationDate,
                          now.timeIntervalSince(modified) < 172800 else { continue }
                    candidates.append((file, modified))
                }
            }
            files = candidates.sorted { $0.1 > $1.1 }.prefix(80).map { $0.0 }
            let paths = Set(files.map(\.path)); cursors = cursors.filter { paths.contains($0.key) }
        }
        for file in files {
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            var cursor = cursors[file.path] ?? Cursor()
            guard let size = try? handle.seekToEnd() else { continue }
            if size < cursor.offset { cursor = Cursor() }
            // Read only recent records on initial attachment; never infer a start from a running process.
            if size - cursor.offset > 4 * 1024 * 1024 {
                if cursor.session == nil { cursor = seedCursor(handle: handle, size: size, id: file.lastPathComponent) }
                cursor.offset = size - 4 * 1024 * 1024; cursor.tail = Data()
                try? handle.seek(toOffset: cursor.offset)
                if let bytes = try? handle.readToEnd(), let first = bytes.firstIndex(of: 10) {
                    cursor.tail = Data(bytes[bytes.index(after: first)...]); cursor.offset = size
                }
            } else {
                try? handle.seek(toOffset: cursor.offset)
                if let bytes = try? handle.readToEnd() { cursor.tail.append(bytes); cursor.offset = size }
            }
            while let newline = cursor.tail.firstIndex(of: 10) {
                let line = Data(cursor.tail[..<newline]); cursor.tail.removeSubrange(...newline)
                guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      record["type"] as? String == "event_msg", let payload = record["payload"] as? [String: Any],
                      let event = payload["type"] as? String, let stamp = record["timestamp"] as? String,
                      let time = dateParser.date(from: stamp)?.timeIntervalSince1970 else { continue }
                let turnID = payload["turn_id"] as? String
                if event == "task_started" {
                    cursor.turnID = turnID
                    cursor.session = AgentSession(id: file.lastPathComponent, state: .working, updatedAt: time)
                } else if ["task_complete", "turn_aborted"].contains(event) {
                    if let known = cursor.turnID, let turnID, known != turnID { continue }
                    cursor.session = AgentSession(id: file.lastPathComponent, state: event == "task_complete" ? .completed : .failed, updatedAt: time, completionID: event == "task_complete" ? (turnID ?? stamp) : nil)
                } else if cursor.session?.state == .working { cursor.session?.updatedAt = time }
            }
            cursors[file.path] = cursor
        }
        return cursors.values.compactMap(\.session)
    }
    private func seedCursor(handle: FileHandle, size: UInt64, id: String) -> Cursor {
        // Search backwards for an explicit lifecycle record; long turns can exceed the normal tail size.
        var end = size, carry = Data(), cursor = Cursor()
        var examined = 0
        while end > 0, examined < 128 * 1024 * 1024 {
            let start = end > 1048576 ? end - 1048576 : 0
            try? handle.seek(toOffset: start)
            guard let data = try? handle.read(upToCount: Int(end-start)) else { break }
            var chunk = data; chunk.append(carry); examined += data.count
            let lines = chunk.split(separator: 10, omittingEmptySubsequences: false)
            carry = start > 0 ? Data(lines.first ?? Data.SubSequence()) : Data()
            for line in (start > 0 ? Array(lines.dropFirst()) : Array(lines)).reversed() {
                guard line.range(of: Data("\"event_msg\"".utf8)) != nil,
                      let value = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any], value["type"] as? String == "event_msg",
                      let event = value["payload"] as? [String: Any], let type = event["type"] as? String,
                      ["task_started", "task_complete", "turn_aborted"].contains(type),
                      let stamp = value["timestamp"] as? String, let date = dateParser.date(from: stamp) else { continue }
                cursor.turnID = event["turn_id"] as? String
                cursor.session = AgentSession(id: id, state: type == "task_started" ? .working : type == "task_complete" ? .completed : .failed, updatedAt: date.timeIntervalSince1970, completionID: type == "task_complete" ? (cursor.turnID ?? stamp) : nil)
                return cursor
            }
            end = start
        }
        return cursor
    }
    nonisolated static func executable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", "/Applications/Codex.app/Contents/Resources/codex"].first(where: FileManager.default.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }
    nonisolated static func parseQuotas(_ result: [String: Any], now: Double) -> [AgentQuota] {
        let buckets = result["rateLimitsByLimitId"] as? [String: [String: Any]]
            ?? (result["rateLimits"] as? [String: Any]).map { ["codex": $0] } ?? [:]
        return buckets.sorted(by: { $0.key < $1.key }).flatMap { key, value in
            ["primary", "secondary"].compactMap { slot -> AgentQuota? in
                guard let window = value[slot] as? [String: Any], let used = window["usedPercent"] as? Double,
                      used.isFinite, (0...100).contains(used) else { return nil }
                let minutes = window["windowDurationMins"] as? Double
                let prefix = buckets.count > 1 ? "\(value["limitName"] as? String ?? key) · " : ""
                return AgentQuota(id: "\(key)/\(slot)", label: prefix + AgentBridge.quotaLabel(minutes: minutes), remainingPercent: 100-used, resetsAt: window["resetsAt"] as? Double, updatedAt: now)
            }
        }
    }
    nonisolated static func quotas() async throws -> [AgentQuota] {
        guard let executable = executable() else { throw AgentReadError.unavailable("未找到Codex，请先安装并登录。") }
        let result = try await CodexQuotaRequest(executable: executable).run()
        return parseQuotas(result, now: Date().timeIntervalSince1970)
    }
}

/// Only initialize and account/rateLimits/read are sent. No task or model call is created.
private final class CodexQuotaRequest: @unchecked Sendable {
    let process = Process(), input = Pipe(), output = Pipe()
    let queue = DispatchQueue(label: "island.codex.quota")
    var continuation: CheckedContinuation<[String: Any], Error>?
    var buffer = Data()
    init(executable: URL) { process.executableURL = executable }
    func run() async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                self.continuation = continuation
                self.process.arguments = ["app-server", "--listen", "stdio://"]
                self.process.standardInput = self.input; self.process.standardOutput = self.output; self.process.standardError = FileHandle.nullDevice
                self.output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                    let data = handle.availableData
                    self?.queue.async { self?.receive(data) }
                }
                do {
                    try self.process.run()
                    try self.send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "youzi_island", "version": "0.5.1"]]])
                    self.queue.asyncAfter(deadline: .now() + 12) { self.finish(.failure(AgentReadError.unavailable("Codex额度读取超时，请确认已登录并联网。"))) }
                } catch { self.finish(.failure(AgentReadError.unavailable("Codex暂时无法启动额度查询。"))) }
            }
        }
    }
    func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object); data.append(10); try input.fileHandleForWriting.write(contentsOf: data)
    }
    func receive(_ data: Data) {
        guard continuation != nil else { return }
        guard !data.isEmpty else { finish(.failure(AgentReadError.unavailable("Codex额度查询已断开。"))); return }
        buffer.append(data)
        guard buffer.count <= 1048576 else { finish(.failure(AgentReadError.unavailable("Codex返回的数据过大。"))); return }
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
            guard let response = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = response["id"] as? Int else { continue }
            if response["error"] != nil { finish(.failure(AgentReadError.unavailable("无法读取Codex额度，请确认使用ChatGPT账号登录。"))); return }
            do {
                if id == 1 {
                    try send(["method": "initialized", "params": [:]])
                    try send(["id": 2, "method": "account/rateLimits/read"])
                } else if id == 2, let result = response["result"] as? [String: Any] { finish(.success(result)); return }
            } catch { finish(.failure(error)); return }
        }
    }
    func finish(_ result: Result<[String: Any], Error>) {
        guard let continuation else { return }; self.continuation = nil
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        let process = process
        queue.asyncAfter(deadline: .now() + 2) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        continuation.resume(with: result)
    }
}
