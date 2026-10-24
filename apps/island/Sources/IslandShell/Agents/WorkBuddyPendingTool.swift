import Foundation

/// Read only the pending tool's name and call ID; never retain its arguments or output.
enum WorkBuddyPendingTool {
    struct Hint { var reason: String; var id: String }
    static func hint(sessionID: String, root: URL) -> Hint? {
        guard AgentBridge.validID(sessionID) else { return nil }
        let projects = root.appendingPathComponent("projects")
        guard let folders = try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return nil }
        for folder in folders.prefix(512) {
            guard (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else { continue }
            let file = folder.appendingPathComponent(sessionID + ".jsonl")
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]), values.isRegularFile == true, values.isSymbolicLink == false,
                  let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            guard let size = try? handle.seekToEnd() else { return nil }
            let offset = size > 524288 ? size - 524288 : 0
            try? handle.seek(toOffset: offset)
            guard let data = try? handle.read(upToCount: 524288) else { return nil }
            return parse(data, sessionID: sessionID, skipFirst: offset > 0)
        }
        return nil
    }
    static func parse(_ data: Data, sessionID: String, skipFirst: Bool = false) -> Hint? {
        guard data.count <= 524288 else { return nil }
        var calls: [(String, String)] = []
        for (index, line) in data.split(separator: 10).enumerated() {
            if skipFirst && index == 0 { continue }
            guard let value = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any], value["sessionId"] as? String == sessionID else { continue }
            let type = value["type"] as? String
            if type == "message", value["role"] as? String == "user" { calls = []; continue }
            guard let id = value["callId"] as? String, !id.isEmpty, id.utf8.count <= 256 else { continue }
            if ["function_call_result", "function_call_output"].contains(type ?? "") { calls.removeAll { $0.0 == id }; continue }
            if type == "function_call", let rawName = value["name"] as? String {
                let name = rawName.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
                let reason = ["askuserquestion", "askfollowupquestion", "picklocation"].contains(name) ? "input" : name == "exitplanmode" ? "approval" : nil
                if let reason { calls.append((id, reason)); calls = Array(calls.suffix(32)) }
            }
        }
        return calls.last.map { Hint(reason: $0.1, id: "tool:" + AgentHookRecord.digest($0.0)) }
    }
}
