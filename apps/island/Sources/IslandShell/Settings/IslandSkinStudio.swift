import NookApp
import SwiftUI

/// The original web gallery's hierarchy, using the island's real theme and artwork.
/// Preview controls only change this view; selection writes through the existing store.
struct IslandSkinStudio: View {
    @ObservedObject var store: AgentStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.nookResolvedTheme) private var theme
    @State private var contentWidth: CGFloat = 700
    @State private var previewMode: SkinStudioPreviewMode = .expanded
    private var dark: Bool { scheme == .dark }
    private var skin: AgentSkin { store.selectedSkin }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            showcase
            HStack(alignment: .firstTextBaseline) {
                Text("挑一款喜欢的").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("4款皮肤").font(.system(size: 11)).foregroundStyle(theme.tertiaryLabel)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: contentWidth >= 640 ? 4 : 2), spacing: 12) {
                ForEach(AgentSkin.allCases, id: \.rawValue) { candidate in
                    SkinStudioChoice(skin: candidate, selected: skin == candidate,
                                     motion: store.preferences.effectsEnabled) {
                        store.selectSkin(candidate.rawValue)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { preferences }
                    VStack(alignment: .leading, spacing: 12) { preferences }
                }
                Text(store.preferences.skinID == "auto"
                     ? "当前跟随\(store.primary.name)，切换主用Agent时一起换肤。"
                     : "当前：\(skin.title)。手动选择皮肤不会改变主用Agent。")
                    .font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                Text("点选即生效，自动保存。系统开启“减少动态效果”时使用静态材质。")
                    .font(.system(size: 10)).foregroundStyle(theme.tertiaryLabel)
            }
            .padding(.top, 2)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        .accessibilityIdentifier("island.skinStudio")
    }

    @ViewBuilder private var preferences: some View {
        Toggle("跟随主用Agent", isOn: Binding(
            get: { store.preferences.skinID == "auto" },
            set: { store.selectSkin($0 ? "auto" : store.selectedSkin.rawValue) }
        ))
        .toggleStyle(.switch).fixedSize()
        .accessibilityIdentifier("island.skinStudio.follow")
        Toggle("少量动态效果", isOn: Binding(
            get: { store.preferences.effectsEnabled },
            set: { store.setEffectsEnabled($0) }
        ))
        .toggleStyle(.switch).fixedSize()
        .accessibilityIdentifier("island.skinStudio.effects")
    }

    private var showcase: some View {
        Group {
            if contentWidth >= 660 {
                HStack(spacing: 16) {
                    introduction.frame(maxWidth: .infinity, alignment: .leading)
                    SkinStudioArtwork(skin: skin, size: 118, motion: store.preferences.effectsEnabled)
                        .frame(width: 128)
                    livePreview.frame(width: 218)
                }
            } else {
                VStack(spacing: 18) {
                    HStack(spacing: 12) {
                        introduction.frame(maxWidth: .infinity, alignment: .leading)
                        SkinStudioArtwork(skin: skin, size: 110, motion: store.preferences.effectsEnabled)
                            .frame(width: 132)
                    }
                    livePreview.frame(maxWidth: 280)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background { IslandSkinBackdrop(store: store, dark: dark, compact: false, notched: false) }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(theme.subtleStroke, lineWidth: 1) }
        .accessibilityIdentifier("island.skinStudio.showcase")
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前皮肤").font(.system(size: 10, weight: .medium)).foregroundStyle(theme.tertiaryLabel)
            Text(skin.title).font(.system(size: 20, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(skin.definition.subtitle).font(.system(size: 11))
                .foregroundStyle(theme.secondaryLabel).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text("胶囊、功能页和设置一起换肤")
                .font(.system(size: 10)).foregroundStyle(theme.secondaryLabel)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(theme.subtleFill, in: Capsule())
        }
    }

    private var livePreview: some View {
        VStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(SkinStudioPreviewMode.allCases) { mode in
                    Button { previewMode = mode } label: {
                        Text(mode.rawValue).font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(previewMode == mode ? theme.subtleFill : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(previewMode == mode ? theme.primaryLabel : theme.secondaryLabel)
                    .accessibilityAddTraits(previewMode == mode ? [.isSelected] : [])
                    .accessibilityIdentifier("island.skinStudio.preview.\(mode.id)")
                }
            }
            .padding(3).overlay { Capsule().strokeBorder(theme.subtleStroke) }
            SkinStudioIslandPreview(store: store, mode: previewMode, dark: dark)
                .frame(height: 134)
            Text("实时主题预览 · 角色按主用Agent显示")
                .font(.system(size: 9)).foregroundStyle(theme.tertiaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum SkinStudioPreviewMode: String, CaseIterable, Identifiable {
    case capsule = "胶囊", expanded = "展开", settings = "设置"
    var id: String { String(describing: self) }
}

private struct SkinStudioChoice: View {
    let skin: AgentSkin
    let selected: Bool
    let motion: Bool
    let select: () -> Void
    @Environment(\.nookResolvedTheme) private var theme
    // Match the web collection's distinctive graphite, paper, mint and ink swatches.
    private var palette: SkinPalette { skin.palette(dark: skin == .codex || skin == .virxact) }

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    LinearGradient(colors: [Color(skinHex: palette.well), Color(skinHex: palette.bg)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    SkinStudioArtwork(skin: skin, size: 96, motion: motion)
                        .foregroundStyle(Color(skinHex: palette.ink))
                }
                .frame(height: 122).clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .symbolRenderingMode(.palette).foregroundStyle(.black.opacity(0.8), .white)
                            .padding(7)
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(skin.title).font(.system(size: 11, weight: .semibold))
                        .lineLimit(2).frame(height: 28, alignment: .topLeading)
                    Text(skin.definition.subtitle).font(.system(size: 9))
                        .foregroundStyle(theme.secondaryLabel).lineLimit(2)
                        .frame(height: 25, alignment: .topLeading)
                }
                .padding(.horizontal, 6).padding(.top, 12).padding(.bottom, 8)
            }
            .padding(7).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.subtleFill.opacity(0.6), in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(selected ? theme.accent : theme.subtleStroke, lineWidth: selected ? 1.6 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.primaryLabel)
        .accessibilityLabel("选择皮肤：\(skin.title)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("island.skinStudio.choice.\(skin.rawValue)")
    }
}

private struct SkinStudioArtwork: View {
    let skin: AgentSkin
    let size: CGFloat
    let motion: Bool
    var body: some View {
        Group {
            if skin == .virxact, let image = SkinResources.images["virxact-logo.png"] {
                Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
                    .frame(maxWidth: .infinity).padding(.horizontal, 12)
                    .accessibilityLabel("虚实传媒完整字标")
            } else {
                AgentPortrait(id: skin.rawValue, size: size, motion: motion, tapFeedback: false)
            }
        }
    }
}

private struct SkinStudioIslandPreview: View {
    @ObservedObject var store: AgentStore
    let mode: SkinStudioPreviewMode
    let dark: Bool
    @Environment(\.nookResolvedTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if mode != .capsule {
                HStack {
                    Text("你的飞包")
                    Spacer()
                    Image(systemName: "gearshape")
                }.font(.system(size: 8)).foregroundStyle(theme.tertiaryLabel)
            }
            HStack(spacing: 8) {
                AgentPortrait(id: store.primary.id, size: mode == .capsule ? 24 : 32, avatar: true,
                              state: store.state, motion: store.preferences.effectsEnabled, tapFeedback: false)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.primary.name).font(.system(size: 10, weight: .semibold))
                    Text(store.preferences.enabled ? store.state.label : "监测已暂停")
                        .font(.system(size: 8)).foregroundStyle(theme.secondaryLabel)
                }
                Spacer(minLength: 0)
                Circle().fill(store.state.color).frame(width: 5, height: 5)
            }
            if mode == .expanded {
                HStack(spacing: 6) {
                    previewLabel("飞书消息")
                    previewLabel("待办")
                }
            } else if mode == .settings {
                HStack(spacing: 6) {
                    previewLabel("皮肤")
                    previewLabel("外观")
                    previewLabel("显示屏")
                }
            }
        }
        .padding(mode == .capsule ? 12 : 14)
        .background { IslandSkinBackdrop(store: store, dark: dark, compact: true, notched: false) }
        .clipShape(RoundedRectangle(cornerRadius: mode == .capsule ? 28 : 16))
        .overlay { RoundedRectangle(cornerRadius: mode == .capsule ? 28 : 16).strokeBorder(theme.subtleStroke) }
        .frame(maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mode.rawValue)预览，\(store.selectedSkin.title)，主用\(store.primary.name)")
    }
    private func previewLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 8)).foregroundStyle(theme.secondaryLabel)
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(theme.subtleFill, in: RoundedRectangle(cornerRadius: 5))
    }
}
