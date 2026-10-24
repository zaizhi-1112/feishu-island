import AppKit
import Combine
import NookApp

struct TodoAttachment: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var relativePath: String
}

struct TodoItem: Codable, Equatable, Identifiable, Sendable {
    var id = UUID().uuidString
    var title: String
    var text = ""
    var link: URL?
    var attachments: [TodoAttachment] = []
    var createdAt: Date
    var dueAt: Date?
    var completedAt: Date?
    var notifiedAt: Date?
    var archivedAt: Date?

    var archiveExpiresAt: Date? { archivedAt?.addingTimeInterval(30 * 24 * 60 * 60) }
}

struct TodoPreferences: Codable, Equatable, Sendable {
    var revision = 0
    var defaultMinutes = 20
    var soundEnabled = true
}

struct TodoDocument: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var items: [TodoItem] = []
    var preferences = TodoPreferences()
    // Persist cleanup work so interrupted or failed attachment removal can retry safely.
    var attachmentCleanupIDs: [String]?
}

enum TodoFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

/// One atomic document contains both items and their delivered-reminder state.
@MainActor
final class TodoStore: ObservableObject {
    static let shared = TodoStore(directory: runtimeDirectory)
    static var runtimeDirectory: URL {
        let args = ProcessInfo.processInfo.arguments
        if (IslandRuntime.isSkinPreview || args.contains("--self-test")),
           let i = args.firstIndex(of: "--todo-test-root"), args.indices.contains(i + 1) {
            return URL(fileURLWithPath: args[i + 1], isDirectory: true)
        }
        let host: String
        if args.contains("--self-test") { host = "local.youzi.island.self-test" }
        else if IslandRuntime.isTodoPreview { host = "local.youzi.island.todo-preview" }
        else if IslandRuntime.isSkinPreview { host = "local.youzi.island.skin-preview" }
        else { host = Bundle.main.bundleIdentifier ?? "local.youzi.island.development" }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(host).appendingPathComponent("Modules").appendingPathComponent(IslandHost.todoID)
    }

    @Published private(set) var document: TodoDocument
    @Published var error: String?
    @Published private(set) var importingCount = 0
    @Published var savedID: String?
    @Published var selectedID: String?
    let directory: URL
    private(set) var loadFailed = false
    private let now: () -> Date
    private var nextAttachmentCleanup: Date?
    var onDue: (([TodoItem]) -> Void)?

    init(directory: URL, now: @escaping () -> Date = Date.init) {
        self.directory = directory; self.now = now
        do {
            let file = directory.appendingPathComponent("todos.json")
            if FileManager.default.fileExists(atPath: file.path) {
                let loaded = try JSONDecoder().decode(TodoDocument.self, from: Data(contentsOf: file))
                guard loaded.schemaVersion == 1, Set(loaded.items.map(\.id)).count == loaded.items.count else {
                    throw TodoFailure.invalid("待办数据版本不兼容或存在重复记录。")
                }
                self.document = loaded
            } else { self.document = TodoDocument() }
        } catch {
            document = TodoDocument(); loadFailed = true
            self.error = "待办数据读取失败，已保留原文件，请先恢复数据后重启。\(error.localizedDescription)"
        }
        purgeExpiredArchives()
    }

