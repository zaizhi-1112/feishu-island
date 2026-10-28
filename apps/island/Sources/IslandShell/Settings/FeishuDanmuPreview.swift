import AppKit
import SwiftUI

/// Reuses the desktop text renderer without creating a desktop window or queueing
/// a synthetic event into the real receiver.
struct FeishuDanmuPreview: NSViewRepresentable {
    let appearance: [String: Any]
    let playing: Bool
    let started: Date
    var onFinished: () -> Void = {}
    func makeNSView(context: Context) -> FeishuDanmuPreviewView { FeishuDanmuPreviewView() }
    func updateNSView(_ view: FeishuDanmuPreviewView, context: Context) {
        view.onFinished = onFinished
        view.configure(appearance, playing: playing, started: started)
    }
    static func dismantleNSView(_ view: FeishuDanmuPreviewView, coordinator: ()) { view.stop() }
}

final class FeishuDanmuPreviewView: NSView {
    let text = FlyingText(frame: .zero)
    var onFinished: () -> Void = {}
    private var timer: Timer?
    private var started = Date()
    private var playing = false
    private var speed: CGFloat = 100
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect); wantsLayer = true; layer?.masksToBounds = true; addSubview(text)
        setAccessibilityLabel("合成弹幕预览，不发送真实消息")
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(_ appearance: [String: Any], playing: Bool, started: Date) {
        func color(_ key: String, fallback: NSColor?) -> NSColor? {
            guard let raw = appearance[key] as? String, let hex = UInt32(raw.dropFirst(), radix: 16) else { return fallback }
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
        let fontSize = CGFloat((appearance["fontSize"] as? NSNumber)?.doubleValue ?? 28)
        let bubble = appearance["bubble"] as? String ?? "none"
        text.backdrop = bubble != "none"
        text.textColor = color("foreground", fallback: bubble == "light" ? NSColor(srgbRed: 0.1, green: 0.12, blue: 0.15, alpha: 1) : .white)!
        text.fillColor = color("background", fallback: bubble == "light" ? .white.withAlphaComponent(0.94) : nil)
        text.borderColor = color("border", fallback: nil)
        text.corner = CGFloat((appearance["corner"] as? NSNumber)?.doubleValue ?? 12)
        var attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium), .foregroundColor: text.textColor]
        if !text.backdrop { attrs[.strokeColor] = NSColor.black; attrs[.strokeWidth] = -1.5 }
        text.content = NSAttributedString(string: "小林：方案已更新", attributes: attrs)
        let measured = text.content.size()
        text.setFrameSize(NSSize(width: ceil(measured.width) + 28, height: ceil(measured.height) + 16))
        text.needsDisplay = true
        speed = CGFloat((appearance["speed"] as? NSNumber)?.doubleValue ?? 100)
        self.playing = playing; self.started = started
        if playing && timer == nil {
            timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.place() }
            RunLoop.main.add(timer!, forMode: .common)
        } else if !playing { stop() }
        place()
    }
    override func layout() { super.layout(); place() }
    private func place() {
        let distance = CGFloat(Date().timeIntervalSince(started)) * speed
        let finished = distance >= bounds.width + text.frame.width
        let x = playing && !finished ? bounds.width - distance : max(8, (bounds.width - text.frame.width) / 2)
        text.setFrameOrigin(NSPoint(x: x, y: (bounds.height - text.frame.height) / 2))
        if playing && finished {
            playing = false; stop()
            let completed = onFinished
            DispatchQueue.main.async { completed() }
        }
    }
    func stop() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }
}
