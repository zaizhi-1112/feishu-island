import SwiftUI

/// Quotas always belong to the selected Agent. Missing data never borrows another source.
struct AgentQuotaCompactSummary {
    let quotas:[AgentQuota]
    let refreshing:Bool
    let now:Double
    var agentID:String="codex"
    var state:AgentState = .unknown
    var attentionReason:String? = nil
    var displayName:String? = nil
    var metrics:[AgentMetric] = []
    var hasRunningSession=false
    var isRunning:Bool { state == .working || hasRunningSession }
    var name:String { displayName ?? AgentCatalogStore.builtins.first{$0.id==agentID}?.name ?? "Agent" }
    var windows:[AgentQuota] {
        let codex=agentID == "codex" ? quotas.filter{$0.id.hasPrefix("codex/")} : quotas
        guard !codex.isEmpty else { return [] }
        return Array(codex.prefix(2))
    }
    func quota(leading:Bool)->AgentQuota? {
        if windows.count>1 { return windows[leading ? 0:1] }
        return leading ? nil:windows.first
    }
    func text(leading:Bool)->String {
        let runningPrefix = !leading && isRunning ? "正在运行 · " : ""
        if !leading,state == .waiting { return runningPrefix+(attentionReason == "input" ? "等你输入":"等你确认") }
        if let quota=quota(leading:leading) {
            guard quota.isFresh(now:now) else { return runningPrefix+"待刷新" }
            if let units=quota.remainingUnits { return runningPrefix+"剩余 " + Self.number(units) + "积分" }
            let name=quota.label.components(separatedBy:" · ").last ?? quota.label
            let short=name.replacingOccurrences(of:"额度",with:"").replacingOccurrences(of:"小时",with:"h").replacingOccurrences(of:"分钟",with:"分")
            return runningPrefix+short+" "+String(format:"%.0f%%",quota.remainingPercent)
        }
        if !leading, let metric=metrics.first { return metric.isFresh(now:now) ? runningPrefix+metric.label+" "+Self.number(metric.value)+metric.unit : runningPrefix+"待刷新" }
        return leading ? name : isRunning ? "正在运行" : refreshing ? "读取中" : "额度未知"
    }
    static func number(_ value:Double)->String { value.formatted(.number.precision(.fractionLength(0...2))) }
    func accessibility(leading:Bool)->String {
        if !leading,isRunning { return name+" · "+text(leading:false)+"（红色运行指示灯）" }
        if !leading, let quota=quota(leading:false), quota.remainingUnits != nil { return name+" · "+text(leading:false) }
        if !leading, windows.isEmpty, !metrics.isEmpty { return name+" · "+text(leading:false) }
        if !leading,state == .waiting { return name+" · "+text(leading:false) }
        if let quota=quota(leading:leading),quota.isFresh(now:now) { return name+" "+(state == .working ? "运行中，":"")+quota.label+"剩余 "+String(format:"%.0f%%",quota.remainingPercent) }
        return leading && windows.count<2 ? name : name+"额度"+(refreshing ? "读取中" : windows.isEmpty ? "未知" : "已过期，等待刷新")
    }
}

struct AgentQuotaCompactSlot:View,Sendable {
    @ObservedObject var store:AgentStore
    let leading:Bool
    var body:some View {
        TimelineView(.periodic(from:.now,by:30)) { context in
            let summary=AgentActivityDisplay.selectedQuotaSummary(snapshots:store.snapshots,preferences:store.preferences,refreshing:store.refreshing,now:context.date.timeIntervalSince1970)
            AgentQuotaCompactBadge(summary:summary,leading:leading)
        }
    }
}

