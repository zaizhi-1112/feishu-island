import AppKit
import NookApp
import SwiftUI

@MainActor
final class AgentModule: NookModule {
    nonisolated static let info: NookModuleDescriptor = {
        var info = NookModuleDescriptor(id: IslandHost.agentID, displayName: "Agent 状态", icon: "sparkles", backgroundPolicy: .stayResident)
        info.loadsAtLaunch = true; return info
    }()
    var descriptor: NookModuleDescriptor { Self.info }
    init(context: NookModuleContext) { AgentStore.shared.start(activities: context.services.resolve(NookLiveActivitiesKey.self)) }
    func makeConfiguration() -> NookConfiguration {
        var config = IslandHost.baseConfiguration(title: "Agent状态", symbol: "sparkles")
        config.setCompactLeading { AgentCompanionGlyph(store:.shared) }
        config.setCompactTrailing { AgentCompactView(store:.shared) }
        config.allowsHorizontalModuleSwipe = true
        config.setHome { UnifiedAgentIslandView(store:.shared).islandTextSize() }
        config.onReady = { IslandModuleNavigation.shared.bind(coordinator:$0) }
        return config
    }
}

extension AgentState {
    var color: Color {
        switch self { case .working: return .red; case .completed: return .green; case .waiting, .failed: return .orange; case .unknown: return .gray }
    }
}

