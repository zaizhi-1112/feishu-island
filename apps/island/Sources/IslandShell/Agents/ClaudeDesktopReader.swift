import Foundation

/// Use the newest available terminal or desktop usage record, preserving its source timestamp.
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
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
        if let bytes = try? Data(contentsOf: desktop), bytes.count < 4194304,
           let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
           let samples = value["samples"] as? [[String: Any]],
           let latest = samples.max(by: { ($0["t"] as? Double ?? 0) < ($1["t"] as? Double ?? 0) }),
           let stamp = latest["t"] as? Double, stamp.isFinite, stamp / 1000 <= now + 60,
           stamp / 1000 > (snapshot.quotas.map(\.updatedAt).max() ?? 0),
           let usage = latest["u"] as? [String: Double] {
            let quotas = [("fh", "5小时额度"), ("sd", "周额度")].compactMap { key, label -> AgentQuota? in
                guard let used = usage[key], used.isFinite, (0...100).contains(used) else { return nil }
                return AgentQuota(id: key, label: label, remainingPercent: 100-used, resetsAt: nil, updatedAt: stamp / 1000)
            }
            if !quotas.isEmpty {
                snapshot.quotas = quotas
                snapshot.source = "Claude 桌面端额度"
                snapshot.detail = "来自 Claude 桌面端的最近记录；客户端更新后自动同步。"
            }
        }
        let cached = cachedDesktopQuotas(now: now)
        for quota in cached {
            if let index = snapshot.quotas.firstIndex(where: { $0.label == quota.label }) {
                if quota.updatedAt >= snapshot.quotas[index].updatedAt {
                    snapshot.quotas[index] = quota
                } else if snapshot.quotas[index].resetsAt == nil, let reset = quota.resetsAt, reset > now {
                    // Same account, still-current window: retain the newer utilization sample.
                    snapshot.quotas[index].resetsAt = reset
                }
            } else { snapshot.quotas.append(quota) }
        }
        if !cached.isEmpty {
            snapshot.source = "Claude 桌面端额度"
            snapshot.detail = "已读取客户端额度与重置时间；每分钟同步客户端已有记录。"
        }
        return snapshot
    }

    private static let cacheLock = NSLock()
    private static var lastRead: Double = 0
    private static var lastQuotas: [AgentQuota] = []
    private static func cachedDesktopQuotas(now: Double) -> [AgentQuota] {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if now >= lastRead, now - lastRead < 60 { return lastQuotas.filter { ($0.resetsAt ?? 0) > now } }
        lastRead = now
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let node = ["/opt/homebrew/bin/node", "/usr/local/bin/node", home + "/.local/node/bin/node"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return [] }
        let development = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/claude-desktop-usage.cjs")
        let script = Bundle.main.resourceURL?.appendingPathComponent("claude-desktop-usage.cjs")
        let path = script.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? development
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: node); process.arguments = [path.path]
        process.environment = ["HOME": home, "PATH": "/usr/bin:/bin"]
        process.standardInput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice; process.standardOutput = output
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        defer { timeout.cancel(); try? output.fileHandleForReading.close(); try? output.fileHandleForWriting.close() }
        do { try process.run() } catch { return [] }
        try? output.fileHandleForWriting.close()
        DispatchQueue.global().asyncAfter(deadline: .now()+6, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, data.count <= 8192,
              let record = try? JSONDecoder().decode(ClaudeQuotaRecord.self, from: data), record.quotas.count <= 2,
              AgentSnapshot(quotas: record.quotas).validationError == nil else { return [] }
        lastQuotas = record.quotas
        return lastQuotas
    }
}
