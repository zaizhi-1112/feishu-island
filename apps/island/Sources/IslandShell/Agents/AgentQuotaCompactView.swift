import SwiftUI

/// Only the Codex bucket is combined. Missing windows never become zero or another model's limits.
struct AgentQuotaCompactSummary {
    let quotas:[AgentQuota]
    let refreshing:Bool
    let now:Double
    var agentID:String="codex"
    var state:AgentState = .unknown
    var attentionReason:String? = nil
    var displayName:String? = nil
    var name:String { displayName ?? AgentCatalogStore.builtins.first{$0.id==agentID}?.name ?? "Agent" }
    var windows:[AgentQuota] {
        let codex=agentID == "codex" ? quotas.filter{$0.id.hasPrefix("codex/")} : agentID == "workbuddy" ? quotas : []
        guard !codex.isEmpty else { return [] }
        return Array(codex.prefix(2))
    }
    func quota(leading:Bool)->AgentQuota? {
        if windows.count>1 { return windows[leading ? 0:1] }
        return leading ? nil:windows.first
    }
    func text(leading:Bool)->String {
        if !leading,state == .waiting { return attentionReason == "input" ? "等你输入":"等你确认" }
        if let quota=quota(leading:leading) {
            guard quota.isFresh(now:now) else { return "待刷新" }
            let name=quota.label.components(separatedBy:" · ").last ?? quota.label
            let short=name.replacingOccurrences(of:"额度",with:"").replacingOccurrences(of:"小时",with:"h").replacingOccurrences(of:"分钟",with:"分")
            return (!leading && state == .working ? "运行中 · ":"")+short+" "+String(format:"%.0f%%",quota.remainingPercent)
        }
        return leading ? name : state == .working ? "运行中" : refreshing ? "读取中" : agentID == "codex" ? "额度未知" : "状态未接入"
    }
    func accessibility(leading:Bool)->String {
        if !leading,state == .waiting { return name+" · "+text(leading:false) }
        if let quota=quota(leading:leading),quota.isFresh(now:now) { return name+" "+(state == .working ? "运行中，":"")+quota.label+"剩余 "+String(format:"%.0f%%",quota.remainingPercent) }
        return leading && windows.count<2 ? name : name+"额度"+(refreshing ? "读取中" : windows.isEmpty ? "未知" : "已过期，等待刷新")
    }
}

struct AgentQuotaCompactSlot:View,Sendable {
    @ObservedObject var store:AgentStore
    let leading:Bool
    @ObservedObject private var catalog=AgentCatalogStore.shared
    @ObservedObject private var workspace=WorkspaceStore.shared
    var body:some View {
        TimelineView(.periodic(from:.now,by:30)) { context in
            let selected=catalog.selected(in:workspace)
            let active=AgentActivityDisplay.activeAgent(snapshots:store.snapshots,preferences:store.preferences,fallback:selected.id,now:context.date.timeIntervalSince1970)
            let snapshot=store.snapshots[active]
            let hasWaiting=snapshot?.sessions.contains{$0.state == .waiting && context.date.timeIntervalSince1970-$0.updatedAt<900 && $0.updatedAt<=context.date.timeIntervalSince1970+60} ?? false
            let sessionState=store.preferences.enabled && store.preferences.visibleIDs.contains(active) ? (hasWaiting ? .waiting : snapshot?.state(now:context.date.timeIntervalSince1970) ?? .unknown) : .unknown
            let localWorking=workspace.disk.items.contains{$0.service==active && ["running","queued","dot_waiting","dot_running"].contains($0.state)}
            let state:AgentState=localWorking && sessionState != .waiting ? .working:sessionState
            let summary=AgentQuotaCompactSummary(quotas:snapshot?.quotas ?? [],refreshing:store.refreshing,now:context.date.timeIntervalSince1970,agentID:active,state:state,attentionReason:snapshot?.sessions.first{$0.state == .waiting}?.attentionReason,displayName:active==selected.id ? selected.name:nil)
            AgentQuotaCompactBadge(summary:summary,leading:leading)
        }
    }
}

struct AgentQuotaCompactBadge:View {
    let summary:AgentQuotaCompactSummary
    let leading:Bool
    var body:some View {
            let quota=summary.quota(leading:leading)
            let fresh=quota?.isFresh(now:summary.now) ?? false
            HStack(spacing:5) {
                if leading { AgentIdentityIcon(id:summary.agentID,size:18) }
                Text(summary.text(leading:leading)).font(.system(size:11,weight:.semibold,design:.rounded)).monospacedDigit()
                    .foregroundStyle(summary.state == .waiting || (fresh && (quota?.remainingPercent ?? 100)<20) ? Color.orange : Color.white.opacity(0.9))
            }.fixedSize().frame(height:16).accessibilityElement(children:.ignore)
                .accessibilityLabel(summary.accessibility(leading:leading))
                .accessibilityIdentifier(leading ? "agent.quota.leading" : "agent.quota.trailing")
                .help(summary.accessibility(leading:leading))
    }
}
struct AgentPersistentCompactSlot:View,Sendable {
    @ObservedObject var store:AgentStore
    let leading:Bool
    var body:some View {
        if let notice=store.completionNotice {
            if leading { AgentIdentityIcon(id:notice.profileID,size:22) }
            else { AgentCompletionStatus(notice:notice,motion:store.preferences.effectsEnabled) }
        }
        else if store.preferences.quotaDisplayEnabled { AgentQuotaCompactSlot(store:store,leading:leading) }
        else if leading { AgentCompanionGlyph(store:store) }
        else { AgentCompactView(store:store) }
    }
}

struct AgentPersistentExpanded:View,Sendable {
    @ObservedObject var store:AgentStore
    var body:some View {
        if store.preferences.quotaDisplayEnabled { AgentWorkHomeSurface() }
        else { AgentPanel(store:store) }
    }
}

/// Waiting work wins over running work, then return to the selected Agent without mixing quotas.
enum AgentActivityDisplay {
    static func activeAgent(snapshots:[String:AgentSnapshot],preferences:AgentPreferences,fallback:String,now:Double)->String {
        guard preferences.enabled else { return fallback }
        for state in [AgentState.waiting,.working] {
            if let id=([fallback]+preferences.visibleIDs.filter{$0 != fallback}).filter({preferences.visibleIDs.contains($0)}).first(where:{ snapshots[$0]?.sessions.contains(where:{$0.state==state && now-$0.updatedAt<900 && $0.updatedAt<=now+60}) == true }) { return id }
        }
        return fallback
    }
}
struct AgentIdentityIcon:View {
    let id:String
    let size:CGFloat
    var body:some View {
        if ["codex","claude","workbuddy"].contains(id) {
            AgentPortrait(id:id,size:size,avatar:true,motion:false,tapFeedback:false)
        } else {
            Image(systemName:id == "dot" ? "sparkles" : id == "doubao" ? "bubble.left.and.text.bubble.right.fill" : "person.crop.square")
                .font(.system(size:size*0.8)).foregroundStyle(.white).frame(width:size,height:size)
                .accessibilityLabel(id == "dot" ? "Dot" : id == "doubao" ? "豆包工作" : "自定义Agent")
        }
    }
}
