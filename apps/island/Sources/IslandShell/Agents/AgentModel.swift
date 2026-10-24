import Foundation

public enum AgentState: String, Codable, Sendable {
    case working, completed, waiting, failed, unknown
    public var label: String {
        switch self {
        case .working: return "正在工作"
        case .completed: return "本轮已完成"
        case .waiting: return "等待操作"
        case .failed: return "任务中断"
        case .unknown: return "等待状态数据"
        }
    }
}

public struct AgentSession: Codable, Equatable, Sendable {
    public var id: String
    public var state: AgentState
    public var updatedAt: Double
    public var completionID: String?
    public init(id: String, state: AgentState, updatedAt: Double, completionID: String? = nil) {
        self.id = id; self.state = state; self.updatedAt = updatedAt; self.completionID = completionID
    }
}

public struct AgentQuota: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var remainingPercent: Double
    public var resetsAt: Double?
    public var updatedAt: Double
    public var remainingUnits: Double? = nil
    public var totalUnits: Double? = nil
    public init(id: String, label: String, remainingPercent: Double, resetsAt: Double?, updatedAt: Double) {
        self.id = id; self.label = label; self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt; self.updatedAt = updatedAt
    }
    public func isFresh(now: Double) -> Bool {
        remainingPercent.isFinite && (0...100).contains(remainingPercent)
        && updatedAt <= now + 60 && now - updatedAt < 900 && (resetsAt.map { $0 > now } ?? true)
    }
}

public struct AgentSnapshot: Codable, Sendable {
    public var sessions: [AgentSession] = []
    public var quotas: [AgentQuota] = []
    public var source = "等待接入"
    public var detail = "尚未收到Agent的数据。"
    public init(sessions: [AgentSession] = [], quotas: [AgentQuota] = [], source: String = "等待接入", detail: String = "尚未收到Agent的数据。") {
        self.sessions = sessions; self.quotas = quotas; self.source = source; self.detail = detail
    }
    public func state(now: Double) -> AgentState {
        let recent = sessions.filter { $0.updatedAt <= now + 60 && now - $0.updatedAt < 900 }
        if recent.contains(where: { $0.state == .working }) { return .working }
        if recent.contains(where: { $0.state == .waiting }) { return .waiting }
        if sessions.contains(where: { ($0.state == .working || $0.state == .waiting) && now - $0.updatedAt >= 900 }) { return .unknown }
        return recent.max(by: { $0.updatedAt < $1.updatedAt })?.state ?? .unknown
    }
    public var validationError: String? {
        guard sessions.count <= 200, quotas.count <= 30,
              Set(sessions.map(\.id)).count == sessions.count, Set(quotas.map(\.id)).count == quotas.count,
              sessions.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 200 && $0.updatedAt.isFinite }),
              quotas.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 160 && $0.label.count <= 80 && $0.updatedAt.isFinite && $0.remainingPercent.isFinite && (0...100).contains($0.remainingPercent) && ($0.resetsAt?.isFinite ?? true) }) else { return "接入数据格式无效，百分比应为0至100。" }
        return nil
    }
}

public struct AgentProfile: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// The three built-in adapters own their data source and connection method.
    public var kind: String
    public var dataPath: String
    public init(id: String, name: String, kind: String, dataPath: String = "") {
        self.id = id; self.name = name; self.kind = kind; self.dataPath = dataPath
    }
}

