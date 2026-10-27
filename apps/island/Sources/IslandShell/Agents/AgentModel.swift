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
    public var attentionID:String?
    public var attentionReason:String?
    public init(id: String, state: AgentState, updatedAt: Double, completionID: String? = nil, attentionID:String? = nil, attentionReason:String? = nil) {
        self.id = id; self.state = state; self.updatedAt = updatedAt; self.completionID = completionID
        self.attentionID=attentionID;self.attentionReason=attentionReason
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
        && AgentTimestamp.isValid(updatedAt) && (resetsAt.map(AgentTimestamp.isValid) ?? true)
        && updatedAt <= now + 60 && now - updatedAt < 900 && (resetsAt.map { $0 > now } ?? true)
    }
}

/// A measured value does not imply a known total or a percentage quota.
public struct AgentMetric: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var value: Double
    public var unit: String
    public var updatedAt: Double
    public init(id: String, label: String, value: Double, unit: String, updatedAt: Double) {
        self.id=id; self.label=label; self.value=value; self.unit=unit; self.updatedAt=updatedAt
    }
    public func isFresh(now: Double) -> Bool {
        value.isFinite && AgentTimestamp.isValid(updatedAt) && updatedAt <= now+60 && now-updatedAt < 900
    }
}

enum AgentTimestamp {
    // Reject unrepresentable calendar dates before formatting or integer conversion.
    static func isValid(_ value: Double) -> Bool { value.isFinite && (0...253_402_300_799).contains(value) }
}

