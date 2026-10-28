import AppKit
import NookApp
import SwiftUI
@testable import IslandShell


/// One bounded place to choose an Agent and hand over the current material.
struct AgentWorkspaceSurface:View {
    @ObservedObject var agents:AgentStore
    @ObservedObject var workspace:WorkspaceStore
    @ObservedObject var catalog:AgentCatalogStore = .shared
    @State private var connectionCopied=false
    var desktop=false
    var onTaskCreated:(() -> Void)?
    @Environment(\.nookResolvedTheme) private var theme
    private var entry:AgentCatalogEntry { catalog.selected(in:workspace) }
    private var provider:AgentWorkProvider? { entry.taskProvider }
    var body:some View {
        Group {
            if desktop {
                VStack(alignment:.leading,spacing:16) {
                    destinations
                    identity
                    content
                }.padding(24)
            } else {
                WorkspaceIslandFrame { bodyHeight in
                    VStack(alignment:.leading,spacing:10) {
                        destinations.frame(height:68)
                        ScrollView {
                            VStack(alignment:.leading,spacing:10) {
                                identity
                                content
                            }
                        }.frame(height:max(0,bodyHeight-36))
                    }.padding(12)
                }
            }
        }.foregroundStyle(theme.primaryLabel).accessibilityIdentifier("agent.workspace")
            .onAppear { provider?.select(in:workspace) }
            .onChange(of:entry.id) { _,_ in provider?.select(in:workspace) }
    }
    @ViewBuilder private var content:some View {
        if entry.taskProvider != nil { composer }
        else { externalAgent }
    }
    private var externalAgent:some View {
        VStack(alignment:.leading,spacing:12) {
            if let id=entry.monitorID {
                Text(id == "claude" ? "状态与额度尚未接通" : (agents.preferences.enabled && agents.preferences.visibleIDs.contains(id) ? (agents.snapshots[id]?.detail ?? "等待本机状态") : "本机状态监测已暂停"))
                    .font(.system(size:13)).foregroundStyle(theme.secondaryLabel)
                if let snapshot=agents.snapshots[id],agents.preferences.enabled,agents.preferences.visibleIDs.contains(id) {
                    ForEach(snapshot.quotas.prefix(2)) { quota in
                        HStack { Text(quota.label); Spacer(); Text(quota.isFresh(now:Date().timeIntervalSince1970) ? String(format:"剩余 %.0f%%",quota.remainingPercent) : "上次记录已过期") }.font(.system(size:13))
                    }
                }
            }
            Text("项目："+workspace.draftProject).font(.system(size:13,weight:.medium))
            Text("可复制当前项目的连接，在这个 Agent 中配置后读取、处理已有任务并回传。尚未启用一键派发。")
                .font(.system(size:12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal:false,vertical:true)
            HStack {
                Button(connectionCopied ? "已复制连接" : "复制项目连接") {
                    workspace.error=""
                    SettingsServer.shared.copyWorkspaceConnection(store:workspace)
                    connectionCopied=SettingsServer.shared.workspaceAgent.active && workspace.error.isEmpty
                }.buttonStyle(IslandButtonStyle(prominent:true))
                if let id=entry.monitorID {
                    Button("打开 "+entry.name) { if !agents.openAgent(id) { workspace.error="未找到 "+entry.name+"，请先在本机安装该客户端。" } }.buttonStyle(IslandButtonStyle())
                } else if let url=URL(string:entry.launchURL),!entry.launchURL.isEmpty {
                    Button("打开 Agent") { NSWorkspace.shared.open(url) }.buttonStyle(IslandButtonStyle())
                }
            }
            if !workspace.error.isEmpty { Text(workspace.error).font(.system(size:12)).foregroundStyle(.orange) }
            if entry.monitorID != nil {
                Button("状态与额度设置") { WorkspaceWindow.shared.openAgentStatus(store:workspace) }.buttonStyle(IslandButtonStyle())
            }
        }.onChange(of:entry.id) { _,_ in connectionCopied=false }
    }
    private var composer:some View {
        WorkspaceView(store:workspace,desktop:desktop,pageOverride:0,onTaskCreated:{
            if let onTaskCreated { onTaskCreated() }
            else { IslandModuleNavigation.shared.openWorkspace() }
        },agentComposer:true)
    }
    private var destinations:some View {
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:6),count:3),spacing:4) {
            ForEach(AgentCatalogStore.builtins) { option in
                Button { catalog.select(option.id,in:workspace); agents.monitorSelected(option.id) } label: {
                    HStack(spacing:5) {
                        if let id=option.monitorID { AgentPortrait(id:id,size:16,avatar:true,motion:false,tapFeedback:false) }
                        else { Image(systemName:option.symbol).font(.system(size:11)) }
                        Text(option.name).font(.system(size:11,weight:.semibold)).lineLimit(1)
                    }.frame(maxWidth:.infinity).frame(height:30)
                        .background(entry.id==option.id ? theme.accent.opacity(0.16) : .clear,in:Capsule())
                        .contentShape(Capsule())
                }.buttonStyle(.plain).foregroundStyle(entry.id==option.id ? theme.accent : theme.secondaryLabel)
                    .accessibilityLabel("选择"+option.name)
                    .accessibilityAddTraits(entry.id==option.id ? [.isSelected] : [])
                    .accessibilityIdentifier("agent.destination."+option.id)
            }
            if catalog.custom.isEmpty {
                Button { WorkspaceWindow.shared.openAgentConnections(store:workspace) } label: { Label("添加 Agent",systemImage:"plus").font(.system(size:11)).frame(maxWidth:.infinity).frame(height:30) }.buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(catalog.custom) { item in Button(item.name) { catalog.select(item.id,in:workspace) } }
                    Divider()
                    Button("添加 / 管理 Agent") { WorkspaceWindow.shared.openAgentConnections(store:workspace) }
                } label: { Text(entry.isBuiltin ? "更多 Agent" : entry.name).font(.system(size:11)).lineLimit(1).frame(maxWidth:.infinity).frame(height:30) }
                    .menuStyle(.borderlessButton).accessibilityLabel("添加或切换其他Agent")
            }
        }
    }
    private var identity:some View {
        HStack(spacing:9) {
            if let id=entry.monitorID {
                AgentPortrait(id:id,size:30,motion:agents.preferences.effectsEnabled)
            } else {
                Image(systemName:entry.symbol).font(.system(size:19)).foregroundStyle(theme.accent).frame(width:30,height:30)
            }
            VStack(alignment:.leading,spacing:2) {
                Text(entry.name).font(.system(size:13,weight:.semibold))
                Text(status).font(.system(size:10)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
            }
            Spacer(minLength:4)
            Button { WorkspaceWindow.shared.openAgentStatus(store:workspace) } label: {
                Image(systemName:"chart.bar.xaxis").frame(width:24,height:28)
            }.buttonStyle(.plain).help("查看 Agent 状态与额度").accessibilityLabel("Agent状态与额度")
        }
    }
    private var status:String {
        if let provider,workspace.disk.items.contains(where:{$0.service==provider.rawValue && ["running","queued","dot_waiting","dot_running"].contains($0.state)}) { return "任务处理中 · 结果会返回待办" }
        if provider == .codex, agents.preferences.enabled || agents.preferences.quotaDisplayEnabled, let snapshot=agents.snapshots["codex"],
           let quota=snapshot.quotas.first(where:{$0.isFresh(now:Date().timeIntervalSince1970)}) {
            return quota.label+"剩余 "+String(format:"%.0f%%",quota.remainingPercent)
        }
        return provider?.detail ?? (entry.monitorID != nil ? "本机状态与额度 · 项目连接" : "自定义 Agent · 项目连接")
    }
}

struct AgentWorkHomeSurface:View,Sendable {
    var body:some View {
        WorkspaceDropSurface(store:.shared) { AgentWorkspaceSurface(agents:.shared,workspace:.shared) }
            .modifier(IslandReadingModule(moduleID:IslandHost.agentID))
    }
}

struct AgentWorkCompactGlyph:View {
    @ObservedObject var workspace:WorkspaceStore
    @ObservedObject private var catalog=AgentCatalogStore.shared
    var body:some View {
        let entry=catalog.selected(in:workspace)
        Image(systemName:entry.symbol).font(.system(size:12)).foregroundStyle(.white)
    }
}
struct AgentWorkCompactLabel:View {
    @ObservedObject var workspace:WorkspaceStore
    @ObservedObject private var catalog=AgentCatalogStore.shared
    var body:some View {
        let entry=catalog.selected(in:workspace)
        Text(entry.name).font(.system(size:10)).foregroundStyle(.white.opacity(0.8))
    }
}
