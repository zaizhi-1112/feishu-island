import Foundation

/// Subscription usage is emitted by Claude Code's official status-line payload.
/// Desktop history belongs to a different client and must not be presented as a refreshed Code quota.
enum ClaudeDesktopReader {
    static func snapshot(now: Double, quotaRoot: URL = AgentHookFiles.root) -> AgentSnapshot {
        var snapshot = AgentSnapshot(sessions: AgentStatusConnection.sessions(provider: "claude", now: now), source: "Claude Code本机状态与额度", detail: "等待 Claude Code 更新额度；新回复后自动同步。")
        let url = quotaRoot.appendingPathComponent("claude-quota.json")
        if let bytes = try? Data(contentsOf: url), bytes.count <= 8192,
           let record = try? JSONDecoder().decode(ClaudeQuotaRecord.self, from: bytes),
           record.quotas.count <= 2,
           AgentSnapshot(quotas: record.quotas).validationError == nil {
            snapshot.quotas = record.quotas
            snapshot.detail = record.quotas.contains(where: { $0.isFresh(now: now) })
                ? "已同步 Claude Code 额度；新回复后自动更新。"
                : "上次 Claude Code 额度；等待客户端新回复后更新。"
        }
        return snapshot
    }
}
