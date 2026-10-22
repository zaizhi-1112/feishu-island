import AppKit
import NookApp
import SwiftUI

@MainActor
public final class FeishuStore: ObservableObject {
    @Published public private(set) var messages: [FeishuMessage] = []
    @Published private(set) var readingID: String?
    private(set) var readingQueue: [String] = []
    private(set) var readingAccepted = 0
    private(set) var readingPages: [String: Int] = [:]
    var onOpenReader: () -> Void = {}
    var onCloseReader: () -> Void = {}
    @Published public private(set) var status = "正在连接飞书…"
    @Published public private(set) var account = "本机账号"
    @Published public private(set) var enabled: Bool
    @Published public private(set) var mutedUntil: Date?
    @Published public private(set) var followed: Set<String>
    @Published var actionError: String?
    @Published public private(set) var rules: FeishuReminderRules
    @Published public private(set) var customRules: FeishuCustomRules
    public private(set) var settingsRevision: Int
    private let defaults: UserDefaults
    private var reader: AccountReader
    public let playback: DanmuPlayback
    @Published public private(set) var danmu: DanmuOptions
    @Published public private(set) var connection: FeishuConnection
    var appearance: [String:Any]
    var allowsDirectoryLookup: Bool { live }

    private var activities: NookLiveActivities?
    private var timer: Timer?
    private var pendingAlert: Task<Void, Never>?
    private var lastAlert = Date.distantPast
    private var pendingCount = 0
    var canAlert: () -> Bool = { true }
    private let live: Bool
    private var started = false

