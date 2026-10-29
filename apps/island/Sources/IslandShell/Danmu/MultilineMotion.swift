import AppKit

/// Pure text layout shared by the renderer and burst/continuation checks.
enum MotionTextLayout {
    static func scrollFraction(position: CGFloat, screenWidth: CGFloat, panelWidth: CGFloat) -> CGFloat {
        let travel = max(1, screenWidth - panelWidth)
        return min(1, max(0, (travel - position) / travel))
    }
    static func segments(_ text: String, font: NSFont, width: CGFloat, height: CGFloat) -> [String] {
        let characters = Array(text)
        var result: [String] = [], index = 0
        while index < characters.count {
            var low = 1, high = characters.count - index
            while low < high {
                let middle = (low + high + 1) / 2
                let sample = NSAttributedString(string: String(characters[index..<(index + middle)]), attributes: [.font: font])
                let measured = sample.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
                if ceil(measured.height) <= height { low = middle } else { high = middle - 1 }
            }
            result.append(String(characters[index..<(index + low)])); index += low
        }
        return result
    }
}

extension Overlay {
    func tickMotion(now: TimeInterval, dt: TimeInterval) {
        let screen = window.frame
        let scale = window.backingScaleFactor
        // A paused item stops only the items behind it in its own lane.
        for lane in Set(flying.map(\.lane)) {
            var leading: FlyingText?
            for view in flying.filter({ $0.lane == lane }).sorted(by: { $0.position < $1.position }) {
                var x = view.position - (view.clickedPause ? 0 : view.speed * dt)
                if let leading { x = max(x, leading.position + leading.frame.width + 48) }
                view.position = x
                view.needsDisplay = true
                view.motionPanel?.setFrameOrigin(NSPoint(x: screen.minX + (x * scale).rounded() / scale, y: screen.minY + view.motionY))
                leading = view
            }
        }
        let expired = flying.filter { $0.position + $0.frame.width < 0 }
        for view in expired {
            view.motionPanel?.close()
            if let id = view.motionMessage?.messageID { onFinished?(id) }
        }
        flying.removeAll { $0.position + $0.frame.width < 0 }
        guard !queue.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: fontSize, weight: heavy ? .bold : .medium)
        let textHeight = ceil(font.ascender - font.descender + font.leading) * 4 + 4
        let rowHeight = textHeight + 56
        let lanes = min(laneCount, max(1, Int((screen.height - 120) / rowHeight)))
        guard let lane = (0..<lanes).first(where: { candidate in !flying.contains { $0.lane == candidate && $0.position + $0.frame.width > screen.width - 60 } }) else { return }
        if let id = queue[0].messageID, let verifyUnread, verified != queue[0].identity {
            guard checking == nil, now >= retryAt else { return }
            let identity = queue[0].identity; checking = identity
            verifyUnread(id) { [weak self] unread in
                guard let self, self.checking == identity else { return }
                self.checking = nil
                guard self.queue.first?.identity == identity else { return }
                self.onUnreadCheck?(unread)
                if unread == true { self.verified = identity }
                else if unread == false { self.queue.removeFirst(); self.onFinished?(id); self.onChange?() }
                else {
                    // An unavailable read check should not freeze the next eight messages.
                    let deferred = self.queue.removeFirst(); self.queue.append(deferred)
                    self.retryAt = now + 1
                }
            }
            return
        }
        var message = queue.removeFirst(); verified = nil; retryAt = 0
        let width = min(620, max(280, screen.width * 0.48))
        if message.segments.isEmpty {
            let text = message.demo ? "[演示] " + message.text : message.text
            message.segments = [text]
            message.segment = 0
        }
        guard message.segment < message.segments.count else { if let id = message.messageID { onFinished?(id) }; return }
        let view = FlyingText(frame: .zero)
        view.motionMessage = message; view.motionPages = message.segments
        view.textColor = message.gray ? .lightGray : (skinForeground ?? .white)
        view.fillColor = skinBackground; view.borderColor = skinBorder; view.corner = skinCorner; view.backdrop = backdrop
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: view.textColor]
        if !backdrop { attributes[.strokeColor] = NSColor.black; attributes[.strokeWidth] = -1.5 }
        view.content = NSAttributedString(string: message.segments[message.segment], attributes: attributes)
        let measured = view.content.boundingRect(with: NSSize(width: width - 28, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let height = min(rowHeight - 6, ceil(measured.height) + 52)
        let actualWidth = min(width, max(180, ceil(measured.width) + 28))
        let band = CGFloat(lanes) * rowHeight
        let top = position == 1 ? (screen.height + band) / 2 : position == 2 ? band + 32 : screen.height - 64
        view.frame = NSRect(x: screen.width, y: max(20, top - CGFloat(lane + 1) * rowHeight), width: actualWidth, height: height)
        view.position = screen.width; view.lane = lane; view.alphaValue = opacity
        view.motionScreenWidth = screen.width
        let readingSeconds = max(1, Double(view.content.string.count) / 8)
        view.speed = min(movementSpeed ?? screen.width / duration, max(1, screen.width - actualWidth) / readingSeconds)
        let panel = PassThroughWindow(contentRect: view.frame.offsetBy(dx: screen.minX, dy: screen.minY), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = false; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.level = .statusBar; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // The view's frame tracks desktop coordinates; an inner copy of its origin
        // is reset by contentView, so restore it after attaching a sized container.
        let container = NSView(frame: NSRect(origin: .zero, size: view.frame.size))
        panel.contentView = container
        let localFrame = view.frame
        view.frame.origin = .zero; container.addSubview(view)
        if let id = message.messageID {
            view.motionOpen = { [weak self] in self?.onOpenConversation?(id) }
            view.openButton.target = view; view.openButton.action = #selector(FlyingText.openMotionConversation)
            view.openButton.bezelStyle = .rounded; view.openButton.font = .systemFont(ofSize: 12)
            view.openButton.frame = NSRect(x: actualWidth - 112, y: 6, width: 100, height: 26)
            view.openButton.isHidden = true; view.addSubview(view.openButton)
        }
        view.motionPanel = panel
        // Desktop position is kept separately: view frames inside their panel stay local.
        view.motionY = localFrame.minY
        flying.append(view)
        if showsWindow { panel.orderFrontRegardless() }
        onPresented?(message); onChange?()
    }
}
