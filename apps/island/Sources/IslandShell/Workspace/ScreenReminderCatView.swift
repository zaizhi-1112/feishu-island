import AppKit
import QuartzCore

/// Original vector artwork. No Cat Gatekeeper media, icons, or traced frames.
/// The host owns presentation and dismissal; this view never creates a window.
@MainActor
final class ScreenReminderCatView: NSView {
    private var animationTimer: Timer?
    private var startedAt: CFTimeInterval = 0
    private var progress: Double = 0
    private let duration: Double = 7

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func start() {
        stop()
        startedAt = CACurrentMediaTime()
        progress = 0
        needsDisplay = true
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { timer.invalidate(); return }
                let elapsed = max(0, CACurrentMediaTime() - self.startedAt)
                self.progress = min(1, elapsed / self.duration)
                self.needsDisplay = true
                if elapsed >= self.duration {
                    self.animationTimer?.invalidate()
                    self.animationTimer = nil
                }
            }
        }
    }

    func stop() {
        animationTimer?.invalidate()
        animationTimer = nil
        progress = 0
        needsDisplay = true
    }

    /// Deterministic, off-screen inspection. This neither starts a timer nor opens a window.
    static func renderPreview(size: NSSize = NSSize(width: 600, height: 400), progress: Double = 0.45) -> NSBitmapImageRep? {
        guard size.width.isFinite, size.height.isFinite,
              (1...4096).contains(size.width), (1...4096).contains(size.height) else { return nil }
        let view = ScreenReminderCatView(frame: NSRect(origin: .zero, size: size))
        view.progress = progress.isFinite ? min(1, max(0, progress)) : 0
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0,
              let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.clear(bounds)
        let scale = min(bounds.width / 600, bounds.height / 400)
        context.translateBy(x: bounds.midX - 300 * scale, y: bounds.midY - 200 * scale)
        context.scaleBy(x: scale, y: scale)

        // A soft stretch, a raised paw, then a calm rest. All inputs are bounded.
        let p = progress.isFinite ? min(1, max(0, progress)) : 0
        let stretch = sin(.pi * min(1, max(0, (p - 0.08) / 0.55)))
        let paw = sin(.pi * min(1, max(0, (p - 0.57) / 0.36)))
        let breath = sin(p * .pi * 4) * 2
        let ivory = NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.89, alpha: 1)
        let warmWhite = NSColor(calibratedRed: 1, green: 0.99, blue: 0.95, alpha: 1)
        let orange = NSColor(calibratedRed: 0.87, green: 0.48, blue: 0.20, alpha: 1)
        let deepOrange = NSColor(calibratedRed: 0.72, green: 0.33, blue: 0.13, alpha: 1)
        let ink = NSColor(calibratedRed: 0.23, green: 0.20, blue: 0.18, alpha: 1)
        let pink = NSColor(calibratedRed: 0.89, green: 0.58, blue: 0.53, alpha: 1)

        func ellipse(_ rect: NSRect, _ color: NSColor) {
            color.setFill(); NSBezierPath(ovalIn: rect).fill()
        }
        func stroke(_ points: [NSPoint], color: NSColor, width: CGFloat) {
            guard let first = points.first else { return }
            let path = NSBezierPath(); path.move(to: first)
            points.dropFirst().forEach { path.line(to: $0) }
            path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
            color.setStroke(); path.stroke()
        }

        // Tail behind the body: broad warm contour, lighter inner edge.
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 220, y: 169))
        tail.curve(to: NSPoint(x: 119, y: 248 + 12 * stretch),
                   controlPoint1: NSPoint(x: 125, y: 137), controlPoint2: NSPoint(x: 79, y: 231))
        tail.curve(to: NSPoint(x: 153, y: 275 + 10 * stretch),
                   controlPoint1: NSPoint(x: 131, y: 285), controlPoint2: NSPoint(x: 159, y: 289))
        tail.lineWidth = 30; tail.lineCapStyle = .round
        orange.setStroke(); tail.stroke()
        tail.lineWidth = 9
        NSColor(calibratedRed: 0.98, green: 0.69, blue: 0.36, alpha: 0.75).setStroke(); tail.stroke()

        let body = NSRect(x: 190 - 15 * stretch, y: 108 + breath, width: 202 + 45 * stretch, height: 140 - 20 * stretch)
        ellipse(body.insetBy(dx: -1.5, dy: -1.5), orange)
        ellipse(body, ivory)
        ellipse(NSRect(x: 194, y: 150 + breath, width: 109 + 12 * stretch, height: 94 - 15 * stretch), orange)
        ellipse(NSRect(x: 236, y: 117 + breath, width: 145 + 15 * stretch, height: 77), warmWhite)
        // Orange fur marks are part of this original vector construction.
        stroke([NSPoint(x: 219, y: 219), NSPoint(x: 232, y: 207)], color: deepOrange, width: 7)
        stroke([NSPoint(x: 240, y: 232), NSPoint(x: 254, y: 215)], color: deepOrange, width: 7)
        stroke([NSPoint(x: 265, y: 232), NSPoint(x: 273, y: 215)], color: deepOrange, width: 7)

        // Back paws stay planted; the front reaches forward as the shoulders lower.
        ellipse(NSRect(x: 203, y: 92, width: 69, height: 42), ivory)
        ellipse(NSRect(x: 277, y: 91, width: 72, height: 37), warmWhite)
        let frontX = 345 + 62 * stretch
        let frontY = 98 + 82 * paw
        let leg = NSBezierPath()
        leg.move(to: NSPoint(x: 350 + 12 * stretch, y: 171 - 18 * stretch))
        leg.curve(to: NSPoint(x: frontX + 29, y: frontY + 13),
                  controlPoint1: NSPoint(x: 361 + 24 * stretch, y: 130 + 48 * paw),
                  controlPoint2: NSPoint(x: frontX + 6, y: frontY + 13))
        leg.lineWidth = 36; leg.lineCapStyle = .round
        ivory.setStroke(); leg.stroke()
        ellipse(NSRect(x: frontX, y: frontY, width: 68, height: 35), warmWhite)
        for x in [frontX + 44, frontX + 54] {
            stroke([NSPoint(x: x, y: frontY + 4), NSPoint(x: x - 1, y: frontY + 12)], color: orange.withAlphaComponent(0.55), width: 2)
        }
        if paw > 0.2 {
            ellipse(NSRect(x: frontX + 18, y: frontY + 10, width: 20, height: 12), pink.withAlphaComponent(paw))
        }

        context.saveGState()
        context.translateBy(x: 376 + 31 * stretch, y: 220 - 31 * stretch + breath)
        context.rotate(by: -0.10 * stretch + 0.07 * paw)

        func ear(_ left: Bool) {
            let sign: CGFloat = left ? -1 : 1
            let shape = NSBezierPath()
            shape.move(to: NSPoint(x: sign * 22, y: 35))
            shape.curve(to: NSPoint(x: sign * 50, y: 82), controlPoint1: NSPoint(x: sign * 26, y: 55), controlPoint2: NSPoint(x: sign * 42, y: 77))
            shape.curve(to: NSPoint(x: sign * 61, y: 21), controlPoint1: NSPoint(x: sign * 58, y: 86), controlPoint2: NSPoint(x: sign * 64, y: 41))
            shape.close(); orange.setFill(); shape.fill()
            let inner = NSBezierPath()
            inner.move(to: NSPoint(x: sign * 35, y: 35)); inner.line(to: NSPoint(x: sign * 50, y: 66)); inner.line(to: NSPoint(x: sign * 54, y: 28)); inner.close()
            pink.setFill(); inner.fill()
        }
        ear(true); ear(false)
        ellipse(NSRect(x: -65, y: -48, width: 130, height: 114), orange)
        ellipse(NSRect(x: -57, y: -45, width: 116, height: 92), warmWhite)
        // Forehead cap and a narrow blaze keep the face readable at small sizes.
        ellipse(NSRect(x: -56, y: 16, width: 112, height: 43), orange)
        let blaze = NSBezierPath()
        blaze.move(to: NSPoint(x: 0, y: 55)); blaze.curve(to: NSPoint(x: -15, y: -1), controlPoint1: NSPoint(x: -2, y: 29), controlPoint2: NSPoint(x: -15, y: 21))
        blaze.line(to: NSPoint(x: 15, y: -1)); blaze.curve(to: NSPoint(x: 0, y: 55), controlPoint1: NSPoint(x: 15, y: 21), controlPoint2: NSPoint(x: 2, y: 29)); blaze.close()
        warmWhite.setFill(); blaze.fill()

        for x: CGFloat in [-29, 29] {
            let eye = NSBezierPath()
            eye.move(to: NSPoint(x: x - 9, y: 10))
            eye.curve(to: NSPoint(x: x + 9, y: 10), controlPoint1: NSPoint(x: x - 3, y: 3 - 3 * stretch), controlPoint2: NSPoint(x: x + 3, y: 3 - 3 * stretch))
            eye.lineWidth = 3.5; eye.lineCapStyle = .round; ink.setStroke(); eye.stroke()
        }
        ellipse(NSRect(x: -8, y: -10, width: 16, height: 10), pink)
        stroke([NSPoint(x: 0, y: -10), NSPoint(x: 0, y: -19)], color: ink, width: 2)
        let smile = NSBezierPath(); smile.move(to: NSPoint(x: -12, y: -19))
        smile.curve(to: NSPoint(x: 0, y: -19), controlPoint1: NSPoint(x: -7, y: -25), controlPoint2: NSPoint(x: -3, y: -23))
        smile.curve(to: NSPoint(x: 12, y: -19), controlPoint1: NSPoint(x: 3, y: -23), controlPoint2: NSPoint(x: 7, y: -25))
        smile.lineWidth = 2; smile.lineCapStyle = .round; ink.setStroke(); smile.stroke()
        for sign: CGFloat in [-1, 1] {
            stroke([NSPoint(x: sign * 30, y: -8), NSPoint(x: sign * 72, y: -2)], color: ink.withAlphaComponent(0.6), width: 1.7)
            stroke([NSPoint(x: sign * 32, y: -17), NSPoint(x: sign * 73, y: -21)], color: ink.withAlphaComponent(0.6), width: 1.7)
        }
        context.restoreGState()
    }
}