    public init(defaults: UserDefaults, live: Bool = false, receivingDefault: Bool = true, headlessRenderer: Bool? = nil) {
        self.defaults = defaults; self.live = live
        rules = defaults.data(forKey: "reminderRules").flatMap { try? JSONDecoder().decode(FeishuReminderRules.self, from: $0) } ?? .init()
        customRules = defaults.data(forKey: "customRules").flatMap { try? JSONDecoder().decode(FeishuCustomRules.self, from: $0) } ?? .init()
        settingsRevision = defaults.integer(forKey: "settingsRevision")
        enabled = defaults.object(forKey: "enabled") as? Bool ?? receivingDefault
        danmu = defaults.data(forKey: "danmu").flatMap { try? JSONDecoder().decode(DanmuOptions.self, from: $0) } ?? .init()
        let initialConnection = defaults.data(forKey:"connection").flatMap { try? JSONDecoder().decode(FeishuConnection.self,from:$0) }.flatMap { $0.valid ? $0 : nil } ?? .init()
        connection = initialConnection
        appearance = defaults.data(forKey:"danmuAppearance").flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:Any] }.flatMap(AppearanceMCP.validate) ?? AppearanceMCP.defaults
        playback = DanmuPlayback(headless: headlessRenderer ?? !live)
        followed = Set(defaults.stringArray(forKey: "followed") ?? [])
        let mute = defaults.double(forKey: "mutedUntil")
        mutedUntil = mute > Date().timeIntervalSince1970 ? Date(timeIntervalSince1970: mute) : nil
        reader = AccountReader(cli:URL(fileURLWithPath:initialConnection.cliPath),profile:initialConnection.profile)
        wireReader()
        playback.configure(danmu,appearance:appearance)
        if !enabled { status = "接收已停止" }
    }

    #if DEBUG
    func startSyntheticReader(_ input: AccountReader) {
        precondition(!live, "Synthetic checks must never replace a live account")
        reader.stop(); reader = input; wireReader(); reader.start()
    }
    #endif
    private func wireReader() {
        reader.onMessage = { [weak self] in self?.receive($0) }
        reader.onStatus = { [weak self] in self?.status = $0 }
        reader.onAccount = { [weak self] in self?.account = $0 }
        playback.checkUnread = { [weak self] id, completion in
            guard let self, self.enabled else { completion(false); return }
            if self.messages.first(where: { $0.id == id })?.viewed == true { completion(false); return }
            if self.live { self.reader.checkUnread(id,completion:completion) } else { completion(true) }
        }
    }
    @discardableResult
    public func updateConnection(_ value: FeishuConnection) -> Bool {
        guard value.valid else { return false }
        if value == connection { return true }
        reader.stop(); enabled = false; defaults.set(false,forKey:"enabled")
        playback.resetAccount(); messages.removeAll(); pendingAlert?.cancel(); pendingAlert = nil; pendingCount = 0; activities?.end("messages")
        closeReader(); readingAccepted = 0; readingPages.removeAll()
        // Session-specific rules must never follow a different account.
        followed.removeAll(); customRules = .init(); defaults.removeObject(forKey:"followed"); defaults.removeObject(forKey:"customRules")
        connection = value; defaults.set(try? JSONEncoder().encode(value),forKey:"connection")
        reader = AccountReader(cli:URL(fileURLWithPath:value.cliPath),profile:value.profile); wireReader()
        status = "连接配置已保存，请先完成本人只读授权，再开始接收"; account = "尚未连接"; bumpSettingsRevision(); return true
    }
    public func updateDanmu(_ value: DanmuOptions) {
        guard value != danmu else { return }
        danmu = value
        defaults.set(try? JSONEncoder().encode(value), forKey: "danmu")
        playback.configure(value, appearance: appearance)
        bumpSettingsRevision()
    }
    @discardableResult
    func updateAppearance(_ input:[String:Any]) -> Bool {
        guard let value = AppearanceMCP.validate(input) else { return false }
        if NSDictionary(dictionary:appearance).isEqual(to:value) { return true }
        appearance = value; defaults.set(try? JSONSerialization.data(withJSONObject:value),forKey:"danmuAppearance")
        playback.configure(danmu,appearance:value); bumpSettingsRevision(); return true
    }
    public func playSynthetic() {
        let message = FeishuMessage(raw:["message_id":"demo_" + UUID().uuidString,"sender":["id":"ou_demo","sender_name":"合成示例"],"msg_type":"text","body":["content":"{\"text\":\"透明试播\"}"]],chatID:"oc_demo",chatName:"演示",chatKind:"p2p",ownID:"")
        receive(message)
    }
    func start(activities: NookLiveActivities) {
        self.activities = activities
        guard !started else { return }; started = true
        startReaderIfAllowed()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reader.stop() }
        }
    }
    public var isMuted: Bool { (mutedUntil ?? .distantPast) > Date() }
    public var visibleMessages: [FeishuMessage] { messages.filter { !customRules.blocks($0) } }
    public var important: [FeishuMessage] { messages.filter { $0.isImportant(followed: followed, rules: rules, custom: customRules) } }
    public var waitingCount: Int { important.filter { !$0.viewed && $0.remindAt == nil }.count }

    public func receive(_ message: FeishuMessage) {
        guard enabled, !customRules.blocks(message), !messages.contains(where: { $0.id == message.id }) else { return }
        messages.append(message)
        messages.sort { $0.created > $1.created }
        if messages.count > 100 {
            // A burst of new messages must not discard a reminder the user set.
            let reminders = messages.filter { $0.remindAt != nil || $0.id == readingID }
            let recent = messages.filter { $0.remindAt == nil && $0.id != readingID }.prefix(max(0, 100 - reminders.count))
            messages = (reminders + recent).sorted { $0.created > $1.created }
        }
        if message.isImportant(followed: followed, rules: rules, custom: customRules) {
            if !isMuted && !playback.suspended {
                // The island and desktop are independent outputs of one read-only event.
                // Opening the island must not suppress a short floating message.
                playback.enqueue(message)
                readingQueue = readingQueue.filter { id in messages.contains { $0.id == id } }
                readingQueue.append(message.id); readingAccepted += 1
                if readingID == nil { readingID = readingQueue.first; onOpenReader() }
            }
        }
    }
    func rememberReadingPage(_ page: Int, for id: String) {
        guard messages.contains(where: { $0.id == id }) else { return }
        readingPages = readingPages.filter { key, _ in messages.contains { $0.id == key } }
        readingPages[id] = max(0, page)
    }
    func openReader(_ id: String) {
        guard visibleMessages.contains(where: { $0.id == id }) else { return }
        if !readingQueue.contains(id) { readingQueue.insert(id, at: 0) }
        readingID = id; markViewed(id)
    }
    func closeReader() { readingID = nil; readingQueue.removeAll(); activities?.end("reading") }
    func finishReading() {
        guard let id = readingID else { return }
        markViewed(id); readingQueue.removeAll { $0 == id }
        readingQueue = readingQueue.filter { id in visibleMessages.contains { $0.id == id } }
        readingID = readingQueue.first
        if readingID == nil { activities?.end("reading"); onCloseReader() }
    }
    func presentReadingActivity() {
        var activity = NookLiveActivity(id: "reading", priority: .high, lifetime: .ongoing,
                                        alert: .expand(.seconds(5)), accessibilityLabel: "飞书消息阅读") {
            IslandCompactGlyph(symbol: "paperplane.fill")
        } compactTrailing: {
            Text("\(self.readingQueue.count)条").font(.system(size: 10))
        } minimal: { IslandCompactGlyph(symbol: "paperplane.fill") }
        activity.setExpanded { WorkspaceDropSurface(store:.shared) { FeishuView(store:self) } }
        activities?.start(activity)
    }
    var deliveryDiagnostics: [String: Any] {
        ["retained": messages.count, "important": important.count,
         "danmuAccepted": playback.accepted, "danmuQueued": playback.queued,
         "danmuVisible": playback.visible, "danmuPresented": playback.presented,
         "danmuSkippedRead": playback.skippedRead, "danmuUnreadRetries": playback.unreadRetries,
         "islandReadingAccepted": readingAccepted, "islandReadingPending": readingQueue.count,
         "suspended": playback.suspended, "islandCanAlert": canAlert()]
    }
    public func markViewed(_ id: String) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[i].viewed = true
    }
    public func toggleFollow(_ chatID: String) {
        if followed.contains(chatID) { followed.remove(chatID) } else { followed.insert(chatID) }
        defaults.set(Array(followed), forKey: "followed")
    }
    public func toggleMute() {
        mutedUntil = isMuted ? nil : Date().addingTimeInterval(3600)
        defaults.set(mutedUntil?.timeIntervalSince1970 ?? 0, forKey: "mutedUntil")
        pendingAlert?.cancel(); pendingAlert = nil; pendingCount = 0
        playback.clear(); activities?.end("messages")
        closeReader()
    }
    var receiveConflict: String? {
        guard live else { return nil }
        if legacyDanmuConflict(NSWorkspace.shared.runningApplications.compactMap { $0.executableURL?.path }) {
            return "检测到旧弹幕仍在运行。预览版暂不开启真实接收；可继续使用旧版或先看合成演示。"
        }
        return nil
    }
    private func startReaderIfAllowed() {
        guard live, enabled else { return }
        if let conflict = receiveConflict {
            reader.stop(); enabled = false; defaults.set(false,forKey:"enabled"); playback.clear(); status = conflict; actionError = conflict
        } else { reader.start() }
    }
    public func toggleReceiving() {
        if !enabled, let conflict = receiveConflict { actionError = conflict; status = conflict; return }
        enabled.toggle(); defaults.set(enabled, forKey: "enabled")
        bumpSettingsRevision()
        pendingAlert?.cancel(); pendingAlert = nil; pendingCount = 0
        if enabled {
            if live { startReaderIfAllowed() } else { status = "测试模式" }
        } else {
            reader.stop(); playback.clear(); activities?.end("messages")
            closeReader()
        }
    }
    private func bumpSettingsRevision() {
        settingsRevision += 1; defaults.set(settingsRevision, forKey: "settingsRevision")
    }
    public func updateSettings(enabled: Bool, rules: FeishuReminderRules, custom: FeishuCustomRules? = nil) {
        let nextCustom = custom ?? customRules
        guard nextCustom.validationError == nil else { return }
        if self.enabled != enabled { toggleReceiving() }
        guard self.rules != rules || customRules != nextCustom else { return }
        self.rules = rules
        customRules = nextCustom
        defaults.set(try? JSONEncoder().encode(nextCustom), forKey: "customRules")
        defaults.set(try? JSONEncoder().encode(rules), forKey: "reminderRules")
        bumpSettingsRevision()
        // A pending batch was selected using the old rules. Only future messages alert.
        pendingAlert?.cancel(); pendingAlert = nil; pendingCount = 0
        playback.clear(); activities?.end("messages")
        closeReader()
    }
    public func reconnect() {
        reader.stop(); playback.clear()
        startReaderIfAllowed()
    }
    public func remindLater(_ id: String, now: Date = Date()) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[i].remindAt = now.addingTimeInterval(600)
        messages[i].viewed = true
    }
    public func tick(now: Date = Date()) {
        if let until = mutedUntil, until <= now {
            mutedUntil = nil; defaults.removeObject(forKey: "mutedUntil")
            if waitingCount > 0 { queueAlert() }
        }
        for i in messages.indices where messages[i].remindAt.map({ $0 <= now }) == true {
            messages[i].remindAt = nil; messages[i].viewed = false; messages[i].reminded = true
            if enabled, !customRules.blocks(messages[i]) { queueAlert() }
        }
    }
    public func open(_ message: FeishuMessage) {
        guard let url = message.chatURL else { actionError = "缺少有效会话地址"; return }
        let targets = ["com.bytedance.macos.feishu", "com.bytedance.macos.lark", "com.electron.lark", "com.bytedance.Lark"]
        guard let app = targets.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first else {
            actionError = "未找到飞书客户端，请先安装并登录飞书。"; return
        }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            MainActor.assumeIsolated {
                if error == nil { self?.markViewed(message.id) }
                else { self?.actionError = "飞书未能打开会话，请在飞书中查找该会话。" }
            }
        }
    }
    private func queueAlert() {
        guard enabled, !isMuted, !playback.suspended, canAlert() else { return }
        pendingCount += 1
        guard pendingAlert == nil else { return }
        let wait = max(1, 12 - Date().timeIntervalSince(lastAlert))
        pendingAlert = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.pendingAlert = nil
            guard self.enabled, !self.isMuted, !self.playback.suspended, self.canAlert() else { self.pendingCount = 0; return }
            let count = self.pendingCount; self.pendingCount = 0
            self.lastAlert = Date()
            self.presentAlert(count: count)
        }
    }
    private func presentAlert(count: Int) {
        var activity = NookLiveActivity(id: "messages", priority: .high, lifetime: .transient(.seconds(8)),
                                        alert: .peek(.seconds(4)), accessibilityLabel: "飞书消息") {
            IslandCompactGlyph(symbol: "paperplane.fill")
        } compactTrailing: {
            IslandAlertLabel(count: count, expanded: false)
        } minimal: {
            IslandCompactGlyph(symbol: "paperplane.fill")
        }
        activity.setPeek {
            IslandAlertLabel(count: count, expanded: true)
        }
        // Keep the activity alive once opened so the timed alert cannot remove a reading view.
        activity.setExpanded {
            WorkspaceDropSurface(store:.shared) { FeishuView(store:self) }
                .onAppear { self.activities?.end("messages", after: .seconds(3600)) }
                .onDisappear { self.activities?.end("messages") }
        }
        activities?.start(activity)
    }
    func loadDemo() {
        status = "演示模式 · 未连接网络"; account = "示例账号"
        for (i, kind, content, mentioned) in [(1, "group", "@_user_1 这版方案我看过了，请帮忙确认最终时间。", true), (2, "p2p", "资料已经整理好了，方便时看一下。", false), (3, "group", "今天的会议纪要已更新。", false)] {
            let demoText = i == 1 ? String(repeating: content + "\n", count: 20) : content
            let body = String(data: try! JSONSerialization.data(withJSONObject: ["text": demoText]), encoding: .utf8)!
            receive(FeishuMessage(raw: ["message_id": "demo\(i)", "create_time": String(Int(Date().timeIntervalSince1970 * 1000) - i * 60000), "msg_type": "text", "sender": ["sender_name": i == 2 ? "小林" : "项目同事"], "body": ["content": body], "mentions": mentioned ? [["id": "demo_me", "name": "佑哥", "key": "@_user_1"]] : []], chatID: "demo_chat_\(i)", chatName: i == 2 ? "小林" : "项目讨论群", chatKind: kind, ownID: "demo_me"))
        }
    }
}