    var preferences: TodoPreferences { document.preferences }
    var pending: [TodoItem] {
        document.items.filter { $0.archivedAt == nil && $0.completedAt == nil }.sorted {
            if $0.dueAt != $1.dueAt { return ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            return $0.createdAt > $1.createdAt
        }
    }
    var completed: [TodoItem] { document.items.filter { $0.archivedAt == nil && $0.completedAt != nil }.sorted { $0.completedAt! > $1.completedAt! } }
    var archived: [TodoItem] {
        document.items.filter { $0.archivedAt != nil }.sorted { $0.archivedAt! > $1.archivedAt! }
    }
    func archiveDaysRemaining(_ item: TodoItem) -> Int {
        guard let expiry = item.archiveExpiresAt else { return 0 }
        return max(0, Int(ceil(expiry.timeIntervalSince(now()) / 86400)))
    }
    var overdueCount: Int { document.items.filter { $0.archivedAt == nil && $0.completedAt == nil && ($0.dueAt.map { $0 <= now() } ?? false) }.count }
    func item(_ id: String) -> TodoItem? { document.items.first { $0.id == id } }

    @discardableResult
    func capture(_ payload: NookDropPayload) async -> String? {
        guard !loadFailed else { error = "原待办数据读取失败，请恢复数据后重启；原文件已保留。"; return nil }
        importingCount += 1
        defer { importingCount -= 1 }
        let created = now()
        var item = TodoItem(title: "", createdAt: created, dueAt: created.addingTimeInterval(Double(preferences.defaultMinutes) * 60))
        var attachmentFolder: URL?
        do {
            switch payload {
            case .text(let value):
                let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw TodoFailure.invalid("请输入待办内容。") }
                item.text = text
                if let link = NookDropPayload.webURL(text) { item.link = link }
                item.title = String((text.components(separatedBy: .newlines).first ?? text).prefix(160))
            case .link(let url):
                guard NookDropPayload.webURL(url.absoluteString) != nil else { throw TodoFailure.invalid("仅支持网页链接。") }
                item.link = url; item.title = String(url.absoluteString.prefix(160))
            case .files(let urls):
                guard !urls.isEmpty else { throw TodoFailure.invalid("没有可保存的文件。") }
                let id = item.id, root = directory
                item.attachments = try await Task.detached(priority: .userInitiated) {
                    try Self.copyFiles(urls, id: id, root: root)
                }.value
                attachmentFolder = directory.appendingPathComponent("attachments/\(item.id)")
                item.title = urls.count == 1 ? urls[0].lastPathComponent : "\(urls[0].lastPathComponent)等\(urls.count)个文件"
            }
            var next = document; next.items.insert(item, at: 0)
            try commit(next)
            error = nil; savedID = item.id
            return item.id
        } catch {
            if let attachmentFolder { try? FileManager.default.removeItem(at: attachmentFolder) }
            self.error = "未能保存待办：\(error.localizedDescription)"
            return nil
        }
    }

    nonisolated private static func copyFiles(_ urls: [URL], id: String, root: URL) throws -> [TodoAttachment] {
        let fm = FileManager.default
        let staging = root.appendingPathComponent("staging/\(id)")
        let destination = root.appendingPathComponent("attachments/\(id)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            var attachments: [TodoAttachment] = []
            for url in urls {
                guard url.isFileURL else { throw TodoFailure.invalid("拖入的文件地址无效。") }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true, values.isAliasFile != true else {
                    throw TodoFailure.invalid("第一版只接收普通文件，暂不支持文件夹或替身：\(url.lastPathComponent)")
                }
                let attachmentID = UUID().uuidString
                let name = "\(attachmentID)-\(url.lastPathComponent)"
                try fm.copyItem(at: url, to: staging.appendingPathComponent(name))
                attachments.append(TodoAttachment(id: attachmentID, name: url.lastPathComponent, relativePath: "attachments/\(id)/\(name)"))
            }
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: staging, to: destination)
            return attachments
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    private func commit(_ next: TodoDocument) throws {
        guard !loadFailed else { throw TodoFailure.invalid("原待办数据未成功读取，暂不能覆盖。") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(next).write(to: directory.appendingPathComponent("todos.json"), options: .atomic)
        document = next
    }

    @discardableResult
    func update(_ id: String, title: String, dueAt: Date?) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { error = "待办名称不能为空。"; return false }
        return mutate(id) { item in
            item.title = title
            if item.dueAt != dueAt { item.dueAt = dueAt; item.notifiedAt = nil }
        }
    }
    @discardableResult
    func archive(_ id: String) -> Bool {
        let success = mutate(id) { if $0.archivedAt == nil { $0.archivedAt = now() } }
        if success {
            if selectedID == id { selectedID = nil }
            if savedID == id { savedID = nil }
        }
        return success
    }
    @discardableResult
    func unarchive(_ id: String) -> Bool {
        purgeExpiredArchives()
        guard let expiry = item(id)?.archiveExpiresAt, expiry > now() else { return false }
        return mutate(id, includingArchived: true) { $0.archivedAt = nil }
    }

    /// At 30 elapsed days the record is removed atomically. Only its owned copies are deleted.
    func purgeExpiredArchives() {
        guard !loadFailed else { return }
        let date = now()
        let expired = document.items.filter { $0.archiveExpiresAt.map { $0 <= date } ?? false }
        if !expired.isEmpty {
            let ids = Set(expired.map(\.id))
            var next = document
            next.items.removeAll { ids.contains($0.id) }
            next.attachmentCleanupIDs = Array(Set(next.attachmentCleanupIDs ?? []).union(ids)).sorted()
            do {
                try commit(next)
                if let id = selectedID, ids.contains(id) { selectedID = nil }
                if let id = savedID, ids.contains(id) { savedID = nil }
            } catch { self.error = "到期归档未能清理，将稍后重试：\(error.localizedDescription)"; return }
        }
        guard let ids = document.attachmentCleanupIDs, !ids.isEmpty,
              nextAttachmentCleanup.map({ $0 <= date }) ?? true else { return }
        nextAttachmentCleanup = date.addingTimeInterval(60)
        do {
            for id in ids {
                guard UUID(uuidString: id) != nil, item(id) == nil else {
                    throw TodoFailure.invalid("待清理附件的记录标识无效。")
                }
                let folder = directory.appendingPathComponent("attachments/\(id)")
                if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
            }
            var next = document; next.attachmentCleanupIDs = nil
            try commit(next)
            nextAttachmentCleanup = nil
            if error?.hasPrefix("到期归档") == true { error = nil }
        } catch { self.error = "到期归档附件未能清理，将稍后重试：\(error.localizedDescription)" }
    }

    func complete(_ id: String) { _ = mutate(id) { $0.completedAt = now() } }
    func restore(_ id: String) { _ = mutate(id) { $0.completedAt = nil } }
    func snooze(_ id: String, minutes: Int) {
        _ = mutate(id) { $0.dueAt = now().addingTimeInterval(Double(minutes) * 60); $0.notifiedAt = nil }
    }
    @discardableResult
    private func mutate(_ id: String, includingArchived: Bool = false, _ body: (inout TodoItem) -> Void) -> Bool {
        guard let i = document.items.firstIndex(where: { $0.id == id && (includingArchived || $0.archivedAt == nil) }) else { return false }
        var next = document; body(&next.items[i])
        do { try commit(next); error = nil; return true }
        catch { self.error = "修改未保存：\(error.localizedDescription)"; return false }
    }
    func undoCapture() {
        guard let id = savedID else { return }
        var next = document; next.items.removeAll { $0.id == id }
        do {
            try commit(next); savedID = nil
            if selectedID == id { selectedID = nil }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("attachments/\(id)"))
        } catch { self.error = "撤销未保存：\(error.localizedDescription)" }
    }

