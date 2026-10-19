import AppKit
import NookApp
import SwiftUI

struct IslandHomeView: View {
    @Environment(\.nookChromeActions) private var actions
    @Environment(\.nookSwitchModule) private var switchModule
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("常用功能，抬手即达。")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.primaryLabel)
                    Text("消息与工具，留在桌面顶边。")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryLabel)
                }
                Spacer(minLength: 8)
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(theme.accent)
                    .frame(width: 32, height: 32)
                    .background(theme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            }
            DisplayStatusView()
            HStack(spacing: 8) {
                Button { switchModule?(IslandHost.sampleID) } label: {
                    Label("试用交互示例", systemImage: "square.stack.3d.up")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(IslandButtonStyle(prominent: true))
                    .accessibilityIdentifier("island.openSample")
                Button(action: actions.collapse) {
                    Label("收起", systemImage: "chevron.up")
                        .frame(width: 48)
                }.buttonStyle(IslandButtonStyle())
                    .accessibilityIdentifier("island.collapse")
            }
            Text("移到顶边露出 · 点击展开 · 移开收回")
                .font(.system(size: 10)).foregroundStyle(theme.tertiaryLabel)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 10)
        .accessibilityIdentifier("island.home")
    }
}

private struct DisplayStatusView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.nookResolvedTheme) private var theme
    @State private var revision = 0
    var body: some View {
        let _ = revision
        let screen = NookScreenLocator.screen(matching: appState.displayPreference)
        let notched = (screen?.safeAreaInsets.top ?? 0) > 0
        HStack(spacing: 8) {
            Image(systemName: notched ? "laptopcomputer" : "display")
                .font(.system(size: 17)).foregroundStyle(theme.secondaryLabel)
            VStack(alignment: .leading, spacing: 3) {
                Text(screen?.localizedName ?? "正在识别屏幕")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.primaryLabel)
                Text(appState.displayPreference.mode == .automatic ? "自动适配 · 优先外接屏" : "使用已选屏幕")
                    .font(.system(size: 10)).foregroundStyle(theme.secondaryLabel)
            }
            Spacer()
            Circle().fill(theme.accent).frame(width: 5, height: 5)
        }
        .padding(12).modifier(IslandCard())
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            revision += 1
        }
    }
}

struct SampleView: View {
    @ObservedObject var state: SampleState
    @Environment(\.nookSwitchModule) private var switchModule
    @Environment(\.nookResolvedTheme) private var theme
    var body: some View {
        VStack(spacing: 10) {
            Text("试试你的第一块模块")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.primaryLabel)
            Text("点击计数，切回首页后再来，数字还在。")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            Text("\(state.count)")
                .font(.system(size: 36, weight: .light))
                .monospacedDigit().foregroundStyle(theme.accent)
                .accessibilityIdentifier("island.sampleCount")
            HStack(spacing: 10) {
                Button { switchModule?(IslandHost.homeID) } label: {
                    Text("回到首页").frame(maxWidth: .infinity)
                }.buttonStyle(IslandButtonStyle())
                Button { state.increment() } label: {
                    Text("点一下 +1").frame(maxWidth: .infinity)
                }.buttonStyle(IslandButtonStyle(prominent: true))
                    .accessibilityIdentifier("island.increment")
            }
            Text("这是可移除的演示，后续换成你的常用功能。")
                .font(.system(size: 10)).foregroundStyle(theme.tertiaryLabel)
        }.padding(12).accessibilityIdentifier("island.sample")
    }
}
