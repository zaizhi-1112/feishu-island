import AppKit
import Foundation
import CryptoKit

@MainActor
extension WorkspaceStore {
    func setReminder(_ id: UUID, date: Date) { guard abs(date.timeIntervalSinceNow) < 366*86400 else{return};_ = mutate { s in if let i=s.items.firstIndex(where:{$0.id==id}){s.items[i].due=date;s.items[i].reminded=false} } }
    static func canEdit(_ item: WorkItem) -> Bool {
        !["running","queued","dot_running"].contains(item.state) && !["running","pending"].contains(item.archive?.state ?? "") && item.archive?.intent == nil && !(item.remoteSubmissionPending == true && item.remoteTaskURL == nil)
    }
    func beginEdit(_ id: UUID) {
        guard let item = disk.items.first(where:{$0.id == id}), Self.canEdit(item) else { error = "先停止处理或核对原任务，再修改材料。"; return }
        editingID = id; editTitle = item.title; editInput = item.input; editInstruction = item.instruction; editProject = item.project ?? "日常工作"
    }
    func cancelEdit() { editingID = nil; editTitle = ""; editInput = ""; editInstruction = ""; editProject = "" }
    func saveEdit() {
        guard let id=editingID, let item=disk.items.first(where:{$0.id==id}), Self.canEdit(item) else { error = "任务状态已变化，未覆盖内容。"; return }
        let title=editTitle.trimmingCharacters(in:.whitespacesAndNewlines), input=editInput.trimmingCharacters(in:.whitespacesAndNewlines)
        let instruction=editInstruction.trimmingCharacters(in:.whitespacesAndNewlines), project=editProject.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !title.isEmpty, title.count<=80, !input.isEmpty, input.utf8.count<=200_000, !instruction.isEmpty, instruction.utf8.count<=16_000, !project.isEmpty, project.count<=60 else { error = "请填写标题、内容、处理要求和项目；标题最多80字，内容最多200KB。"; return }
        let changed = item.input != input || item.instruction != instruction || (item.project ?? "日常工作") != project
        if mutate({ state in
            guard let i=state.items.firstIndex(where:{$0.id==id}) else { return }
            state.items[i].title=title; state.items[i].input=input; state.items[i].instruction=instruction; state.items[i].project=project
            if changed {
                state.items[i].state="todo"; state.items[i].dotClaim=nil; state.items[i].result=""; state.items[i].resultSource=nil; state.items[i].failure=""
                state.items[i].remoteTaskURL=nil; state.items[i].remoteSubmissionPending=nil; state.items[i].cloudDocuments=nil
                state.items[i].exportSourceID=nil; state.items[i].exportDigest=nil; state.items[i].exportVerifiedAt=nil
                state.items[i].archive=nil
            }
        }) { cancelEdit() }
    }
    func deleteItem(_ id: UUID) {
        guard let item=disk.items.first(where:{$0.id==id}), Self.canEdit(item) else { error = "请先停止处理或核对归档，再删除这条本机记录。"; return }
        if mutate({ state in state.items.removeAll{$0.id==id}; state.trash=(state.trash ?? []).filter{$0.id != id}; var archived=item; if archived.state=="dot_waiting" { archived.state="todo"; archived.dotClaim=nil }; state.trash!.insert(archived,at:0) }) {
            if selected==id { selected=nil }; if editingID==id { cancelEdit() }
        }
    }
    func restoreItem(_ id: UUID) {
        guard disk.items.filter({ $0.archivedAt == nil }).count<500, let item=disk.trash?.first(where:{$0.id==id}), !disk.items.contains(where:{$0.id==id}) else { error = "待办已恢复或列表已满。"; return }
        if mutate({ state in state.trash?.removeAll{$0.id==id}; state.items.insert(item,at:0) }) { selected=id }
    }
    func complete(_ id: UUID, now: Date = Date()) {
        guard let item=disk.items.first(where:{$0.id==id}), item.state != "done", item.archivedAt == nil,
              !["running","queued","dot_running"].contains(item.state) else { return }
        let saved = mutate { state in
            guard let index=state.items.firstIndex(where:{$0.id==id}) else { return }
            state.items[index].state="done"; state.items[index].completedAt=now
            state.items[index].completedCollapsed=false
            state.items[index].due=nil; state.items[index].reminded=true; state.items[index].todoReminder=nil
            var history=state.todoHistory ?? []
            history.append(WorkTodoCompletion(taskID:id,title:item.title,content:item.input,completedAt:now,deadline:item.deadline,project:item.project))
            state.todoHistory=history
        }
        if saved, !remindersAreLocked(), let style=item.completionReminder {
            do { presentScreenReminder(try screenReminderRequest(style:style,title:"完成了 · "+item.title)) }
            catch { self.error=error.localizedDescription; notify("已完成 · "+item.title+"（冲屏素材暂不可用）") }
        }
    }
    /// Local archive is reversible and never deletes the person's attachments.
    func archiveItem(_ id: UUID) {
        guard let item=disk.items.first(where:{$0.id==id}), item.state=="done", item.archive?.state != "running" else { error="请先完成任务并等待归档结束。"; return }
        _ = mutate { state in if let index=state.items.firstIndex(where:{$0.id==id}) { state.items[index].archivedAt=Date(); state.items[index].due=nil } }
    }
    @discardableResult func archiveCompletedTodos(now: Date = Date()) -> Bool {
        let completed = disk.items.filter { $0.state == "done" && $0.archivedAt == nil }
        guard !completed.isEmpty else { return false }
        guard !completed.contains(where: { $0.archive?.state == "running" }) else {
            error = "有记录正在归档，请稍后再试。"; return false
        }
        let ids = Set(completed.map(\.id))
        return mutate { state in
            for index in state.items.indices where ids.contains(state.items[index].id) {
                state.items[index].archivedAt = now
                state.items[index].due = nil
            }
        }
    }
    func unarchiveItem(_ id: UUID) {
        _ = mutate { state in if let index=state.items.firstIndex(where:{$0.id==id}) {
            state.items[index].archivedAt=nil; state.items[index].completedCollapsed=false
        } }
    }
    func snooze(_ id: UUID, minutes: Int = 20) { guard (1...10080).contains(minutes) else { return }; _ = mutate { s in if let i = s.items.firstIndex(where:{$0.id == id}) { s.items[i].due = Date().addingTimeInterval(Double(minutes)*60); s.items[i].reminded = false } } }
}
