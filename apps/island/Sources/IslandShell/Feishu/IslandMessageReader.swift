import AppKit
import NookApp
import SwiftUI

enum IslandReadingPages {
    static func split(_ text: String, width: CGFloat = 306, height: CGFloat = 174, fontSize: CGFloat = 14) -> [String] {
        guard !text.isEmpty else { return [""] }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize), .paragraphStyle: paragraph]
        let characters = Array(text); var pages: [String] = []; var index = 0
        while index < characters.count {
            var low = 1, high = characters.count - index
            while low < high {
                let middle = (low + high + 1) / 2
                let sample = NSAttributedString(string: String(characters[index..<(index + middle)]), attributes: attributes)
                let measured = sample.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
                if measured.height <= height { low = middle } else { high = middle - 1 }
            }
            pages.append(String(characters[index..<(index + low)])); index += low
        }
        return pages
    }
}

/// Content of the existing Nook surface, never a separate desktop window.
struct IslandMessageReader: View {
    let message: FeishuMessage
    let followed: Bool
    let pending: Int
    var onBack: () -> Void
    var onFollow: () -> Void
    var onDone: () -> Void
    var onRemind: () -> Void
    var onOpen: () -> Void
    var initialPage = 0
    var onPageChange: (Int) -> Void = { _ in }
    @Environment(\.nookResolvedTheme) private var theme
    @State private var page = 0
    @State private var automatic = false
    @State private var remaining: TimeInterval = 12
    @State private var pages: [String] = []
    @Environment(\.islandTextScale) private var textScale
    private let fontSize: CGFloat = 14
    var body: some View {
        let parts = pages.isEmpty ? [""] : pages
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: onBack) { Label("消息列表", systemImage: "chevron.left") }
                    .buttonStyle(.plain).accessibilityIdentifier("feishu.reader.back")
                Spacer()
                // Conversation reminders are managed together in native settings.
            }.islandFont(size: 11).foregroundStyle(theme.secondaryLabel)
            HStack(alignment: .firstTextBaseline) {
                Text(message.source).islandFont(size: 14, weight: .semibold).lineLimit(1)
                Spacer()
                Text(message.created, style: .time).islandFont(size: 10).foregroundStyle(theme.tertiaryLabel)
            }
            if message.source != message.senderName {
                Text(message.senderName).islandFont(size: 10).foregroundStyle(theme.secondaryLabel)
            }
            Text(parts[min(page, parts.count - 1)]).islandFont(size: fontSize).lineSpacing(4)
                .foregroundStyle(theme.primaryLabel)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
                .background(theme.subtleFill, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.subtleStroke, lineWidth: 0.8))
                .accessibilityIdentifier("feishu.reader.body")
            HStack(spacing: 8) {
                Button("上一页") { move(-1, count: parts.count) }
                    .disabled(page == 0).accessibilityIdentifier("feishu.reader.previous")
                Text("\(page + 1) / \(parts.count)").islandFont(size: 10).monospacedDigit()
                    .foregroundStyle(theme.secondaryLabel).accessibilityIdentifier("feishu.reader.page")
                Button("下一页") { move(1, count: parts.count) }
                    .disabled(page + 1 >= parts.count).accessibilityIdentifier("feishu.reader.next")
                Spacer(minLength: 0)
                Button(automatic ? "暂停" : "自动") {
                    automatic.toggle(); remaining = cardReadingDuration(parts[page].count)
                }.accessibilityIdentifier("feishu.reader.automatic")
            }.buttonStyle(IslandButtonStyle())
            HStack(spacing: 8) {
                Button("稍后提醒", action: onRemind).buttonStyle(IslandButtonStyle())
                Button("打开会话", action: onOpen).buttonStyle(IslandButtonStyle()).disabled(message.chatURL == nil)
                Spacer(minLength: 0)
                Button(pending > 1 ? "读完 · 下一条" : "读完", action: onDone)
                    .buttonStyle(IslandButtonStyle(prominent: true)).accessibilityIdentifier("feishu.reader.done")
            }
        }
        .foregroundStyle(theme.primaryLabel)
        .accessibilityIdentifier("feishu.reader")
        .onAppear {
            if pages.isEmpty { pages = IslandReadingPages.split(message.displayText, fontSize: fontSize * textScale) }
            page = min(max(0, initialPage), pages.count - 1)
        }
        .onChange(of: textScale) { _, _ in
            pages = IslandReadingPages.split(message.displayText, fontSize: fontSize * textScale)
            page = min(page, max(0, pages.count - 1)); automatic = false
        }
        .onChange(of: page) { _, value in onPageChange(value) }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard automatic else { return }
            remaining -= 1
            if remaining <= 0 {
                if page + 1 < parts.count { page += 1; remaining = cardReadingDuration(parts[page].count) }
                else { automatic = false } // Keep the final page until the user finishes.
            }
        }
    }
    private func move(_ delta: Int, count: Int) {
        page = min(max(0, page + delta), count - 1); automatic = false
    }
}