struct AgentStatusDot: View {
    @ObservedObject var store: AgentStore
    var body: some View {
        Circle().fill(store.state.color).frame(width: 8, height: 8)
            .shadow(color: store.state.color.opacity(0.6), radius: 4)
            .accessibilityLabel("\(store.primary.name)，\(store.state.label)")
    }
}
struct AgentCompactView: View {
    @ObservedObject var store: AgentStore
    @Environment(\.nookResolvedTheme) private var theme
    var body: some View {
        HStack(spacing:6) {
            if store.state == .working { AgentStatusLight(color:.red,motion:false) }
            Text(store.preferences.isMonitoring(store.primary.id) ? "\(store.primary.name) · \(store.state == .working ? "正在运行" : store.state == .completed ? "已完成" : store.state == .waiting ? "等你确认" : store.state == .failed ? "任务中断" : "等待数据")" : "监测已暂停")
        }
        .islandFont(size:10,weight:.medium).foregroundStyle(theme.secondaryLabel).lineLimit(1).truncationMode(.tail).frame(maxWidth:200)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(store.state == .working ? store.primary.name+" · 正在运行（红色运行指示灯）" : store.primary.name+" · "+store.state.label)
    }
}
struct AgentPanel: View {
    @ObservedObject var store: AgentStore
    @Environment(\.nookResolvedTheme) private var theme
    @State private var profileID: String?
    init(store: AgentStore, profileID: String? = nil) {
        self.store = store
        _profileID = State(initialValue: profileID)
    }
    private var profile: AgentProfile { store.preferences.islandProfile(preferredID:profileID) ?? store.primary }
    private var snapshot: AgentSnapshot { store.snapshots[profile.id] ?? AgentSnapshot() }
    private var monitoring: Bool { store.preferences.isMonitoring(profile.id) }
    private var state: AgentState { store.state(for:profile.id) }
    private var skin: AgentSkin { store.selectedSkin }
    var body: some View {
        IslandContentScroll {
            VStack(alignment: .leading, spacing: 14) {
                if store.preferences.visibleProfiles.count > 1 {
                  HStack(spacing: 8) {
                    ForEach(store.preferences.visibleProfiles) { profile in
                        Button { self.profileID = profile.id; store.selectPrimary(profile.id) } label: {
                            HStack(spacing: 5) {
                                AgentBrandIcon(id: profile.id, size: 18, motion: store.preferences.effectsEnabled)
                                Text(profile.name).islandFont(size: 11, weight: .medium).lineLimit(1)
                            }.frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(self.profile.id == profile.id ? theme.accent.opacity(0.15) : Color.clear, in: Capsule())
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(self.profile.id == profile.id ? theme.accent : theme.secondaryLabel)
                            .accessibilityAddTraits(self.profile.id == profile.id ? [.isSelected] : [])
                    }
                  }
                }
                HStack {
                    AgentPortrait(id: profile.id, size: 70, state: state, motion: store.preferences.effectsEnabled)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.name).islandFont(size: 19, weight: .semibold)
                        Text(skin.greeting(state: state, enabled: monitoring))
                            .islandFont(size: 11).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Circle().fill(state.color).frame(width: 8, height: 8)
                            Text(profile.id == "deepseek" ? (snapshot.metrics.isEmpty ? "等待余额" : "账户余额") : monitoring ? state.label : "监测已暂停").islandFont(size: 10).foregroundStyle(theme.secondaryLabel)
                        }
                    }
                    Spacer()
                    if monitoring && snapshot.quotas.contains(where: { $0.isFresh(now: Date().timeIntervalSince1970) && $0.remainingPercent < 20 }) {
                        Label("额度预警", systemImage: "flame.fill").islandFont(size: 11).foregroundStyle(.orange)
                    }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [theme.accent.opacity(0.13), theme.accent.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(theme.accent.opacity(0.16), lineWidth: 0.7))
                if snapshot.quotas.isEmpty && snapshot.metrics.isEmpty {
                    Text("此来源尚未提供额度或指标").islandFont(size: 14, weight: .medium).foregroundStyle(theme.secondaryLabel).padding(.vertical, 12)
                } else {
                    ForEach(snapshot.quotas.prefix(4)) { quota in
                        AgentQuotaRow(quota: quota)
                    }
                }
                ForEach(snapshot.metrics) { metric in AgentMetricRow(metric:metric) }
                Text(snapshot.detail).islandFont(size: 11).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button { Task { await store.poll(); store.refreshQuotas() } } label: {
                        Label(store.refreshing ? "读取中…" : "刷新状态", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                    }.buttonStyle(IslandButtonStyle(prominent: true)).disabled(store.refreshing || !(monitoring || (profile.id=="codex" && store.preferences.quotaDisplayEnabled)))
                    if profile.kind != "file" { Button { store.openAgent(profile.id) } label: { Image(systemName: "arrow.up.right.square") }.buttonStyle(IslandButtonStyle()) }
                }
                Text("\(skin.title) · \(store.preferences.skinID == "auto" ? "跟随主用Agent" : "自选皮肤")").islandFont(size: 10).foregroundStyle(theme.secondaryLabel).frame(maxWidth: .infinity)
            }.padding(14).foregroundStyle(theme.primaryLabel).accessibilityIdentifier("island.agentPanel")
        }
            .modifier(IslandReadingModule(moduleID: IslandHost.agentID))

    }
}
private struct AgentMetricRow: View {
    let metric: AgentMetric
    @Environment(\.nookResolvedTheme) private var theme
    var body: some View {
        let fresh=metric.isFresh(now:Date().timeIntervalSince1970)
        HStack(alignment:.firstTextBaseline) {
            Text(metric.label).islandFont(size:11).foregroundStyle(theme.secondaryLabel)
            Spacer()
            Text(metric.displayNumber)
                .islandFont(size:23,weight:.medium,design:.rounded).lineLimit(1).minimumScaleFactor(0.6)
            Text(metric.unit).islandFont(size:11).foregroundStyle(theme.secondaryLabel)
            if !fresh { Text("上次记录").islandFont(size:10).foregroundStyle(theme.secondaryLabel) }
        }.padding(.vertical,5)
    }
}
private struct AgentBrandIcon: View {
    let id: String
    let size: CGFloat
    let motion: Bool
    var body: some View {
        AgentPortrait(id: id, size: size, avatar: true, motion: motion, tapFeedback: false).accessibilityHidden(true)
    }
}
private struct AgentQuotaRow: View {
    let quota: AgentQuota
    @Environment(\.nookResolvedTheme) private var theme
    var body: some View {
        let fresh = quota.isFresh(now: Date().timeIntervalSince1970)
        let accent = !fresh ? Color.gray : quota.remainingPercent < 20 ? Color.orange : theme.accent
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(quota.remainingUnits != nil ? "剩余积分" : quota.label).islandFont(size: 11).foregroundStyle(theme.secondaryLabel)
                Spacer()
                if let left = quota.remainingUnits {
                    Text(left, format: .number.precision(.fractionLength(0...2)))
                        .islandFont(size: 26, weight: .medium, design: .rounded).monospacedDigit()
                    Text(fresh ? "积分" : "积分 · 上次记录").islandFont(size: 10).foregroundStyle(theme.secondaryLabel)
                } else {
                    Text("\(quota.remainingPercent, specifier: "%.1f")%").islandFont(size: 26, weight: .medium, design: .rounded)
                    Text(fresh ? "剩余" : "上次记录").islandFont(size: 10).foregroundStyle(theme.secondaryLabel)
                }
            }
            GeometryReader { geometry in
                Capsule().fill(theme.subtleFill)
                    .overlay(alignment: .leading) { Capsule().fill(accent).frame(width: geometry.size.width * min(100, max(0, quota.remainingPercent)) / 100) }
            }.frame(height: 5)
            HStack {
                if quota.remainingUnits != nil, let total = quota.totalUnits {
                    Text("总计\(total, specifier: "%.0f")积分 · 剩余\(quota.remainingPercent, specifier: "%.1f")%")
                } else if let reset = quota.resetsAt {
                    Text("重置：\(Date(timeIntervalSince1970: reset).formatted(date: .abbreviated, time: .shortened))")
                }
                if quota.resetsAt == nil && quota.remainingUnits == nil {
                    Text("重置时间暂未提供")
                }
                Spacer()
            }.islandFont(size: 9).foregroundStyle(theme.secondaryLabel)
        }
    }
}
