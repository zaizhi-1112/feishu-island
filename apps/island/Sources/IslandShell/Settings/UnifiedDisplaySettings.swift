import AppKit
import NookApp
import SwiftUI

struct UnifiedDisplaySettings: View {
    @ObservedObject var appState: AppState
    @State private var displays = NookScreenLocator.connectedDisplays()
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            option("自动选择", detail: "优先外接屏；断开后自动回到可用屏幕。", symbol: "display.2", preference: .automatic)
            option("内置显示屏", detail: "使用Mac自身的屏幕，未连接时回退到可用屏幕。", symbol: "laptopcomputer", preference: .builtIn)
            option("主显示屏", detail: "跟随系统中设置的主显示屏。", symbol: "menubar.rectangle", preference: .main)
            if !displays.isEmpty {
                Text("固定在一块显示屏").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.secondaryLabel).padding(.top, 12)
                ForEach(displays, id: \.uuid) { display in
                    option(display.name, detail: "记住这块屏幕，重新连接后自动恢复。", symbol: "display", preference: .specific(display.uuid))
                }
            }
            if appState.displayPreference.mode == .specific,
               let uuid = appState.displayPreference.displayUUID,
               !displays.contains(where: { $0.uuid == uuid }) {
                Label("已选的显示屏未连接，暂用可用屏幕；重连后恢复。", systemImage: "display.trianglebadge.exclamationmark")
                    .font(.system(size: 12)).foregroundStyle(theme.warning).padding(.top, 8)
            }
            Text("选择后立即生效。所有屏幕统一使用悬浮胶囊，展开尺寸保持一致。")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).padding(.top, 8)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = NookScreenLocator.connectedDisplays()
        }
    }

    private func option(_ title: String, detail: String, symbol: String, preference: NookDisplayPreference) -> some View {
        let selected = appState.displayPreference == preference
        return Button { appState.replaceDisplayPreference(preference) } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 23)).foregroundStyle(theme.accent).frame(width: 36)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.primaryLabel)
                    Text(detail).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? theme.accent : theme.tertiaryLabel)
            }.padding(14)
                .background(selected ? theme.accent.opacity(0.08) : theme.subtleFill, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? theme.accent.opacity(0.5) : theme.subtleStroke, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
