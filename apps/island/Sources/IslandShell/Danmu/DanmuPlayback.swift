import AppKit

public struct DanmuOptions: Codable, Equatable, Sendable {
    public var enabled = false
    public var paused = false
    public init(enabled: Bool = false, paused: Bool = false) { self.enabled = enabled; self.paused = paused }
}

/// Receives events from FeishuStore; this class never reads an account or binds a port.
@MainActor
public final class DanmuPlayback {
    var overlay: Overlay?
    let headless: Bool
    public private(set) var accepted = 0
    public private(set) var presented = 0
    public private(set) var agentAccepted = 0
    public private(set) var skippedRead = 0
    public private(set) var unreadRetries = 0
    public private(set) var suspended = false
    private var seen = Set<String>(), order: [String] = []
    private var observers: [NSObjectProtocol] = []
    var options = DanmuOptions()
    var appearance = AppearanceMCP.defaults
    var checkUnread: ((String, @escaping (Bool?) -> Void) -> Void)?
    public init(headless: Bool = true) {
        self.headless = headless
        if !headless {
            let center = NSWorkspace.shared.notificationCenter
            observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.suspend(true) } })
            observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.suspend(false) } })
        }
    }
    deinit { for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
    func configure(_ value: DanmuOptions, appearance: [String:Any]) {
        options = value; self.appearance = appearance
        if !value.enabled { clear(); overlay = nil; return }
        overlay?.paused = value.paused || suspended
        applyAppearance()
    }
    func applyAppearance() {
        guard let overlay else { return }
        overlay.fontSize = CGFloat((appearance["fontSize"] as? NSNumber)?.doubleValue ?? 28)
        func color(_ key:String) -> NSColor? {
            guard let raw = appearance[key] as? String, let rgb = UInt32(raw.dropFirst(),radix:16) else { return nil }
            return NSColor(srgbRed:CGFloat((rgb >> 16) & 255)/255,green:CGFloat((rgb >> 8) & 255)/255,blue:CGFloat(rgb & 255)/255,alpha:1)
        }
        overlay.skinForeground = color("foreground"); overlay.skinBackground = color("background"); overlay.skinBorder = color("border")
        overlay.skinCorner = CGFloat((appearance["corner"] as? NSNumber)?.doubleValue ?? 12)
        // Desktop output is always a small moving line. Static/long reading stays
        // inside the island, even if an older appearance requested a desktop card.
        overlay.preferStatic = false
        overlay.allowsCards = false
        overlay.backdrop = false
    }
    static func isShortMessage(_ message: FeishuMessage) -> Bool {
        let body = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !body.isEmpty && body.count <= 80 && message.danmuText.count <= 140
            && message.danmuText.rangeOfCharacter(from: .newlines) == nil
    }
    @discardableResult
    func enqueue(_ message: FeishuMessage, demo: Bool = false) -> Bool {
        guard options.enabled, !suspended, Self.isShortMessage(message), !seen.contains(message.id) else { return false }
        if overlay == nil {
            overlay = Overlay(showsWindow: !headless, frame: headless ? NSRect(x:0,y:0,width:640,height:480) : nil)
            overlay?.allowsCards = false // Long messages are read in the actual island surface.
            overlay?.verifyUnread = { [weak self] id, completion in self?.checkUnread?(id,completion) }
            overlay?.onPresented = { [weak self] _ in self?.presented += 1 }
            overlay?.onUnreadCheck = { [weak self] unread in
                if unread == false { self?.skippedRead += 1 }
                if unread == nil { self?.unreadRetries += 1 }
            }
            overlay?.paused = options.paused
            applyAppearance()
        }
        seen.insert(message.id); order.append(message.id)
        if order.count > 1000 { seen.remove(order.removeFirst()) }
        overlay?.enqueue(message.danmuText,demo:demo,createdAt:message.created,messageID:demo ? nil : message.id)
        accepted += 1
        return true
    }
    /// Local Agent events never pass through Feishu history or unread checks.
    /// The same pause, lock and global desktop-output switch still apply.
    @discardableResult
    func enqueueAgent(id:String,source:String,text:String) -> Bool {
        guard options.enabled, !suspended, !seen.contains(id) else { return false }
        let body=text.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
        guard !body.isEmpty else { return false }
        let label=String(source.prefix(16))+" · "+String(body.prefix(64))+(body.count>64 ? "…" : "")
        // Share only the renderer; never insert Agent events into Feishu history.
        if overlay == nil {
            overlay = Overlay(showsWindow:!headless,frame:headless ? NSRect(x:0,y:0,width:640,height:480) : nil)
            overlay?.verifyUnread = { [weak self] id,completion in self?.checkUnread?(id,completion) }
            overlay?.onPresented = { [weak self] _ in self?.presented += 1 }
            overlay?.onUnreadCheck = { [weak self] unread in
                if unread == false { self?.skippedRead += 1 }
                if unread == nil { self?.unreadRetries += 1 }
            }
            overlay?.paused=options.paused; applyAppearance()
        }
        seen.insert(id); order.append(id)
        if order.count>1000 { seen.remove(order.removeFirst()) }
        overlay?.enqueue(label,demo:false,createdAt:Date(),messageID:nil)
        accepted += 1; agentAccepted += 1
        return true
    }
    func clear() { overlay?.clear() }
    func suspend(_ value: Bool) { suspended = value; if value { clear(); overlay?.window.orderOut(nil) }; overlay?.paused = value || options.paused; if !value, !headless, options.enabled { overlay?.window.orderFrontRegardless() } }
    func resetAccount() { clear(); seen.removeAll(); order.removeAll(); accepted = 0; presented = 0; skippedRead = 0; unreadRetries = 0 }
    public var queued: Int { overlay?.queue.count ?? 0 }
    public var visible: Int { overlay?.flying.count ?? 0 }
    public var windowVisible: Bool { overlay?.window.isVisible ?? false }
}