public struct AgentSnapshot: Codable, Sendable {
    public var sessions: [AgentSession] = []
    public var quotas: [AgentQuota] = []
    public var metrics: [AgentMetric] = []
    public var source = "等待接入"
    public var detail = "尚未收到Agent的数据。"
    public init(sessions: [AgentSession] = [], quotas: [AgentQuota] = [], metrics: [AgentMetric] = [], source: String = "等待接入", detail: String = "尚未收到Agent的数据。") {
        self.sessions = sessions; self.quotas = quotas; self.metrics=metrics; self.source = source; self.detail = detail
    }
    enum CodingKeys: String, CodingKey { case sessions, quotas, metrics, source, detail }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy:CodingKeys.self)
        sessions = try values.decodeIfPresent([AgentSession].self,forKey:.sessions) ?? []
        quotas = try values.decodeIfPresent([AgentQuota].self,forKey:.quotas) ?? []
        metrics = try values.decodeIfPresent([AgentMetric].self,forKey:.metrics) ?? []
        source = try values.decodeIfPresent(String.self,forKey:.source) ?? "自定义状态文件"
        detail = try values.decodeIfPresent(String.self,forKey:.detail) ?? "仅展示来源实际提供的数据。"
    }
    public func state(now: Double) -> AgentState {
        let recent = sessions.filter { $0.updatedAt <= now + 60 && now - $0.updatedAt < 900 }
        if recent.contains(where: { $0.state == .working }) { return .working }
        if recent.contains(where: { $0.state == .waiting }) { return .waiting }
        if sessions.contains(where: { ($0.state == .working || $0.state == .waiting) && now - $0.updatedAt >= 900 }) { return .unknown }
        return recent.max(by: { $0.updatedAt < $1.updatedAt })?.state ?? .unknown
    }
    public var validationError: String? {
        guard sessions.count <= 200, quotas.count <= 30, metrics.count <= 30, source.count<=160, detail.count<=1000,
              Set(sessions.map(\.id)).count == sessions.count, Set(quotas.map(\.id)).count == quotas.count,
              Set(metrics.map(\.id)).count == metrics.count,
              sessions.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 200 && AgentTimestamp.isValid($0.updatedAt) && ($0.completionID?.count ?? 0)<=200 && ($0.attentionID?.count ?? 0)<=200 && ($0.attentionReason?.count ?? 0)<=200 }),
              quotas.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 160 && $0.label.count <= 80 && AgentTimestamp.isValid($0.updatedAt) && $0.remainingPercent.isFinite && (0...100).contains($0.remainingPercent) && ($0.resetsAt.map(AgentTimestamp.isValid) ?? true) && ($0.remainingUnits.map { $0.isFinite && $0 >= 0 } ?? true) && ($0.totalUnits.map { $0.isFinite && $0 > 0 } ?? true) }),
              metrics.allSatisfy({ !$0.id.isEmpty && $0.id.count<=160 && !$0.label.isEmpty && $0.label.count<=80 && $0.unit.count<=24 && $0.value.isFinite && AgentTimestamp.isValid($0.updatedAt) }) else { return "接入数据格式无效，请检查字段长度、数值与时间；百分比应为0至100。" }
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
    /// Read only Codex account limits; never implies session monitoring.
    public var quotaDisplayEnabled = false
    public var completionAlerts = true
    public var quotaAlerts = true
    public var monitoredIDs: [String]? = ["codex", "claude", "workbuddy"]
    public var completionScreenMaterialID: String? = nil
    public var primaryID = "codex"
    /// Visual preference is independent of the monitored Agent. Auto is optional.
    public var skinID = "auto"
    public var effectsEnabled = true
    public var visibleIDs = ["codex", "claude", "workbuddy"]
    public var profiles = [AgentProfile(id: "codex", name: "Codex", kind: "codex"), AgentProfile(id: "claude", name: "Claude Code", kind: "claude"), AgentProfile(id: "workbuddy", name: "WorkBuddy", kind: "workbuddy")]
    public init() {}
    enum CodingKeys: String, CodingKey { case revision, enabled, quotaDisplayEnabled, completionAlerts, quotaAlerts, monitoredIDs, completionScreenMaterialID, primaryID, skinID, effectsEnabled, visibleIDs, profiles }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        revision = try values.decode(Int.self, forKey: .revision)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        quotaDisplayEnabled = try values.decodeIfPresent(Bool.self, forKey: .quotaDisplayEnabled) ?? false
        completionAlerts = try values.decode(Bool.self, forKey: .completionAlerts)
        quotaAlerts = try values.decode(Bool.self, forKey: .quotaAlerts)
        monitoredIDs = try values.decodeIfPresent([String].self, forKey: .monitoredIDs)
        completionScreenMaterialID = try values.decodeIfPresent(String.self, forKey: .completionScreenMaterialID)
        primaryID = try values.decode(String.self, forKey: .primaryID)
        skinID = try values.decodeIfPresent(String.self, forKey: .skinID) ?? "auto"
        effectsEnabled = try values.decodeIfPresent(Bool.self, forKey: .effectsEnabled) ?? true
        profiles = try values.decode([AgentProfile].self, forKey: .profiles)
        // Existing installations retain all three until the user chooses a display set.
        visibleIDs = try values.decodeIfPresent([String].self, forKey: .visibleIDs) ?? profiles.map(\.id)
    }
    public var visibleProfiles: [AgentProfile] { visibleIDs.compactMap { id in profiles.first { $0.id == id } } }
    public var activeMonitorIDs: [String] { monitoredIDs ?? visibleIDs }
    public func isMonitoring(_ id: String) -> Bool { enabled && activeMonitorIDs.contains(id) }
    public func islandProfile(preferredID: String?) -> AgentProfile? {
        visibleProfiles.first { $0.id == preferredID } ?? visibleProfiles.first { $0.id == primaryID } ?? visibleProfiles.first
    }
    public mutating func setVisibleIDs(_ ids: [String]) {
        if monitoredIDs == nil { monitoredIDs = visibleIDs }
        visibleIDs = ids
        if !ids.contains(primaryID), let first = visibleProfiles.first { primaryID = first.id }
    }
    public var validationError: String? {
        guard ["auto", "codex", "claude", "workbuddy", "virxact"].contains(skinID) else { return "请选择可用的皮肤。" }
        let builtins = Set(["codex", "claude", "workbuddy"])
        let allIDs = Set(profiles.map(\.id))
        guard (3...20).contains(profiles.count), builtins.isSubset(of:allIDs), allIDs.count == profiles.count,
              profiles.contains(where:{$0.id==primaryID}),
              profiles.allSatisfy({ profile in
                  AgentBridge.validID(profile.id) && !profile.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && profile.name.count<=40 &&
                  (builtins.contains(profile.id) ? profile.kind==profile.id && profile.dataPath.isEmpty : profile.kind=="file" && profile.dataPath.hasPrefix("/") && profile.dataPath.hasSuffix(".json"))
              }) else { return "保留内置接入；自定义 Agent 需要名称和你选定的本机 JSON 状态文件，最多20个。" }
        guard visibleIDs.count<=3, Set(visibleIDs).count==visibleIDs.count, Set(visibleIDs).isSubset(of:allIDs),
              visibleIDs.isEmpty || visibleIDs.contains(primaryID) else { return "灵动岛最多显示3个 Agent；主用 Agent 应在显示列表内。" }
        guard Set(activeMonitorIDs).isSubset(of:allIDs), Set(activeMonitorIDs).count==activeMonitorIDs.count else { return "监测列表无效。" }
        guard completionScreenMaterialID.map({ !$0.isEmpty && $0.count<=100 }) ?? true else { return "请选择有效的提醒素材。" }
        return nil
    }
}

