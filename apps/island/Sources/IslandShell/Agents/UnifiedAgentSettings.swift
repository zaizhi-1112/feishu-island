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
        return value
    }
    static func example(now:Double)->AgentSnapshot {
        .init(sessions:[.init(id:"task-001",state:.working,updatedAt:now)],quotas:[.init(id:"weekly",label:"本周额度",remainingPercent:80,resetsAt:nil,updatedAt:now)],metrics:[.init(id:"credits",label:"剩余积分",value:128,unit:"积分",updatedAt:now)],source:"自定义 Agent 状态",detail:"由你的 Agent 工具更新此文件；应用只读取状态与额度。")
    }
}
struct UnifiedAgentSettings:View {
    @ObservedObject var store:AgentStore
    @State private var adding=false
    @State private var editingID:String?
    @State private var error=""
    @State private var replacing:String?
    @State private var undo:AgentPreferences?
    @State private var undoRevision:Int?
    @State private var demo="attention"
    @State private var replay=0
    private var orderedProfiles:[AgentProfile] { store.preferences.visibleProfiles + store.preferences.profiles.filter{ !store.preferences.visibleIDs.contains($0.id) } }
    var body:some View {
        VStack(alignment:.leading,spacing:24) {
            IslandSettingsCard("获取本机 Agent") { AgentDiscoveryView(store: store) }
            IslandSettingsCard("我的工具") {
                HStack { Text("选择工具的使用方式，修改后立即生效。").font(.system(size:12)).foregroundStyle(.secondary);Spacer();Button("接入Agent"){editingID=nil;adding=true}.buttonStyle(.borderedProminent) }
                LazyVGrid(columns:[GridItem(.flexible(),alignment:.top),GridItem(.flexible(),alignment:.top)],alignment:.leading,spacing:16) {
                    ForEach(orderedProfiles) { profile in
                        AgentToolCard(store:store,profile:profile,mode:mode(profile.id),setMode:{setMode(profile.id,$0)},setup:{editingID=profile.id;adding=true},open:{open(profile)})
                    }
                }
                if undo != nil, undoRevision == store.preferences.revision { Button("撤销刚才的使用方式更改"){restore()} }
            }
            IslandSettingsCard("岛上怎样显示") {
                HStack(spacing:12) {
                    ForEach(store.preferences.visibleProfiles) { profile in
                        AgentPrimaryChoice(profile:profile,selected:store.primary.id==profile.id,motion:store.preferences.effectsEnabled) {store.selectPrimary(profile.id)}
                    }
                    if store.preferences.visibleIDs.isEmpty { Text("还没有选择显示在岛上的工具").foregroundStyle(.secondary) }
                }
                Toggle("收起时显示主用Agent的额度",isOn:setting(\.quotaDisplayEnabled))
                Text("点击上方工具或岛内工具切换主用Agent。Codex显示剩余比例，WorkBuddy显示积分，DeepSeek Harness显示余额。查看额度可独立于任务状态读取。").font(.caption).foregroundStyle(.secondary)
            }
            IslandSettingsCard("什么时候提醒我") {
                Toggle("需要我确认或补充信息",isOn:setting(\.attentionAlerts))
                Toggle("任务完成",isOn:setting(\.completionAlerts))
                Toggle("正在工作",isOn:setting(\.startAlerts))
                Toggle("额度不足",isOn:setting(\.quotaAlerts))
                Text("只在岛上轻提醒。隐藏工具仍按这里的规则提醒；不使用的工具不读取任务状态。额度不足以来源提供的可靠百分比低于20%为准。").font(.caption).foregroundStyle(.secondary)
            }
            IslandSettingsCard("轻提醒预览") {
                Picker("情境",selection:$demo) {Text("需要确认").tag("attention");Text("任务完成").tag("complete");Text("正在工作").tag("start");Text("额度不足").tag("low")}.pickerStyle(.segmented)
                HStack {AgentIdentityIcon(id:store.primary.id,size:28);if demo=="low" {AgentStatusLight(color:.orange,pulse:true);Text("额度不足 · 示例18%")} else {AgentCompletionStatus(notice:AgentCompletionNotice(profileID:store.primary.id,name:store.primary.name,count:1,stillWorking:demo=="start",attention:demo=="attention" ? "input":demo=="start" ? "running":nil),motion:true)}}.padding(20).frame(maxWidth:.infinity).background(.quaternary.opacity(0.4),in:Capsule()).id(demo+String(replay))
                HStack {Text("示例 · 只在设置页展示").font(.caption).foregroundStyle(.secondary);Spacer();Button("重播轻提醒"){replay += 1} }
            }
            if !error.isEmpty {Text(error).foregroundStyle(.orange).font(.caption)}
        }.sheet(isPresented:$adding){AgentSetupSheet(store:store,editingID:editingID)}
        .sheet(isPresented:Binding(get:{replacing != nil},set:{if !$0 {replacing=nil}})) {
            VStack(alignment:.leading,spacing:16) {Text("岛上已经显示3个工具").font(.title2.bold());Text("选择替换哪个。被替换的工具仍接收提醒。");ForEach(store.preferences.visibleProfiles) {p in Button("替换"+p.name){if let id=replacing {setMode(id,"show",replace:p.id)};replacing=nil}};Button("取消"){replacing=nil}}.padding(28).frame(width:420)
        }
    }
    private func mode(_ id:String)->String {store.preferences.visibleIDs.contains(id) ? "show" : store.preferences.isMonitoring(id) ? "alerts":"off"}
    private func setting(_ key:WritableKeyPath<AgentPreferences,Bool>)->Binding<Bool>{Binding(get:{store.preferences[keyPath:key]},set:{value in change{$0[keyPath:key]=value}})}
    private func change(_ action:(inout AgentPreferences)->Void) {var p=store.preferences;action(&p);do{try store.update(p);error="";undo=nil}catch{self.error=error.localizedDescription}}
    private func setMode(_ id:String,_ mode:String,replace:String?=nil) {
        if mode=="show",!store.preferences.visibleIDs.contains(id),store.preferences.visibleIDs.count==3,replace==nil {replacing=id;return}
        let old=store.preferences
        change {p in
            var ids=p.visibleIDs.filter{$0 != id};if let replace {ids=ids.map{$0==replace ? id:$0}} else if mode=="show" {ids.append(id)}
            var monitored=p.activeMonitorIDs.filter{$0 != id};if mode != "off" {monitored.append(id);p.enabled=true};p.monitoredIDs=monitored;p.setVisibleIDs(ids)
        }
        if error.isEmpty {undo=old;undoRevision=store.preferences.revision}
    }
    private func restore(){guard var old=undo,undoRevision==store.preferences.revision else{return};old.revision=store.preferences.revision;do{try store.update(old);undo=nil}catch{self.error=error.localizedDescription}}

