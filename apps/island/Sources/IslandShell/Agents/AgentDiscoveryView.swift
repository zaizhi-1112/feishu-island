import SwiftUI

/// Discovery only inspects installed app bundles; activation is a separate explicit action.
struct AgentDiscoveryView: View {
    @ObservedObject var store: AgentStore
    @State private var discovered: [AgentSetupOption] = []
    @State private var searched = false
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(searched ? "重新获取本机 Agent" : "一键获取本机 Agent") {
                discovered = AgentSetupOption.all.filter { $0.native && $0.installedApplication != nil }
                searched = true
            }.buttonStyle(.borderedProminent).controlSize(.large)
            Text("找到工具后，点击“连接”才开始读取状态。也可以先不连接。")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if searched && discovered.isEmpty { Text("未找到支持的桌面工具，可稍后在设置中添加。").font(.caption) }
            ForEach(discovered) { option in
                HStack(spacing: 10) {
                    AgentIdentityIcon(id: option.id, size: 24)
                    Text(option.name).font(.system(size: 13, weight: .medium))
                    Spacer()
                    if store.preferences.isMonitoring(option.id) {
                        Text(!store.preferences.visibleIDs.contains(option.id) ? "监测已开启 · 未在岛上显示" : (store.snapshots[option.id]?.sessions.isEmpty == false || store.snapshots[option.id]?.quotas.isEmpty == false || store.snapshots[option.id]?.metrics.isEmpty == false ? "已收到数据" : "监测已开启 · 等待数据")).font(.caption).foregroundStyle(.secondary)
                    }
                    else { Button("连接") { connect(option.id) }.buttonStyle(.bordered) }
                }.padding(.vertical, 4)
            }
            if discovered.contains(where: { store.preferences.isMonitoring($0.id) && !store.preferences.visibleIDs.contains($0.id) }) {
                Text("岛上最多显示三个；可在设置的 Agent 状态中更换。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
    private func connect(_ id: String) {
        var preferences = store.preferences
        preferences.monitoredIDs = Array(Set(preferences.activeMonitorIDs + [id])).sorted()
        preferences.enabled = true; preferences.quotaDisplayEnabled = true
        if preferences.visibleIDs.count < 3 { preferences.setVisibleIDs(preferences.visibleIDs + [id]) }
        do { try store.update(preferences); error = "" } catch { self.error = error.localizedDescription }
    }
}