    func updatePreferences(_ input: TodoPreferences) throws {
        guard input.revision == preferences.revision else { throw TodoFailure.invalid("设置已改变，请重新载入后保存。") }
        guard (1...10080).contains(input.defaultMinutes) else { throw TodoFailure.invalid("默认提醒时间应为1～10080分钟。") }
        var next = document; next.preferences = input; next.preferences.revision += 1
        try commit(next)
    }
    func webSnapshot() -> [String: Any] {
        ["revision": preferences.revision, "defaultMinutes": preferences.defaultMinutes, "soundEnabled": preferences.soundEnabled]
    }

    /// Called on a timer, after wake, and at launch. Persist before emitting an alert.
    @discardableResult
    func checkDue() -> [TodoItem] {
        purgeExpiredArchives()
        let date = now()
        let due = document.items.filter { $0.archivedAt == nil && $0.completedAt == nil && $0.notifiedAt == nil && ($0.dueAt.map { $0 <= date } ?? false) }
        guard !due.isEmpty else { return [] }
        let ids = Set(due.map(\.id))
        var next = document
        for i in next.items.indices where ids.contains(next.items[i].id) { next.items[i].notifiedAt = date }
        do { try commit(next); onDue?(due); return due }
        catch { self.error = "提醒状态未保存：\(error.localizedDescription)"; return [] }
    }

    func attachmentURL(_ attachment: TodoAttachment) -> URL? {
        let url = directory.appendingPathComponent(attachment.relativePath).standardizedFileURL
        guard url.path.hasPrefix(directory.standardizedFileURL.path + "/attachments/") else { return nil }
        return url
    }
    func openAttachment(_ attachment: TodoAttachment) {
        guard let url = attachmentURL(attachment), FileManager.default.fileExists(atPath: url.path), NSWorkspace.shared.open(url) else {
            error = "文件副本无法打开，请检查文件是否仍在。"; return
        }
    }
}
