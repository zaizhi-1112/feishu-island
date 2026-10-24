import NookApp
import SwiftUI

/// One navigation bar for both code lines; all settings stay in the ordinary window.
struct IntegrationTopBar: View {
    let bar: NookTopBarContext
    @ObservedObject private var attention = IslandModuleAttention.shared
    @Environment(\.nookNotchCutout) private var cutout
    @Environment(\.nookResolvedTheme) private var theme
    var body: some View {
        VStack(spacing: 0) {
            if !cutout.isEmpty { Color.clear.frame(height: cutout.height) }
            HStack(spacing: 6) {
                if bar.canGoBack {
                    Button { bar.goBack() } label: { Image(systemName: "chevron.left").frame(width: 24,height:24) }.help("返回")
                } else if let switcher = bar.moduleSwitcher {
                    ForEach(switcher.modules.filter { [IslandHost.workspaceID,IslandHost.feishuID,IslandHost.agentID].contains($0.id) }) { module in
                        Button {
                            if module.id == IslandHost.workspaceID { IslandModuleNavigation.shared.openWorkspace() }
                            else { switcher.switchTo(module.id) }
                        } label: {
                            Image(systemName: module.icon).frame(width: 26,height:24)
                                .foregroundStyle(switcher.activeID == module.id ? theme.accent : theme.secondaryLabel)
                                .overlay(alignment:.bottom) { if attention.hints[module.id] != nil { Circle().fill(theme.accent).frame(width:4,height:4).offset(y:3) } }
                                .background(switcher.activeID == module.id ? theme.accent.opacity(0.14) : .clear,in:RoundedRectangle(cornerRadius:6))
                        }.help(module.displayName + " · 双指左右滑动切换").accessibilityLabel(module.displayName)
                    }
                }
                Spacer(minLength:4)
                Button { WorkspaceWindow.shared.open(store:.shared) } label: { Image(systemName:"macwindow").frame(width:24,height:24) }.help("打开工作台")
                Button { WorkspaceWindow.shared.openSettings(store:.shared) } label: { Image(systemName:"gearshape").frame(width:24,height:24) }.help("工作台设置")
                Button { bar.toggleKeepOpen() } label: { Image(systemName:bar.isKeepOpen ? "lock.fill" : "lock.open").frame(width:24,height:24) }.help("保持展开")
            }.frame(height:28)
        }.buttonStyle(.plain).font(.system(size:12)).foregroundStyle(theme.secondaryLabel)
    }
}

/// Skins do not require monitoring. Reading other agents is an explicit local opt-in.
struct IntegrationAgentSettings: View {
    @ObservedObject private var store = AgentStore.shared
    var body: some View {
        VStack(alignment:.leading,spacing:22) {
            Text("选择你的岛").font(.system(size:20,weight:.semibold))
            IslandSkinSettings(store:store)
            Divider()
            Text("本机 Agent 状态").font(.system(size:18,weight:.semibold))
            Text("与“交给 AI”分开。开启后，仅读取你选中的本机客户端任务状态与额度；不把聊天材料交给其他 Agent。").foregroundStyle(.secondary)
            Toggle("开启本机状态监测",isOn:Binding(get:{store.preferences.enabled},set:{ value in var next=store.preferences; next.enabled=value; save(next) }))
            ForEach(store.preferences.profiles) { profile in
                Toggle(profile.name,isOn:Binding(get:{store.preferences.visibleIDs.contains(profile.id)},set:{ value in
                    var next=store.preferences
                    var ids=next.visibleIDs.filter{$0 != profile.id}; if value { ids.append(profile.id) }
                    next.setVisibleIDs(ids); save(next)
                })).disabled(profile.id == "claude")
            }
            Text("Claude 暂未接通。关闭的来源不会读取；额度未知时不会显示为零。").font(.system(size:13)).foregroundStyle(.secondary)
            AgentPanel(store:store)
        }.font(.system(size:15)).frame(maxWidth:680,alignment:.leading)
    }
    private func save(_ next:AgentPreferences) { do { try store.update(next) } catch { WorkspaceStore.shared.error=error.localizedDescription } }
}