struct AgentQuotaCompactBadge:View {
    let summary:AgentQuotaCompactSummary
    let leading:Bool
    @Environment(\.nookResolvedTheme) private var theme
    var body:some View {
            let quota=summary.quota(leading:leading)
            let fresh=quota?.isFresh(now:summary.now) ?? false
            HStack(spacing:5) {
                if !leading, summary.isRunning { AgentStatusLight(color:.red,motion:false) }
                if leading { AgentIdentityIcon(id:summary.agentID,size:18) }
                Text(summary.text(leading:leading)).font(.system(size:11,weight:.semibold,design:.rounded)).monospacedDigit()
                    .foregroundStyle(summary.state == .waiting || (fresh && (quota?.remainingPercent ?? 100)<20) ? Color.orange : theme.primaryLabel)
            }.lineLimit(1).truncationMode(.tail).frame(maxWidth: 180).fixedSize(horizontal:false,vertical:true).frame(height:20).accessibilityElement(children:.ignore)
                .accessibilityLabel(summary.accessibility(leading:leading))
                .accessibilityIdentifier(leading ? "agent.quota.leading" : "agent.quota.trailing")
                .help(summary.accessibility(leading:leading))
    }
}
struct AgentPersistentCompactSlot:View,Sendable {
    @ObservedObject var store:AgentStore
    let leading:Bool
    var body:some View {
        if let notice=store.primarySwitchNotice {
            if leading { AgentIdentityIcon(id:notice.profileID,size:24) }
            else { AgentPrimarySwitchStatus(notice:notice,running:store.state(for:notice.profileID) == .working) }
        }
        else if let notice=store.completionNotice {
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
        UnifiedAgentIslandView(store:store)
    }
}

/// Waiting work wins over running work, then return to the selected Agent without mixing quotas.
enum AgentActivityDisplay {
    static func selectedQuotaSummary(snapshots:[String:AgentSnapshot],preferences:AgentPreferences,refreshing:Bool,now:Double)->AgentQuotaCompactSummary {
        let id=preferences.primaryID, snapshot=snapshots[preferences.primaryID]
        let waiting=snapshot?.sessions.first { $0.state == .waiting && now-$0.updatedAt<900 && $0.updatedAt<=now+60 }
        let state:AgentState=preferences.isMonitoring(id) ? (waiting == nil ? snapshot?.state(now:now) ?? .unknown:.waiting):.unknown
        return AgentQuotaCompactSummary(quotas:snapshot?.quotas ?? [],refreshing:refreshing,now:now,agentID:id,state:state,attentionReason:waiting?.attentionReason,displayName:preferences.profiles.first{$0.id==id}?.name,metrics:snapshot?.metrics ?? [],hasRunningSession:preferences.isMonitoring(id) && snapshot?.sessions.contains(where:{$0.state == .working && now-$0.updatedAt<900 && $0.updatedAt<=now+60}) == true)
    }
    static func activeAgent(snapshots:[String:AgentSnapshot],preferences:AgentPreferences,fallback:String,now:Double)->String {
        guard preferences.enabled else { return fallback }
        for state in [AgentState.waiting,.working] {
            if let id=([fallback]+preferences.visibleIDs.filter{$0 != fallback}).filter({preferences.visibleIDs.contains($0) && preferences.isMonitoring($0)}).first(where:{ snapshots[$0]?.sessions.contains(where:{$0.state==state && now-$0.updatedAt<900 && $0.updatedAt<=now+60}) == true }) { return id }
        }
        return fallback
    }
}
struct AgentIdentityIcon:View {
    @Environment(\.nookResolvedTheme) private var theme
    let id:String
    let size:CGFloat
    var body:some View {
        if ["codex","claude","workbuddy"].contains(id) {
            AgentPortrait(id:id,size:size,avatar:true,motion:false,tapFeedback:false)
        } else {
            Image(systemName:id == "dot" ? "sparkles" : id == "doubao" ? "bubble.left.and.text.bubble.right.fill" : "person.crop.square")
                .font(.system(size:size*0.8)).foregroundStyle(theme.primaryLabel).frame(width:size,height:size)
                .accessibilityLabel(id == "dot" ? "Dot" : id == "doubao" ? "豆包工作" : "自定义Agent")
        }
    }
}

struct AgentPrimarySwitchNotice {
    let id=UUID()
    let profileID:String
    let name:String
    var message:String { "已切换为"+name }
}
struct AgentPrimarySwitchStatus:View {
    let notice:AgentPrimarySwitchNotice
    let running:Bool
    @Environment(\.nookResolvedTheme) private var theme
    var body:some View {
        HStack(spacing:6) {
            if running { AgentStatusLight(color:.red,motion:false) }
            Image(systemName:"checkmark.circle.fill").foregroundStyle(.green)
            Text(notice.message).foregroundStyle(theme.primaryLabel)
        }.font(.system(size:11,weight:.semibold)).lineLimit(1)
        .accessibilityElement(children:.ignore).accessibilityLabel(notice.message+(running ? "，正在运行（红色运行指示灯）":""))
    }
}
