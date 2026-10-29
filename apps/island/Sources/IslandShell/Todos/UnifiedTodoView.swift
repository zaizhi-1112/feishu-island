import AppKit
import NookApp
import SwiftUI
import UniformTypeIdentifiers

/// A single scrollable surface backed by the original workspace. No AI composer,
/// file intake, parallel todo database or second reminder timer is created here.
struct UnifiedTodoPanel: View {
    @ObservedObject var store: WorkspaceStore
    var compact = true
    
    @State private var showCompleted = false
    @State private var detail:WorkItem?
    @State private var recentCompletion: UUID?
    @State private var restoredTask: UUID?
    @State private var deletedTask: UUID?
    @State private var editingID: UUID?
    @State private var notice = ""
    @FocusState private var inputFocused: Bool
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        Group {
            if compact {
                VStack(spacing:0) {
                    HStack(spacing:3) {
                        todoTab("我的待办",symbol:"checklist",page:"tasks")
                        todoTab("飞书日程",symbol:"calendar",page:"calendar")
                    }.padding(3).background(theme.secondaryLabel.opacity(0.09),in:RoundedRectangle(cornerRadius:12))
                        .padding(.horizontal,14).padding(.top,8).padding(.bottom,6)
                    if let editingID, let item=store.pendingTodos.first(where:{$0.id==editingID}), store.todoPage=="tasks" {
                        UnifiedTodoEditor(store:store,item:item) { self.editingID=nil }.id(item.id)
                    } else {
                        ScrollView {
                            if store.todoPage=="calendar" {FeishuScheduleSection(store:store).padding(14)}
                            else {contents.frame(maxWidth:.infinity).fixedSize(horizontal:false,vertical:true)}
                        }.scrollBounceBehavior(.basedOnSize).frame(maxWidth:.infinity,maxHeight:.infinity)
                        if store.todoPage=="tasks" {completedFooter.padding(.horizontal,14).padding(.bottom,10)}
                    }
                }.frame(height:IslandHost.panelHeight)
            }
            else { TodoCompletionHistory(store:store) }
        }
        .frame(maxWidth:.infinity)
        .foregroundStyle(theme.primaryLabel)
        .nookKeepsExpanded(whileFocused:$inputFocused)
        .accessibilityIdentifier("unified.todo.panel")
        .sheet(item:$detail) {item in TodoRecordDetail(title:item.title,content:item.input,completedAt:item.completedAt,receipt:item.archive) {detail=nil}}
    }

    private func todoTab(_ title: String, symbol: String, page: String) -> some View {
        Button {store.todoPage=page} label: {
            Label(title + (page == "calendar" && store.hasUnviewedScheduleReminder ? " · 待查看" : ""),systemImage:symbol).islandFont(size:13,weight:.medium).frame(maxWidth:.infinity).frame(height:32)
                .foregroundStyle(theme.primaryLabel)
                .background(store.todoPage==page ? theme.subtleFill:Color.clear,in:RoundedRectangle(cornerRadius:10))
                .shadow(color:store.todoPage==page ? .black.opacity(0.07):.clear,radius:4,y:2)
        }.buttonStyle(.plain).disabled(editingID != nil).accessibilityAddTraits(store.todoPage==page ? .isSelected:[])
    }

    private var contents: some View {
        VStack(alignment: .leading, spacing: 14) {
            if compact {
                HStack(alignment: .firstTextBaseline) {
                    Text("待办").islandFont(size: 20, weight: .semibold)
                    Spacer()
                    Text("\(store.pendingTodos.count)项待完成").islandFont(size: 12).foregroundStyle(theme.secondaryLabel)
                }
                HStack(spacing: 8) {
                    TextField("接下来要做的事", text: Binding(get: { store.todoDraft }, set: { store.todoDraft = $0 })).textFieldStyle(.plain)
                        .islandFont(size: 14).focused($inputFocused).onSubmit(add)
                        .accessibilityIdentifier("unified.todo.input")
                    Button(action: add) { Image(systemName: "plus").frame(width: 26, height: 26) }
                        .buttonStyle(IslandButtonStyle(prominent: true))
                        .disabled(store.todoDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("添加待办")
                }.padding(12).modifier(IslandCard(radius: 12))
                if !store.error.isEmpty {
                    Text(store.error).islandFont(size: 12).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true)
                }
                if !notice.isEmpty {
                    HStack {
                        Text(notice).islandFont(size: 11).foregroundStyle(theme.secondaryLabel)
                        Spacer(minLength: 4)
                        if let id = restoredTask {
                            Button("撤销完成") { store.reopenTodo(id); if store.disk.items.first(where:{$0.id==id})?.state != "done" {restoredTask = nil; recentCompletion = nil; notice = ""} }
                                .buttonStyle(.plain).islandFont(size: 11).foregroundStyle(theme.accent)
                        }
                        if let id = deletedTask {
                            Button("撤销删除") { store.restoreItem(id); if store.disk.items.contains(where:{$0.id==id}) {deletedTask = nil; notice = ""} }
                                .buttonStyle(.plain).islandFont(size: 11).foregroundStyle(theme.accent)
                        }
                    }
                }
                if store.pendingTodos.isEmpty && recentCompletion == nil {
                    VStack(spacing:10) {
                        Image(systemName:"checkmark.circle").islandFont(size:38,weight:.light).foregroundStyle(theme.secondaryLabel)
                        Text("暂无待办事项").islandFont(size:14).foregroundStyle(theme.secondaryLabel)
                    }.frame(maxWidth:.infinity).padding(.vertical,26)
                }
                ForEach(store.pendingTodos) { item in taskRow(item) }
                if store.disk.todoCompletionEncouragement != true, let id=recentCompletion,let item=store.completedTodos.first(where:{$0.id==id}) {taskRow(item)}
                if recentCompletion != nil && store.disk.todoCompletionEncouragement == true {
                    Label("又完成一件事",systemImage:"checkmark.circle.fill").islandFont(size:17,weight:.medium).foregroundStyle(theme.accent).frame(maxWidth:.infinity).padding(.vertical,20)
                }


            }
        }
        .padding(compact ? 14 : 0)
        .task(id: recentCompletion) {
            guard recentCompletion != nil else { return }
            do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
            recentCompletion = nil
        }
    }

    private var completedFooter: some View {
        VStack(alignment:.leading,spacing:8) {
            Divider().overlay(theme.subtleStroke)
            HStack {
                Button {showCompleted.toggle()} label: {
                    HStack(spacing:7) {
                        Image(systemName:showCompleted ? "chevron.down":"chevron.right")
                        Text("已完成 \(store.completedTodos.count)")
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("unified.todo.completed")
                    .accessibilityValue(showCompleted ? "已展开":"已折叠")
                Spacer()
                if !store.completedTodos.isEmpty {Button("全部归档") {
                    if store.archiveCompletedTodos() {showCompleted=false;notice="已归档，可在设置的完成记录中查看。"} else {notice=""}
                }.buttonStyle(.plain).foregroundStyle(theme.accent)}
            }.islandFont(size:12)
            if showCompleted {
                if store.completedTodos.isEmpty {Text("完成的事项会显示在这里。").islandFont(size:11).foregroundStyle(theme.secondaryLabel)}
                else {ScrollView {ForEach(store.completedTodos){item in taskRow(item)}}.frame(maxHeight:130)}
            }
        }
    }

    private func taskRow(_ item:WorkItem) -> some View {
        VStack(alignment:.leading,spacing:11) {
            HStack(alignment:.top,spacing:10) {
                Button {
                    if item.state == "done" { store.reopenTodo(item.id); recentCompletion = nil }
                    else {
                        store.complete(item.id)
                        if store.disk.items.first(where: { $0.id == item.id })?.state == "done" {
                            recentCompletion = item.id; restoredTask = item.id; deletedTask = nil; notice = "已完成"
                        }
                    }
                } label: {
                    Image(systemName:item.state == "done" ? "checkmark.circle.fill" : "circle")
                        .islandFont(size:21).frame(width:24,height:24,alignment:.center).foregroundStyle(item.state == "done" ? theme.accent : theme.secondaryLabel)
                }.buttonStyle(.plain).disabled(["running","queued","dot_running"].contains(item.state))
                    .accessibilityLabel((item.state == "done" ? "重新打开：" : "完成：")+item.title)
                VStack(alignment:.leading,spacing:5) {
                    Text(item.title).islandFont(size:14,weight:.medium)
                        .foregroundStyle(theme.primaryLabel)
                        .fixedSize(horizontal:false,vertical:true)
                    if let deadline=item.deadline {
                        Text("完成期限 · "+deadline.formatted(date:.abbreviated,time:.shortened)).islandFont(size:11)
                            .foregroundStyle(deadline<Date() && item.state != "done" ? theme.warning:theme.secondaryLabel)
                    }
                    if let completed=item.completedAt, item.state == "done" {
                        Text("完成于 "+completed.formatted(date:.abbreviated,time:.shortened)).islandFont(size:11).foregroundStyle(theme.secondaryLabel)
                    } else if item.state == "done" {
                        Text("旧记录 · 完成时间未记录").islandFont(size:11).foregroundStyle(theme.secondaryLabel)
                    } else if let due=item.due {
                        Text(reminderSummary(item))
                            .islandFont(size:11).foregroundStyle(due < Date() && !item.reminded ? theme.warning : theme.secondaryLabel)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
                if item.state != "done" {
                    Button("编辑") { inputFocused=false; editingID=item.id }
                        .islandFont(size:12).foregroundStyle(theme.accent).fixedSize()
                        .buttonStyle(.plain).disabled(!WorkspaceStore.canEdit(item)).accessibilityLabel("编辑："+item.title)
                    Button("删除", role: .destructive) {
                            store.deleteItem(item.id)
                            if !store.disk.items.contains(where: { $0.id == item.id }) { deletedTask = item.id; restoredTask = nil; notice = "已移到设置中的最近删除。" }
                    }.buttonStyle(.plain).islandFont(size: 12).fixedSize().disabled(!WorkspaceStore.canEdit(item))
                    .accessibilityLabel("删除待办：" + item.title)
                }
            }
            if !WorkspaceStore.canEdit(item), item.archive != nil {
                Button("旧归档待核对 · 查看记录") {detail=item}.buttonStyle(.plain).foregroundStyle(theme.accent).islandFont(size:12)
            }
            if item.state == "done" {
                HStack(spacing:14) {
                    Spacer()
                    Button("查看详情") {detail=item}.buttonStyle(.plain).islandFont(size:12).foregroundStyle(theme.accent)
                    Button("重新打开") {
                        store.reopenTodo(item.id)
                        if store.disk.items.first(where:{$0.id==item.id})?.state != "done" {recentCompletion=nil;restoredTask=nil;notice="已恢复待办，旧提醒已关闭。"}
                    }.buttonStyle(.plain).islandFont(size:12).foregroundStyle(theme.accent)
                        .accessibilityIdentifier("unified.todo.reopen.\(item.id)")
                    Button {
                        store.archiveItem(item.id)
                        if store.disk.items.first(where:{$0.id==item.id})?.archivedAt != nil {restoredTask=nil;deletedTask=nil;recentCompletion=nil;notice="已归档，可在设置的完成记录中查看。"}
                    } label:{Image(systemName:"archivebox")}
                        .buttonStyle(.plain).foregroundStyle(theme.secondaryLabel).help("归档到长期历史").accessibilityLabel("归档："+item.title)
                }
            }
        }.padding(12).modifier(IslandCard(radius:12))
    }
    private func reminderSummary(_ item: WorkItem) -> String {
        guard let due=item.due else{return ""}
        if item.reminded{return "已提醒 · "+due.formatted(date:.abbreviated,time:.shortened)}
        if let plan=item.todoReminder,let minutes=plan.repeatMinutes {
            let stop=plan.repeatUntil.map{"完成或"+$0.formatted(date:.abbreviated,time:.shortened)+"时停止"} ?? "完成后停止"
            let interval=minutes%60==0 ? "\(minutes/60)小时":"\(minutes)分钟"
            return "下次 "+due.formatted(date:.abbreviated,time:.shortened)+" · 每"+interval+"，"+stop
        }
        let dates=item.todoReminder?.pendingDates ?? [due]
        let text=dates.prefix(3).map{$0.formatted(date:.abbreviated,time:.shortened)}.joined(separator:"、")
        return "提醒 · "+text+(dates.count>3 ? "，另有\(dates.count-3)次":"")
    }

    private func add() {
        guard (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() != true else { return }
        guard !store.todoDraft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
        do { _ = try store.addTodo(title:store.todoDraft); store.todoDraft=""; editingID=nil; notice=""; store.error="" }
        catch { store.error=error.localizedDescription }
    }
}
