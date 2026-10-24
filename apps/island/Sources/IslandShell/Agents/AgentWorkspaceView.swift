import NookApp
import SwiftUI

/// These are task destinations, not the independent local monitoring adapters.
enum AgentWorkProvider: String, CaseIterable, Identifiable {
    case codex, dot, doubao
    var id:String { rawValue }
    var title:String { switch self { case .codex: return "Codex"; case .dot: return "Dot"; case .doubao: return "豆包工作" } }
    var symbol:String { switch self { case .codex: return "terminal"; case .dot: return "sparkles"; case .doubao: return "bubble.left.and.text.bubble.right" } }
    var detail:String { switch self { case .codex: return "独立后台处理"; case .dot: return "项目任务 · 自动回传"; case .doubao: return "专属伙伴 · 结果回到岛内" } }
    @MainActor func select(in workspace:WorkspaceStore) { workspace.draftService=rawValue }
}

/// One bounded place to choose an Agent and hand over the current material.
struct AgentWorkspaceSurface:View {
    @ObservedObject var agents:AgentStore
    @ObservedObject var workspace:WorkspaceStore
    var desktop=false
    var onTaskCreated:(() -> Void)?
    @Environment(\.nookResolvedTheme) private var theme
    private var provider:AgentWorkProvider { AgentWorkProvider(rawValue:workspace.draftService) ?? .codex }
    var body:some View {
        Group {
            if desktop {
                VStack(alignment:.leading,spacing:16) {
                    destinations
                    identity
                    composer
                }.padding(24)
            } else {
                WorkspaceIslandFrame { bodyHeight in
                    VStack(alignment:.leading,spacing:10) {
                        destinations.frame(height:32)
                        ScrollView {
                            VStack(alignment:.leading,spacing:10) {
                                identity
                                composer
                            }
                        }.frame(height:bodyHeight)
                    }.padding(12)
                }
            }
        }.foregroundStyle(theme.primaryLabel).accessibilityIdentifier("agent.workspace")
    }
    private var composer:some View {
        WorkspaceView(store:workspace,desktop:desktop,pageOverride:0,onTaskCreated:{
            if let onTaskCreated { onTaskCreated() }
            else { IslandModuleNavigation.shared.openWorkspace() }
        },agentComposer:true)
    }
    private var destinations:some View {
        HStack(spacing:6) {
            ForEach(AgentWorkProvider.allCases) { option in
                Button { option.select(in:workspace) } label: {
                    HStack(spacing:6) {
                        Image(systemName:option.symbol).font(.system(size:11))
                        Text(option.title).font(.system(size:12,weight:.semibold))
                    }.frame(maxWidth:.infinity).frame(height:30)
                        .background(provider==option ? theme.accent.opacity(0.16) : .clear,in:Capsule())
                        .contentShape(Capsule())
                }.buttonStyle(.plain).foregroundStyle(provider==option ? theme.accent : theme.secondaryLabel)
                    .accessibilityLabel("交给"+option.title)
                    .accessibilityAddTraits(provider==option ? [.isSelected] : [])
                    .accessibilityIdentifier("agent.destination."+option.rawValue)
            }
        }
    }
    private var identity:some View {
        HStack(spacing:9) {
            if provider == .codex {
                AgentPortrait(id:"codex",size:30,motion:agents.preferences.effectsEnabled)
            } else {
                Image(systemName:provider.symbol).font(.system(size:19)).foregroundStyle(theme.accent).frame(width:30,height:30)
            }
            VStack(alignment:.leading,spacing:2) {
                Text(provider.title).font(.system(size:13,weight:.semibold))
                Text(status).font(.system(size:10)).foregroundStyle(theme.secondaryLabel).lineLimit(1)
            }
            Spacer(minLength:4)
            Button { WorkspaceWindow.shared.openAgents(store:workspace) } label: {
                Image(systemName:"chart.bar.xaxis").frame(width:24,height:28)
            }.buttonStyle(.plain).help("查看 Agent 状态与额度，包括 Claude 和 WorkBuddy").accessibilityLabel("Agent状态与额度")
        }
    }
    private var status:String {
        if workspace.disk.items.contains(where:{$0.service==provider.rawValue && ["running","queued","dot_waiting","dot_running"].contains($0.state)}) { return "任务处理中 · 结果会返回待办" }
        if provider == .codex, agents.preferences.enabled, let snapshot=agents.snapshots["codex"],
           let quota=snapshot.quotas.first(where:{$0.isFresh(now:Date().timeIntervalSince1970)}) {
            return quota.label+"剩余 "+String(format:"%.0f%%",quota.remainingPercent)
        }
        return provider.detail
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
    var body:some View {
        let provider=AgentWorkProvider(rawValue:workspace.draftService) ?? .codex
        Image(systemName:provider.symbol).font(.system(size:12)).foregroundStyle(.white)
    }
}
struct AgentWorkCompactLabel:View {
    @ObservedObject var workspace:WorkspaceStore
    var body:some View {
        let provider=AgentWorkProvider(rawValue:workspace.draftService) ?? .codex
        Text(provider.title).font(.system(size:10)).foregroundStyle(.white.opacity(0.8))
    }
}
