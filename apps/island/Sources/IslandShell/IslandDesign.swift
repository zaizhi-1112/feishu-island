import NookApp
import SwiftUI

/// Shared with SettingsWeb: warm light surfaces, graphite dark cards, and a restrained teal accent.
/// Keep the physical notch's outer surface and interaction geometry owned by OpenNook.
enum IslandDesign {
    static var chrome: NookTheme {
        var theme = NookTheme(name: "柚子岛 · 清晰", accent: .adaptive(.init(dark: "#12CCD8", light: "#176B75")))
        theme.tokens[.labelPrimary] = .adaptive(.init(dark: "#E7ECEB", light: "#202A30"))
        theme.tokens[.labelSecondary] = .adaptive(.init(dark: "#B2BDBF", light: "#59656B"))
        theme.tokens[.labelTertiary] = .adaptive(.init(dark: "#94A3A8", light: "#657176"))
        theme.tokens[.labelQuaternary] = .adaptive(.init(dark: "#74858C", light: "#7A878B"))
        theme.tokens[.fillSubtle] = .adaptive(.init(dark: "#1A2226", light: "#F5F6F3"))
        theme.tokens[.strokeSubtle] = .adaptive(.init(dark: "#FFFFFF16", light: "#DFE4E1"))
        theme.tokens[.iconInactive] = .adaptive(.init(dark: "#A5B0B3", light: "#59656B"))
        theme.tokens[.topBarLabel] = NookFontSpec(size: .points(11), weight: .medium)
        theme.tokens[.headerIconCornerRadius] = 7
        theme.tokens[.settingsSectionLabelTracking] = 0
        return theme
    }
}

struct IslandCard: ViewModifier {
    @Environment(\.nookResolvedTheme) private var theme
    var highlighted = false
    var radius: CGFloat = 10
    func body(content: Content) -> some View {
        content
            .background(theme.subtleFill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .strokeBorder(highlighted ? theme.accent.opacity(0.28) : theme.subtleStroke, lineWidth: 0.8))
    }
}

struct IslandButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .islandFont(size: 11, weight: .medium)
            .padding(.vertical, 8).padding(.horizontal, 11)
            .foregroundStyle(prominent ? theme.accent : theme.secondaryLabel)
            .background(prominent ? theme.accent.opacity(0.12) : theme.subtleFill, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(prominent ? theme.accent.opacity(0.24) : theme.subtleStroke, lineWidth: 0.8))
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
    }
}

struct IslandCompactGlyph: View {
    let symbol: String
    @Environment(\.nookResolvedTheme) private var theme
    var body: some View {
        Image(systemName: symbol).islandFont(size: 12, weight: .medium).foregroundStyle(theme.accent)
    }
}

struct IslandAlertLabel: View {
    let count: Int
    let expanded: Bool
    @Environment(\.nookResolvedTheme) private var theme
    var body: some View {
        Text(expanded ? "\(count)条重要消息 · 点击查看" : "\(count)条")
            .islandFont(size: expanded ? 12 : 11, weight: .medium)
            .foregroundStyle(theme.primaryLabel)
            .padding(.horizontal, expanded ? 12 : 0).padding(.vertical, expanded ? 8 : 0)
    }
}
