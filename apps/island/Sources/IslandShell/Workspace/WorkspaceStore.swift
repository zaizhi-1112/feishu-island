import AppKit
import Foundation

@MainActor
final class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore(root: IslandRuntime.isSkinPreview ? FileManager.default.temporaryDirectory.appendingPathComponent("island-skin-workspace-"+UUID().uuidString) : Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.dot-sandbox" ? Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("workspace") : Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview" ? nil : FileManager.default.temporaryDirectory.appendingPathComponent("island-workspace-fixture-"+UUID().uuidString))
    @Published var todoDraft = ""
    @Published var todoPage = "tasks" { didSet { if todoPage == "calendar" { hasUnviewedScheduleReminder = false } } }
    @Published var hasUnviewedScheduleReminder = false
    @Published private(set) var disk = WorkDisk()
    @Published var error = ""
    @Published var selected: UUID?
    @Published var boardTab = 0
    @Published var draftText = "" {
        didSet { if oldValue != draftText { webPages=[]; webInput=nil; if draftText.isEmpty { chromeDraft=false } } }
    }
    @Published var chromeImportEnabled = false {
        didSet { if oldValue != chromeImportEnabled { _ = mutate { $0.chromeImportEnabled=chromeImportEnabled } } }
    }
    @Published var readWebLinks = false {
        didSet { if oldValue != readWebLinks { _ = mutate { $0.readWebLinks=readWebLinks }; webPages=[]; webInput=nil } }
    }
    @Published var webPages: [WorkWebPage] = []
    @Published var webBusy = false
    var webInput: String?
    @Published var chromeDraft = false
    @Published var draftProject = "日常工作"
    @Published var draftRecipe = "work"
    @Published var draftReminderMinutes = 20
    @Published var draftScreenReminder: ScreenReminderStyle?
    @Published var draftArchive = WorkArchiveTarget(mode:"new")
    @Published var draftFiles: [URL] = []
    @Published var archiveFields: [String] = []
    @Published var archiveFieldsBusy = false
    var archiveBusy = false
    @Published var draftService = "codex" {
        didSet {
            guard ["codex","doubao","dot","workbuddy"].contains(draftService), draftService != oldValue else { return }
            _ = mutate { $0.preferredService = draftService }
        }
    }
    @Published var editingID: UUID?
    @Published var editTitle = ""
    @Published var editInput = ""
    @Published var editInstruction = ""
    @Published var editProject = ""
    @Published var draftImages: [PendingWorkImage] = []
    @Published var accepted = 0
    var acceptedAt = Date.distantPast
    @Published var ingestActive = false
    @Published var ingestSaving = false
    @Published var hub = HubSnapshot()
    var notify: (String) -> Void = { _ in }
    var agentNotice: (String,String,String) -> Void = { _,_,_ in }
    var dotQueued: () -> Void = {}
    var openBoard: () -> Void = {}
    /// Tests replace this callback; isolated stores never create an on-screen renderer.
    var presentScreenReminder: (ScreenReminderRequest) -> Void = { _ in }
    /// Synthetic stores do not query the user's lock state; the live store binds it below.
    var remindersAreLocked: () -> Bool = { false }
    private let root: URL
    var runner: (any WorkRunning)?
    var job: Task<Void,Never>?
    var cancelledJobs: Set<UUID> = []
    private var timer: Timer?
    private var screenTimer: Timer?
    private var restObservers:[NSObjectProtocol]=[]
    var restSleeping=false
    var calendarTimer: Timer?
    var calendarObservers: [NSObjectProtocol] = []
    var calendarVerifiedAt: Date?
    @Published var calendarStatus = "未连接飞书日历"
    @Published var calendarSyncing = false
    @Published var scheduleNow = Date()
    var integrationEnabled = false
    private var activity: NSObjectProtocol?
    private var writable = true
    var hubBusy = false
    var lastHubRefresh = Date.distantPast
    let hubClient: HubClient
    init(root: URL? = nil, startTimers: Bool = true, hubClient: HubClient? = nil) {
        self.root = root ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FeishuIsland/Workspace")
        self.hubClient = hubClient ?? HubClient()
        do {
            try FileManager.default.createDirectory(at:self.root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:self.root.path)
            let file = self.root.appendingPathComponent("workspace.json")
            if FileManager.default.fileExists(atPath:file.path) { disk = try JSONDecoder().decode(WorkDisk.self,from:Data(contentsOf:file)) }
            if let service=disk.preferredService, ["codex","doubao","dot","workbuddy"].contains(service) { draftService=service }
            readWebLinks = disk.readWebLinks ?? false
            chromeImportEnabled = disk.chromeImportEnabled ?? false
            draftArchive = disk.archiveTarget ?? WorkArchiveTarget(mode:"new")
            draftReminderMinutes = disk.reminderMinutes
            if !disk.recipes.contains(where:{$0.id == "work"}) { disk.recipes.insert(WorkRecipe.presets.first(where:{$0.id == "work"})!,at:0) }
            for i in disk.items.indices {
                if ["running","queued","dot_running"].contains(disk.items[i].state) {
                    // Keep the legacy claim and result as history without resuming it.
                    disk.items[i].state = "interrupted"; disk.items[i].failure = "旧处理任务已停止；保留原记录，可作为待办继续编辑或完成。"
                }
                if ["running", "pending"].contains(disk.items[i].archive?.state ?? "") {
                    disk.items[i].archive?.state = "failed"
                    disk.items[i].archive?.error = disk.items[i].archive?.intent == nil
                        ? "旧归档队列已停止，原回执保留，可继续编辑本机待办。"
                        : "旧归档写入结果待核对，原回执保留，不自动重复写入。"
                }
            }
            if var trash=disk.trash {
                for i in trash.indices where ["running","pending"].contains(trash[i].archive?.state ?? "") {
                    let hasNoIntent=trash[i].archive?.intent == nil
                    trash[i].archive?.state="failed"
                    trash[i].archive?.error=hasNoIntent
                        ? "旧归档队列已停止，原回执保留，恢复后可编辑本机待办。"
                        : "旧归档写入结果待核对，原回执保留，不自动重复写入。"
                }
                disk.trash=trash
            }
            migrateExistingTodoCompletions()
            try save()
        } catch { self.writable = false; self.error = "本机工作区未能载入或保存；原文件保留，已停止写入。" }
        integrationEnabled = startTimers && !IslandRuntime.isSkinPreview && !ProcessInfo.processInfo.arguments.contains("--self-test") && Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview"
        if integrationEnabled {
            startFeishuScheduleSync()
            importLegacyTodosIfNeeded()
            remindersAreLocked = { ScreenReminderSession.isLocked }
            restObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main){[weak self] _ in Task{@MainActor in self?.restSleeping=true;self?.tickRest(away:true)}})
            restObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main){[weak self] _ in Task{@MainActor in self?.restSleeping=false;self?.tickRest(away:ScreenReminderSession.isLocked)}})
            if restPlan.systemPaused {changeRest{$0.setAway(ScreenReminderSession.isLocked,now:Date())}}

            ScreenReminderPresenter.shared.deliveryFailed = { [weak self] request,issue in
                self?.error=issue.localizedDescription
                self?.notify("屏幕提醒未能播放 · "+request.title)
            }
            presentScreenReminder = { [weak self] request in
                guard self?.remindersAreLocked() == false else { return }
                do { try ScreenReminderPresenter.shared.present(request) }
                catch {
                    self?.error = error.localizedDescription
                    self?.notify("冲屏素材暂不可用 · "+request.title)
                }
            }
            activity = ProcessInfo.processInfo.beginActivity(options:.userInitiatedAllowingIdleSystemSleep,reason:"接收飞书与处理本人后台任务")
            timer = Timer.scheduledTimer(withTimeInterval:15,repeats:true) { [weak self] _ in Task { @MainActor in self?.tick() } }
            // Only reminders need a seconds-level countdown; the existing AI/archive/
            // hub timer and all Feishu receiver settings retain their old cadence.
            screenTimer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in Task { @MainActor in self?.tickReminders() } }
            if let timer { RunLoop.main.add(timer, forMode: .common) }
            if let screenTimer { RunLoop.main.add(screenTimer, forMode: .common) }
            Task { await refreshHub() }
        }
    }
    private func save() throws {
        let file = root.appendingPathComponent("workspace.json")
        try JSONEncoder().encode(disk).write(to:file,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    }
    var todoStorageRoot: URL { root }
    func mutate(_ change: (inout WorkDisk) -> Void) -> Bool {
        guard writable else { error = "原工作区文件无法读取，已停止写入以保留原文件。"; return false }
        let old = disk; change(&disk)
        do { try save(); error = ""; return true } catch { disk = old; self.error = "保存失败，操作未生效。请检查磁盘空间。"; return false }
    }
    func tick(now: Date = Date()) {
        // The unified product monitors Agents; it no longer dispatches or resumes
        // legacy material/AI/archive work. Old records remain available on disk.
        tickReminders(now:now)
        if integrationEnabled && now.timeIntervalSince(lastHubRefresh) > 600 { Task { await refreshHub() } }
    }
}
