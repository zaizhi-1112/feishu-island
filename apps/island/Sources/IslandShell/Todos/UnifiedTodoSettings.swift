import AppKit
import SwiftUI
import NookApp

struct UnifiedTodoSettings: View {
    @ObservedObject var store: WorkspaceStore
    @State private var demo=false
    var body: some View {
        VStack(alignment:.leading,spacing:24) {
            IslandSettingsCard("提醒方式") {
                Text("待办和飞书日程到时间后，怎样提醒你。").font(.system(size:12)).foregroundStyle(.secondary)
                HStack(spacing:12) {
                    effectChoice("灵动岛提醒",subtitle:"在屏幕顶部轻轻提醒",symbol:"capsule.fill",selected:store.disk.defaultTodoScreen==nil){_ = store.mutate{$0.defaultTodoScreen=nil}}
                    effectChoice("屏幕动效",subtitle:"用一段动效提醒你",symbol:"sparkles.rectangle.stack",selected:store.disk.defaultTodoScreen != nil){_ = store.mutate{$0.defaultTodoScreen = .init()}}
                }
                if store.disk.defaultTodoScreen != nil {
                    WorkspaceReminderLibrary(store:store,selected:Binding(get:{store.disk.defaultTodoScreen?.materialID ?? "cat"},set:{v in _=store.mutate{$0.defaultTodoScreen = .init(materialID:v)}}))
                }
                HStack {
                    Text("新待办使用默认效果，已有待办可单独调整。").font(.system(size:12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("体验提醒") {
                        if let style=store.disk.defaultTodoScreen {do{store.presentScreenReminder(try store.screenReminderRequest(style:style,title:"该处理这件事了"))}catch{store.error=error.localizedDescription}}
                        else {store.notify("该处理这件事了")}
                    }.buttonStyle(TodoSettingsActionStyle())
                }
            }
            IslandSettingsCard("完成时") {
                HStack(spacing:12) {
                    effectChoice("标记完成",subtitle:"保留完整文字，方便回看",symbol:"checkmark",selected:store.disk.todoCompletionEncouragement != true){_=store.mutate{$0.todoCompletionEncouragement=false}}
                    effectChoice("对勾鼓励",subtitle:"完成一件，给自己一个肯定",symbol:"checkmark.circle.fill",selected:store.disk.todoCompletionEncouragement == true){_=store.mutate{$0.todoCompletionEncouragement=true}}
                }
                HStack {if demo {Label(store.disk.todoCompletionEncouragement == true ? "又完成一件事":"已完成",systemImage:"checkmark.circle.fill").foregroundStyle(.green)};Spacer();Button("体验一下"){demo=true}.buttonStyle(TodoSettingsActionStyle())}
                    .task(id:demo){if demo{try? await Task.sleep(for:.seconds(2));demo=false}}
            }
            TodoCompletionHistory(store:store)
            IslandSettingsCard("飞书日历") {UnifiedCalendarSettings(store:store)}
            if !store.error.isEmpty {Text(store.error).font(.system(size:12)).foregroundStyle(.orange)}
        }
    }
    private func effectChoice(_ title: String, subtitle: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            VStack(alignment:.leading,spacing:12) {
                HStack {Image(systemName:symbol).font(.system(size:25,weight:.medium)).foregroundStyle(selected ? Color.accentColor:Color.secondary);Spacer();Image(systemName:selected ? "checkmark.circle.fill":"circle").foregroundStyle(selected ? Color.accentColor:Color.secondary.opacity(0.4))}
                VStack(alignment:.leading,spacing:5) {Text(title).font(.system(size:14,weight:.semibold));Text(subtitle).font(.system(size:12)).foregroundStyle(.secondary)}
            }.frame(maxWidth:.infinity,alignment:.leading).padding(18)
                .background(RoundedRectangle(cornerRadius:14).fill(selected ? Color.accentColor.opacity(0.07):Color.primary.opacity(0.025)))
                .overlay(RoundedRectangle(cornerRadius:14).stroke(selected ? Color.accentColor.opacity(0.5):Color.primary.opacity(0.08),lineWidth:selected ? 1.5:1))
        }.buttonStyle(.plain).accessibilityValue(selected ? "已选择":"未选择")
    }
}

struct UnifiedCalendarSettings: View {
    @ObservedObject var store: WorkspaceStore
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.top,spacing:12) {
                Image(systemName:"calendar").font(.system(size:26)).foregroundStyle(.blue).frame(width:44,height:44).background(.blue.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
                VStack(alignment:.leading,spacing:5) {
                    Text(LocalFeishuService.shared.connection(.calendar)?.localAccount?.userName ?? "连接你的飞书日历").font(.system(size:14,weight:.semibold))
                    Text(store.calendarStatus).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }
                Spacer(minLength:0)
                if store.calendarSyncing {ProgressView().controlSize(.small)}
            }
            Text("一键同步本人主日历未来30天的日程。默认提前1天、提前15分钟提醒，可在每张日程卡片中调整。").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack {
                Button(store.calendarSyncing ? "同步中…":"一键同步"){Task{await store.connectFeishuSchedule()}}.disabled(store.calendarSyncing).buttonStyle(TodoSettingsActionStyle(prominent:true))
                Button("新建日程"){store.openFeishuCalendar()}.buttonStyle(TodoSettingsActionStyle())
                Spacer()
                Button("管理连接"){LocalFeishuService.shared.open(.calendar)}.buttonStyle(TodoSettingsLinkStyle())
            }
            if store.disk.feishuSchedule != nil {
                Toggle("自动同步并提醒",isOn:Binding(get:{store.disk.feishuSchedule?.enabled == true},set:{v in
                    _=store.mutate{$0.feishuSchedule?.enabled=v};store.calendarVerifiedAt=nil
                    if v{Task{await store.syncFeishuSchedule()}}else{store.calendarStatus="已暂停自动同步和日程提醒"}
                })).toggleStyle(.switch).font(.system(size:13))
            }
            Text("日程在飞书中创建、改期或取消；返回后自动刷新。每分钟也会检查一次。").font(.system(size:12)).foregroundStyle(.secondary)
        }
    }
}

struct TodoSettingsActionStyle: ButtonStyle {
    var prominent=false
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size:13,weight:.medium)).padding(.horizontal,15).frame(height:36)
            .foregroundStyle(prominent ? theme.accent:theme.primaryLabel)
            .background(prominent ? theme.accent.opacity(0.1):theme.secondaryLabel.opacity(0.05),in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).stroke(prominent ? theme.accent.opacity(0.3):theme.subtleStroke,lineWidth:1))
            .opacity(!enabled ? 0.45:configuration.isPressed ? 0.65:1)
    }
}
