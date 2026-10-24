import SwiftUI

/// Only the Codex bucket is combined. Missing windows never become zero or another model's limits.
struct AgentQuotaCompactSummary {
    let quotas:[AgentQuota]
    let refreshing:Bool
    let now:Double
    var windows:[AgentQuota] {
        let codex=quotas.filter{$0.id.hasPrefix("codex/")}
        guard !codex.isEmpty else { return [] }
        return Array(codex.prefix(2))
    }
    func quota(leading:Bool)->AgentQuota? {
        if windows.count>1 { return windows[leading ? 0:1] }
        return leading ? nil:windows.first
    }
    func text(leading:Bool)->String {
        if let quota=quota(leading:leading) {
            guard quota.isFresh(now:now) else { return "待刷新" }
            let name=quota.label.components(separatedBy:" · ").last ?? quota.label
            let short=name.replacingOccurrences(of:"额度",with:"").replacingOccurrences(of:"小时",with:"h").replacingOccurrences(of:"分钟",with:"分")
            return short+" "+String(format:"%.0f%%",quota.remainingPercent)
        }
        return leading ? "Codex" : refreshing ? "读取中" : "额度未知"
    }
    func accessibility(leading:Bool)->String {
        if let quota=quota(leading:leading),quota.isFresh(now:now) { return "Codex "+quota.label+"剩余 "+String(format:"%.0f%%",quota.remainingPercent) }
        return leading && windows.count<2 ? "Codex" : "Codex额度"+(refreshing ? "读取中" : windows.isEmpty ? "未知" : "已过期，等待刷新")
    }
}

struct AgentQuotaCompactSlot:View,Sendable {
    @ObservedObject var store:AgentStore
    let leading:Bool
    var body:some View {
        TimelineView(.periodic(from:.now,by:30)) { context in
            let summary=AgentQuotaCompactSummary(quotas:store.snapshots["codex"]?.quotas ?? [],refreshing:store.refreshing,now:context.date.timeIntervalSince1970)
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
                if leading { Image(systemName:"chart.pie.fill").font(.system(size:11)).foregroundStyle(.mint) }
                Text(summary.text(leading:leading)).font(.system(size:11,weight:.semibold,design:.rounded)).monospacedDigit()
                    .foregroundStyle(fresh && (quota?.remainingPercent ?? 100)<20 ? Color.orange : Color.white.opacity(0.9))
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
        if store.preferences.quotaDisplayEnabled { AgentQuotaCompactSlot(store:store,leading:leading) }
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
