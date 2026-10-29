import AppKit
import NookApp
import SwiftUI

@MainActor
final class AgentStore: ObservableObject {
    static let shared = AgentStore()
    @Published private(set) var preferences: AgentPreferences
    @Published private(set) var preferencesReadError: String?
    @Published private(set) var snapshots: [String: AgentSnapshot] = [:]
    @Published private(set) var refreshing = false
    @Published private(set) var lastAlert = ""
    @Published private(set) var completionNotice: AgentCompletionNotice?
    @Published private(set) var unviewedCompletionProfiles = Set<String>()
    var statusNotice:(String,String,String)->Void = { _,_,_ in }
    @Published private(set) var primarySwitchNotice: AgentPrimarySwitchNotice?
    private var primarySwitchTask: Task<Void,Never>?
    private var completionTask: Task<Void, Never>?
    private var pendingNotices: [AgentCompletionNotice] = []
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
    private var completionBatches: [String:AgentCompletionBatch] = [:]
    private var activityPrimary = ""
    private var lastAlertDate = Date.distantPast
    private var lastAlertProfile: String?
    private let allowsLiveReads: Bool
    private let sessionIsLocked: () -> Bool
    private var lockObservers: [NSObjectProtocol] = []
    init(defaults: UserDefaults? = nil, allowsLiveReads: Bool = true, sessionIsLocked: @escaping () -> Bool = { ScreenReminderSession.isLocked }) {
        self.allowsLiveReads=allowsLiveReads; self.sessionIsLocked=sessionIsLocked
        let defaults = defaults ?? UserDefaults(suiteName: IslandRuntime.isSkinPreview ? "local.youzi.island.skin-preview.agents" : "local.zaizhi.feishu-island.preview.agents")!
        self.defaults = defaults
        preferences = .init()
        if defaults.object(forKey: "preferences") == nil, allowsLiveReads {
            preferences = IslandOnboardingPolicy.unselectedAgents(preferences)
            // Persist opting into no tools so skipping stays quiet after restart.
            if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: "preferences") }
        }
        if let raw = defaults.object(forKey:"preferences") {
            do {
                guard let bytes=raw as? Data else {throw AgentReadError.unavailable("配置格式不正确。")}
                let decoded=try JSONDecoder().decode(AgentPreferences.self,from:bytes)
                if let issue=decoded.validationError {throw AgentReadError.unavailable(issue)}
                preferences=decoded
            } catch {
                preferencesReadError="Agent配置未能读取，原文件已保留。修复前暂停监测与设置保存。"
                preferences.enabled=false;preferences.quotaDisplayEnabled=false
            }
        }
        quotaTracker.notifiedQuotaCycles = Set(defaults.stringArray(forKey: "notifiedQuotaCycles") ?? [])
    }
    var primary: AgentProfile { preferences.profiles.first { $0.id == preferences.primaryID } ?? preferences.profiles[0] }
    var primarySnapshot: AgentSnapshot { snapshots[primary.id] ?? .init() }
    var state: AgentState { state(for:primary.id) }
    func state(for id: String, now: Double = Date().timeIntervalSince1970) -> AgentState {
        preferences.isMonitoring(id) ? snapshots[id]?.state(now:now) ?? .unknown : .unknown
    }
    func start(activities: NookLiveActivities) {
        self.activities = activities
        guard allowsLiveReads, timer == nil, Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview", !IslandRuntime.isSkinPreview, !ProcessInfo.processInfo.arguments.contains("--self-test") else { return }
        lockObservers.append(DistributedNotificationCenter.default().addObserver(forName:NSNotification.Name("com.apple.screenIsLocked"),object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.handleSessionLock() } })
        lockObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.sessionDidResignActiveNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.handleSessionLock() } })
        let timer = Timer(timeInterval:2,repeats:true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        self.timer=timer;RunLoop.main.add(timer,forMode:.common)
        saveStatusPolicy()
        updateActivity()
        Task { await connectSelectedStatuses(); await poll() }
    }
    func reloadPreferences() {
        do {
            guard let bytes=defaults.data(forKey:"preferences") else {throw AgentReadError.unavailable("原配置仍不可读，请先导出检查。")}
            let decoded=try JSONDecoder().decode(AgentPreferences.self,from:bytes)
            if let issue=decoded.validationError {throw AgentReadError.unavailable(issue)}
            // Reload never replaces or re-encodes the original bytes.
            preferences=decoded;preferencesReadError=nil
            themeSource.replace(selectedSkin.theme);saveStatusPolicy();updateActivity()
            Task {await connectSelectedStatuses();await poll()}
        } catch {preferencesReadError="原配置仍未能读取，请保留导出的副本后修复，再重新读取。"}
    }
    func restorePreferences(from url:URL) throws {
        guard preferencesReadError != nil else {throw AgentReadError.unavailable("当前配置可正常读取，无需恢复。")}
        let access=url.startAccessingSecurityScopedResource();defer {if access {url.stopAccessingSecurityScopedResource()}}
        let info=try url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
        guard info.isRegularFile == true,(info.fileSize ?? Int.max)<=1_048_576 else {throw AgentReadError.unavailable("请选择1MB以内的配置JSON文件。")}
        let bytes=try Data(contentsOf:url)
        let decoded=try JSONDecoder().decode(AgentPreferences.self,from:bytes)
        if let issue=decoded.validationError {throw AgentReadError.unavailable(issue)}
        // Keep the exact original in the same preferences domain before explicit recovery.
        if let original=defaults.object(forKey:"preferences") {
            defaults.set(original,forKey:"preferencesRecoveryBackup."+UUID().uuidString)
        }
        defaults.set(bytes,forKey:"preferences")
        reloadPreferences()
    }
    func exportOriginalPreferences(to url:URL) throws {
        guard let raw=defaults.object(forKey:"preferences") else {throw AgentReadError.unavailable("没有找到原配置。")}
        let bytes:Data
        if let data=raw as? Data {bytes=data}
        else {bytes=try PropertyListSerialization.data(fromPropertyList:raw,format:.xml,options:0)}
        try bytes.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
    func update(_ next: AgentPreferences) throws {
        if let issue=preferencesReadError {lastAlert=issue;throw AgentReadError.unavailable(issue)}
        guard next.revision == preferences.revision else { throw AgentReadError.unavailable("设置已在别处更改，请重新载入。") }
        var next = next
        next.setVisibleIDs(next.visibleIDs)
        guard next.validationError == nil else { throw AgentReadError.unavailable(next.validationError!) }
        let previousPrimary = preferences.primaryID
        let previousEnabled = preferences.enabled
        let previousVisible = preferences.visibleIDs
        let previousQuotaDisplay = preferences.quotaDisplayEnabled
        let previousMonitored=Set(preferences.activeMonitorIDs)
        let nextMonitored=Set(next.activeMonitorIDs)
        if nextMonitored.contains("deepseek") && !previousMonitored.contains("deepseek") { lastQuotaAttempt = .distantPast }
        preferences = next; preferences.revision += 1
        unviewedCompletionProfiles.formIntersection(next.enabled && (next.completionAlerts || next.attentionAlerts) ? nextMonitored : [])
        for id in previousMonitored.symmetricDifference(nextMonitored) {
            trackers.removeValue(forKey:id)
            completionBatches.removeValue(forKey:id)
            if !nextMonitored.contains(id) { snapshots[id]?.sessions=[] }
        }
        snapshots=snapshots.filter { id,_ in next.profiles.contains { $0.id==id } }
        if !(next.enabled && nextMonitored.contains("deepseek")) && !(next.quotaDisplayEnabled && next.primaryID == "deepseek") { snapshots["deepseek"] = nil }
        defaults.set(try JSONEncoder().encode(preferences), forKey: "preferences")
        saveStatusPolicy()
        themeSource.replace(selectedSkin.theme)
        if let lastAlertProfile, !preferences.isMonitoring(lastAlertProfile) {
            activities?.end("agent-alert"); lastAlert = ""; self.lastAlertProfile = nil
        }
        pendingNotices.removeAll { !allowsNotice($0) }
        if let notice=completionNotice, !allowsNotice(notice) { finishNotice(notice.id) }
        if !preferences.enabled || !preferences.completionAlerts { completionBatches=[:] }
        if !preferences.enabled {
            activities?.end("agent-alert"); activityPrimary = ""
            if !preferences.quotaDisplayEnabled { activities?.end("agent-status") }
        } else {
            if !previousEnabled { trackers = [:]; lastQuotaAttempt = .distantPast }
            updateActivity(); Task { await connectSelectedStatuses(); await poll() }
            if previousVisible != preferences.visibleIDs { checkQuotaAlerts() }
        }
        if previousQuotaDisplay != preferences.quotaDisplayEnabled || previousPrimary != preferences.primaryID { lastQuotaAttempt = .distantPast; activityPrimary = "" }
        if let notice=primarySwitchNotice, notice.profileID != primary.id || !preferences.visibleIDs.contains(notice.profileID) {
            primarySwitchTask?.cancel();primarySwitchNotice=nil
        }
        updateActivity()
        if preferences.quotaDisplayEnabled { Task { await poll() } }
    }
    private func saveStatusPolicy() {
        guard preferencesReadError == nil, Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview", !IslandRuntime.isSkinPreview else { return }
        do { try AgentHookPolicy.save(enabled: preferences.enabled, visibleIDs: preferences.activeMonitorIDs) }
        catch { lastAlert = "状态事件开关未能保存，请重试。" }
    }
    private func connectSelectedStatuses() async {
        guard allowsLiveReads, !sessionIsLocked(), preferences.enabled else { return }
        for id in preferences.activeMonitorIDs where ["claude", "workbuddy"].contains(id) {
            guard !sessionIsLocked(), preferences.isMonitoring(id) else { return }
            let installed=await AgentStatusConnection.install(id)
            guard !sessionIsLocked(), preferences.isMonitoring(id) else { return }
            if !installed {
                var value = snapshots[id] ?? .init()
                value.detail = "状态提醒配置未完成，请在 Agent 状态设置重试。"; snapshots[id] = value
            }
        }
    }
    func connectStatus(_ id: String) {
        guard ["claude", "workbuddy"].contains(id) else { return }
        var next = preferences; next.enabled = true
        if !next.activeMonitorIDs.contains(id) { next.monitoredIDs=next.activeMonitorIDs+[id] }
        if !next.visibleIDs.contains(id), next.visibleIDs.count<3 { next.visibleIDs.append(id) }
        try? update(next)
    }
    func monitorSelected(_ id:String) {
        guard preferences.enabled,["codex","claude","workbuddy"].contains(id),!preferences.activeMonitorIDs.contains(id) else { return }
        var next=preferences;next.monitoredIDs=next.activeMonitorIDs+[id];try? update(next)
    }
    func selectPrimary(_ id: String) {
        guard id != preferences.primaryID, preferences.visibleIDs.contains(id) else { return }
        var next = preferences; next.primaryID = id
        do { try update(next) } catch { lastAlert=error.localizedDescription;return }
        guard !sessionIsLocked() else { return }
        let notice=AgentPrimarySwitchNotice(profileID:primary.id,name:primary.name)
        primarySwitchTask?.cancel();primarySwitchNotice=notice;updateActivity()
        primarySwitchTask=Task { @MainActor [weak self] in
            do { try await Task.sleep(for:.seconds(4)) } catch { return }
            guard let self,self.primarySwitchNotice?.id==notice.id else { return }
            self.primarySwitchNotice=nil;self.updateActivity()
        }
    }
    func selectSkin(_ id: String) {
        var next = preferences; next.skinID = id; try? update(next)
    }
    func setEffectsEnabled(_ value: Bool) {
        var next = preferences; next.effectsEnabled = value; try? update(next)
    }
    func poll() async {
        guard !sessionIsLocked() else { handleSessionLock(); return }
        guard allowsLiveReads, !IslandRuntime.isSkinPreview, preferences.enabled || preferences.quotaDisplayEnabled, !polling else { return }
        // Quota-only mode never attaches to local conversations.
        if !preferences.enabled {
            updateActivity()
            if Date().timeIntervalSince(lastQuotaAttempt) >= 180 { refreshQuotas() }
            return
        }
        polling = true; defer { polling = false }
        let revision = preferences.revision
        // A large Codex history must not delay the other providers or quota reads.
        if Date().timeIntervalSince(lastQuotaAttempt) >= 180 { refreshQuotas() }
        let monitorCodex = preferences.activeMonitorIDs.contains("codex")
        let monitorWork = preferences.activeMonitorIDs.contains("workbuddy")
        let monitorClaude = preferences.activeMonitorIDs.contains("claude")
        async let codexSessions: [AgentSession] = monitorCodex ? codex.sessions(now: Date()) : []
        async let workResult: Result<[AgentSession], Error> = Task.detached { Result { monitorWork ? try WorkBuddyReader.sessions(now: Date().timeIntervalSince1970) : [] } }.value
        async let claudeSnapshot: AgentSnapshot = Task.detached { monitorClaude ? ClaudeDesktopReader.snapshot(now: Date().timeIntervalSince1970) : AgentSnapshot() }.value
        let work = await workResult
        let claude = await claudeSnapshot
        guard !sessionIsLocked(), preferences.enabled, preferences.revision == revision else { return }
        var received: [String:AgentSnapshot]=[:]
        var workValue = snapshots["workbuddy"] ?? .init(source: "WorkBuddy本机任务＋客户端积分接口", detail: "打开WorkBuddy并开始新任务后显示状态。")
        switch work {
        case .success(let sessions): workValue.sessions = sessions
        case .failure(let error): workValue.sessions = []; workValue.detail = error.localizedDescription
        }
        received["workbuddy"] = workValue
        received["claude"] = claude
        for profile in preferences.profiles where profile.kind == "file" && preferences.activeMonitorIDs.contains(profile.id) {
            let result = await Task.detached { Result { try CustomAgentReader.read(profile) } }.value
            guard !sessionIsLocked(), preferences.enabled, preferences.revision == revision else { return }
            switch result {
            case .success(let value): received[profile.id] = value
            case .failure(let error): var value = snapshots[profile.id] ?? .init(); value.detail = String(error.localizedDescription.prefix(1000)); received[profile.id] = value
            }
        }
        ingestSnapshots(received,now:Date().timeIntervalSince1970)
        let sessions = await codexSessions
        guard !sessionIsLocked(), preferences.enabled, preferences.revision == revision else { return }
        var codexValue = snapshots["codex"] ?? .init(source: "Codex本机事件＋官方额度接口", detail: "仅监测这台Mac保存的Codex任务。")
        codexValue.sessions = sessions
        ingestSnapshots(["codex":codexValue],now:Date().timeIntervalSince1970)
    }
    /// All readers enter through this gate so a lock or monitoring change cannot consume an alert.
    func ingestSnapshots(_ values: [String:AgentSnapshot], now: Double) {
        guard !sessionIsLocked(), preferences.enabled else { return }
        for (id,value) in values where preferences.isMonitoring(id) && value.validationError == nil { snapshots[id]=value }
        for profile in preferences.profiles where preferences.isMonitoring(profile.id) && values[profile.id]?.validationError == nil && values[profile.id] != nil {
            var tracker = trackers[profile.id] ?? .init()
            let sessions=snapshots[profile.id]?.sessions ?? []
            let started = tracker.starts(sessions, now: now)
            let count = tracker.completions(sessions, now: now)
            let attention=tracker.attentionRequests(sessions,now:now)
            trackers[profile.id] = tracker
            if started > 0, preferences.startAlerts, preferences.activeMonitorIDs.contains(profile.id) {
                presentCompletion(profileID: profile.id, count: started, stillWorking: true, attention: "running")
            }
            if preferences.completionAlerts, preferences.activeMonitorIDs.contains(profile.id) {
                var batch=completionBatches[profile.id] ?? .init()
                let settled=batch.ingest(count:count,sessions:sessions,now:now)
                completionBatches[profile.id]=batch
                if settled > 0 { presentCompletion(profileID:profile.id,count:settled,stillWorking:false) }
            }
            if let pending=attention.first,preferences.attentionAlerts,preferences.activeMonitorIDs.contains(profile.id) {
                presentCompletion(profileID:profile.id,count:attention.count,stillWorking:false,attention:pending.attentionReason ?? "approval")
            }
        }
        updateActivity()
        checkQuotaAlerts(now:now)
    }
    func refreshQuotas() {
        guard !sessionIsLocked() else { handleSessionLock(); return }
        guard allowsLiveReads, !IslandRuntime.isSkinPreview, preferences.enabled || preferences.quotaDisplayEnabled, !refreshing, Date().timeIntervalSince(lastQuotaAttempt) >= 5 else { return }
        refreshing = true; lastQuotaAttempt = Date()
        let codexEnabled = (preferences.quotaDisplayEnabled && preferences.primaryID == "codex") || (preferences.enabled && preferences.activeMonitorIDs.contains("codex"))
        let workEnabled = (preferences.quotaDisplayEnabled && preferences.primaryID == "workbuddy") || (preferences.enabled && preferences.activeMonitorIDs.contains("workbuddy"))
        let deepSeekEnabled = (preferences.quotaDisplayEnabled && preferences.primaryID == "deepseek") || (preferences.enabled && preferences.activeMonitorIDs.contains("deepseek"))
        let revision = preferences.revision
        let fileProfile = preferences.quotaDisplayEnabled ? preferences.profiles.first{$0.id==preferences.primaryID && $0.kind=="file"}:nil
        Task {
            async let codexResult: Result<[AgentQuota], Error> = Self.readCodexQuota(enabled: codexEnabled)
            async let workResult: Result<[AgentQuota], Error> = Task.detached { Result { workEnabled ? try WorkBuddyReader.quotas(now: Date().timeIntervalSince1970) : [] } }.value
            async let deepSeekResult: Result<AgentSnapshot, Error> = Task.detached { Result { deepSeekEnabled ? try DeepSeekReader.snapshot() : AgentSnapshot() } }.value
            let balance = await deepSeekResult
            if deepSeekEnabled, !sessionIsLocked(), preferences.revision == revision {
                switch balance {
                case .success(let snapshot): snapshots["deepseek"] = snapshot
                case .failure(let error): snapshots["deepseek"] = AgentSnapshot(source: "DeepSeek Harness 账户余额", detail: error.localizedDescription)
                }
            }
            let results = await [("codex", codexResult), ("workbuddy", workResult)]
            defer { refreshing = false }
            guard !sessionIsLocked(), preferences.enabled || preferences.quotaDisplayEnabled, preferences.revision == revision else { return }
            for (id, result) in results {
                guard id == "codex" ? codexEnabled : workEnabled else { continue }
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
            if let fileProfile, !preferences.isMonitoring(fileProfile.id) {
                let result=await Task.detached {Result {try CustomAgentReader.read(fileProfile)}}.value
                guard !sessionIsLocked(),preferences.revision==revision else{return}
                if case .success(let value)=result {var quotaOnly=value;quotaOnly.sessions=[];snapshots[fileProfile.id]=quotaOnly}
            }
            if preferences.isMonitoring("claude") {
                let value=await Task.detached { ClaudeDesktopReader.snapshot(now: Date().timeIntervalSince1970) }.value
                guard !sessionIsLocked(), preferences.revision==revision else { return }
                snapshots["claude"]=value
            }
            if preferences.enabled { checkQuotaAlerts() }
        }
    }
    nonisolated private static func readCodexQuota(enabled: Bool) async -> Result<[AgentQuota], Error> {
        guard enabled else { return .success([]) }; do { return .success(try await CodexReader.quotas()) } catch { return .failure(error) }
    }
    private func checkQuotaAlerts(now: Double = Date().timeIntervalSince1970) {
        guard !sessionIsLocked(), preferences.enabled, preferences.quotaAlerts else { return }
        for profile in preferences.profiles.filter({preferences.activeMonitorIDs.contains($0.id)}) where profile.kind != "claude" {
            let low = quotaTracker.lowQuotas(snapshots[profile.id]?.quotas ?? [], profile: profile.id, now: now)
            if let quota = low.min(by: { $0.remainingPercent < $1.remainingPercent }) {
                alert("\(profile.name) · \(quota.label)剩余\(String(format: "%.1f", quota.remainingPercent))%", profileID: profile.id)
            }
        }
        defaults.set(Array(quotaTracker.notifiedQuotaCycles.suffix(200)), forKey: "notifiedQuotaCycles")
    }
    private func updateActivity() {
        guard !sessionIsLocked() else { handleSessionLock(); return }
        guard completionNotice != nil || primarySwitchNotice != nil || (preferences.enabled && !preferences.visibleIDs.isEmpty) || preferences.quotaDisplayEnabled else { activities?.end("agent-status"); activityPrimary=""; return }
        let key=primary.id+"/"+String(preferences.quotaDisplayEnabled)+"/"+String(preferences.enabled)+"/"+(completionNotice?.id.uuidString ?? "idle")+"/"+(primarySwitchNotice?.id.uuidString ?? "idle")
        guard activityPrimary != key else { return }; activityPrimary=key
        var activity = NookLiveActivity(id:"agent-status",priority:completionNotice == nil && primarySwitchNotice == nil ? .low:.high,accessibilityLabel:primarySwitchNotice?.message ?? completionNotice?.message ?? (preferences.quotaDisplayEnabled ? primary.name+"剩余额度" : "Agent状态")) {
            AgentPersistentCompactSlot(store:self,leading:true)
        } compactTrailing: {
            AgentPersistentCompactSlot(store:self,leading:false)
        } minimal: { AgentCompanionGlyph(store:self) }
        // Quota is content for the revealed pill, not a permanent reveal request.
        // Explicit selection feedback and task notices reveal briefly, without collapsing a locked/input panel.
        activity.keepsCompactVisible = completionNotice != nil || primarySwitchNotice != nil
        activity.setExpanded { AgentPersistentExpanded(store:self) }
        activities?.start(activity)
    }
    private func presentCompletion(profileID: String, count: Int, stillWorking: Bool, attention:String? = nil) {
        guard !sessionIsLocked(), preferences.isMonitoring(profileID), let profile=preferences.profiles.first(where:{$0.id==profileID}) else { return }
        if attention != "running" { unviewedCompletionProfiles.insert(profileID) }
        let notice=AgentCompletionNotice(profileID:profileID,name:profile.name,count:count,stillWorking:stillWorking,attention:attention)
        enqueueNotice(notice)
    }
    private func enqueueNotice(_ notice:AgentCompletionNotice) {
        if let material = preferences.completionScreenMaterialID, allowsLiveReads, !IslandRuntime.isSkinPreview, !sessionIsLocked() {
            do {
                let request = try WorkspaceStore.shared.screenReminderRequest(style: ScreenReminderStyle(materialID: material), title: notice.message)
                try ScreenReminderPresenter.shared.present(request)
                lastAlert = notice.message
                return
            } catch { lastAlert = "屏幕动效暂不可用，已改用灵动岛提醒。" }
        }
        // Status and quota notices have separate slots, so neither can consume the other.
        if let current=completionNotice, current.profileID != notice.profileID || current.isQuota != notice.isQuota {
            if let index=pendingNotices.firstIndex(where:{$0.profileID==notice.profileID && $0.isQuota==notice.isQuota}) { pendingNotices[index]=notice }
            else { pendingNotices.append(notice) }
        } else { showNotice(notice) }
    }
    private func allowsNotice(_ notice:AgentCompletionNotice) -> Bool {
        preferences.isMonitoring(notice.profileID) && (notice.isQuota ? preferences.quotaAlerts : notice.attention == "running" ? preferences.startAlerts : notice.attention != nil ? preferences.attentionAlerts : preferences.completionAlerts)
    }
    private func showNotice(_ notice:AgentCompletionNotice) {
        completionTask?.cancel()
        primarySwitchTask?.cancel();primarySwitchNotice=nil
        lastAlert=notice.message;lastAlertDate=Date();lastAlertProfile=notice.profileID
        completionNotice=notice
        updateActivity()
        completionTask=Task { @MainActor [weak self] in
            do { try await Task.sleep(for:.seconds(6)) } catch { return }
            self?.finishNotice(notice.id)
        }
    }
    func finishNotice(_ id:UUID) {
        guard completionNotice?.id==id else {return}
        completionTask?.cancel();completionNotice=nil;activityPrimary=""
        guard !sessionIsLocked() else {pendingNotices=[];updateActivity();return}
        pendingNotices.removeAll { !allowsNotice($0) }
        if !pendingNotices.isEmpty { showNotice(pendingNotices.removeFirst()) }
        else {updateActivity()}
    }
    func acknowledgeCompletions() {
        guard !unviewedCompletionProfiles.isEmpty else { return }
        unviewedCompletionProfiles.removeAll()
    }
    func handleSessionLock() {
        primarySwitchTask?.cancel();primarySwitchNotice=nil
        completionTask?.cancel(); completionNotice=nil; pendingNotices=[]; activityPrimary=""
        activities?.end("agent-alert"); activities?.end("agent-status")
    }

    var hasLowQuota: Bool {
        !lowQuotaMessages.isEmpty
    }
    var lowQuotaMessages: [String] {
        lowQuotaAlerts.map(\.message)
    }
    var lowQuotaAlerts: [(id: String, message: String)] {
        guard !sessionIsLocked(), preferences.enabled, preferences.quotaAlerts else { return [] }
        let now = Date().timeIntervalSince1970
        return preferences.profiles.filter { preferences.activeMonitorIDs.contains($0.id) && $0.kind != "claude" }.flatMap { profile in
            (snapshots[profile.id]?.quotas ?? []).filter {
                $0.isFresh(now: now) && $0.remainingPercent < 20
            }.map { quota in
                (id: "quota:\(profile.id):\(quota.id):\(quota.resetsAt.map(String.init(describing:)) ?? "pool")",
                 message: "\(profile.name) · \(quota.label)剩余\(String(format: "%.1f", quota.remainingPercent))%（低于20%）")
            }
        }
    }
    private func alert(_ message:String,profileID:String) {
        guard !sessionIsLocked(),preferences.isMonitoring(profileID),preferences.quotaAlerts,
              let profile=preferences.profiles.first(where:{$0.id==profileID}) else{return}
        enqueueNotice(AgentCompletionNotice(profileID:profileID,name:profile.name,count:0,stillWorking:false,attention:"quota",quotaMessage:message))
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
    @discardableResult func openAgent(_ id: String) -> Bool {
        if id == "deepseek", let app = DeepSeekReader.application { return NSWorkspace.shared.open(app) }
        guard ["codex","claude","workbuddy"].contains(id) else { return false }
        let candidates = id == "claude" ? ["/Applications/Claude.app"] : id == "workbuddy" ? ["/Applications/WorkBuddy.app"] : ["/Applications/ChatGPT.app", "/Applications/Codex.app"]
        if let path = candidates.first(where: FileManager.default.fileExists(atPath:)) { return NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        return false
    }
    func webSnapshot() -> [String: Any] {
        let now = Date().timeIntervalSince1970
        let states: [String: Any] = Dictionary(uniqueKeysWithValues: snapshots.map { id, value in
            (id, ["state": state(for:id,now:now).rawValue, "stateLabel": preferences.isMonitoring(id) ? state(for:id,now:now).label : "监测已暂停",
             "source": value.source, "detail": value.detail,
             "statusConnected": preferences.isMonitoring(id) && (["claude","workbuddy"].contains(id) ? AgentStatusConnection.isConfigured(id) : true),
             "activeCount": preferences.isMonitoring(id) ? value.sessions.filter { $0.state == .working && now - $0.updatedAt < 900 }.count : 0,
             "quotas": value.quotas.map { quota -> [String: Any] in
                 ["id": quota.id, "label": quota.label, "remainingPercent": quota.remainingPercent, "resetsAt": quota.resetsAt as Any? ?? NSNull(), "updatedAt": quota.updatedAt, "fresh": quota.isFresh(now: now), "remainingUnits": quota.remainingUnits as Any? ?? NSNull(), "totalUnits": quota.totalUnits as Any? ?? NSNull()]
             }, "metrics":value.metrics.map { metric -> [String:Any] in
                 ["id":metric.id,"label":metric.label,"value":metric.value,"unit":metric.unit,"updatedAt":metric.updatedAt,"fresh":metric.isFresh(now:now)]
             }] as [String: Any])
        })
        return ["surfaceWindowNumber":IslandModuleNavigation.shared.surfaceWindowNumber as Any? ?? NSNull(),"preferences": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences))) ?? [:], "agents": states, "refreshing": refreshing, "lastAlert": lastAlert, "threshold": 20]
    }
}
