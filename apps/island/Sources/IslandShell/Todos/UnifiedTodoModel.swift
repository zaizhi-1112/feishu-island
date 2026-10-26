import AppKit
import CryptoKit
import Foundation

/// Optional additions to WorkItem preserve the original workspace and every material.
struct WorkTodoReminder: Codable, Equatable {
    var pendingDates: [Date] = []
    var repeatMinutes: Int?
    var repeatUntil: Date?
}

/// An immutable completion event. Reopening a task does not erase completed work.
struct WorkTodoCompletion: Codable, Identifiable, Equatable {
    var id = UUID()
    var taskID: UUID
    var title: String
    var content: String
    var completedAt: Date?
    var project: String?
    var source = "human"
}

@MainActor
extension WorkspaceStore {
    var pendingTodos: [WorkItem] {
        disk.items.filter { $0.archivedAt == nil && $0.state != "done" }.sorted {
            if $0.due != $1.due { return ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            return $0.created > $1.created
        }
    }
    var completedTodos: [WorkItem] {
        disk.items.filter { $0.archivedAt == nil && $0.state == "done" }.sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
    }
    var unfoldedCompletedTodos: [WorkItem] { completedTodos.filter { $0.completedCollapsed != true } }
    var foldedCompletedTodos: [WorkItem] { completedTodos.filter { $0.completedCollapsed == true } }
    var archivedTodos: [WorkItem] {
        disk.items.filter { $0.archivedAt != nil }.sorted {
            ($0.completedAt ?? $0.archivedAt ?? .distantPast) > ($1.completedAt ?? $1.archivedAt ?? .distantPast)
        }
    }
    /// The predecessor allowed archiving unfinished work. Keep it separate from completion events.
    var archivedIncompleteTodos: [WorkItem] { archivedTodos.filter { $0.state != "done" } }
    var todoHistory: [WorkTodoCompletion] {
        (disk.todoHistory ?? []).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    func migrateExistingTodoCompletions() {
        let recorded=Set((disk.todoHistory ?? []).map(\.taskID))
        let missing=disk.items.filter { $0.state == "done" && !recorded.contains($0.id) }
        guard !missing.isEmpty else { return }
        _ = mutate { state in
            var history=state.todoHistory ?? []
            for item in missing {
                history.append(WorkTodoCompletion(taskID:item.id,title:item.title,content:item.input,
                    completedAt:item.completedAt,project:item.project,
                    source:item.completedAt == nil ? "legacy_time_unknown" : "human"))
            }
            state.todoHistory=history
        }
    }

    @discardableResult
    func addTodo(title: String, details: String = "", now: Date = Date()) throws -> UUID {
        let title=title.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 160, details.utf8.count <= 200_000,
              disk.items.filter({ $0.archivedAt == nil }).count < 500 else {
            throw WorkError.message("请填写160字以内的待办名称；当前列表最多500项，已归档历史不限期保留。")
        }
        let item=WorkItem(title:title,input:details.isEmpty ? title : details,instruction:"",service:"todo",created:now)
        guard mutate({ $0.items.insert(item,at:0) }) else { throw WorkError.message(error) }
        return item.id
    }

    func updateTodo(_ id: UUID, title: String, details: String) -> Bool {
        let title=title.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 160, details.utf8.count <= 200_000,
              let item=disk.items.first(where:{$0.id==id}), Self.canEdit(item), item.archivedAt == nil else {
            error="待办名称不能为空或超过160字；正在处理的旧任务暂时不能编辑。"; return false
        }
        return mutate { state in
            guard let index=state.items.firstIndex(where:{$0.id==id}) else { return }
            state.items[index].title=title; state.items[index].input=details.isEmpty ? title : details
        }
    }

    func reopenTodo(_ id: UUID) {
        guard let item=disk.items.first(where:{$0.id==id}), item.state == "done" else { return }
        _ = mutate { state in
            guard let index=state.items.firstIndex(where:{$0.id==id}) else { return }
            state.items[index].state="todo"; state.items[index].completedAt=nil
            state.items[index].completedCollapsed=false
            state.items[index].archivedAt=nil; state.items[index].due=nil
            state.items[index].reminded=false; state.items[index].todoReminder=nil
        }
    }
    func setTodoCollapsed(_ id: UUID, collapsed: Bool) {
        guard let item=disk.items.first(where:{$0.id==id}),item.state=="done",item.archivedAt==nil else { return }
        _ = mutate { state in
            if let index=state.items.firstIndex(where:{$0.id==id}) { state.items[index].completedCollapsed=collapsed }
        }
    }

    @discardableResult
    func configureTodoReminder(_ id: UUID, dates: [Date], repeatMinutes: Int? = nil,
                               repeatUntil: Date? = nil, style: ScreenReminderStyle? = nil,
                               completionStyle: ScreenReminderStyle? = nil, now: Date = Date(),
                               title: String? = nil, details: String? = nil) throws -> Bool {
        guard let item=disk.items.first(where:{$0.id==id}), item.archivedAt == nil, item.state != "done" else {
            throw WorkError.message("只能为未完成待办设置提醒。")
        }
        guard dates.count <= 48, dates.allSatisfy({ $0 > now && $0.timeIntervalSince(now) <= 366*86400 }),
              repeatMinutes.map({ (1...10080).contains($0) }) ?? true,
              repeatUntil.map({ $0 > now && $0.timeIntervalSince(now) <= 366*86400 }) ?? true,
              repeatUntil.map({ until in dates.first.map({ $0 <= until }) ?? true }) ?? true,
              repeatMinutes == nil || !dates.isEmpty else {
            throw WorkError.message("提醒时间须在未来一年内，最多48个时间；循环间隔为1到10080分钟。")
        }
        if let style { try ScreenReminderRules.validate(style,materials:screenMaterials) }
        if let completionStyle { try ScreenReminderRules.validate(completionStyle,materials:screenMaterials) }
        let cleanedTitle=title?.trimmingCharacters(in:.whitespacesAndNewlines)
        guard cleanedTitle.map({ !$0.isEmpty && $0.count <= 160 }) ?? true,
              details.map({ $0.utf8.count <= 200_000 }) ?? true else { throw WorkError.message("任务名称须为1到160字，说明最多200KB。") }
        let sorted=Array(Set(dates)).sorted()
        return mutate { state in
            guard let index=state.items.firstIndex(where:{$0.id==id}) else { return }
            state.items[index].due=sorted.first; state.items[index].reminded=false
            state.items[index].todoReminder=sorted.isEmpty ? nil : WorkTodoReminder(pendingDates:sorted,repeatMinutes:repeatMinutes,repeatUntil:repeatUntil)
            state.items[index].screenReminder=style; state.items[index].completionReminder=completionStyle
            if let cleanedTitle { state.items[index].title=cleanedTitle }
            if let details { state.items[index].input=details.isEmpty ? (cleanedTitle ?? item.title) : details }
        }
    }

    /// Stable versioned, read-only projection, suitable for an explicitly authorized client.
    /// This contains only human todo history; no Agent secrets, account data or chat history.
    func todoHistorySnapshot() -> [String:Any] {
        let formatter=ISO8601DateFormatter()
        return ["schema_version":1,"generated_at":formatter.string(from:Date()),"retention":"indefinite",
                "archived_incomplete":archivedIncompleteTodos.map { item -> [String:Any] in
            ["task_id":item.id.uuidString,"title":item.title,"content":item.input,"status":"incomplete",
             "archived_at":item.archivedAt.map(formatter.string) as Any? ?? NSNull(),"completed_at":NSNull()]
        },
                "completions":todoHistory.map { event -> [String:Any] in
            ["id":event.id.uuidString,"task_id":event.taskID.uuidString,"title":event.title,
             "content":event.content,"status":"completed",
             "completed_at":event.completedAt.map(formatter.string) as Any? ?? NSNull(),
             "completion_time_known":event.completedAt != nil,"source":event.source,
             "archived":disk.items.first(where:{$0.id==event.taskID})?.archivedAt != nil]
        }]
    }
    func exportTodoHistory(to url: URL) throws {
        let bytes=try JSONSerialization.data(withJSONObject:todoHistorySnapshot(),options:[.prettyPrinted,.sortedKeys])
        try bytes.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }

    /// Read once from known predecessor locations. The source and its attachments remain intact.
    func importLegacyTodosIfNeeded() {
        let support=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        for name in ["local.youzi.island", "local.zaizhi.feishu-island.preview"] {
            let folder=support.appendingPathComponent(name+"/Modules/local.youzi.island.todos")
            guard FileManager.default.fileExists(atPath:folder.appendingPathComponent("todos.json").path) else { continue }
            do { _ = try importLegacyTodos(from:folder) } catch { self.error="旧待办已保留，导入暂未完成："+error.localizedDescription }
        }
    }

    @discardableResult
    func importLegacyTodos(from folder: URL) throws -> Int {
        struct LegacyDocument: Decodable { var schemaVersion:Int; var items:[LegacyItem] }
        struct LegacyItem: Decodable {
            struct Attachment: Decodable { var name:String; var relativePath:String }
            var id:String; var title:String; var text:String; var link:URL?; var attachments:[Attachment]
            var createdAt:Date; var dueAt:Date?; var completedAt:Date?; var notifiedAt:Date?; var archivedAt:Date?; var isStored:Bool?
        }
        let file=folder.appendingPathComponent("todos.json")
        let source=SHA256.hash(data:Data(file.standardizedFileURL.path.utf8)).map { String(format:"%02x",$0) }.joined()
        guard !(disk.importedTodoSources ?? []).contains(source) else { return 0 }
        let values=try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= 16_000_000 else { throw WorkError.message("旧待办文件无效或过大。") }
        let legacy=try JSONDecoder().decode(LegacyDocument.self,from:Data(contentsOf:file))
        guard legacy.schemaVersion == 1, legacy.items.count <= 10000, Set(legacy.items.map(\.id)).count == legacy.items.count else { throw WorkError.message("旧待办版本或记录标识无效。") }
        var imported:[WorkItem]=[], history:[WorkTodoCompletion]=[]
        for old in legacy.items {
            guard old.title.count <= 1000, old.text.utf8.count <= 1_000_000 else { throw WorkError.message("旧待办内容超过可导入范围。") }
            let key=source+":"+old.id
            guard !disk.items.contains(where:{$0.legacyTodoSource==key}) else { continue }
            var item=WorkItem(title:old.title,input:old.text.isEmpty ? (old.link?.absoluteString ?? old.title) : old.text,
                              instruction:"",service:"todo",archivedAt:old.archivedAt,completedAt:old.completedAt,
                              legacyTodoSource:key,state:old.completedAt == nil ? "todo" : "done",created:old.createdAt,
                              due:old.isStored == true || old.archivedAt != nil || old.completedAt != nil ? nil : old.dueAt,
                              reminded:old.notifiedAt != nil)
            if !old.attachments.isEmpty {
                let target=todoStorageRoot.appendingPathComponent("Files/"+item.id.uuidString,isDirectory:true)
                try FileManager.default.createDirectory(at:target,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                item.archiveFiles=[]
                for attachment in old.attachments {
                    let sourceURL=folder.appendingPathComponent(attachment.relativePath).standardizedFileURL
                    guard sourceURL.path.hasPrefix(folder.standardizedFileURL.path+"/attachments/"),
                          sourceURL.resolvingSymlinksInPath().path.hasPrefix(folder.resolvingSymlinksInPath().path+"/attachments/") else { throw WorkError.message("旧附件路径不在待办目录中。") }
                    guard FileManager.default.fileExists(atPath:sourceURL.path) else { continue }
                    let info=try sourceURL.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                    guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? 0) <= 150_000_000 else { throw WorkError.message("旧附件不是支持的普通文件。") }
                    let filename=UUID().uuidString+"-"+sourceURL.lastPathComponent
                    let destination=target.appendingPathComponent(filename)
                    try FileManager.default.copyItem(at:sourceURL,to:destination)
                    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:destination.path)
                    item.archiveFiles?.append(WorkFile(name:attachment.name,filename:filename)); item.files.append(attachment.name)
                }
            }
            imported.append(item)
            if let time=old.completedAt { history.append(WorkTodoCompletion(taskID:item.id,title:item.title,content:item.input,completedAt:time,source:"imported_youge")) }
        }
        guard mutate({ state in
            state.items.append(contentsOf:imported); state.todoHistory=(state.todoHistory ?? [])+history
            state.importedTodoSources=(state.importedTodoSources ?? [])+[source]
        }) else { throw WorkError.message(error) }
        return imported.count
    }
}
