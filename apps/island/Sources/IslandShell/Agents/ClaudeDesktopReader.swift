import Foundation

/// Desktop usage history is a local snapshot, not a fresh network quota query.
/// Task states come from passive Code lifecycle hooks, separately from old usage samples.
enum ClaudeDesktopReader {
    static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude")
    static func snapshot(now: Double) -> AgentSnapshot {
        var snapshot = AgentSnapshot(sessions: AgentStatusConnection.sessions(provider: "claude", now: now), source: "Claude Code本机状态事件", detail: AgentStatusConnection.isConfigured("claude") ? "状态提醒已配置；新任务开始后显示。额度仅为桌面历史记录。" : "状态提醒尚未配置，请在工作台Agent接入中连接。")
        let url = root.appendingPathComponent("plan-usage-history.json")
        if let bytes = try? Data(contentsOf: url), bytes.count < 4194304,
           let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
           let samples = value["samples"] as? [[String: Any]],
           let latest = samples.max(by: { ($0["t"] as? Double ?? 0) < ($1["t"] as? Double ?? 0) }),
           let timestamp = latest["t"] as? Double, let usage = latest["u"] as? [String: Double] {
            snapshot.quotas = [("fh", "5小时额度"), ("sd", "周额度")].compactMap { key, title in
                guard let used = usage[key], used.isFinite, (0...100).contains(used) else { return nil }
                return AgentQuota(id: key, label: title, remainingPercent: 100-used, resetsAt: nil, updatedAt: timestamp/1000)
            }
            snapshot.detail = "任务状态来自Claude Code事件；额度为桌面上次记录，不是实时查询。"
        }
        return snapshot
    }
}
