import AppKit
import NookApp
import SwiftUI
import UniformTypeIdentifiers

enum CustomAgentReader {
    static func read(_ profile:AgentProfile) throws -> AgentSnapshot {
        guard profile.kind=="file", profile.dataPath.hasSuffix(".json") else { throw AgentReadError.unavailable("请选择 JSON 状态文件。") }
        let url=URL(fileURLWithPath:profile.dataPath)
        let attrs=try FileManager.default.attributesOfItem(atPath:url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular, (attrs[.size] as? NSNumber)?.intValue ?? Int.max <= 262144 else { throw AgentReadError.unavailable("状态文件须为256KB以内的普通 JSON 文件。") }
        let data=try Data(contentsOf:url)
        guard data.count<=262144 else { throw AgentReadError.unavailable("状态文件过大。") }
        let value=try JSONDecoder().decode(AgentSnapshot.self,from:data)
        if let error=value.validationError { throw AgentReadError.unavailable(error) }
        guard value.source.count<=160,value.detail.count<=1000 else { throw AgentReadError.unavailable("状态说明过长。") }
        return value
    }
    static func example(now:Double)->AgentSnapshot {
        .init(sessions:[.init(id:"task-001",state:.working,updatedAt:now)],quotas:[.init(id:"weekly",label:"本周额度",remainingPercent:80,resetsAt:nil,updatedAt:now)],metrics:[.init(id:"credits",label:"剩余积分",value:128,unit:"积分",updatedAt:now)],source:"自定义 Agent 状态",detail:"由你的 Agent 工具更新此文件；应用只读取状态与额度。")
    }
}
struct UnifiedAgentSettings:View {
    @ObservedObject var store:AgentStore
    @State private var name=""
    @State private var selectedFile:URL?
    @State private var error=""
    @State private var detailID="codex"
    @ObservedObject private var workspace=WorkspaceStore.shared
    private var orderedProfiles:[AgentProfile] {
        let preferences=store.preferences
        let visible=Set(preferences.visibleIDs)
        return preferences.visibleProfiles + preferences.profiles.filter { !visible.contains($0.id) }
    }
    var body:some View {
        IslandSettingsCard("监测与提醒") {
            Toggle("开启 Agent 状态监测",isOn:setting(\.enabled))
            Toggle("在刘海显示 Codex 剩余额度",isOn:setting(\.quotaDisplayEnabled))
            Toggle("状态变化与完成提醒",isOn:setting(\.completionAlerts))
            Toggle("额度不足提醒",isOn:setting(\.quotaAlerts))
            Picker("任务完成时",selection:Binding(get:{store.preferences.completionScreenMaterialID ?? "light"},set:{ value in change { $0.completionScreenMaterialID=value=="light" ? nil:value } })) {
                Text("轻提醒").tag("light")
                ForEach(workspace.screenMaterials) { Text("冲屏 · "+$0.name).tag($0.id) }
            }
            Text("只展示工具实际提供的状态与额度。未知数据会明确显示；不会在这里下发任务。冲屏素材在“外观与交互”管理。").font(.system(size:12)).foregroundStyle(.secondary)
        }
        IslandSettingsCard("我的 Agent · 主栏最多三个") {
            ForEach(orderedProfiles) { profile in
                VStack(alignment:.leading,spacing:10) {
                    HStack {
                        VStack(alignment:.leading,spacing:3) { Text(profile.name).fontWeight(.semibold); Text(store.snapshots[profile.id]?.source ?? "尚未取得状态").font(.system(size:11)).foregroundStyle(.secondary) }
                        Spacer()
                        Button("查看") { detailID=profile.id }.accessibilityIdentifier("agent.details.\(profile.id)")
                        if profile.kind=="file" { Button("移除") { change { prefs in prefs.profiles.removeAll{$0.id==profile.id}; prefs.monitoredIDs=prefs.activeMonitorIDs.filter{$0 != profile.id}; prefs.setVisibleIDs(prefs.visibleIDs.filter{$0 != profile.id}); if prefs.primaryID==profile.id { prefs.primaryID=prefs.visibleIDs.first ?? "codex" } } } }
                    }
                    HStack(spacing:18) {
                        Toggle("监测",isOn:Binding(get:{store.preferences.activeMonitorIDs.contains(profile.id)},set:{ enabled in change { prefs in var ids=prefs.activeMonitorIDs.filter{$0 != profile.id}; if enabled {ids.append(profile.id)}; prefs.monitoredIDs=ids } })).fixedSize().accessibilityIdentifier("agent.monitor.\(profile.id)")
                        Toggle("显示在岛上",isOn:Binding(get:{store.preferences.visibleIDs.contains(profile.id)},set:{ enabled in change { prefs in var ids=prefs.visibleIDs.filter{$0 != profile.id}; if enabled {ids.append(profile.id)}; prefs.setVisibleIDs(ids) } })).fixedSize().accessibilityIdentifier("agent.visible.\(profile.id)")
                            .disabled(!store.preferences.visibleIDs.contains(profile.id) && store.preferences.visibleIDs.count>=3)
                        Spacer()
                        if let index=store.preferences.visibleIDs.firstIndex(of:profile.id) {
                            Button { move(profile.id,by:-1) } label:{Image(systemName:"arrow.up")}.disabled(index==0).help("向前排序").accessibilityIdentifier("agent.up.\(profile.id)")
                            Button { move(profile.id,by:1) } label:{Image(systemName:"arrow.down")}.disabled(index==store.preferences.visibleIDs.count-1).help("向后排序").accessibilityIdentifier("agent.down.\(profile.id)")
                        }
                    }.font(.system(size:12))
                    Divider()
                }
            }
            if !error.isEmpty { Text(error).foregroundStyle(.orange).font(.system(size:12)) }
            Text("列表与灵动岛使用同一顺序，隐藏项排在末尾。隐藏不会断开监测；关闭“监测”后不再读取该来源。").font(.system(size:12)).foregroundStyle(.secondary)
        }
        IslandSettingsCard("当前状态") { UnifiedAgentSnapshotView(store:store,profileID:detailID) }
        IslandSettingsCard("添加自定义 Agent") {
            TextField("Agent 名称",text:$name).textFieldStyle(.roundedBorder)
            HStack { Button("选择状态 JSON") { selectFile() }; Text(selectedFile?.lastPathComponent ?? "仅读取你选定的文件").foregroundStyle(.secondary).font(.system(size:12)) }
            HStack {
                Button("保存接入") { add() }.disabled(selectedFile==nil || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                Button("导出接入示例") { exportExample() }
            }
            Text("支持 sessions（任务状态）、quotas（百分比额度）与 metrics（积分等实际数值），可只提供工具能够读取的字段。工具更新选定文件后自动刷新；不执行其中指令，也不读取聊天正文。").font(.system(size:12)).foregroundStyle(.secondary)
        }
    }
    private func setting(_ key:WritableKeyPath<AgentPreferences,Bool>)->Binding<Bool> { Binding(get:{store.preferences[keyPath:key]},set:{value in change{$0[keyPath:key]=value}}) }
    private func change(_ action:(inout AgentPreferences)->Void) { var next=store.preferences; action(&next); do { try store.update(next); error="" } catch { self.error=error.localizedDescription } }
    private func move(_ id:String,by delta:Int) { change { prefs in guard let a=prefs.visibleIDs.firstIndex(of:id),prefs.visibleIDs.indices.contains(a+delta) else{return}; prefs.visibleIDs.swapAt(a,a+delta) } }
    private func selectFile() { let panel=NSOpenPanel(); panel.allowedContentTypes=[.json]; panel.canChooseDirectories=false; panel.allowsMultipleSelection=false; panel.begin { if $0 == .OK { selectedFile=panel.url } } }
    private func add() {
        guard let selectedFile else{return}
        let profile=AgentProfile(id:"custom-"+UUID().uuidString.lowercased(),name:name.trimmingCharacters(in:.whitespacesAndNewlines),kind:"file",dataPath:selectedFile.path)
        do { _=try CustomAgentReader.read(profile); change { prefs in let monitored=prefs.activeMonitorIDs; prefs.profiles.append(profile); prefs.monitoredIDs=monitored+[profile.id]; if prefs.visibleIDs.count<3 {prefs.visibleIDs.append(profile.id)} }; if error.isEmpty {name="";self.selectedFile=nil} }
        catch {self.error=error.localizedDescription}
    }
    private func exportExample() { let panel=NSSavePanel(); panel.allowedContentTypes=[.json]; panel.nameFieldStringValue="agent-status.json"; panel.begin { result in guard result == .OK,let url=panel.url else{return}; do { let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];try encoder.encode(CustomAgentReader.example(now:Date().timeIntervalSince1970)).write(to:url,options:.atomic) } catch {self.error=error.localizedDescription} } }
}

struct UnifiedAgentIslandView:View {
    @ObservedObject var store:AgentStore
    var body:some View {
        if store.preferences.visibleProfiles.isEmpty {
            ContentUnavailableView { Label("这里还没有 Agent",systemImage:"sparkles") } description: { Text("在设置里选择最多三个显示在岛上。") } actions: { Button("打开 Agent 设置") {UnifiedSettingsWindow.shared.open(section:"agents")} }.fixedSize(horizontal:false,vertical:true).padding(.vertical,18)
        } else { AgentPanel(store:store) }
    }
}
struct UnifiedAgentSnapshotView:View {
    @ObservedObject var store:AgentStore
    let profileID:String
    var body:some View {
        let profile=store.preferences.profiles.first{$0.id==profileID} ?? store.primary
        let snapshot=store.snapshots[profile.id] ?? AgentSnapshot()
        VStack(alignment:.leading,spacing:14) {
            HStack { AgentIdentityIcon(id:profile.id,size:28); Text(profile.name).font(.system(size:20,weight:.semibold)); Spacer(); Button("刷新") {store.refreshQuotas();Task{await store.poll()}} }
            Text(store.preferences.isMonitoring(profile.id) ? snapshot.state(now:Date().timeIntervalSince1970).label : "监测已暂停").foregroundStyle(.secondary)
            if snapshot.quotas.isEmpty { Text("此来源尚未提供额度数据").font(.system(size:13)).foregroundStyle(.secondary) }
            ForEach(snapshot.quotas) { quota in
                HStack { Text(quota.label);Spacer();Text(String(format:"%.1f%%",quota.remainingPercent)+(quota.isFresh(now:Date().timeIntervalSince1970) ? " 剩余":" · 上次记录")).monospacedDigit() }
                if let left=quota.remainingUnits { Text(String(format:"%.2f",left)+" 积分").font(.system(size:13)).foregroundStyle(.secondary) }
            }
            ForEach(snapshot.metrics) { metric in
                HStack { Text(metric.label); Spacer(); Text(String(format:"%.2f",metric.value)+" "+metric.unit+(metric.isFresh(now:Date().timeIntervalSince1970) ? "":" · 上次记录")).monospacedDigit() }
            }
            Text(snapshot.detail).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
}
