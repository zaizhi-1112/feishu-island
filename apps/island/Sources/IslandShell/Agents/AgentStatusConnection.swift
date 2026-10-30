import Foundation

enum AgentStatusConnection {
    static func isConfigured(_ provider: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let file = home.appendingPathComponent(provider == "claude" ? ".claude/settings.json" : ".workbuddy/settings.json")
        guard let data = try? Data(contentsOf: file), data.count < 4194304,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = object["hooks"] as? [String: Any],
              let helper = Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Helpers/agent-status-helper") else { return false }
        if provider == "claude" {
            guard let statusLine = object["statusLine"] as? [String: Any],
                  let command = statusLine["command"] as? String,
                  command.contains(helper.path), command.hasSuffix(" --statusline claude") else { return false }
        }
        return ["UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop"].allSatisfy { event in
            (hooks[event] as? [[String: Any]] ?? []).contains { entry in
                (entry["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(helper.path) == true && ($0["command"] as? String)?.hasSuffix(" --record " + provider) == true }
            }
        }
    }
    static func sessions(provider: String, now: Double, root: URL = AgentHookFiles.root) -> [AgentSession] {
        AgentHookFiles.read(provider: provider, root: root, now: now).compactMap { record in
            guard let state = AgentState(rawValue: record.state) else { return nil }
            return AgentSession(id: record.id, state: state, updatedAt: record.updatedAt, completionID: record.completionID,
                                attentionID: record.attentionID, attentionReason: record.attentionReason, startID:record.startID)
        }
    }
    static func merge(database: [AgentSession], events: [AgentSession], now: Double) -> [AgentSession] {
        var result = Dictionary(database.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for event in events {
            // A fresh explicit human request overrides WorkBuddy's coarse pending/working row.
            if let row = result[event.id], row.updatedAt > event.updatedAt,
               !(event.state == .waiting && now - event.updatedAt < 900 && (row.state == .working || row.state == .unknown)) { continue }
            result[event.id] = event
        }
        return Array(result.values).sorted { $0.updatedAt > $1.updatedAt }.prefix(200).map { $0 }
    }
    static func install(_ provider: String) async -> Bool {
        guard ["claude", "workbuddy"].contains(provider), !IslandRuntime.isSkinPreview,
              Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview",
              let helper = Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Helpers/agent-status-helper"),
              FileManager.default.isExecutableFile(atPath: helper.path) else { return false }
        return await Task.detached {
            let process = Process(); process.executableURL = helper; process.arguments = ["--install", provider]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 } catch { return false }
        }.value
    }
}