/// Kept independent of UI so threshold/reset/deduplication behavior can be verified with fixtures.
public struct AgentAlertTracker {
    private var previousRunning = Set<String>()
    private var runningInitialized = false
    public mutating func starts(_ sessions: [AgentSession], now: Double) -> Int {
        let running = sessions.filter { $0.state == .working && now - $0.updatedAt < 900 && $0.updatedAt <= now + 60 }
        defer { previousRunning = Set(running.map(\.id)); runningInitialized = true }
        guard runningInitialized else { return 0 }
        return running.filter { !previousRunning.contains($0.id) && now - $0.updatedAt < 60 }.count
    }
    public var notifiedQuotaCycles: Set<String> = []
    private var previousAttention:[String:String]=[:]
    private var attentionInitialized=false
    private var previousSessions: [String: AgentSession] = [:]
    private var seenCompletions: [String:Double] = [:]
    private var initialized = false
    private var previousCheckAt = 0.0
    private var monitoringStartedAt = 0.0
    public init() {}
    public mutating func completions(_ sessions: [AgentSession], now: Double) -> Int {
        defer { previousSessions = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new }); initialized = true; previousCheckAt = now }
        seenCompletions=seenCompletions.filter { now-$0.value < 900 }
        func key(_ session:AgentSession)->String { session.id+"/"+(session.completionID ?? String(session.updatedAt)) }
        guard initialized else {
            monitoringStartedAt = now
            for session in sessions where session.state == .completed { seenCompletions[key(session)]=now }
            return 0
        }
        return sessions.filter { session in
            guard seenCompletions[key(session)] == nil else {return false}
            defer { if session.state == .completed {seenCompletions[key(session)]=now} }
            guard session.state == .completed, now - session.updatedAt < 60, session.updatedAt <= now + 60 else { return false }
            // Fast tasks may both start and finish between polls. An explicit new completion is sufficient.
            guard let old = previousSessions[session.id] else { return session.updatedAt > monitoringStartedAt }
            guard session.updatedAt > old.updatedAt else { return false }
            return old.state == .working || old.state == .waiting
                || (session.completionID != nil && session.completionID != old.completionID && session.updatedAt > previousCheckAt)
        }.count
    }
    public mutating func attentionRequests(_ sessions:[AgentSession],now:Double)->[AgentSession] {
        let waiting=sessions.filter{$0.state == .waiting && now-$0.updatedAt<900 && $0.updatedAt<=now+60}
        let fresh=waiting.filter { session in
            let key=session.attentionID ?? "waiting"
            return previousAttention[session.id] != key && (attentionInitialized || now-session.updatedAt<60)
        }
        previousAttention=Dictionary(waiting.map{($0.id,$0.attentionID ?? "waiting")},uniquingKeysWith:{$1})
        attentionInitialized=true
        return fresh
    }
    public mutating func lowQuotas(_ quotas: [AgentQuota], profile: String, now: Double) -> [AgentQuota] {
        quotas.filter { quota in
            guard quota.isFresh(now: now) else { return false }
            let cycle = "\(profile)/\(quota.id)/\(quota.resetsAt.map { String(Int($0)) } ?? "no-reset")"
            if quota.remainingPercent >= 20 {
                if quota.resetsAt == nil { notifiedQuotaCycles.remove(cycle) }
                return false
            }
            return notifiedQuotaCycles.insert(cycle).inserted
        }
    }
}

/// Coalesce completion events until the monitored Agent is stably idle.
struct AgentCompletionBatch {
    private var pending=0
    private var quietSince:Double?
    private var unfinished=Set<String>()
    mutating func ingest(count:Int,sessions:[AgentSession],now:Double)->Int {
        for session in sessions {
            if session.state == .working || session.state == .waiting {unfinished.insert(session.id)}
            else if session.state == .completed || session.state == .failed {unfinished.remove(session.id)}
        }
        pending += count
        if count > 0 {quietSince=nil}
        guard pending > 0 else {return 0}
        // Empty/missing reads and stale running sessions are not proof of completion.
        guard !sessions.isEmpty,unfinished.isEmpty,
              sessions.contains(where:{$0.state == .completed && now-$0.updatedAt<900}) else {quietSince=nil;return 0}
        if quietSince == nil {quietSince=now}
        guard now-(quietSince ?? now)>=20 else {return 0}
        let result=pending;pending=0;quietSince=nil;return result
    }
}
