import Foundation

/// Hooks send only state and quota fields. Prompts, replies and credentials are never persisted.
public enum AgentBridge {
    public static var root: URL {
        if let test = ProcessInfo.processInfo.environment["YU_ISLAND_AGENT_BRIDGE_DIR"], test.hasPrefix("/") { return URL(fileURLWithPath: test) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/YouziIsland/AgentBridge")
    }
    public static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 64 && value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
    }
    public static func quotaLabel(minutes: Double?) -> String {
        guard let minutes else { return "额度窗口" }
        if minutes == 10080 { return "周额度" }
        if minutes >= 60 { return "\(Int(minutes / 60))小时额度" }
        return "\(Int(minutes))分钟额度"
    }
    public static func claudeQuotas(_ raw: [String: Any], now: Double) -> [AgentQuota] {
        [("five_hour", "5小时额度"), ("seven_day", "周额度")].compactMap { key, name in
            guard let window = raw[key] as? [String: Any], let used = window["used_percentage"] as? Double,
                  used.isFinite, (0...100).contains(used) else { return nil }
            return AgentQuota(id: key, label: name, remainingPercent: 100 - used, resetsAt: window["resets_at"] as? Double, updatedAt: now)
        }
    }
}
