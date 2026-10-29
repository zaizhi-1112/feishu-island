import SwiftUI

enum IslandTextSize: Double, CaseIterable, Identifiable {
    case standard = 1, large = 1.25, extraLarge = 1.5
    var id: Double { rawValue }
    var title: String {
        switch self { case .standard: return "标准"; case .large: return "大"; case .extraLarge: return "特大" }
    }
    static let preferenceKey = "island.contentTextScale"
    static func scale(_ value: Double) -> CGFloat { CGFloat(Self(rawValue: value)?.rawValue ?? 1) }
}
private struct IslandTextScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
extension EnvironmentValues {
    var islandTextScale: CGFloat {
        get { self[IslandTextScaleKey.self] }
        set { self[IslandTextScaleKey.self] = newValue }
    }
}
private struct IslandTextScope: ViewModifier {
    @AppStorage(IslandTextSize.preferenceKey) private var scale = 1.0
    func body(content: Content) -> some View {
        content.environment(\.islandTextScale, IslandTextSize.scale(scale))
            .font(.system(size: 13 * IslandTextSize.scale(scale)))
    }
}
private struct IslandScaledFont: ViewModifier {
    @Environment(\.islandTextScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    func body(content: Content) -> some View { content.font(.system(size: size * scale, weight: weight, design: design)) }
}
extension View {
    func islandTextSize() -> some View { modifier(IslandTextScope()) }
    func islandFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(IslandScaledFont(size: size, weight: weight, design: design))
    }
}
struct IslandTextSizeControls: View {
    @AppStorage(IslandTextSize.preferenceKey) private var scale = 1.0
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("岛内字号", selection: $scale) {
                ForEach(IslandTextSize.allCases) { value in Text(value.title).tag(value.rawValue) }
            }.pickerStyle(.segmented).accessibilityIdentifier("island.textSize")
            VStack(alignment: .leading, spacing: 8) {
                Text("今天的待办").islandFont(size: 14, weight: .semibold)
                Text("把重要的事，清楚地放在眼前。").islandFont(size: 14)
                Text("消息、Agent、待办与中台").islandFont(size: 10).foregroundStyle(.secondary)
            }.environment(\.islandTextScale, IslandTextSize.scale(scale))
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("island.textSize.preview")
            Text("立即生效，自动保存。桌面弹幕字号在“飞书消息”中单独调整。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
