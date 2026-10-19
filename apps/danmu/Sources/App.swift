import Cocoa
import ApplicationServices
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    var overlay: Overlay!
    var reader = AccountReader()
    var statusItem: NSStatusItem!
    var panel: NSWindow!
    var settings = Settings()
    var subscription: AnyCancellable?
    var appliedStyle = ""
    var received = 0
    var history: [String] = []
    var sessionObservers: [NSObjectProtocol] = []
    var pausedBeforeLock: Bool?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); mainMenu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "退出飞书弹幕", action: #selector(quit), keyEquivalent: "q").target = self
        NSApp.mainMenu = mainMenu
        overlay = Overlay()
        applySettings()
        let workspace = NSWorkspace.shared.notificationCenter
        sessionObservers.append(workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.pausedBeforeLock == nil { self.pausedBeforeLock = self.overlay.paused }
            self.overlay.paused = true; self.settings.paused = true
        })
        sessionObservers.append(workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, let paused = self.pausedBeforeLock else { return }
            self.overlay.paused = paused; self.settings.paused = paused; self.pausedBeforeLock = nil
        })
        overlay.grayRules = UserDefaults.standard.stringArray(forKey: "grayRules") ?? []
        overlay.hiddenRules = UserDefaults.standard.stringArray(forKey: "hiddenRules") ?? []
        overlay.onChange = { [weak self] in self?.updateCounter() }
        subscription = settings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.applySettings() }
        }
        reader.onStatus = { [weak self] s in
            guard let self else { return }; self.settings.status = s; self.settings.receiving = self.reader.enabled; self.settings.healthy = s.hasPrefix("账号接收中")
        }
        overlay.onPresented = { [weak self] message in
            guard let self, !message.demo else { return }
            let queue = max(0, ProcessInfo.processInfo.systemUptime - message.enqueuedUptime)
            if let created = message.createdAt, message.receivedAt >= created {
                let receive = message.receivedAt.timeIntervalSince(created)
                self.settings.latency = String(format:"最近真实消息：接收 %.1f 秒 + 排队 %.1f 秒 = %.1f 秒", receive, queue, receive + queue)
            } else { self.settings.latency = String(format:"最近真实消息：排队 %.1f 秒；服务端时间缺失或时钟不一致", queue) }
        }
        overlay.verifyUnread = { [weak self] id, completion in self?.reader.checkUnread(id, completion: completion) }
        reader.onIdentifiedMessage = { [weak self] message, gray, createdAt, messageID in
            guard let self else { return }
            self.received += 1
            self.history.append(message)
            if self.history.count > 100 { self.history.removeFirst() }
            self.settings.history = self.history.reversed().joined(separator: "\n\n")
            self.overlay.enqueue(message, gray: gray, createdAt: createdAt, receivedAt: self.reader.currentTime(), messageID: messageID)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "弹幕"
        let menu = NSMenu()
        menu.addItem(withTitle: "打开控制台", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "暂停 / 继续", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(withTitle: "清空弹幕与记录", action: #selector(clear), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出飞书弹幕", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        buildPanel(); showPanel()
        reader.setRules(gray: overlay.grayRules, hidden: overlay.hiddenRules)
        if !CommandLine.arguments.contains("--render-check") { reader.start() }
        if CommandLine.arguments.contains("--demo") { demo() }
        if CommandLine.arguments.contains("--render-check") {
            let renderOutput = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DANMU_RENDER_OUTPUT"]
                ?? FileManager.default.currentDirectoryPath + "/.build")
            try? FileManager.default.createDirectory(at: renderOutput, withIntermediateDirectories: true)
            overlay.clear(); overlay.grayRules = ["李四"]; overlay.fontSize = 32; overlay.duration = 12; overlay.palette = 0
            overlay.enqueue("同事：短消息", demo: true)
            overlay.enqueue("张三：中午吃饭", demo: true)
            overlay.enqueue("李四：周报记得交", demo: true)
            for _ in 0..<480 { overlay.last = ProcessInfo.processInfo.systemUptime - 1.0 / 60; overlay.tick() }
            assert(overlay.flying.count == 3)
            assert(overlay.window.ignoresMouseEvents)
            assert(!overlay.window.canBecomeKey)
            assert(overlay.flying.contains { $0.textColor == NSColor.lightGray })
            let root = overlay.window.contentView!
            if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                root.cacheDisplay(in: root.bounds, to: bitmap)
                let output = renderOutput.appendingPathComponent("overlay-check.png")
                try? bitmap.representation(using: .png, properties: [:])?.write(to: output)
            }
            if let root = panel.contentView, let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                root.cacheDisplay(in: root.bounds, to: bitmap)
                let output = renderOutput.appendingPathComponent("panel-check.png")
                try? bitmap.representation(using: .png, properties: [:])?.write(to: output)
            }
            // A second message can enter before the first exits, without overlap.
            overlay.laneCount = 1; overlay.clear()
            overlay.enqueue("短消息", demo: true); overlay.tick()
            for _ in 0..<40 { overlay.last = ProcessInfo.processInfo.systemUptime - 0.1; overlay.tick() }
            overlay.enqueue("第二条", demo: true); overlay.tick()
            assert(overlay.queue.isEmpty && overlay.flying.count == 2)
            assert(overlay.flying[0].frame.maxX + 50 < overlay.flying[1].frame.minX)
            overlay.clear()
            let longText = String(repeating: "长消息应该完整分页，留够时间阅读。", count: 30)
            overlay.enqueue(longText, demo: true); overlay.tick()
            assert(overlay.flying.count == 1 && overlay.flying[0].card)
            let card = overlay.flying[0]
            assert(card.pages.count > 1)
            assert(card.pages.map { $0.string }.joined() == "[演示] " + longText)
            assert(card.remaining >= 12)
            let cardRoot = overlay.window.contentView!
            if let bitmap = cardRoot.bitmapImageRepForCachingDisplay(in: cardRoot.bounds) {
                cardRoot.cacheDisplay(in: cardRoot.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: renderOutput.appendingPathComponent("card-check.png"))
            }
            print("PASS: short lanes, gray exception, mouse passthrough, non-key overlay, gap reuse, complete multiline card pagination and minimum reading time")
            NSApp.terminate(nil)
        }
    }
    func applySettings() {
        let signature = "\(settings.size)|\(settings.duration)|\(settings.opacity)|\(settings.palette)|\(settings.backdrop)|\(settings.heavy)|\(settings.lanes)|\(settings.position)|\(settings.poll)"
        guard signature != appliedStyle else { return }; appliedStyle = signature
        overlay.fontSize = CGFloat(settings.size); overlay.duration = settings.duration
        overlay.opacity = CGFloat(settings.opacity); overlay.palette = settings.palette
        overlay.backdrop = settings.backdrop; overlay.heavy = settings.heavy
        overlay.laneCount = Int(settings.lanes); overlay.position = settings.position
        reader.setPollDelay(settings.poll); settings.save()
    }
    func buildPanel() {
        panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 830), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        panel.title = "飞书弹幕 · 文豪野犬通信簿"; panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 960, height: 680)
        panel.appearance = NSAppearance(named: .aqua)
        panel.backgroundColor = NSColor(calibratedRed:0.94,green:0.91,blue:0.84,alpha:1)
        panel.contentView = NSHostingView(rootView: SettingsPanel(settings:settings,
            preview:{ [weak self] in self?.demo() }, pause:{ [weak self] in self?.togglePause() },
            listen:{ [weak self] in self?.toggleListen() }, clear:{ [weak self] in self?.clear() },
            saveRules:{ [weak self] in self?.saveRules() }, guide:{ [weak self] in self?.openGuide() }))
        panel.center()
    }
    func updateCounter() {
        let pending = overlay.queue.filter { !$0.demo }.count
        settings.pending = pending
        settings.counter = "真实消息 \(received) 条 · 未读待展示 \(pending) 条" + (overlay.overflow > 0 ? " · 积压已移出 \(overlay.overflow) 条" : "")
    }
    @objc func showPanel() { NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }
    @objc func demo() {
        overlay.enqueue("同事：文档发你邮箱了，查收下", demo: true)
        overlay.enqueue("张三：中午一起吃饭吗？ 🍜", demo: true)
        overlay.enqueue("李四：周报记得今天交～", demo: true)
    }
    @objc func togglePause() { overlay.paused.toggle(); settings.paused = overlay.paused }
    @objc func clear() { overlay.clear(); history.removeAll(); settings.history = "" }
    @objc func toggleListen() {
        overlay.cancelVerification()
        if reader.enabled { reader.stop(); settings.receiving = false }
        else { reader.start(); settings.receiving = true }
    }
    @objc func saveRules() {
        func split(_ value: String) -> [String] { value.components(separatedBy: CharacterSet(charactersIn: ",，、\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
        overlay.grayRules = split(settings.gray); overlay.hiddenRules = split(settings.hidden)
        UserDefaults.standard.set(overlay.grayRules, forKey: "grayRules"); UserDefaults.standard.set(overlay.hiddenRules, forKey: "hiddenRules")
        reader.setRules(gray: overlay.grayRules, hidden: overlay.hiddenRules)
        settings.status = "名单已保存 · 下一轮读取生效"
    }
    @objc func openLark() { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Lark.app"), configuration: NSWorkspace.OpenConfiguration()) }
    @objc func openGuide() {
        let url = Bundle.main.url(forResource: "使用说明", withExtension: "html")
            ?? Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("使用说明.html")
        NSWorkspace.shared.open(url)
    }
    func applicationWillTerminate(_ notification: Notification) {
        reader.stop()
        for observer in sessionObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    @objc func quit() { reader.stop(); NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
