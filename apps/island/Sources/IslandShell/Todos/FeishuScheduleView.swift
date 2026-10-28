import NookApp
import SwiftUI

struct FeishuScheduleSection: View {
    @ObservedObject var store: WorkspaceStore
    @State private var editID: String?
    @State private var limit=20
    @Environment(\.nookResolvedTheme) private var theme
    private var groups: [(String,[FeishuScheduleEvent])] {
        var result: [(String,[FeishuScheduleEvent])] = []
        for event in store.scheduleEvents.prefix(limit) {
            let date=day(event.start)
            if result.last?.0==date {result[result.count-1].1.append(event)}else{result.append((date,[event]))}
        }
        return result
    }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                Button {Task{await store.connectFeishuSchedule()}} label: {
                    Label(store.calendarSyncing ? "正在同步…" : store.disk.feishuSchedule == nil ? "连接飞书" : "立即同步",systemImage:"arrow.triangle.2.circlepath")
                }.buttonStyle(TodoSettingsLinkStyle()).disabled(store.calendarSyncing)
                Spacer()
                Button {store.openFeishuCalendar()} label: {HStack(spacing:6){Image(systemName:"plus");Text("新建日程");Image(systemName:"arrow.up.right").font(.system(size:10))}}
                    .buttonStyle(TodoSettingsActionStyle())
            }
            VStack(alignment:.leading,spacing:5) {
                HStack(spacing:7) {
                    Circle().fill(store.calendarVerifiedAt != nil || (!store.integrationEnabled && store.disk.feishuSchedule?.lastSync != nil) ? Color(red:0.1,green:0.52,blue:0.42):theme.secondaryLabel).frame(width:6,height:6)
                    Text(store.calendarAccountName+" · 本人主日历 · 未来30天")
                        .font(.system(size:11)).foregroundStyle(theme.secondaryLabel)
                }
                Text(store.calendarStatus).font(.system(size:10)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal:false,vertical:true)
            }
            if store.scheduleEvents.isEmpty {
                VStack(spacing:10) {
                    Image(systemName:"calendar").font(.system(size:30,weight:.light)).foregroundStyle(theme.secondaryLabel)
                    Text(store.disk.feishuSchedule?.lastSync == nil ? "把飞书日程带到岛上":"未来30天暂无日程").font(.system(size:14,weight:.medium))
                    Text("默认提前1天和15分钟提醒，可随时调整。").font(.system(size:11)).foregroundStyle(theme.secondaryLabel)
                }.frame(maxWidth:.infinity).padding(.vertical,25)
            }
            ForEach(groups,id:\.0) {date,events in
                VStack(alignment:.leading,spacing:9) {
                    Text(date).font(.system(size:12)).foregroundStyle(theme.secondaryLabel)
                    ForEach(events) {event in eventCard(event)}
                }
            }
            if store.scheduleEvents.count>limit {Button("查看更多日程"){limit+=20}.buttonStyle(TodoSettingsLinkStyle())}
        }.padding(.top,2)
    }
    private func eventCard(_ event: FeishuScheduleEvent) -> some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.top,spacing:10) {
                Image(systemName:"calendar").font(.system(size:16)).foregroundStyle(theme.accent)
                    .frame(width:32,height:32).background(theme.secondaryLabel.opacity(0.08),in:RoundedRectangle(cornerRadius:10))
                VStack(alignment:.leading,spacing:5) {
                    Text(event.title).font(.system(size:14,weight:.semibold)).fixedSize(horizontal:false,vertical:true)
                    Text(time(event)).font(.system(size:13)).foregroundStyle(theme.accent)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            HStack(alignment:.top,spacing:7) {
                Label("提醒",systemImage:"bell").font(.system(size:11)).foregroundStyle(theme.secondaryLabel).padding(.vertical,4)
                if !event.active {Text("日程已移除，提醒已停止").font(.system(size:11)).foregroundStyle(theme.secondaryLabel).padding(.vertical,4)}
                else if event.offsets.isEmpty {Text("不提醒").font(.system(size:11)).foregroundStyle(theme.secondaryLabel).padding(.vertical,4)}
                else {
                    ScheduleChipFlow(spacing:5) {
                        ForEach(event.offsets.sorted(by:>),id:\.self) {offset in
                            Text(FeishuScheduleEvent.offsetText(offset)).font(.system(size:11)).padding(.horizontal,7).padding(.vertical,5)
                                .background(theme.secondaryLabel.opacity(0.08),in:RoundedRectangle(cornerRadius:7))
                        }
                    }
                }
                Spacer(minLength:0)
            }
            Rectangle().fill(theme.subtleStroke).frame(height:1)
            HStack {
                Button {editID=editID==event.id ? nil:event.id} label:{Label("修改提醒",systemImage:"bell")}.disabled(!event.active)
                Spacer()
                Button {store.openFeishuCalendar(event:event)} label:{HStack(spacing:5){Text("在飞书中查看");Image(systemName:"arrow.up.right")}}
            }.buttonStyle(TodoSettingsLinkStyle())
            if editID==event.id {FeishuScheduleReminderEditor(store:store,event:event){editID=nil}.id(event.id)}
        }.padding(14).foregroundStyle(theme.primaryLabel)
            .background(LinearGradient(colors:[theme.subtleFill,theme.secondaryLabel.opacity(0.035)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:15))
            .overlay(RoundedRectangle(cornerRadius:15).stroke(theme.subtleStroke,lineWidth:1))
            .shadow(color:.black.opacity(0.035),radius:4,y:2)
    }
    private func day(_ date: Date) -> String {
        let f=DateFormatter();f.dateFormat="M月d日"
        return (Calendar.current.isDateInToday(date) ? "今天 · ":"")+f.string(from:date)
    }
    private func time(_ event: FeishuScheduleEvent) -> String {
        if event.allDay{return "全天"}
        let end=event.end.formatted(date:Calendar.current.isDate(event.start,inSameDayAs:event.end) ? .omitted:.abbreviated,time:.shortened)
        return event.start.formatted(date:.omitted,time:.shortened)+"—"+end
    }
}

