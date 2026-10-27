import AppKit
import NookApp
import SwiftUI
import UniformTypeIdentifiers

/// A single scrollable surface backed by the original workspace. No AI composer,
/// file intake, parallel todo database or second reminder timer is created here.
struct UnifiedTodoPanel: View {
    @ObservedObject var store: WorkspaceStore
    var compact = true
    @State private var title = ""
    @State private var showCompleted = false
    @State private var showHistory = false
    @State private var editingID: UUID?
    @State private var historyDay = "all"
    @State private var historyLimit = 50
    @State private var incompleteArchiveLimit = 50
    @State private var notice = ""
    @State private var deletingHistory: WorkTodoCompletion?
    @State private var deletingArchived:WorkItem?
    @FocusState private var inputFocused: Bool
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        Group {
            if compact { IslandContentScroll { contents } }
            else { contents }
        }
        .frame(maxWidth:.infinity)
        .foregroundStyle(theme.primaryLabel)
        .nookKeepsExpanded(whileFocused:$inputFocused)
        .accessibilityIdentifier("unified.todo.panel")
        .alert("永久删除这条历史记录？", isPresented: Binding(get:{deletingHistory != nil || deletingArchived != nil},set:{if !$0 {deletingHistory=nil;deletingArchived=nil}})) {
            Button("取消",role:.cancel) { deletingHistory=nil;deletingArchived=nil }
            Button("永久删除",role:.destructive) {
                if let event=deletingHistory,store.permanentlyDeleteTodoHistory(event.id) { notice="历史记录已永久删除。" }
                if let item=deletingArchived,store.permanentlyDeleteArchivedTodo(item.id) {notice="归档记录已永久删除。"}
                deletingHistory=nil;deletingArchived=nil
            }
        } message: { Text("删除后无法在应用内恢复。当前未归档的待办会保留；最后一条完成记录删除后，对应的已完成归档也会移除。") }
    }

    private var contents:some View {
            VStack(alignment:.leading,spacing:18) {
                HStack(alignment:.firstTextBaseline) {
                    Text("待办").font(.system(size:compact ? 20 : 25,weight:.semibold))
                    Spacer()
                    Text("\(store.pendingTodos.count) 项待完成").font(.system(size:12)).foregroundStyle(theme.secondaryLabel)
                }
                if compact { HStack(spacing:8) {
                    TextField("接下来要做的事",text:$title).textFieldStyle(.plain)
                        .font(.system(size:14)).focused($inputFocused).onSubmit(add)
                        .accessibilityIdentifier("unified.todo.input")
                    Button(action:add) { Image(systemName:"plus").frame(width:26,height:26) }
                        .buttonStyle(IslandButtonStyle(prominent:true))
                        .disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("添加待办")
                }.padding(12).modifier(IslandCard(radius:12)) }
                HStack(spacing:8) {
                    VStack(alignment:.leading,spacing:3) {
                        Text("飞书日历").font(.system(size:13,weight:.medium))
                        Text(store.calendarStatus).font(.system(size:11)).foregroundStyle(theme.secondaryLabel)
                    }
                    Spacer()
                    if store.disk.calendarSyncEnabled == true {
                        Button("同步") { Task { await store.syncTodoCalendar() } }.disabled(store.calendarSyncing)
                        Button("暂停") { _=store.mutate{$0.calendarSyncEnabled=false}; store.calendarStatus="日历同步已暂停" }
                    } else {
                        Button("连接") { Task { await store.connectTodoCalendar() } }.disabled(store.calendarSyncing)
                    }
                }.buttonStyle(.plain)
                if !store.error.isEmpty { Text(store.error).font(.system(size:12)).foregroundStyle(theme.warning).fixedSize(horizontal:false,vertical:true) }
                if !notice.isEmpty { Text(notice).font(.system(size:12)).foregroundStyle(theme.secondaryLabel) }
                if store.pendingTodos.isEmpty {
                    VStack(alignment:.leading,spacing:7) {
                        Label("手上的事都处理好了",systemImage:"checkmark.circle").font(.system(size:15,weight:.medium))
                        Text("记下一件新任务，或向下回顾已完成的工作。").font(.system(size:12)).foregroundStyle(theme.secondaryLabel)
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(16).modifier(IslandCard(radius:12))
                }
                ForEach(store.pendingTodos) { item in taskRow(item) }
                ForEach(store.unfoldedCompletedTodos) { item in taskRow(item) }
                if !store.foldedCompletedTodos.isEmpty {
                    VStack(alignment:.leading,spacing:10) {
                        HStack {
                            Button { showCompleted.toggle() } label: {
                                HStack(spacing:7) {
                                    Image(systemName:showCompleted ? "chevron.down" : "chevron.right")
                                    Text("已完成 · 已折叠 \(store.foldedCompletedTodos.count) 项").fontWeight(.medium)
                                }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("unified.todo.completed")
                            Button("归档这组") { for item in store.foldedCompletedTodos { store.archiveItem(item.id) } }
                                .buttonStyle(.plain).foregroundStyle(theme.accent)
                        }.font(.system(size:12))
                        if showCompleted { ForEach(store.foldedCompletedTodos) { item in taskRow(item) } }
                    }
                }
                Divider().overlay(theme.subtleStroke)
                UnifiedHabitReminders(store:store,compact:compact)
                Divider().overlay(theme.subtleStroke)
                history

            }.padding(compact ? 14 : 6)
    }

    private func taskRow(_ item:WorkItem) -> some View {
        VStack(alignment:.leading,spacing:11) {
            HStack(alignment:.top,spacing:10) {
                Button { item.state == "done" ? store.reopenTodo(item.id) : store.complete(item.id) } label: {
                    Image(systemName:item.state == "done" ? "checkmark.circle.fill" : "circle")
                        .font(.system(size:21)).foregroundStyle(item.state == "done" ? theme.accent : theme.secondaryLabel)
                }.buttonStyle(.plain).disabled(["running","queued","dot_running"].contains(item.state))
                    .accessibilityLabel((item.state == "done" ? "重新打开：" : "完成：")+item.title)
                VStack(alignment:.leading,spacing:5) {
                    Text(item.title).font(.system(size:14,weight:.medium)).strikethrough(item.state == "done")
                        .foregroundStyle(item.state == "done" ? theme.secondaryLabel : theme.primaryLabel)
                        .fixedSize(horizontal:false,vertical:true)
                    if let deadline=item.deadline {
                        Text("截止 · "+deadline.formatted(date:.abbreviated,time:.shortened)).font(.system(size:11))
                            .foregroundStyle(deadline<Date() && item.state != "done" ? theme.warning:theme.secondaryLabel)
                    }
                    if item.calendarSync == true { Text(item.calendarLink?.eventID == nil ? "等待同步到飞书日历":"双向同步飞书日历").font(.system(size:10)).foregroundStyle(theme.secondaryLabel) }
                    if let issue=item.calendarError { Text(issue).font(.system(size:11)).foregroundStyle(theme.warning).fixedSize(horizontal:false,vertical:true) }
                    if let completed=item.completedAt, item.state == "done" {
                        Text("完成于 "+completed.formatted(date:.abbreviated,time:.shortened)).font(.system(size:11)).foregroundStyle(theme.secondaryLabel)
                    } else if item.state == "done" {
                        Text("旧记录 · 完成时间未记录").font(.system(size:11)).foregroundStyle(theme.secondaryLabel)
                    } else if let due=item.due {
                        Text((item.reminded ? "已提醒 · " : "提醒 · ")+due.formatted(date:.abbreviated,time:.shortened)+(item.todoReminder?.repeatMinutes.map { " · 每\($0)分钟" } ?? ""))
                            .font(.system(size:11)).foregroundStyle(due < Date() && !item.reminded ? theme.warning : theme.secondaryLabel)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
                if item.state == "done" {
                    Button {
                        let collapse=item.completedCollapsed != true
                        store.setTodoCollapsed(item.id,collapsed:collapse)
                        if collapse { showCompleted=false }
                    } label: { Image(systemName:item.completedCollapsed == true ? "arrow.up.left" : "chevron.down.square") }
                        .buttonStyle(.plain)
                        .help(item.completedCollapsed == true ? "移回列表底部" : "折叠到已完成")
                        .accessibilityLabel((item.completedCollapsed == true ? "移回列表底部：" : "折叠完成任务：")+item.title)
                    Button { store.archiveItem(item.id) } label: { Image(systemName:"archivebox") }
                        .buttonStyle(.plain).help("归档到长期历史").accessibilityLabel("归档："+item.title)
                } else {
                    Button { editingID=editingID == item.id ? nil : item.id } label: { Image(systemName:editingID == item.id ? "chevron.up" : "slider.horizontal.3") }
                        .buttonStyle(.plain).disabled(!WorkspaceStore.canEdit(item)).accessibilityLabel("编辑与提醒："+item.title)
                }
            }
            if editingID == item.id, item.state != "done" {
                UnifiedTodoEditor(store:store,item:item) { editingID=nil }.id(item.id)
            }
        }.padding(12).modifier(IslandCard(radius:12))
    }
    private var historyDays:[String] {
        Array(Set(store.todoHistory.compactMap { $0.completedAt.map(Self.day) })).sorted(by:>)
    }
    private static func day(_ date:Date) -> String {
        let formatter=DateFormatter(); formatter.dateFormat="yyyy-MM-dd"; return formatter.string(from:date)
    }
    private var visibleHistory:[WorkTodoCompletion] {
        store.todoHistory.filter { historyDay == "all" || ($0.completedAt.map(Self.day) ?? "unknown") == historyDay }
    }
    private var history:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Button { showHistory.toggle() } label: {
                    HStack(spacing:7) {
                        Image(systemName:showHistory ? "chevron.down" : "chevron.right")
                        Text("历史记录 · \(store.todoHistory.count+store.archivedIncompleteTodos.count)").fontWeight(.medium)
                    }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("unified.todo.history")
                Menu("导出") {
                    Button("复制给 Agent") { copyForAgent() }
                    Button("保存 JSON 文件") { export() }
                }.menuStyle(.borderlessButton).fixedSize()
            }.font(.system(size:12))
            if showHistory {
                Text("长期保留，不自动清理。重新打开任务不会抹掉之前的完成记录。").font(.system(size:11)).foregroundStyle(theme.secondaryLabel)
                Picker("查看日期",selection:$historyDay) {
                    Text("所有日期").tag("all")
                    ForEach(historyDays,id:\.self) { Text($0).tag($0) }
                    if store.todoHistory.contains(where:{$0.completedAt == nil}) { Text("旧记录 · 时间未知").tag("unknown") }
                }.pickerStyle(.menu).font(.system(size:12))
                    .onChange(of:historyDay) { _,_ in historyLimit=50 }
                if visibleHistory.isEmpty { Text("这个日期还没有完成记录。").font(.system(size:12)).foregroundStyle(theme.secondaryLabel) }
                ForEach(Array(visibleHistory.prefix(historyLimit))) { event in
                    VStack(alignment:.leading,spacing:6) {
                        HStack(alignment:.top) {
                            Image(systemName:"checkmark.circle.fill").foregroundStyle(theme.accent)
                            Button(role:.destructive) { deletingHistory=event } label: { Image(systemName:"trash") }
                                .buttonStyle(.plain).accessibilityLabel("永久删除历史："+event.title)
                            Text(event.title).font(.system(size:13,weight:.medium)).frame(maxWidth:.infinity,alignment:.leading)
                            if store.archivedTodos.contains(where:{$0.id==event.taskID}) {
                                Button("移回列表") { store.unarchiveItem(event.taskID) }.buttonStyle(.plain).font(.system(size:11))
                            }
                        }
                        Text(event.completedAt.map { Self.day($0)+" · "+$0.formatted(date:.omitted,time:.shortened) } ?? "完成时间未记录，不计入某一天")
                            .font(.system(size:11)).foregroundStyle(theme.secondaryLabel)
                        if event.content != event.title {
                            Text(event.content).font(.system(size:12)).foregroundStyle(theme.secondaryLabel).textSelection(.enabled)
                                .fixedSize(horizontal:false,vertical:true)
                        }
                    }.padding(12).modifier(IslandCard(radius:12))
                }
                if visibleHistory.count > historyLimit {
                    Button("继续查看历史（还有\(visibleHistory.count-historyLimit)条）") { historyLimit += 50 }
                        .buttonStyle(IslandButtonStyle())
                }
                if !store.archivedIncompleteTodos.isEmpty { incompleteArchiveHistory }
            }
        }
    }
    private var incompleteArchiveHistory:some View {
        VStack(alignment:.leading,spacing:10) {
            Divider().overlay(theme.subtleStroke)
            Text("旧归档 · 未完成 \(store.archivedIncompleteTodos.count) 项").font(.system(size:13,weight:.medium))
            Text("这些旧记录尚未完成，不计入每日完成统计。归档日期仅用于查找，你可以移回列表继续做。")
                .font(.system(size:11)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal:false,vertical:true)
            ForEach(Array(store.archivedIncompleteTodos.prefix(incompleteArchiveLimit))) { item in
                VStack(alignment:.leading,spacing:7) {
                    HStack(alignment:.top) {
                        Button(role:.destructive) {deletingArchived=item} label: {Image(systemName:"trash")}
                            .buttonStyle(.plain).accessibilityLabel("永久删除旧归档："+item.title)
                        Text(item.title).font(.system(size:13,weight:.medium)).frame(maxWidth:.infinity,alignment:.leading)
                        Button("移回列表") { store.unarchiveItem(item.id) }.buttonStyle(.plain).font(.system(size:11))
                            .accessibilityLabel("恢复未完成归档："+item.title)
                    }
                    Text(item.archivedAt.map { "归档于 "+Self.day($0)+" · "+$0.formatted(date:.omitted,time:.shortened) } ?? "归档时间未记录")
                        .font(.system(size:11)).foregroundStyle(theme.secondaryLabel)
                    if item.input != item.title {
                        Text(item.input).font(.system(size:12)).foregroundStyle(theme.secondaryLabel).textSelection(.enabled)
                            .fixedSize(horizontal:false,vertical:true)
                    }
                }.padding(12).modifier(IslandCard(radius:12))
            }
            if store.archivedIncompleteTodos.count>incompleteArchiveLimit {
                Button("继续查看旧归档（还有\(store.archivedIncompleteTodos.count-incompleteArchiveLimit)条）") { incompleteArchiveLimit+=50 }
                    .buttonStyle(IslandButtonStyle())
            }
        }
    }
    private func add() {
        do { let id=try store.addTodo(title:title); title=""; editingID=id; notice="" }
        catch { store.error=error.localizedDescription }
    }
    private func copyForAgent() {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(store.todoSummaryText(history:visibleHistory),forType:.string) {
            notice="已复制待办与完成记录，可直接粘贴给 Agent 总结。"
        } else { store.error="复制失败，请重试。" }
    }
    private func export() {
        let panel=NSSavePanel(); panel.allowedContentTypes=[.json]
        panel.nameFieldStringValue="待办完成历史-"+Self.day(Date())+".json"
        panel.begin { response in
            guard response == .OK, let url=panel.url else { return }
            do { try store.exportTodoHistory(to:url); notice="已导出长期历史；你可以把这份文件交给 Agent 做总结。" }
            catch { store.error=error.localizedDescription }
        }
    }
    private func importLegacyDirectory() {
        let panel=NSOpenPanel()
        panel.title="导入旧待办目录"
        panel.message="选择包含 todos.json 的原待办文件夹；附件会一并复制，原文件不会修改。"
        panel.prompt="导入"
        panel.canChooseDirectories=true; panel.canChooseFiles=false
        panel.allowsMultipleSelection=false; panel.canCreateDirectories=false
        panel.begin { response in
            guard response == .OK, let folder=panel.url else { return }
            let accessed=folder.startAccessingSecurityScopedResource()
            defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
            do {
                let count=try store.importLegacyTodos(from:folder)
                store.error=""
                notice=count>0 ? "已导入 \(count) 项旧待办，完成记录与附件已保留。" : "没有新的待办需要导入；该目录可能已经导入。"
            } catch { notice=""; store.error="旧待办未导入，原文件保持不变："+error.localizedDescription }
        }
    }
}

struct UnifiedTodoSettings:View {
    @ObservedObject var store:WorkspaceStore
    var body:some View { UnifiedTodoPanel(store:store,compact:false) }
}

private struct UnifiedTodoEditor:View {
    @ObservedObject var store:WorkspaceStore
    let item:WorkItem
    let finished:()->Void
    @State private var title=""
    @State private var details=""
    @State private var syncCalendar=false
    @State private var hasDeadline=false
    @State private var deadline=Date().addingTimeInterval(86400)
    @State private var mode="off"
    @State private var due=Date().addingTimeInterval(1800)
    @State private var offsets="60, 120, 180"
    @State private var minutes=30
    @State private var bounded=false
    @State private var end=Date().addingTimeInterval(10800)
    @State private var reminder:ScreenReminderStyle?
    @State private var completion:ScreenReminderStyle?
    @State private var error=""
    @FocusState private var editorFocused:Bool
    @Environment(\.nookResolvedTheme) private var theme
    var body:some View {
        VStack(alignment:.leading,spacing:11) {
            Divider()
            TextField("任务名称",text:$title).textFieldStyle(.roundedBorder).focused($editorFocused)
            TextField("补充说明（可选）",text:$details,axis:.vertical).lineLimit(2...5).textFieldStyle(.roundedBorder).focused($editorFocused)
            Toggle("截止日期",isOn:$hasDeadline).toggleStyle(.switch)
            if hasDeadline { DatePicker("截止于",selection:$deadline,displayedComponents:[.date,.hourAndMinute]).datePickerStyle(.field) }
            if hasDeadline {
                Toggle("双向同步飞书日历",isOn:$syncCalendar).toggleStyle(.switch)
                if syncCalendar { Text("首次在截止时间创建1分钟日程；同步标题、说明和截止时间。请先连接日历。").font(.system(size:11)).foregroundStyle(theme.secondaryLabel) }
            }
            Picker("提醒节奏",selection:$mode) {
                Text("不提醒").tag("off"); Text("单次").tag("once"); Text("多次提醒").tag("multiple"); Text("周期提醒").tag("repeat")
            }.pickerStyle(.menu)
            if mode == "once" || mode == "repeat" {
                DatePicker("下次时间",selection:$due,displayedComponents:[.date,.hourAndMinute]).datePickerStyle(.field)
            }
            if mode == "multiple" {
                TextField("从现在起的分钟数，例如 60,120,180",text:$offsets).textFieldStyle(.roundedBorder).focused($editorFocused)
                Text("按填写的分钟数分别提醒；睡眠期间错过的提醒只合并提示一次。").font(.system(size:11)).foregroundStyle(theme.secondaryLabel)
            }
            if mode == "repeat" {
                Stepper("每 \(minutes) 分钟提醒",value:$minutes,in:1...10080)
                Toggle("在指定时间停止循环",isOn:$bounded).toggleStyle(.switch)
                if bounded { DatePicker("结束时间",selection:$end,displayedComponents:[.date,.hourAndMinute]).datePickerStyle(.field) }
            }
            if mode != "off" { ScreenReminderChoice(store:store,selection:$reminder) }
            Picker("完成时",selection:Binding(get:{ completion?.materialID ?? "off" },set:{ completion=$0 == "off" ? nil : .init(materialID:$0,durationSeconds:10) })) {
                Text("划线完成").tag("off")
                ForEach(store.screenMaterials) { Text("冲屏 · "+$0.name).tag($0.id) }
            }.pickerStyle(.menu)
            if !error.isEmpty { Text(error).foregroundStyle(theme.warning).font(.system(size:11)) }
            Button("保存任务与提醒") { save() }.buttonStyle(IslandButtonStyle(prominent:true))
        }.font(.system(size:12)).nookKeepsExpanded(whileFocused:$editorFocused).onAppear {
            syncCalendar=item.calendarSync == true
            hasDeadline=item.deadline != nil; deadline=item.deadline ?? Date().addingTimeInterval(86400)
            title=item.title; details=item.input == item.title ? "" : item.input
            reminder=item.screenReminder; completion=item.completionReminder
            if let value=item.due, !item.reminded {
                due=max(value,Date().addingTimeInterval(60)); mode="once"
                if let plan=item.todoReminder {
                    if let repeatMinutes=plan.repeatMinutes { mode="repeat"; minutes=repeatMinutes }
                    else if plan.pendingDates.count > 1 { mode="multiple"; offsets=plan.pendingDates.map { String(max(1,Int(ceil($0.timeIntervalSinceNow/60)))) }.joined(separator:", ") }
                    if let until=plan.repeatUntil { bounded=true; end=until }
                }
            }
        }
    }
    private func save() {
        let now=Date()
        do {
            let dates:[Date]
            if mode == "multiple" {
                let tokens=offsets.replacingOccurrences(of:"，",with:",").split(separator:",",omittingEmptySubsequences:false)
                let values=tokens.compactMap { Int($0.trimmingCharacters(in:.whitespaces)) }
                guard !values.isEmpty, values.count == tokens.count, values.allSatisfy({ (1...525600).contains($0) }) else { throw WorkError.message("请用逗号分隔分钟数，例如 60,120,180。") }
                dates=values.map { now.addingTimeInterval(Double($0)*60) }
            } else { dates=mode == "off" ? [] : [due] }
            // One atomic save covers content and reminder; a failure leaves the old task intact.
            guard try store.configureTodoReminder(item.id,dates:dates,repeatMinutes:mode == "repeat" ? minutes : nil,
                repeatUntil:mode == "repeat" && bounded ? end : nil,style:mode == "off" ? nil : reminder,
                completionStyle:completion,now:now,title:title,details:details,deadline:.some(hasDeadline ? deadline : nil),calendarSync:hasDeadline && syncCalendar) else { throw WorkError.message(store.error) }
            finished()
            Task { await store.syncTodoCalendar() }
        } catch { self.error=error.localizedDescription }
    }
}

private struct UnifiedHabitReminders:View {
    @ObservedObject var store:WorkspaceStore
    var compact:Bool
    @State private var editing=false
    @State private var selected:UUID?
    @State private var title="喝水，起来活动一下"
    @State private var minutes=30
    @State private var repeats=true
    @State private var firstFire=Date().addingTimeInterval(1800)
    @State private var style:ScreenReminderStyle?
    @State private var error=""
    @FocusState private var editorFocused:Bool
    @Environment(\.nookResolvedTheme) private var theme
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Label("生活与习惯提醒",systemImage:"timer").font(.system(size:13,weight:.medium)); Spacer()
                Button { selected=nil; title="喝水，起来活动一下"; minutes=30; repeats=true; firstFire=Date().addingTimeInterval(1800); style=nil; editing.toggle() } label: { Image(systemName:"plus") }
                    .buttonStyle(.plain).accessibilityLabel("添加周期提醒")
            }
            ForEach(store.screenSchedules) { schedule in
                HStack(spacing:9) {
                    VStack(alignment:.leading,spacing:3) {
                        Text(schedule.title).font(.system(size:13))
                        Text(schedule.enabled ? schedule.fireAt.formatted(date:.omitted,time:.shortened)+(schedule.repeatMinutes.map { " · 每\($0)分钟" } ?? " · 单次") : "已暂停")
                            .font(.system(size:11)).foregroundStyle(theme.secondaryLabel)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    Button { selected=schedule.id; title=schedule.title; minutes=schedule.repeatMinutes ?? 30; repeats=schedule.repeatMinutes != nil; firstFire=max(schedule.fireAt,Date().addingTimeInterval(60)); style=schedule.lightOnly == true ? nil : schedule.style; editing=true } label: { Image(systemName:"pencil") }
                        .buttonStyle(.plain).accessibilityLabel("编辑周期提醒："+schedule.title)
                    Toggle("启用",isOn:Binding(get:{ schedule.enabled },set:{ store.setScreenScheduleEnabled(schedule.id,enabled:$0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).accessibilityLabel("启用提醒："+schedule.title)
                }.padding(11).modifier(IslandCard(radius:10))
            }
            if store.screenSchedules.isEmpty && !editing {
                Text("每隔30分钟起身，或为吃饭设一个单次提醒。").font(.system(size:12)).foregroundStyle(theme.secondaryLabel)
            }
            if editing {
                VStack(alignment:.leading,spacing:11) {
                    TextField("提醒内容",text:$title).textFieldStyle(.roundedBorder).focused($editorFocused)
                    DatePicker("首次提醒",selection:$firstFire,displayedComponents:[.date,.hourAndMinute]).datePickerStyle(.field)
                    Toggle("周期重复",isOn:$repeats).toggleStyle(.switch)
                    if repeats { Stepper("每 \(minutes) 分钟",value:$minutes,in:1...10080) }
                    ScreenReminderChoice(store:store,selection:$style)
                    if !error.isEmpty { Text(error).font(.system(size:11)).foregroundStyle(theme.warning) }
                    HStack {
                        Button("保存提醒") {
                            do { _=try store.upsertScreenSchedule(id:selected,title:title,firstFire:firstFire,repeatMinutes:repeats ? minutes : nil,style:style ?? .init(),lightOnly:style == nil); editing=false; error="" }
                            catch { self.error=error.localizedDescription }
                        }.buttonStyle(IslandButtonStyle(prominent:true))
                        Button("取消") { editing=false }.buttonStyle(IslandButtonStyle())
                    }
                }.font(.system(size:12)).padding(12).modifier(IslandCard(radius:12))
            }
        }.nookKeepsExpanded(whileFocused:$editorFocused)
    }
}
