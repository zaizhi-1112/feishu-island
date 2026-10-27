import NookApp
import SwiftUI

/// Reuses the live shell's preference controls in the ordinary workbench window.
/// It owns neither an AppState copy nor a nested scroll view.
struct WorkspaceShellSettings: View {
    @ObservedObject private var navigation = IslandModuleNavigation.shared
    var body: some View {
        if let state = navigation.appState {
            WorkspaceShellPreferenceSections(appState: state)
        } else {
            Text("灵动岛启动后，可在这里设置外观、显示屏和快捷键。")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
}

private struct WorkspaceShellPreferenceSections: View {
    @ObservedObject var appState: AppState
    var body: some View {
        let chrome = IslandDesign.chrome
        VStack(alignment: .leading, spacing: 24) {
            NookSettingsGroup("灵动岛外观") { NookAppearanceSettingsSection(appState: appState) }
            NookSettingsGroup("显示屏") { NookDisplaySettingsSection(appState: appState) }
            NookSettingsGroup("快捷键与交互") { NookShortcutSettingsSection(appState: appState) }
        }
        .environment(\.nookResolvedTheme, NookResolvedTheme.live(appState: appState, theme: chrome))
        .environment(\.nookTheme, chrome)
        .environment(\.nookThemeTokens, chrome.resolvedTokens())
        .environment(\.nookChromeLabels, IslandLabels.chinese)
        .environment(\.nookHostBranding, NookHostBranding(hostName: "一切在岛", hostTagline: "常用功能，抬手即达。"))
        .environment(\.nookChromeActions, NookChromeActions(
            toggleKeepOpen: { IslandModuleNavigation.shared.toggleKeepOpen() },
            toggleSettings: {}, collapse: {},
            // This normal workbench window already owns the keyboard while recording.
            // Calling the island's focus action here would send typing to another window.
            takeKeyboardFocus: {}, releaseKeyboardFocus: {}
        ))
        .accessibilityIdentifier("workspace.shellSettings")
    }
}
