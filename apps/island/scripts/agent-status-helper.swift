import Foundation
import Darwin

@main struct PassiveAgentStatus {
    static func privateDirectory(_ url: URL) throws {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFDIR else { throw Failure.invalid }
        } else { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    static func safeFile(_ url: URL) throws {
        var info = stat()
        if lstat(url.path, &info) == 0 { guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { throw Failure.invalid } }
    }
    static func write(_ data: Data, to url: URL) throws {
        try safeFile(url)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    enum Failure: Error { case invalid }
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3, ["claude", "workbuddy"].contains(args[2]) else { exit(1) }
        let provider = args[2]
        do {
            // Test roots are accepted only through explicit CLI arguments, never inherited env.
            let testRoot = args.count == 5 && args[3] == "--test-root" ? URL(fileURLWithPath: args[4]) : nil
            if args[1] == "--install" {
                let home = testRoot ?? FileManager.default.homeDirectoryForCurrentUser
                let directory = home.appendingPathComponent(provider == "claude" ? ".claude" : ".workbuddy")
                try privateDirectory(directory)
                let settings = directory.appendingPathComponent("settings.json")
                try safeFile(settings)
                let data = try? Data(contentsOf: settings)
                var object: [String: Any] = [:]
                if let data { guard data.count < 4194304, let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.invalid }; object = parsed }
                guard object["hooks"] == nil || object["hooks"] is [String: Any] else { throw Failure.invalid }
                var hooks = object["hooks"] as? [String: Any] ?? [:]
                let executable = URL(fileURLWithPath: args[0]).standardizedFileURL.path
                let command = "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "' --record " + provider
                for event in ["UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "PostToolUseFailure", "Notification", "Elicitation", "ElicitationResult", "Stop", "StopFailure", "SessionEnd"] {
                    guard hooks[event] == nil || hooks[event] is [[String: Any]] else { throw Failure.invalid }
                    var entries = hooks[event] as? [[String: Any]] ?? []
                    // Preserve every existing user hook. Replace only this executable's own entry.
                    entries = entries.compactMap { entry in
                        guard let commands = entry["hooks"] as? [[String: Any]] else { return entry }
                        let kept = commands.filter { ($0["command"] as? String) != command }
                        guard !kept.isEmpty else { return nil }
                        var copy = entry; copy["hooks"] = kept; return copy
                    }
                    var entry: [String: Any] = ["hooks": [["type": "command", "command": command]]]
                    if ["PreToolUse", "PostToolUse", "PostToolUseFailure"].contains(event) { entry["matcher"] = ".*" }
                    if event == "Notification" { entry["matcher"] = "permission_prompt|elicitation_dialog|agent_needs_input|elicitation_complete|elicitation_response" }
                    entries.append(entry); hooks[event] = entries
                }
                object["hooks"] = hooks
                let result = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
                if data != result {
                    let backup = home.appendingPathComponent("Library/Application Support/FeishuIsland/AgentStatus/config-backups")
                    try privateDirectory(backup)
                    if let data { try write(data, to: backup.appendingPathComponent(provider + "-" + UUID().uuidString + ".json")) }
                    // Refuse to overwrite a concurrent settings edit.
                    guard (try? Data(contentsOf: settings)) == data else { throw Failure.invalid }
                    try write(result, to: settings)
                }
            } else if args[1] == "--record" {
                // Passive observers must never stall an interactive tool or ask for a decision.
                signal(SIGALRM) { _ in _exit(0) }; alarm(1)
                if testRoot == nil {
                    let policyURL = AgentHookFiles.root.appendingPathComponent("policy.json")
                    try safeFile(policyURL)
                    guard let data = try? Data(contentsOf: policyURL), data.count < 4096,
                          let policy = try? JSONDecoder().decode(AgentHookPolicy.self, from: data),
                          policy.enabled, policy.visibleIDs.contains(provider) else { return }
                }
                // Parse once, discard all content. No stdout, stderr, decisions or network I/O.
                var input = Data()
                let deadline = Date().addingTimeInterval(0.35)
                while input.count <= 1048576, Date() < deadline {
                    var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
                    guard poll(&descriptor, 1, 50) > 0 else { continue }
                    var buffer = [UInt8](repeating: 0, count: 16384)
                    let count = read(STDIN_FILENO, &buffer, buffer.count)
                    guard count > 0 else { break }
                    input.append(contentsOf: buffer.prefix(count))
                    if (try? JSONSerialization.jsonObject(with: input)) != nil { break }
                }
                guard input.count <= 1048576, let object = try JSONSerialization.jsonObject(with: input) as? [String: Any], let session = object["session_id"] as? String, !session.isEmpty, session.utf8.count <= 256 else { return }
                let root = testRoot ?? AgentHookFiles.root
                try privateDirectory(root)
                let folder = root.appendingPathComponent(provider); try privateDirectory(folder)
                let id = AgentHookRecord.digest(session), file = folder.appendingPathComponent(id + ".json")
                let lock = folder.appendingPathComponent(id + ".lock"); try safeFile(lock)
                let fd = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
                guard fd >= 0 else { return }; defer { close(fd) }
                guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return }; defer { flock(fd, LOCK_UN) }
                try safeFile(file)
                let old = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(AgentHookRecord.self, from: $0) }
                if var record = AgentHookRecord.reduce(object, previous: old, now: Date().timeIntervalSince1970) {
                    if provider == "workbuddy", record.state == "waiting" {
                        let source = testRoot?.appendingPathComponent("source-workbuddy") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".workbuddy")
                        if let hint = WorkBuddyPendingTool.hint(sessionID: session, root: source) {
                            record.attentionReason = hint.reason; record.attentionID = hint.id
                        }
                    }
                    try write(JSONEncoder().encode(record), to: file)
                }
            } else { exit(1) }
        } catch {
            // Recording must never block or approve an Agent action. Install errors are explicit.
            if args[1] == "--install" { fputs("状态提醒配置失败；原配置已保留。\n", stderr); exit(1) }
        }
    }
}
