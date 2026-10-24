import NookApp
import SwiftUI

/// Reuse the framework's working controls inside the product's themed settings.
struct IslandSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.nookResolvedTheme) private var theme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("皮肤设置").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                IslandSkinSettings(store: .shared)
                    .padding(12).modifier(IslandCard(radius: 16))
                NookSettingsGroup("待办设置", isInitiallyExpanded: false) {
                    TodoSettingsView(store: .shared)
                }
                NookSettingsGroup("外观与材质", isInitiallyExpanded: false) {
                    NookAppearanceSettingsSection(appState: appState)
                }
                NookSettingsGroup("显示屏", isInitiallyExpanded: false) {
                    NookDisplaySettingsSection(appState: appState)
                }
                NookSettingsGroup("快捷键与交互", isInitiallyExpanded: false) {
                    NookShortcutSettingsSection(appState: appState)
                }
                NookSettingsGroup("关于", isInitiallyExpanded: false) {
                    NookAboutSettingsSection()
                }
                Button { SettingsServer.shared.open(section: "skins") } label: {
                    Label("打开完整设置面板", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                }.buttonStyle(IslandButtonStyle(prominent: true))
                Text("柚子岛 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.system(size: 10)).foregroundStyle(theme.tertiaryLabel)
            }.padding(.horizontal, 10).padding(.vertical, 8)
        }.frame(maxHeight: 400)
            .foregroundStyle(theme.primaryLabel)
            
            .accessibilityIdentifier("island.settings")
    }
}
