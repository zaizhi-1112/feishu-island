import AppKit
import NookApp
import SwiftUI

@MainActor
final class AgentStore: ObservableObject {
    static let shared = AgentStore()
    @Published private(set) var preferences: AgentPreferences
    @Published private(set) var snapshots: [String: AgentSnapshot] = [:]
    @Published private(set) var refreshing = false
    @Published private(set) var lastAlert = ""
    @Published private(set) var completionNotice: AgentCompletionNotice?
    @Published private(set) var unviewedCompletionProfiles = Set<String>()
    private var completionTask: Task<Void, Never>?
    var selectedSkin: AgentSkin { AgentSkin(agentID: preferences.skinID == "auto" ? primary.id : preferences.skinID) }
    lazy var themeSource = NookThemeSource(selectedSkin.theme)
    private let defaults: UserDefaults
    private let codex = CodexReader()
    private var activities: NookLiveActivities?
    private var timer: Timer?
    private var polling = false
    private var lastQuotaAttempt = Date.distantPast
    private var trackers: [String: AgentAlertTracker] = [:]
    private var quotaTracker = AgentAlertTracker()
    private var activityPrimary = ""
    private var lastAlertDate = Date.distantPast
    private var lastAlertProfile: String?
    init(defaults: UserDefaults? = nil) {
        let defaults = defaults ?? UserDefaults(suiteName: IslandRuntime.isSkinPreview ? "local.youzi.island.skin-preview.agents" : "local.youzi.island.agents")!
        self.defaults = defaults
        let decoded = defaults.data(forKey: "preferences").flatMap { try? JSONDecoder().decode(AgentPreferences.self, from: $0) }
        preferences = decoded?.validationError == nil ? (decoded ?? .init()) : .init()
        quotaTracker.notifiedQuotaCycles = Set(defaults.stringArray(forKey: "notifiedQuotaCycles") ?? [])
    }
    var primary: AgentProfile { preferences.profiles.first { $0.id == preferences.primaryID } ?? preferences.profiles[0] }
    var primarySnapshot: AgentSnapshot { snapshots[primary.id] ?? .init() }
    var state: AgentState { preferences.enabled ? primarySnapshot.state(now: Date().timeIntervalSince1970) : .unknown }
    func start(activities: NookLiveActivities) {
        self.activities = activities
        guard timer == nil, Bundle.main.bundleIdentifier == "local.youzi.island", !ProcessInfo.processInfo.arguments.contains("--self-test") else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        Task { await poll() }
    }
    func update(_ next: AgentPreferences) throws {
        guard next.revision == preferences.revision else { throw AgentReadError.unavailable("设置已在别处更改，请重新载入。") }
        var next = next
        next.setVisibleIDs(next.visibleIDs)
        guard next.validationError == nil else { throw AgentReadError.unavailable(next.validationError!) }
        let previousEnabled = preferences.enabled
        let previousVisible = preferences.visibleIDs
        preferences = next; preferences.revision += 1
        unviewedCompletionProfiles.formIntersection(next.enabled && next.completionAlerts ? Set(next.visibleIDs) : [])
        defaults.set(try JSONEncoder().encode(preferences), forKey: "preferences")
        themeSource.replace(selectedSkin.theme)
        if let lastAlertProfile, !preferences.visibleIDs.contains(lastAlertProfile) {
            activities?.end("agent-alert"); lastAlert = ""; self.lastAlertProfile = nil
        }
        if let notice = completionNotice, !preferences.enabled || !preferences.completionAlerts || !preferences.visibleIDs.contains(notice.profileID) {
            completionTask?.cancel(); completionNotice = nil; activityPrimary = ""
        }
        if !preferences.enabled {
            activities?.end("agent-status"); activities?.end("agent-alert"); activityPrimary = ""
        } else {
            if !previousEnabled { trackers = [:]; lastQuotaAttempt = .distantPast }
            updateActivity(); Task { await poll() }
            if previousVisible != preferences.visibleIDs { checkQuotaAlerts() }
        }
    }
    func selectPrimary(_ id: String) {
        var next = preferences; next.primaryID = id; try? update(next)
    }
    func selectSkin(_ id: String) {
        var next = preferences; next.skinID = id; try? update(next)
    }
    func setEffectsEnabled(_ value: Bool) {
        var next = preferences; next.effectsEnabled = value; try? update(next)
    }
    func poll() async {
        guard !IslandRuntime.isSkinPreview, preferences.enabled, !polling else { return }
        polling = true; defer { polling = false }
        let revision = preferences.revision
        let codexSessions = await codex.sessions(now: Date())
        let workSessions = await Task.detached { try? WorkBuddyReader.sessions(now: Date().timeIntervalSince1970) }.value
        let claude = await Task.detached { ClaudeDesktopReader.snapshot(now: Date().timeIntervalSince1970) }.value
        guard preferences.enabled, preferences.revision == revision else { return }
        var codexValue = snapshots["codex"] ?? .init(source: "Codex本机事件＋官方额度接口", detail: "仅监测这台Mac保存的Codex任务。")
        codexValue.sessions = codexSessions; snapshots["codex"] = codexValue
        var workValue = snapshots["workbuddy"] ?? .init(source: "WorkBuddy本机任务＋客户端积分接口", detail: "打开WorkBuddy并保持登录，即可读取当前积分。")
        workValue.sessions = workSessions ?? []; snapshots["workbuddy"] = workValue
        snapshots["claude"] = claude
        let now = Date().timeIntervalSince1970
        for profile in preferences.profiles {
            var tracker = trackers[profile.id] ?? .init()
            let count = tracker.completions(snapshots[profile.id]?.sessions ?? [], now: now)
            trackers[profile.id] = tracker
            if count > 0, preferences.completionAlerts, preferences.visibleIDs.contains(profile.id) {
                let stillWorking = snapshots[profile.id]?.state(now: now) == .working
                presentCompletion(profileID: profile.id, count: count, stillWorking: stillWorking)
            }
        }
        updateActivity()
        if Date().timeIntervalSince(lastQuotaAttempt) >= 180 { refreshQuotas() }
    }
    func refreshQuotas() {
        guard !IslandRuntime.isSkinPreview, preferences.enabled, !refreshing, Date().timeIntervalSince(lastQuotaAttempt) >= 5 else { return }
        refreshing = true; lastQuotaAttempt = Date()
        Task {
            async let codexResult: Result<[AgentQuota], Error> = Self.readCodexQuota()
            async let workResult: Result<[AgentQuota], Error> = Task.detached { Result { try WorkBuddyReader.quotas(now: Date().timeIntervalSince1970) } }.value
            let results = await [("codex", codexResult), ("workbuddy", workResult)]
            defer { refreshing = false }
            guard preferences.enabled else { return }
            for (id, result) in results {
                var snapshot = snapshots[id] ?? .init()
                switch result {
                case .success(let quotas):
                    snapshot.quotas = quotas
                    snapshot.detail = quotas.isEmpty ? "此账号未返回额度窗口。" : id == "codex" ? "已读取官方额度；每3分钟自动刷新。" : "已读取客户端积分；每3分钟自动刷新。"
                case .failure(let error):
                    snapshot.detail = error.localizedDescription
                    // Keep old data with its original timestamp; it becomes visibly stale, never zero.
                }
                snapshots[id] = snapshot
            }
            snapshots["claude"] = await Task.detached { ClaudeDesktopReader.snapshot(now: Date().timeIntervalSince1970) }.value
            checkQuotaAlerts()
        }
    }
    nonisolated private static func readCodexQuota() async -> Result<[AgentQuota], Error> {
        do { return .success(try await CodexReader.quotas()) } catch { return .failure(error) }
    }
    private func checkQuotaAlerts() {
        guard preferences.quotaAlerts else { return }
        for profile in preferences.visibleProfiles where profile.kind != "claude" {
            let low = quotaTracker.lowQuotas(snapshots[profile.id]?.quotas ?? [], profile: profile.id, now: Date().timeIntervalSince1970)
            if let quota = low.min(by: { $0.remainingPercent < $1.remainingPercent }) {
                alert("\(profile.name) · \(quota.label)剩余\(String(format: "%.1f", quota.remainingPercent))%", color: .orange, profileID: profile.id)
            }
        }
        defaults.set(Array(quotaTracker.notifiedQuotaCycles.suffix(200)), forKey: "notifiedQuotaCycles")
    }
    private func updateActivity() {
        guard completionNotice == nil else { return }
        guard activityPrimary != primary.id else { return }; activityPrimary = primary.id
        var activity = NookLiveActivity(id: "agent-status", priority: .low, accessibilityLabel: "Agent状态") {
            AgentCompanionGlyph(store: self)
        } compactTrailing: { AgentCompactView(store: self) } minimal: { AgentCompanionGlyph(store: self) }
        activity.setExpanded { AgentPanel(store: self) }
        activities?.start(activity)
    }
    private func presentCompletion(profileID: String, count: Int, stillWorking: Bool) {
        guard let profile = preferences.profiles.first(where: { $0.id == profileID }) else { return }
        unviewedCompletionProfiles.insert(profileID)
        let notice = AgentCompletionNotice(profileID: profileID, name: profile.name, count: count, stillWorking: stillWorking)
        completionTask?.cancel()
        completionNotice = notice
        lastAlert = notice.message; lastAlertDate = Date(); lastAlertProfile = profileID
        // Reuse the island's existing status activity: no extra notification or companion.
        var activity = NookLiveActivity(id: "agent-status", priority: .high, alert: .compact(.seconds(5)), accessibilityLabel: notice.message) {
            AgentPortrait(id: profileID, size: 25, avatar: true, motion: self.preferences.effectsEnabled, tapFeedback: false)
        } compactTrailing: {
            AgentCompletionStatus(notice: notice, motion: self.preferences.effectsEnabled)
        } minimal: {
            AgentStatusLight(color: stillWorking ? .red : .green, pulse: !stillWorking, motion: self.preferences.effectsEnabled)
        }
        activity.setExpanded { AgentPanel(store: self, profileID: profileID) }
        activities?.start(activity)
        completionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            guard let self, self.completionNotice?.id == notice.id else { return }
            self.completionNotice = nil; self.activityPrimary = ""
            self.updateActivity()
        }
    }
    func acknowledgeCompletions() {
        guard !unviewedCompletionProfiles.isEmpty else { return }
        unviewedCompletionProfiles.removeAll()
    }

    var hasLowQuota: Bool {
        !lowQuotaMessages.isEmpty
    }
    var lowQuotaMessages: [String] {
        lowQuotaAlerts.map(\.message)
    }
    var lowQuotaAlerts: [(id: String, message: String)] {
        guard preferences.enabled, preferences.quotaAlerts else { return [] }
        let now = Date().timeIntervalSince1970
        return preferences.visibleProfiles.filter { $0.kind != "claude" }.flatMap { profile in
            (snapshots[profile.id]?.quotas ?? []).filter {
                $0.isFresh(now: now) && $0.remainingPercent < 20
            }.map { quota in
                (id: "quota:\(profile.id):\(quota.id):\(quota.resetsAt.map(String.init(describing:)) ?? "pool")",
                 message: "\(profile.name) · \(quota.label)剩余\(String(format: "%.1f", quota.remainingPercent))%（低于20%）")
            }
        }
    }
    private func alert(_ message: String, color: Color, profileID: String) {
        lastAlert = message; lastAlertDate = Date(); lastAlertProfile = profileID
        var activity = NookLiveActivity(id: "agent-alert", priority: .high, lifetime: .transient(.seconds(10)), alert: .peek(.seconds(5)), accessibilityLabel: message) {
            AgentPortrait(id: profileID, size: 25, avatar: true, motion: self.preferences.effectsEnabled, tapFeedback: false)
        } compactTrailing: { Label("额度不足", systemImage: "exclamationmark.circle.fill").font(.system(size: 10)).foregroundStyle(color) } minimal: { AgentPortrait(id: profileID, size: 20, avatar: true, motion: self.preferences.effectsEnabled, tapFeedback: false) }
        activity.setPeek { AgentNotificationPeek(profileID: profileID, message: message, motion: self.preferences.effectsEnabled) }
        activity.setExpanded { AgentPanel(store: self, profileID: profileID) }
        activities?.start(activity)
    }
    /// Synthetic notification, available only in the isolated skin acceptance process.
    func previewNotification(_ profileID: String, stillWorking: Bool = false) {
        guard IslandRuntime.isSkinPreview,
              let profile = preferences.profiles.first(where: { $0.id == profileID }) else { return }
        presentCompletion(profileID: profile.id, count: 1, stillWorking: stillWorking)
    }
    func previewQuotas(_ quotas: [AgentQuota], profileID: String = "codex") {
        guard IslandRuntime.isSkinPreview else { return }
        var snapshot = snapshots[profileID] ?? .init()
        snapshot.quotas = quotas; snapshots[profileID] = snapshot
    }
    func openAgent(_ id: String) {
        let candidates = id == "claude" ? ["/Applications/Claude.app"] : id == "workbuddy" ? ["/Applications/WorkBuddy.app"] : ["/Applications/ChatGPT.app", "/Applications/Codex.app"]
        if let path = candidates.first(where: FileManager.default.fileExists(atPath:)) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
    }
    func webSnapshot() -> [String: Any] {
        let now = Date().timeIntervalSince1970
        let states: [String: Any] = snapshots.mapValues { value in
            ["state": preferences.enabled ? value.state(now: now).rawValue : "unknown", "stateLabel": preferences.enabled ? value.state(now: now).label : "监测已暂停",
             "source": value.source, "detail": value.detail,
             "activeCount": value.sessions.filter { $0.state == .working && now - $0.updatedAt < 900 }.count,
             "quotas": value.quotas.map { quota -> [String: Any] in
                 ["id": quota.id, "label": quota.label, "remainingPercent": quota.remainingPercent, "resetsAt": quota.resetsAt as Any? ?? NSNull(), "updatedAt": quota.updatedAt, "fresh": quota.isFresh(now: now), "remainingUnits": quota.remainingUnits as Any? ?? NSNull(), "totalUnits": quota.totalUnits as Any? ?? NSNull()]
             }] as [String: Any]
        }
        return ["preferences": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences))) ?? [:], "agents": states, "refreshing": refreshing, "lastAlert": lastAlert, "threshold": 20]
    }
}
