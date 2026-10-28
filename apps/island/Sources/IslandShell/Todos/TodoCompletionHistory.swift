import AppKit
import NookApp
import SwiftUI
import UniformTypeIdentifiers

/// The approved settings layout: one toolbar, date groups, and plain record rows.
struct TodoCompletionHistory: View {
    @ObservedObject var store: WorkspaceStore
    @State private var period="all"
    @State private var detail:WorkTodoCompletion?
    @State private var query=""
    @State private var limit=50
    @State private var notice=""
    @State private var deleting: WorkTodoCompletion?
    @State private var recovery: String?
    @Environment(\.nookResolvedTheme) private var theme
    private var records: [WorkTodoCompletion] {
        store.todoHistory.filter {event in
            (period=="all" || event.completedAt.map {date in
                period=="today" ? Calendar.current.isDateInToday(date) : (Calendar.current.dateInterval(of:.weekOfYear,for:Date())?.contains(date) ?? false)
            } == true) && (query.isEmpty || (event.title+"\n"+event.content).localizedStandardContains(query))
        }
    }
    private var groups: [(String,[WorkTodoCompletion])] {
        var groups: [(String,[WorkTodoCompletion])] = []
        for record in records.prefix(limit) {
            let day=dayTitle(record.completedAt)
            if groups.last?.0==day {groups[groups.count-1].1.append(record)}else{groups.append((day,[record]))}
        }
        return groups
    }
    var body: some View {
        VStack(alignment:.leading,spacing:24) {
            HStack {
                Text("完成记录").font(.system(size:16,weight:.semibold))
                Spacer()
                Button("复制本周记录"){copyWeek()}.buttonStyle(TodoSettingsLinkStyle())
            }
            HStack(spacing:12) {
                HStack(spacing:2) {
                    ForEach([("today","今天"),("week","本周"),("all","全部")],id:\.0) {key,title in
                        Button {period=key;limit=50;notice=""} label: {
                            Text(title).font(.system(size:13,weight:period==key ? .medium:.regular))
                                .frame(width:45,height:32).foregroundStyle(theme.primaryLabel)
                                .background(period==key ? theme.subtleFill:Color.clear,in:RoundedRectangle(cornerRadius:9))
                                .shadow(color:period==key ? .black.opacity(0.05):.clear,radius:3,y:1)
                        }.buttonStyle(.plain).accessibilityLabel(title+"完成记录").accessibilityAddTraits(period==key ? .isSelected:[])
                    }
                }.padding(3).background(theme.secondaryLabel.opacity(0.08),in:RoundedRectangle(cornerRadius:11))
                HStack(spacing:9) {
                    Image(systemName:"magnifyingglass").font(.system(size:14)).foregroundStyle(theme.secondaryLabel)
                    TextField("搜索完成记录",text:$query).font(.system(size:13)).textFieldStyle(.plain)
                        .accessibilityIdentifier("unified.todo.history.search").onChange(of:query){_,_ in limit=50;notice=""}
                    if !query.isEmpty {Button{query=""}label:{Image(systemName:"xmark.circle.fill").foregroundStyle(theme.secondaryLabel)}.buttonStyle(.plain).accessibilityLabel("清除搜索")}
                }.padding(.horizontal,12).frame(height:38).overlay(RoundedRectangle(cornerRadius:10).stroke(theme.subtleStroke,lineWidth:1))
            }
            if !notice.isEmpty {Text(notice).font(.system(size:12)).foregroundStyle(theme.accent)}
            if records.isEmpty {
                Text(query.isEmpty ? "这段时间还没有完成记录。":"没有找到对应的完成记录。")
                    .font(.system(size:14)).foregroundStyle(theme.secondaryLabel).frame(maxWidth:.infinity).padding(.vertical,32)
            }
            ForEach(groups,id:\.0) {day,events in
                VStack(alignment:.leading,spacing:8) {
                    Text(day).font(.system(size:13)).foregroundStyle(theme.secondaryLabel)
                    ForEach(events) {event in
                        recordRow(event)
                        Rectangle().fill(theme.subtleStroke).frame(height:1)
                    }
                }
            }
            if records.count>limit {Button("继续查看（还有\(records.count-limit)条）"){limit+=50}.buttonStyle(TodoSettingsLinkStyle())}
            HStack(spacing:20) {
                Button("导出记录"){export()}.buttonStyle(TodoSettingsLinkStyle())
                if !(store.disk.trash ?? []).isEmpty {Button("最近删除（\(store.disk.trash!.count)）"){recovery="trash"}.buttonStyle(TodoSettingsLinkStyle())}
                if !store.archivedIncompleteTodos.isEmpty {Button("找回旧待办"){recovery="incomplete"}.buttonStyle(TodoSettingsLinkStyle())}
                Spacer()
            }
        }.foregroundStyle(theme.primaryLabel).padding(24).frame(maxWidth:.infinity,alignment:.leading).modifier(IslandCard(radius:18))
        .task(id:notice){guard !notice.isEmpty else{return};do{try await Task.sleep(for:.seconds(4));notice=""}catch{}}
        .alert("永久删除这条完成记录？",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})) {
            Button("取消",role:.cancel){deleting=nil}
            Button("永久删除",role:.destructive){if let event=deleting,store.permanentlyDeleteTodoHistory(event.id){notice="完成记录已删除。"};deleting=nil}
        } message:{Text("这条完成记录将无法恢复；仍在进行的待办不会删除。")}
        .sheet(item:$detail) {event in TodoRecordDetail(title:event.title,content:event.content,completedAt:event.completedAt) {detail=nil}}
        .sheet(isPresented:Binding(get:{recovery != nil},set:{if !$0{recovery=nil}})){recoverySheet}
    }
    private func recordRow(_ event: WorkTodoCompletion) -> some View {
        let pending=store.pendingTodos.contains{$0.id==event.taskID}
        return HStack(spacing:12) {
            Image(systemName:"checkmark.circle").font(.system(size:17)).foregroundStyle(Color(red:0.09,green:0.53,blue:0.42))
            VStack(alignment:.leading,spacing:5) {
                Text(event.title).font(.system(size:14)).fixedSize(horizontal:false,vertical:true)
                if !event.content.isEmpty, event.content != event.title {Text(event.content).font(.system(size:13)).lineLimit(2).foregroundStyle(theme.secondaryLabel)}
                Button("查看详情") {detail=event}.buttonStyle(TodoSettingsLinkStyle())
                Text(event.completedAt.map{$0.formatted(date:.omitted,time:.shortened)+"完成"} ?? "完成时间未记录")
                    .font(.system(size:12)).foregroundStyle(theme.secondaryLabel)
            }.frame(maxWidth:.infinity,alignment:.leading)
            Button(pending ? "已在待办":"重新打开") {
                do{try store.reopenTodoCompletion(event);notice="已回到岛内待办，旧提醒已关闭。"}catch{notice=error.localizedDescription}
            }.buttonStyle(TodoSettingsLinkStyle()).disabled(pending)
        }.padding(.vertical,14)
            .contextMenu {Button("复制这条记录"){copy(store.completionRecordsText([event]),message:"记录已复制。")};Button("永久删除记录",role:.destructive){deleting=event}}
    }
    private var recoverySheet: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {Text(recovery=="trash" ? "最近删除":"旧版未完成待办").font(.title3.bold());Spacer();Button("完成"){recovery=nil}.buttonStyle(TodoSettingsLinkStyle())}
            ScrollView {
                VStack(spacing:0) {
                    ForEach(recovery=="trash" ? store.disk.trash ?? []:store.archivedIncompleteTodos) {item in
                        HStack {Text(item.title).font(.system(size:14)).frame(maxWidth:.infinity,alignment:.leading)
                            Button("移回待办") {if recovery=="trash"{store.restoreItem(item.id)}else{store.unarchiveItem(item.id)}}.buttonStyle(TodoSettingsLinkStyle())
                        }.padding(.vertical,16)
                        Divider()
                    }
                }
            }
        }.padding(24).frame(width:520,height:360).foregroundStyle(theme.primaryLabel).background(theme.subtleFill)
    }
    private func dayTitle(_ date: Date?) -> String {
        guard let date else{return "时间未记录"}
        if Calendar.current.isDateInToday(date){return "今天"}
        if Calendar.current.isDateInYesterday(date){return "昨天"}
        let f=DateFormatter();f.dateFormat=Calendar.current.component(.year,from:date)==Calendar.current.component(.year,from:Date()) ? "M月d日":"yyyy年M月d日";return f.string(from:date)
    }
    private func copyWeek() {
        let week=Calendar.current.dateInterval(of:.weekOfYear,for:Date())!
        copy(store.completionRecordsText(store.todoHistory.filter{$0.completedAt.map(week.contains) ?? false}),message:"本周记录已复制。")
    }
    private func copy(_ text: String, message: String) {
        NSPasteboard.general.clearContents()
        notice=NSPasteboard.general.setString(text,forType:.string) ? message:"复制失败，请重试。"
    }
    private func export() {
        let panel=NSSavePanel();panel.allowedContentTypes=[.json];panel.nameFieldStringValue="待办完成记录.json"
        panel.begin {response in
            guard response == .OK,let url=panel.url else{return}
            do{try store.exportTodoHistory(to:url);notice="记录已导出。"}catch{notice=error.localizedDescription}
        }
    }
}
struct TodoSettingsLinkStyle: ButtonStyle {
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size:13)).foregroundStyle(enabled ? theme.accent:theme.secondaryLabel)
            .padding(.vertical,6).contentShape(Rectangle()).opacity(configuration.isPressed ? 0.6:1)
    }
}