public struct AgentPreferences: Codable, Sendable {
    public var revision = 0
    public var enabled = false
    public var completionAlerts = true
    public var quotaAlerts = true
    public var primaryID = "codex"
    /// Visual preference is independent of the monitored Agent. Auto is optional.
    public var skinID = "auto"
    public var effectsEnabled = true
    public var visibleIDs = ["codex", "claude", "workbuddy"]
    public var profiles = [AgentProfile(id: "codex", name: "Codex", kind: "codex"), AgentProfile(id: "claude", name: "Claude Code", kind: "claude"), AgentProfile(id: "workbuddy", name: "WorkBuddy", kind: "workbuddy")]
    public init() {}
    enum CodingKeys: String, CodingKey { case revision, enabled, completionAlerts, quotaAlerts, primaryID, skinID, effectsEnabled, visibleIDs, profiles }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        revision = try values.decode(Int.self, forKey: .revision)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        completionAlerts = try values.decode(Bool.self, forKey: .completionAlerts)
        quotaAlerts = try values.decode(Bool.self, forKey: .quotaAlerts)
        primaryID = try values.decode(String.self, forKey: .primaryID)
        skinID = try values.decodeIfPresent(String.self, forKey: .skinID) ?? "auto"
        effectsEnabled = try values.decodeIfPresent(Bool.self, forKey: .effectsEnabled) ?? true
        profiles = try values.decode([AgentProfile].self, forKey: .profiles)
        // Existing installations retain all three until the user chooses a display set.
        visibleIDs = try values.decodeIfPresent([String].self, forKey: .visibleIDs) ?? profiles.map(\.id)
    }
    public var visibleProfiles: [AgentProfile] { profiles.filter { visibleIDs.contains($0.id) } }
    public mutating func setVisibleIDs(_ ids: [String]) {
        visibleIDs = ids
        if !ids.contains(primaryID), let first = visibleProfiles.first { primaryID = first.id }
    }
    public var validationError: String? {
        guard ["auto", "codex", "claude", "workbuddy", "virxact"].contains(skinID) else { return "请选择可用的皮肤。" }
        guard profiles.count == 3, Set(profiles.map(\.id)) == Set(["codex", "claude", "workbuddy"]), profiles.contains(where: { $0.id == primaryID }),
              Set(profiles.map(\.id)).count == profiles.count,
              profiles.allSatisfy({ $0.kind == $0.id && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.name.count <= 40 && $0.dataPath.isEmpty }) else { return "请选择Codex、Claude Code或WorkBuddy作为主用Agent，并保留三项内置接入。" }
        guard !visibleIDs.isEmpty, Set(visibleIDs).count == visibleIDs.count,
              Set(visibleIDs).isSubset(of: Set(profiles.map(\.id))), visibleIDs.contains(primaryID) else { return "至少显示一个Agent，主用Agent必须包含在显示列表中。" }
        return nil
    }
}

/// Kept independent of UI so threshold/reset/deduplication behavior can be verified with fixtures.
public struct AgentAlertTracker {
    public var notifiedQuotaCycles: Set<String> = []
    private var previousSessions: [String: AgentSession] = [:]
    private var initialized = false
    private var previousCheckAt = 0.0
    private var monitoringStartedAt = 0.0
    public init() {}
    public mutating func completions(_ sessions: [AgentSession], now: Double) -> Int {
        defer { previousSessions = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new }); initialized = true; previousCheckAt = now }
        guard initialized else { monitoringStartedAt = now; return 0 }
        return sessions.filter { session in
            guard session.state == .completed, now - session.updatedAt < 60, session.updatedAt <= now + 60 else { return false }
            // Fast tasks may both start and finish between polls. An explicit new completion is sufficient.
            guard let old = previousSessions[session.id] else { return session.updatedAt > monitoringStartedAt }
            guard session.updatedAt > old.updatedAt else { return false }
            return old.state == .working || old.state == .waiting
                || (session.completionID != nil && session.completionID != old.completionID && session.updatedAt > previousCheckAt)
        }.count
    }
    public mutating func lowQuotas(_ quotas: [AgentQuota], profile: String, now: Double) -> [AgentQuota] {
        quotas.filter { quota in
            let cycle = "\(profile)/\(quota.id)/\(quota.resetsAt.map { String(Int($0)) } ?? "no-reset")"
            guard quota.isFresh(now: now) else { return false }
            if quota.remainingPercent >= 20 {
                if quota.resetsAt == nil { notifiedQuotaCycles.remove(cycle) }
                return false
            }
            return notifiedQuotaCycles.insert(cycle).inserted
        }
    }
}
