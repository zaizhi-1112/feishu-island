import NookApp
import SwiftUI

/// One navigation bar for both code lines; all settings stay in the ordinary window.
struct IntegrationTopBar: View {
    let bar: NookTopBarContext
    @ObservedObject private var attention = IslandModuleAttention.shared
    @Environment(\.nookNotchCutout) private var cutout
    @Environment(\.nookResolvedTheme) private var theme
    var body: some View {
        VStack(spacing: 6) {
            if !cutout.isEmpty { Color.clear.frame(height: cutout.height) }
            HStack(spacing: 3) {
                if let switcher=bar.moduleSwitcher {
                    ForEach(switcher.modules.filter { IslandHost.moduleIDs.contains($0.id) }) { module in
                        Button { switcher.switchTo(module.id) } label: {
                            HStack(spacing:4) {
                                Image(systemName:module.icon)
                                Text(module.id == IslandHost.feishuID ? "消息" : module.id == IslandHost.agentID ? "Agent" : module.id == IslandHost.todoID ? "待办" : "中台")
                            }.font(.system(size:12,weight:.medium)).padding(.horizontal,9).frame(height:IslandHost.navigationHeight)
                                .foregroundStyle(switcher.activeID==module.id ? theme.accent:theme.secondaryLabel)
                                .background(switcher.activeID==module.id ? theme.accent.opacity(0.14):.clear,in:Capsule())
                                .overlay(alignment:.topTrailing) { if attention.hints[module.id] != nil { Circle().fill(theme.accent).frame(width:4,height:4) } }
                        }.help(module.displayName).accessibilityLabel(module.displayName).accessibilityIdentifier("unified.module."+module.id)
                    }
                }
                Spacer(minLength:0)
                Button { bar.toggleKeepOpen() } label: {
                    Image(systemName:bar.isKeepOpen ? "lock.fill" : "lock.open")
                        .frame(width:26,height:IslandHost.navigationHeight)
                        .foregroundStyle(bar.isKeepOpen ? theme.accent : theme.secondaryLabel)
                        .background(bar.isKeepOpen ? theme.accent.opacity(0.14) : .clear,in:RoundedRectangle(cornerRadius:7))
                }.help(bar.isKeepOpen ? "解锁，恢复自动收起" : "锁定，保持展开")
                    .accessibilityLabel(bar.isKeepOpen ? "解锁灵动岛" : "锁定灵动岛")
                    .accessibilityValue(bar.isKeepOpen ? "已锁定" : "未锁定")
                    .accessibilityAddTraits(bar.isKeepOpen ? .isSelected : [])
                    .accessibilityIdentifier("unified.keepOpen")
                Button {
                    let section: UnifiedSettingsSection
                    switch bar.moduleSwitcher?.activeID {
                    case IslandHost.agentID: section = .agents
                    case IslandHost.todoID: section = .todos
                    case IslandHost.platformID: section = .platform
                    default: section = .messages
                    }
                    UnifiedSettingsWindow.shared.open(section: section)
                } label: { Image(systemName:"gearshape").frame(width:26,height:IslandHost.navigationHeight) }
                    .help("打开当前栏目的设置").accessibilityLabel("打开设置").accessibilityIdentifier("unified.openSettings")
            }
        }.buttonStyle(.plain).foregroundStyle(theme.secondaryLabel)
    }
}
struct UnifiedIslandPeek: View, Sendable {
    let title:String
    let symbol:String
    var body:some View {
        VStack(spacing:7) {
            Capsule().fill(.white.opacity(0.65)).frame(width:74,height:2)
            HStack(spacing:7) { Image(systemName:symbol); Text(title); Image(systemName:"chevron.down").font(.system(size:9)) }
                .font(.system(size:12,weight:.medium)).foregroundStyle(.white.opacity(0.92))
            Text("点击展开").font(.system(size:10)).foregroundStyle(.white.opacity(0.55))
        }.frame(maxWidth:220).padding(.vertical,8)
    }
}


struct IslandCompactTitle: View {
    let title: String
    @Environment(\.nookResolvedTheme) private var theme
    var body: some View {
        Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(theme.primaryLabel)
    }
}
