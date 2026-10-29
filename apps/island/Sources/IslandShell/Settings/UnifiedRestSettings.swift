import SwiftUI

struct UnifiedRestSettings:View {
    @ObservedObject var store:WorkspaceStore
    @State private var custom=false
    @State private var minutes="90"
    @State private var inputError=""
    private var selected:Binding<String>{Binding(get:{store.restPlan.materialID},set:{value in store.changeRest{$0.materialID=value}})}
    var body:some View {
        VStack(alignment:.leading,spacing:24) {
            IslandSettingsCard("休息提醒") {
                Toggle("开启休息提醒",isOn:Binding(get:{store.restPlan.enabled},set:{store.setRestEnabled($0)}))
                Text("按设定间隔提醒你离开座位，设置后立即保存。").font(.caption).foregroundStyle(.secondary)
                if store.screenSchedules.contains(where:{$0.enabled}) {Text("另有既有提醒正在运行，可在页面下方查看和调整。").font(.caption).foregroundStyle(.secondary)}
            }
            IslandSettingsCard("多久提醒一次") {
                HStack {ForEach([30,60,120],id:\.self){n in Button(n==30 ? "30分钟":n==60 ? "1小时":"2小时"){apply(n);custom=false}.buttonStyle(.bordered).tint(store.restPlan.intervalMinutes==n ? .accentColor:.secondary)};Button("自定义"){custom=true;minutes=String(store.restPlan.intervalMinutes)}}
                if custom {HStack {TextField("分钟",text:$minutes).textFieldStyle(.roundedBorder).frame(width:90);Text("分钟（5—240）");Button("应用"){guard let n=Int(minutes),(5...240).contains(n) else{inputError="请输入5到240的整数。";return};apply(n)}}}
                if !inputError.isEmpty {Text(inputError).font(.caption).foregroundStyle(.orange)}
                Toggle("锁屏或电脑睡眠时暂停计时",isOn:Binding(get:{store.restPlan.pauseWhenAway},set:{value in store.changeRest{$0.pauseWhenAway=value;$0.setAway(false,now:Date())}}))
                TimelineView(.periodic(from:.now,by:1)) {context in
                    HStack {Text(!store.restPlan.enabled ? "休息提醒已关闭":(store.restPlan.paused || store.restPlan.systemPaused ? "已暂停":"正在计时")+" · 距下次提醒\(Int(ceil(store.restPlan.remaining(at:context.date)/60)))分钟");Spacer();Button(store.restPlan.paused ? "继续计时":"暂停"){store.changeRest{$0.setPaused(!$0.paused,now:Date())}}.disabled(!store.restPlan.enabled)}.padding(.top,6)
                }
            }
            IslandSettingsCard("提醒效果") {
                WorkspaceReminderLibrary(store:store,selected:selected)
                Toggle("实际提醒时播放视频声音",isOn:Binding(get:{store.restPlan.sound},set:{v in store.changeRest{$0.sound=v}})).disabled(store.screenMaterials.isEmpty)
                HStack {Button("在桌面体验提醒"){do{var request=try store.screenReminderRequest(style:.init(materialID:store.restPlan.materialID),title:"站起来，活动一下");request.sound=store.restPlan.sound;request.isRest=true;store.presentScreenReminder(request)}catch{store.error=error.localizedDescription}}.disabled(store.screenMaterials.isEmpty);Button("10分钟后提醒"){store.postponeRest()}.disabled(!store.restPlan.enabled)}
            }
            ExistingReminderSettings(store:store)
            if !store.error.isEmpty {Text(store.error).font(.caption).foregroundStyle(.orange)}
        }.onAppear{custom = ![30,60,120].contains(store.restPlan.intervalMinutes);minutes=String(store.restPlan.intervalMinutes)}
    }
    private func apply(_ n:Int){store.changeRest{$0.intervalMinutes=n;$0.restart(now:Date())};inputError=""}
}

private struct ExistingReminderSettings:View {
    @ObservedObject var store:WorkspaceStore
    @State private var editing:WorkScreenSchedule?
    @State private var deleting:WorkScreenSchedule?
    @Environment(\.nookResolvedTheme) private var theme
    var body:some View {
        IslandSettingsCard("其他计划提醒") {
            Text("这些是单独设置的提醒，不受上方休息开关控制。可在这里分别暂停或修改。")
                .font(.system(size:13)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal:false,vertical:true)
            if store.screenSchedules.isEmpty {Text("暂无其他计划提醒。").foregroundStyle(theme.secondaryLabel)}
            ForEach(store.screenSchedules) {schedule in
                VStack(alignment:.leading,spacing:12) {
                    HStack(alignment:.top,spacing:18) {
                        VStack(alignment:.leading,spacing:6) {
                            Text(schedule.title).font(.system(size:15,weight:.medium)).fixedSize(horizontal:false,vertical:true)
                            Text(schedule.enabled ? "下次："+schedule.fireAt.formatted(date:.abbreviated,time:.shortened)+(schedule.repeatMinutes.map{" · 每\($0)分钟"} ?? " · 仅一次") : "已暂停")
                                .font(.system(size:13)).foregroundStyle(theme.secondaryLabel)
                            if schedule.lightOnly == true {Text("岛内轻提醒").font(.system(size:13)).foregroundStyle(theme.secondaryLabel)}
                        }.frame(maxWidth:.infinity,alignment:.leading)
                        Toggle("开启",isOn:Binding(get:{schedule.enabled},set:{store.setScreenScheduleEnabled(schedule.id,enabled:$0)})).labelsHidden().controlSize(.regular).accessibilityLabel("开启提醒："+schedule.title)
                    }
                    HStack(spacing:24) {
                        Button("修改提醒"){editing=schedule}
                        Button("删除提醒",role:.destructive){deleting=schedule}
                    }.buttonStyle(TodoSettingsLinkStyle())
                    Divider()
                }.padding(.vertical,10)
            }
        }
        .sheet(item:$editing) {schedule in
            VStack(alignment:.leading,spacing:20) {
                HStack {Spacer();Button("取消"){editing=nil}.buttonStyle(TodoSettingsLinkStyle())}
                WorkspaceReminderEditor(store:store,schedule:schedule,onSave:{editing=nil})
            }.padding(28).frame(width:480).foregroundStyle(theme.primaryLabel).background(theme.subtleFill)
        }
        .confirmationDialog("删除“\(deleting?.title ?? "")”提醒？",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})) {
            Button("删除提醒",role:.destructive){if let deleting {store.deleteScreenSchedule(deleting.id)};deleting=nil}
            Button("取消",role:.cancel){deleting=nil}
        }
    }
}