private struct ScheduleChipFlow: Layout {
    var spacing: CGFloat=5
    private func frames(_ views: Subviews, width: CGFloat) -> [CGRect] {
        var x:CGFloat=0,y:CGFloat=0,row:CGFloat=0,result:[CGRect]=[]
        for view in views {
            let size=view.sizeThatFits(.unspecified)
            if x>0 && x+size.width>width{x=0;y+=row+spacing;row=0}
            result.append(CGRect(x:x,y:y,width:size.width,height:size.height));x+=size.width+spacing;row=max(row,size.height)
        }
        return result
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width=proposal.width ?? 260,rects=frames(subviews,width:width)
        return CGSize(width:width,height:rects.map(\.maxY).max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view,rect) in zip(subviews,frames(subviews,width:bounds.width)) {view.place(at:CGPoint(x:bounds.minX+rect.minX,y:bounds.minY+rect.minY),proposal:ProposedViewSize(rect.size))}
    }
}

private struct FeishuScheduleReminderEditor: View {
    @ObservedObject var store: WorkspaceStore
    let event: FeishuScheduleEvent
    let close: () -> Void
    private struct Offset: Identifiable {
        var id=UUID()
        var value: Int
        var unit: Int
        var minutes: Int {let result=value.multipliedReportingOverflow(by:unit);return result.overflow ? Int.max:result.partialValue}
        init(_ minutes: Int) {unit=minutes>0 && minutes%1440==0 ? 1440:minutes>0 && minutes%60==0 ? 60:1;value=minutes/unit}
    }
    @State private var values: [Offset] = []
    @State private var enabled=true
    @State private var error=""
    @FocusState private var editing: Bool
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Divider()
            Text("只调整你的提醒，不改变会议时间。").font(.system(size:11)).foregroundStyle(.secondary)
            Toggle("提醒我",isOn:$enabled)
            if enabled {
                ForEach($values) { $value in
                    HStack {
                        Text("提前")
                        TextField("数量",value:$value.value,format:.number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width:48).focused($editing)
                        Picker("单位",selection:$value.unit) {Text("分钟").tag(1);Text("小时").tag(60);Text("天").tag(1440)}.labelsHidden().frame(width:68)
                        Spacer(minLength:4)
                        Button{values.removeAll{$0.id==value.id}}label:{Image(systemName:"minus.circle")}.buttonStyle(.plain).accessibilityLabel("删除提醒")
                    }
                    Text((0...43200).contains(value.minutes) ? FeishuScheduleEvent.offsetText(value.minutes)+" · "+event.start.addingTimeInterval(-Double(value.minutes)*60).formatted(date:.abbreviated,time:.shortened) : "请输入开始时至提前30天的时间").foregroundStyle(.secondary).font(.system(size:10))
                }
                HStack {Button("提前1天"){append(1440)};Button("提前15分钟"){append(15)};Button("再加一次"){append(60)}}.buttonStyle(.plain)
            }
            if !error.isEmpty {Text(error).foregroundStyle(.orange)}
            HStack {
                Button("保存") {do{try store.setScheduleReminders(event.id,offsets:enabled ? values.map(\.minutes):[]);close()}catch{self.error=error.localizedDescription}}.buttonStyle(IslandButtonStyle(prominent:true))
                Button("取消",action:close).buttonStyle(IslandButtonStyle())
            }
        }.font(.system(size:11)).nookKeepsExpanded(whileFocused:$editing).onAppear{values=event.offsets.map(Offset.init);enabled = !values.isEmpty}
    }
    private func append(_ value: Int) {if values.count<12{values.append(Offset(value))}}
}
