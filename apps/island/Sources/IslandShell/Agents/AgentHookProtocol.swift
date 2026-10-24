import Foundation
import CryptoKit

/// Shared by the app and the passive hook executable. Never contains content or paths.
struct AgentHookRecord: Codable, Equatable {
    var id: String
    var state: String
    var updatedAt: Double
    var completionID: String?
    var attentionID: String?
    var attentionReason: String?
    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func reduce(_ input: [String: Any], previous: Self?, now: Double) -> Self? {
        guard let session = input["session_id"] as? String, !session.isEmpty, session.utf8.count <= 256,
              let event = input["hook_event_name"] as? String else { return nil }
        let id = digest(session)
        var state = "working", reason: String?
        let tool = (input["tool_name"] as? String ?? "").lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
        switch event {
        case "UserPromptSubmit": break
        case "PreToolUse":
            if ["askuserquestion", "askfollowupquestion", "picklocation"].contains(tool) { state = "waiting"; reason = "input" }
            else if tool == "exitplanmode" { state = "waiting"; reason = "approval" }
        case "PermissionRequest": state = "waiting"; reason = ["askuserquestion", "askfollowupquestion"].contains(tool) ? "input" : "approval"
        case "Notification":
            switch input["notification_type"] as? String {
            case "permission_prompt": state = "waiting"; reason = previous?.state == "waiting" ? previous?.attentionReason ?? "approval" : "approval"
            case "elicitation_dialog", "agent_needs_input": state = "waiting"; reason = "input"
            case "elicitation_complete", "elicitation_response": break
            // Idle after a completed turn is not a blocked question.
            default: return nil
            }
        case "Elicitation": state = "waiting"; reason = "input"
        case "PostToolUse", "PostToolUseFailure", "ElicitationResult": break
        case "Stop": state = "completed"
        case "StopFailure": state = "failed"
        case "SessionEnd":
            guard previous?.state == "working" || previous?.state == "waiting" else { return nil }
            state = "failed" // Closing a client is never proof of a successful turn.
        default: return nil
        }
        let attention = state == "waiting" ? (previous?.state == "waiting" && previous?.attentionReason == reason ? previous?.attentionID : UUID().uuidString) : nil
        return Self(id: id, state: state, updatedAt: now, completionID: state == "completed" ? UUID().uuidString : previous?.completionID,
                    attentionID: attention, attentionReason: reason)
    }
}

enum AgentHookFiles {
    static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FeishuIsland/AgentStatus")
    static func read(provider: String, root: URL = root, now: Double) -> [AgentHookRecord] {
        let folder = root.appendingPathComponent(provider)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey]) else { return [] }
        return urls.filter { $0.pathExtension == "json" && $0.deletingPathExtension().lastPathComponent.count == 64 }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            .prefix(200).compactMap { url in
                guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
                      let data = try? Data(contentsOf: url), data.count <= 2048,
                      let record = try? JSONDecoder().decode(AgentHookRecord.self, from: data),
                      record.id == url.deletingPathExtension().lastPathComponent,
                      ["working", "waiting", "completed", "failed"].contains(record.state),
                      record.updatedAt.isFinite, record.updatedAt <= now + 60, now - record.updatedAt < 86400 else { return nil }
                return record
            }
    }
}

struct AgentHookPolicy: Codable {
    var enabled: Bool
    var visibleIDs: [String]
    static func save(enabled: Bool, visibleIDs: [String], root: URL = AgentHookFiles.root) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = root.appendingPathComponent("policy.json")
        try JSONEncoder().encode(Self(enabled: enabled, visibleIDs: visibleIDs)).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
