import Cocoa

final class PassThroughWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class FlyingText: NSView {
    var card = false
    var pages: [NSAttributedString] = []
    var pageIndex = 0
    var remaining: TimeInterval = 0
    var manualPaging = false
    var speed: CGFloat = 100
    var lane = 0
    var position: CGFloat = 0
    var textColor: NSColor = .white
    var content = NSAttributedString(string: "")
    var backdrop = true
    var fillColor: NSColor?
    var borderColor: NSColor?
    var corner: CGFloat = 10
    override func draw(_ dirtyRect: NSRect) {
        if backdrop {
            (fillColor ?? NSColor.black.withAlphaComponent(0.76)).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: corner, yRadius: corner).fill()
            if let borderColor { borderColor.setStroke(); let edge = NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:corner,yRadius:corner);edge.lineWidth=1;edge.stroke() }
        }
        if card {
            content.draw(in: NSRect(x: 20, y: 78, width: bounds.width - 40, height: bounds.height - 100))
            let label = "\(pageIndex + 1) / \(pages.count) 页 · 完整正文"
            label.draw(at: NSPoint(x: 20, y: 52), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.lightGray])
        } else { content.draw(at: NSPoint(x: 14, y: 8)) }
    }
}
final class CardPagingButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class Overlay: NSObject {
    var window: PassThroughWindow!
    var flying: [FlyingText] = []
    var queue: [DanmuMessage] = []
    var fontSize: CGFloat = 32
    var duration: Double = 12
    /// nil retains the old duration setting; unified settings use points per second.
    var movementSpeed: CGFloat?
    var opacity: CGFloat = 1
    var palette = 3
    var backdrop = true
    var heavy = false
    var position = 0
    var grayRules: [String] = []
    var hiddenRules: [String] = []
    var laneCount = 4
    var paused = false
    var skinForeground: NSColor?
    var skinBackground: NSColor?
    var skinBorder: NSColor?
    var skinCorner: CGFloat = 10
    var preferStatic = false
    var allowsCards = true
    var timer: Timer?
    private(set) var controlsWindow: PassThroughWindow?
    private(set) var pagingButtons: [NSButton] = []
    var last = ProcessInfo.processInfo.systemUptime
    var onChange: (() -> Void)?
    var onPresented: ((DanmuMessage) -> Void)?
    var overflow = 0
    var verifyUnread: ((String, @escaping (Bool?) -> Void) -> Void)?
    var onUnreadCheck: ((Bool?) -> Void)?
    private var checking: UUID?
    private var verified: UUID?
    private var retryAt: TimeInterval = 0
    let showsWindow: Bool
    let frameOverride: NSRect?
    private var screenObserver: NSObjectProtocol?
    init(showsWindow: Bool = true, frame: NSRect? = nil) {
        if !showsWindow { NSApplication.shared.setActivationPolicy(.prohibited) }
        self.showsWindow = showsWindow; self.frameOverride = frame
        super.init()
        rebuild()
        if showsWindow { timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common) }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.rebuild() }
    }
    deinit { timer?.invalidate(); if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }; controlsWindow?.close(); window?.close() }
    func rebuild() {
        controlsWindow?.close(); controlsWindow = nil; pagingButtons.removeAll()
        window?.close(); flying.removeAll()
        let frame = frameOverride ?? NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = PassThroughWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear
        window.hasShadow = false; window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        if showsWindow { window.orderFrontRegardless() }
    }
    func enqueue(_ text: String, demo: Bool = false, gray: Bool = false, createdAt: Date? = nil, receivedAt: Date? = nil, messageID: String? = nil) {
        let clean = cleanMessage(text)
        guard !clean.isEmpty else { return }

        if queue.count >= 500 { queue.removeFirst(); overflow += 1 }
        var message = DanmuMessage(text: clean, receivedAt: receivedAt ?? Date(), demo: demo, gray: gray, createdAt: createdAt)
        message.messageID = messageID; queue.append(message)
        onChange?()
    }
    func clear() { queue.removeAll(); checking = nil; verified = nil; overflow = 0; flying.forEach { $0.removeFromSuperview() }; flying.removeAll(); controlsWindow?.orderOut(nil); onChange?() }
    func cancelVerification() { checking = nil; verified = nil; retryAt = 0 }
    private var currentCard: FlyingText? { flying.first { $0.card } }
    @objc func previousPage() { turnPage(-1) }
    @objc func nextPage() { turnPage(1) }
    private func turnPage(_ delta: Int) {
        guard let card = currentCard else { return }
        let index = min(max(0, card.pageIndex + delta), card.pages.count - 1)
        guard index != card.pageIndex else { return }
        card.pageIndex = index; card.content = card.pages[index]
        card.remaining = cardReadingDuration(card.content.string.count)
        card.manualPaging = true; card.needsDisplay = true
        syncCardControls(); onChange?()
    }
    @objc func toggleCardAutomatic() {
        guard let card = currentCard else { return }
        card.manualPaging.toggle()
        card.remaining = cardReadingDuration(card.content.string.count)
        syncCardControls(); onChange?()
    }
    @objc func dismissCard() {
        guard let card = currentCard else { return }
        card.removeFromSuperview(); flying.removeAll { $0 === card }
        controlsWindow?.orderOut(nil); onChange?()
    }
    private func syncCardControls() {
        guard let card = currentCard else { controlsWindow?.orderOut(nil); return }
        if controlsWindow == nil {
            // Only this small footer accepts clicks. The desktop-sized window stays pass-through.
            let panel = PassThroughWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.ignoresMouseEvents = false; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let footer = NSView(); footer.wantsLayer = true
            footer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.9).cgColor
            footer.layer?.cornerRadius = 7; footer.appearance = NSAppearance(named: .darkAqua)
            panel.contentView = footer
            let actions: [(String, Selector, String)] = [
                ("上一页", #selector(previousPage), "previous"), ("下一页", #selector(nextPage), "next"),
                ("暂停", #selector(toggleCardAutomatic), "automatic"), ("读完", #selector(dismissCard), "dismiss")]
            pagingButtons = actions.map { title, action, id in
                let button = CardPagingButton(title: title, target: self, action: action)
                button.bezelStyle = .rounded; button.font = .systemFont(ofSize: 12)
                button.setAccessibilityIdentifier("danmu.card." + id)
                footer.addSubview(button); return button
            }
            controlsWindow = panel
            if showsWindow { window.addChildWindow(panel, ordered: .above) }
        }
        guard let panel = controlsWindow else { return }
        let width = min(360, card.bounds.width - 32)
        panel.setFrame(NSRect(x: window.frame.minX + card.frame.minX + 16,
                              y: window.frame.minY + card.frame.minY + 10, width: width, height: 32), display: false)
        for (index, button) in pagingButtons.enumerated() {
            button.frame = NSRect(x: CGFloat(index) * width / 4 + 2, y: 2, width: width / 4 - 4, height: 28)
        }
        pagingButtons[0].isEnabled = card.pageIndex > 0
        pagingButtons[1].isEnabled = card.pageIndex + 1 < card.pages.count
        pagingButtons[2].title = card.manualPaging ? "自动" : "暂停"
        pagingButtons[0].toolTip = "上一页，切换后暂停自动翻页"
        pagingButtons[1].toolTip = "下一页，切换后暂停自动翻页"
        pagingButtons[2].toolTip = card.manualPaging ? "恢复自动翻页" : "暂停自动翻页"
        pagingButtons[3].toolTip = "收起这条消息，继续播放下一条"
        if showsWindow { panel.orderFrontRegardless() }
    }
    func tick(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let dt = min(now - last, 0.1); last = now
        guard !paused else { return }
        let scale = window.backingScaleFactor
        for view in flying {
            if view.card {
                guard !view.manualPaging else { continue }
                view.remaining -= dt
                if view.remaining <= 0 {
                    view.pageIndex += 1
                    if view.pageIndex < view.pages.count {
                        view.content = view.pages[view.pageIndex]
                        view.remaining = cardReadingDuration(view.content.string.count)
                        view.needsDisplay = true
                        syncCardControls()
                    }
                }
                continue
            }
            view.speed = movementSpeed ?? (window.frame.width / duration)
            view.position -= view.speed * dt
            view.frame.origin.x = (view.position * scale).rounded() / scale
        }
        flying.removeAll { if ($0.card && $0.pageIndex >= $0.pages.count) || (!$0.card && $0.frame.maxX < 0) { $0.removeFromSuperview(); return true }; return false }
        if currentCard == nil { controlsWindow?.orderOut(nil) }
        guard !flying.contains(where: { $0.card }) else { return }
        guard !queue.isEmpty else { return }
        let long = allowsCards && (isCardMessage(queue[0].text) || preferStatic)
        if long && !flying.isEmpty { return }
        if let id = queue[0].messageID, let verifyUnread, verified != queue[0].identity {
            guard checking == nil, now >= retryAt else { return }
            let identity = queue[0].identity; checking = identity
            verifyUnread(id) { [weak self] unread in
                guard let self, self.checking == identity else { return }
                self.checking = nil
                guard self.queue.first?.identity == identity else { return }
                self.onUnreadCheck?(unread)
                if unread == true { self.verified = identity }
                else if unread == false { self.queue.removeFirst(); self.onChange?() }
                else { self.retryAt = ProcessInfo.processInfo.systemUptime + 5 }
            }
            return
        }
        // Same speed for all items: an entry gap is enough to guarantee no collisions.
        let availableLanes = min(laneCount, max(1, Int((window.frame.height - 110) / (fontSize + 38))))
        guard let lane = (0..<availableLanes).first(where: { candidate in !flying.contains { $0.lane == candidate && $0.frame.maxX > window.frame.width - 60 } }) else { return }
        let message = queue.removeFirst()
        verified = nil
        let view = FlyingText(frame: .zero)
        let text = message.demo ? "[演示] " + message.text : message.text
        let font = NSFont.systemFont(ofSize: fontSize, weight: heavy ? .bold : .medium)
        let palettes: [[NSColor]] = [[.white, .systemPink, .systemYellow, .systemCyan], [.systemMint, .systemTeal, .systemCyan, .white], [.systemOrange, .systemPink, .systemYellow, .systemRed], [.white]]
        let colors = palettes[min(max(palette, 0), palettes.count - 1)]
        let gray = message.gray || (message.demo && grayRules.contains { message.text.localizedCaseInsensitiveContains($0) })
        view.textColor = gray ? NSColor.lightGray : (skinForeground ?? colors[lane % colors.count])
        view.fillColor = skinBackground; view.borderColor = skinBorder; view.corner = skinCorner
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: view.textColor]
        if !backdrop { attributes[.strokeColor] = NSColor.black; attributes[.strokeWidth] = -1.5 }
        view.content = NSAttributedString(string: text, attributes: attributes)
        view.backdrop = backdrop
        if long {
            view.card = true; view.backdrop = true
            let cardWidth = min(640, max(280, window.frame.width * 0.43))
            let cardHeight = min(500, max(180, window.frame.height * 0.55))
            let available = NSSize(width: cardWidth - 40, height: cardHeight - 100)
            let characters = Array(text); var index = 0
            while index < characters.count {
                var low = 1, high = characters.count - index
                while low < high {
                    let middle = (low + high + 1) / 2
                    let sample = NSAttributedString(string: String(characters[index..<(index + middle)]), attributes: attributes)
                    let measured = sample.boundingRect(with: NSSize(width: available.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
                    if measured.height <= available.height { low = middle } else { high = middle - 1 }
                }
                view.pages.append(NSAttributedString(string: String(characters[index..<(index + low)]), attributes: attributes)); index += low
            }
            view.content = view.pages[0]; view.remaining = cardReadingDuration(view.content.string.count)
            let cardY = position == 1 ? (window.frame.height - cardHeight) / 2 : position == 2 ? 24 : window.frame.height - cardHeight - 64
            view.frame = NSRect(x: max(12, window.frame.width - cardWidth - 24), y: max(24, cardY), width: cardWidth, height: cardHeight)
            window.contentView?.addSubview(view); flying.append(view); syncCardControls(); onPresented?(message); onChange?(); return
        }
        let size = view.content.size()
        view.frame.size = NSSize(width: ceil(size.width) + 28, height: ceil(size.height) + 16)
        let width = window.frame.width
        let spacing = fontSize + 38
        let band = CGFloat(availableLanes) * spacing
        let top = position == 1 ? (window.frame.height + band) / 2 : position == 2 ? band + 42 : window.frame.height - 64
        view.frame.origin = NSPoint(x: width, y: max(20, top - CGFloat(lane + 1) * spacing))
        view.position = width; view.speed = movementSpeed ?? (width / duration)
        view.alphaValue = opacity; view.lane = lane
        window.contentView?.addSubview(view); flying.append(view)
        onPresented?(message)
        onChange?()
    }
}