    private func open(_ p:AgentProfile){if let path=p.applicationPath,FileManager.default.fileExists(atPath:path){NSWorkspace.shared.openApplication(at:URL(fileURLWithPath:path),configuration:.init()){_,err in if let err {Task{@MainActor in error=err.localizedDescription}}}}else if let url=p.launchURL.flatMap(URL.init(string:)){NSWorkspace.shared.open(url)}else{error="客户端找不到了，请重新设置接入。"}}
}

struct UnifiedAgentIslandView:View {
    @ObservedObject var store:AgentStore
    var body:some View {
        if store.preferences.visibleProfiles.isEmpty {
            IslandContentScroll {
            ContentUnavailableView { Label("这里还没有 Agent",systemImage:"sparkles") } description: { Text("点右上角齿轮，在“Agent状态”中选择要显示的工具，最多三个。") }.fixedSize(horizontal:false,vertical:true).padding(.vertical,18)
            }
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
            Text(profile.id == "deepseek" ? (snapshot.metrics.isEmpty ? "等待余额" : "余额已连接") : store.preferences.isMonitoring(profile.id) ? snapshot.state(now:Date().timeIntervalSince1970).label : "监测已暂停").foregroundStyle(.secondary)
            if snapshot.quotas.isEmpty && snapshot.metrics.isEmpty { Text(profile.id == "deepseek" ? "等待账户余额" : "此来源尚未提供额度数据").font(.system(size:13)).foregroundStyle(.secondary) }
            ForEach(snapshot.quotas) { quota in
                HStack {
                    Text(quota.label); Spacer()
                    if let left = quota.remainingUnits {
                        Text(left, format: .number.precision(.fractionLength(0...2))).monospacedDigit()
                        Text("积分").foregroundStyle(.secondary)
                    } else { Text(String(format: "%.1f%%", quota.remainingPercent)).monospacedDigit() }
                    if !quota.isFresh(now: Date().timeIntervalSince1970) { Text("上次记录").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            }
            ForEach(snapshot.metrics) { metric in
                HStack { Text(metric.label); Spacer(); Text(metric.displayNumber+" "+metric.unit+(metric.isFresh(now:Date().timeIntervalSince1970) ? "":" · 上次记录")).monospacedDigit() }
            }
            Text(snapshot.detail).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
}

struct AgentPreferencesRecovery:View {
    @Environment(\.nookResolvedTheme) private var theme
    @ObservedObject var store:AgentStore
    @State private var error=""
    var body:some View {
        IslandSettingsCard("Agent配置需要恢复") {
            Text(store.preferencesReadError ?? "").fixedSize(horizontal:false,vertical:true)
            Text("可先导出检查，再导入修复后的JSON。导入前会自动保留原配置副本。").font(.system(size:13)).foregroundStyle(theme.secondaryLabel)
            HStack(spacing:20) {
                Button("导出原配置") {
                    let panel=NSSavePanel();panel.nameFieldStringValue="Agent原配置备份.json";panel.allowedContentTypes=[.json]
                    panel.begin {response in
                        guard response == .OK,let url=panel.url else{return}
                        do {try store.exportOriginalPreferences(to:url);error="原配置已导出。"} catch {self.error=error.localizedDescription}
                    }
                }
                Button("导入修复后的配置") {
                    let panel=NSOpenPanel();panel.allowedContentTypes=[.json];panel.allowsMultipleSelection=false;panel.canChooseDirectories=false
                    panel.begin {response in
                        guard response == .OK,let url=panel.url else{return}
                        do {try store.restorePreferences(from:url);error=""} catch {self.error=error.localizedDescription}
                    }
                }
                Button("重新读取配置"){store.reloadPreferences()}
            }.buttonStyle(TodoSettingsLinkStyle())
            if !error.isEmpty {Text(error).font(.system(size:13))}
        }
    }
}
