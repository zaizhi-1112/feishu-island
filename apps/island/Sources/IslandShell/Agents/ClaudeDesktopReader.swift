import Foundation

/// Desktop usage history is a local snapshot, not a fresh network quota query.
/// Until a signed-in desktop session can be verified we expose that limitation explicitly.
enum ClaudeDesktopReader {
    static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude")
    static func snapshot(now: Double) -> AgentSnapshot {
        var snapshot = AgentSnapshot(source: "Claude桌面本机记录", detail: "暂无可用的Claude登录数据。任务状态与实时额度接入尚未完成，需登录后继续联调。")
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
            snapshot.detail = "这里显示Claude桌面上次记录的用量。任务状态与实时额度尚未接入，需登录后继续联调。"
        }
        return snapshot
    }
}
