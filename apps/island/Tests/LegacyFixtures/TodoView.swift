import AppKit
import NookApp
import SwiftUI
@testable import IslandShell


struct TodoPanel: View {
    @ObservedObject var store: TodoStore
    @State private var input = ""
    @State private var submitting = false
    @State private var showCompleted = false
    @State private var showArchive = false
    @FocusState private var inputFocused: Bool
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookSwitchModule) private var switchModule

    var body: some View {
        Group {
            if let id = store.selectedID, let item = store.item(id) {
                TodoDetail(store: store, item: item).id(id)
            } else if showArchive {
                archivePage
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("待办").font(.system(size: 19, weight: .semibold))
                            Spacer()
                            Text(store.overdueCount > 0 ? "\(store.overdueCount)项到时间了" : "\(store.pending.count)项未完成")
                                .font(.system(size: 11)).foregroundStyle(store.overdueCount > 0 ? .orange : theme.secondaryLabel)
                            Button { store.purgeExpiredArchives(); showArchive = true } label: {
                                Label("归档", systemImage: "archivebox").font(.system(size: 11))
                            }.buttonStyle(.plain).foregroundStyle(theme.secondaryLabel)
                                .accessibilityIdentifier("island.todo.archive.open")
                        }
                        HStack(spacing: 8) {
                            TextField("先记下这件事…", text: $input).textFieldStyle(.plain)
                                .font(.system(size: 12)).focused($inputFocused).onSubmit(add)
                                .accessibilityIdentifier("island.todo.quickInput")
                            Button(action: add) { Image(systemName: "plus").frame(width: 22, height: 22) }
                                .buttonStyle(IslandButtonStyle(prominent: true))
                                .disabled(submitting || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.loadFailed)
                                .accessibilityLabel("添加待办")
                        }.padding(10).modifier(IslandCard(radius: 12))
                        Text("文字、链接、文件都可以拖到岛里 · 默认\(store.preferences.defaultMinutes)分钟后提醒")
                            .font(.system(size: 10)).foregroundStyle(theme.secondaryLabel)
                        if store.pending.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "tray").font(.system(size: 28)).foregroundStyle(theme.accent)
                                Text("临时来的事，先放在这里").font(.system(size: 12))
                                Text("忙完手头的事，再回来处理。").font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                            }.frame(maxWidth: .infinity).padding(.vertical, 30)
                        } else {
                            VStack(spacing: 8) { ForEach(store.pending) { row($0) } }
                        }
                        if !store.completed.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Button { showCompleted.toggle() } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: showCompleted ? "chevron.down" : "chevron.right")
                                            .frame(width: 10)
                                        Text("已完成（\(store.completed.count)）")
                                        Spacer(minLength: 0)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("已完成（\(store.completed.count)）")
                                .accessibilityValue(showCompleted ? "已展开" : "已折叠")
                                .accessibilityIdentifier("island.todo.completed.toggle")
                                if showCompleted {
                                    VStack(spacing: 8) { ForEach(store.completed) { row($0) } }.padding(.top, 8)
                                }
                            }.font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                        }
                        Button { SettingsServer.shared.open(section: "todos") } label: {
                            Label("待办设置", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                        }.buttonStyle(IslandButtonStyle())
                    }.padding(14)
                }.frame(height: IslandHost.panelHeight)
            }
        }.foregroundStyle(theme.primaryLabel)
            .nookKeepsExpanded(whileFocused: $inputFocused)
            .accessibilityIdentifier("island.todo.panel")
            .modifier(IslandReadingModule(moduleID: IslandHost.todoID))
            .onAppear { switchModule?(IslandHost.todoID) }
    }

    private var archivePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button { showArchive = false } label: { Label("返回待办", systemImage: "chevron.left") }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                    .accessibilityIdentifier("island.todo.archive.back")
                Text("归档（\(store.archived.count)）").font(.system(size: 19, weight: .semibold))
                Text("归档与附件长期保留，可随时恢复，不会按日期自动删除。")
                    .font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                if store.archived.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "archivebox").font(.system(size: 28)).foregroundStyle(theme.accent)
                        Text("暂无归档任务").font(.system(size: 12))
                    }.frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    ForEach(store.archived) { item in
                        HStack(spacing: 10) {
                            Button { store.selectedID = item.id } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                    Text("\(item.completedAt == nil ? "未完成" : "已完成") · 长期保留")
                                        .font(.system(size: 10)).foregroundStyle(theme.secondaryLabel)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Button { store.unarchive(item.id) } label: {
                                Label("恢复", systemImage: "arrow.uturn.backward").font(.system(size: 11))
                            }.buttonStyle(IslandButtonStyle())
                                .accessibilityLabel("取消归档：\(item.title)")
                                .accessibilityIdentifier("island.todo.unarchive.\(item.id)")
                        }.padding(11).modifier(IslandCard(radius: 12))
                    }
                }
            }.padding(14)
        }.frame(height: IslandHost.panelHeight)
            .accessibilityIdentifier("island.todo.archive.panel")
    }

    private func add() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !submitting else { return }
        submitting = true
        Task { @MainActor in
            if await store.capture(.text(value)) != nil, input.trimmingCharacters(in: .whitespacesAndNewlines) == value { input = "" }
            submitting = false
        }
    }

    private func row(_ item: TodoItem) -> some View {
        HStack(spacing: 10) {
            Button {
                if item.completedAt == nil { store.complete(item.id) } else { store.restore(item.id) }
            } label: {
                Image(systemName: item.completedAt == nil ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(item.completedAt == nil ? theme.secondaryLabel : .green).font(.system(size: 18))
            }.buttonStyle(.plain).help(item.completedAt == nil ? "标记完成" : "恢复待办")
                .accessibilityLabel(item.completedAt == nil ? "完成：\(item.title)" : "恢复：\(item.title)")
            Button { store.selectedID = item.id } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            .strikethrough(item.completedAt != nil).frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 6) {
                            if !item.attachments.isEmpty { Label("\(item.attachments.count)", systemImage: "paperclip") }
                            if item.link != nil { Image(systemName: "link") }
                            Text(reminderText(item)).foregroundStyle(isOverdue(item) ? .orange : theme.secondaryLabel)
                        }.font(.system(size: 10))
                    }
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(theme.secondaryLabel)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { store.archive(item.id) } label: {
                Image(systemName: "archivebox").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                    .frame(width: 24, height: 28)
            }.buttonStyle(.plain).help("归档到长期历史，可恢复")
                .accessibilityLabel("归档：\(item.title)")
                .accessibilityIdentifier("island.todo.archive.\(item.id)")
        }.padding(11).modifier(IslandCard(radius: 12))
    }
    private func isOverdue(_ item: TodoItem) -> Bool { item.completedAt == nil && (item.dueAt.map { $0 <= Date() } ?? false) }
    private func reminderText(_ item: TodoItem) -> String {
        if item.completedAt != nil { return "已完成" }
        guard let due = item.dueAt else { return "不提醒" }
        return (isOverdue(item) ? "已到时间 · " : "") + due.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct TodoDetail: View {
    @ObservedObject var store: TodoStore
    let item: TodoItem
    @State private var title: String
    @State private var remind: Bool
    @State private var date: Date
    @FocusState private var focused: Bool
    @Environment(\.nookResolvedTheme) private var theme

    init(store: TodoStore, item: TodoItem) {
        self.store = store; self.item = item
        _title = State(initialValue: item.title)
        _remind = State(initialValue: item.dueAt != nil)
        _date = State(initialValue: item.dueAt ?? Date().addingTimeInterval(1200))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button { store.selectedID = nil } label: { Label(item.archivedAt == nil ? "返回待办" : "返回归档", systemImage: "chevron.left") }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                if item.archivedAt != nil {
                    Text(item.title).font(.system(size: 16, weight: .semibold))
                } else {
                    TextField("待办名称", text: $title, axis: .vertical).font(.system(size: 16, weight: .semibold))
                        .textFieldStyle(.plain).focused($focused).accessibilityIdentifier("island.todo.title")
                }
                if !item.text.isEmpty {
                    Text(item.text).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let link = item.link { Link(destination: link) { Label("打开网页", systemImage: "arrow.up.right.square") }.font(.system(size: 12)) }
                ForEach(item.attachments) { attachment in
                    Button { store.openAttachment(attachment) } label: {
                        Label(attachment.name, systemImage: "doc").font(.system(size: 12)).lineLimit(2)
                    }.buttonStyle(IslandButtonStyle())
                }
                if let expiry = item.archiveExpiresAt {
                    Text("将在\(expiry.formatted(date: .abbreviated, time: .shortened))彻底删除，恢复后回到\(item.completedAt == nil ? "待办" : "已完成")。")
                        .font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                    Button { if store.unarchive(item.id) { store.selectedID = nil } } label: {
                        Label("取消归档", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                    }.buttonStyle(IslandButtonStyle(prominent: true))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("定时提醒", isOn: $remind).font(.system(size: 12)).toggleStyle(.switch)
                        if remind { DatePicker("提醒时间", selection: $date, displayedComponents: [.date, .hourAndMinute]).font(.system(size: 11)) }
                        Button {
                            if store.update(item.id, title: title, dueAt: remind ? date : nil) { store.selectedID = nil }
                        } label: { Label("保存修改", systemImage: "checkmark").frame(maxWidth: .infinity) }
                            .buttonStyle(IslandButtonStyle(prominent: true))
                    }.padding(12).modifier(IslandCard(radius: 12))
                    if item.completedAt == nil {
                        HStack(spacing: 8) {
                            Menu("稍后提醒") {
                                ForEach([10, 20, 60], id: \.self) { minutes in
                                    Button("\(minutes)分钟后") { store.snooze(item.id, minutes: minutes); date = store.item(item.id)?.dueAt ?? date; remind = true }
                                }
                            }.menuStyle(.borderlessButton).font(.system(size: 12))
                            Button { store.complete(item.id); if store.item(item.id)?.completedAt != nil { store.selectedID = nil } } label: {
                                Label("标记完成", systemImage: "checkmark.circle").frame(maxWidth: .infinity)
                            }.buttonStyle(IslandButtonStyle(prominent: true))
                        }
                    } else {
                        Button { store.restore(item.id); if store.item(item.id)?.completedAt == nil { store.selectedID = nil } } label: {
                            Label("恢复待办", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                        }.buttonStyle(IslandButtonStyle())
                    }
                    Button { store.archive(item.id) } label: {
                        Label("归档", systemImage: "archivebox").frame(maxWidth: .infinity)
                    }.buttonStyle(IslandButtonStyle())
                        .accessibilityIdentifier("island.todo.detail.archive")
                    Text("归档后从当前列表隐藏，历史与附件长期保留。")
                        .font(.system(size: 10)).foregroundStyle(theme.secondaryLabel)
                }
            }.padding(14)
        }.frame(height: IslandHost.panelHeight).nookKeepsExpanded(whileFocused: $focused)
    }
}

struct TodoSettingsView: View {
    @ObservedObject var store: TodoStore
    @State private var minutes = "20"
    @State private var sound = true
    @State private var revision = 0
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("默认提醒（分钟）")
                TextField("20", text: $minutes).frame(width: 65)
            }
            Toggle("到期轻响一次", isOn: $sound)
            Text("只影响新建待办；单条可以另设时间或不提醒。").foregroundStyle(.secondary)
            Button("保存待办设置") {
                guard let value = Int(minutes.trimmingCharacters(in: .whitespaces)), (1...10080).contains(value) else {
                    status = "请输入1～10080之间的整数分钟。"; return
                }
                do {
                    try store.updatePreferences(TodoPreferences(revision: revision, defaultMinutes: value, soundEnabled: sound))
                    revision = store.preferences.revision; status = "已保存"
                } catch { status = error.localizedDescription }
            }.buttonStyle(IslandButtonStyle(prominent: true))
            if !status.isEmpty { Text(status).foregroundStyle(.secondary) }
        }.font(.system(size: 11))
            .onAppear { minutes = String(store.preferences.defaultMinutes); sound = store.preferences.soundEnabled; revision = store.preferences.revision }
    }
}
