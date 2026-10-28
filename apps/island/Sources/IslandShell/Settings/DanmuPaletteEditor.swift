import AppKit
import SwiftUI

struct DanmuPaletteEditor: View {
    let appearance: [String: Any]
    var preview: ([String: Any]?) -> Void
    var apply: ([String: Any]) -> Void
    @State private var colors: [String: String] = [:]
    @State private var notice = ""
    private let fields = [("foreground", "文字", "#FFFFFF"), ("background", "背景", "#15171C"), ("border", "边线", "#414753")]
    private var candidate: [String: Any] {
        appearance.merging(colors.mapValues { (Self.hex($0) ?? $0) as Any }) { _, new in new }.merging(["bubble": "custom"]) { _, new in new }
    }
    private var valid: Bool { AppearanceMCP.validate(candidate) != nil }
    static func hex(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let value = text.hasPrefix("#") ? text : "#" + text
        return value.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) == nil ? nil : value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(fields, id: \.0) { key, label, fallback in
                HStack(spacing: 12) {
                    Text(label).frame(width: 40, alignment: .leading)
                    ColorPicker(label, selection: Binding(get: {
                        Color(skinHex: Self.hex(colors[key] ?? fallback) ?? fallback)
                    }, set: { value in
                        guard let rgb = NSColor(value).usingColorSpace(.sRGB) else { return }
                        colors[key] = String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
                    }), supportsOpacity: false).labelsHidden().fixedSize()
                    TextField("#RRGGBB", text: Binding(get: { colors[key] ?? fallback }, set: { colors[key] = $0 }))
                        .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced)).frame(width: 105)
                        .accessibilityLabel(label + "颜色代码")
                        .onSubmit { if let hex = Self.hex(colors[key] ?? fallback) { colors[key] = hex } }
                    Button("复制") {
                        guard let hex = Self.hex(colors[key] ?? fallback) else { notice = "请输入六位颜色代码，例如 #FFFFFF。"; return }
                        NSPasteboard.general.clearContents()
                        notice = NSPasteboard.general.setString(hex, forType: .string) ? "已复制" : "复制失败，请重试"
                    }.buttonStyle(.link).accessibilityLabel("复制" + label + "颜色")
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 16) {
                Button("应用配色") { apply(candidate); notice = "已应用" }.buttonStyle(.borderedProminent).disabled(!valid)
                Button("还原") { reset(); preview(nil); notice = "" }.buttonStyle(.bordered)
                Link("浏览配色", destination: URL(string: "https://coolors.co/palettes/trending")!)
            }
            Text(!valid ? "文字和背景太接近，或颜色代码不完整。调整后即可应用。" : notice.isEmpty ? "上方即时预览；只影响桌面弹幕。" : notice)
                .font(.system(size: 12)).foregroundStyle(valid ? Color.secondary : .orange)
                .fixedSize(horizontal: false, vertical: true)
        }.onAppear { reset() }
            .onChange(of: colors) { _, value in
                if value.values.allSatisfy({ Self.hex($0) != nil }) {
                    let normalized = value.compactMapValues(Self.hex)
                    preview(appearance.merging(normalized.mapValues { $0 as Any }) { _, new in new }.merging(["bubble": "custom"]) { _, new in new })
                }
            }
    }
    private func reset() {
        colors = Dictionary(uniqueKeysWithValues: fields.map { ($0.0, appearance[$0.0] as? String ?? $0.2) })
    }
}
