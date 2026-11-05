import AppKit
import NookApp
import SwiftUI
@testable import IslandShell
@testable import NookSurface

@MainActor func runButtonInteractionChecks(check: (Bool, String) -> Void) async throws {
    precondition(IslandRuntime.isSkinPreview, "Interaction checks require isolated preview preferences")
    let overlay = Overlay(showsWindow: false, frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
    overlay.multilineMotion = true; overlay.fontSize = 28; overlay.movementSpeed = 500; overlay.laneCount = 1
    var finished: [String] = []
    overlay.onFinished = { finished.append($0) }
    overlay.enqueue("读完后立即关闭", messageID: "close-first")
    var time = overlay.last
    time += 0.05; overlay.tick(now: time)
    let first = overlay.flying.first!
    first.position = 600
    overlay.enqueue("同一轨道后续的消息", messageID: "close-next")
    time += 0.05; overlay.tick(now: time)
    check(overlay.flying.count == 2, "a follower enters the same lane")
    let follower = overlay.flying[1]
    let event = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                  windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
    first.mouseEntered(with: event)
    let heldX = first.position
    for _ in 0..<40 { time += 0.1; overlay.tick(now: time) }
    check(first.motionPaused && first.position == heldX && !first.openButton.isHidden, "hover freezes the panel before choosing an action")
    check(follower.position >= first.position + first.frame.width + 48, "hover pause keeps following messages from overlapping")
    check(first.dismissButton.frame.width >= 30 && first.dismissButton.frame.height >= 30, "close has a full 30pt pointer target")
    check(first.bounds.contains(first.dismissButton.frame) && !first.openButton.frame.intersects(first.dismissButton.frame), "actions fit within the panel without overlapping")
    let edge = NSPoint(x: first.dismissButton.frame.minX + 1, y: first.dismissButton.frame.minY + 1)
    check(first.hitTest(edge) === first.dismissButton, "the close target receives clicks near its edge")
    check(first.dismissButton.acceptsFirstMouse(for: nil) && first.dismissButton.isEnabled && !first.dismissButton.isHidden, "close declares first-click acceptance and is available")
    check(first.dismissButton.accessibilityIdentifier() == "danmu.motion.dismiss", "close can be identified by assistive tools")
    let renderDirectory = CommandLine.arguments.firstIndex(of: "--render-button-interactions")
        .map { URL(fileURLWithPath: CommandLine.arguments[$0 + 1]) }
    if let renderDirectory {
        try FileManager.default.createDirectory(at: renderDirectory, withIntermediateDirectories: true)
        for dark in [true, false] {
            first.textColor = dark ? .white : .black
            first.fillColor = dark ? NSColor.black : NSColor.white
            first.dismissButton.contentTintColor = first.textColor
            first.content = NSAttributedString(string: first.content.string,
                                              attributes: [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: first.textColor])
            first.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            if let bitmap = first.bitmapImageRepForCachingDisplay(in: first.bounds) {
                first.cacheDisplay(in: first.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: renderDirectory.appendingPathComponent(dark ? "danmu-dark.png" : "danmu-light.png"))
            }
        }
    }
    overlay.enqueue("排队的消息", messageID: "queued")
    first.dismissButton.performClick(nil)
    check(!overlay.flying.contains { $0 === first } && overlay.flying.contains { $0 === follower }, "close immediately removes only its own message")
    check(overlay.queue.map(\.messageID) == ["queued"] && finished == ["close-first"], "close completes this playback and preserves the queue")
    check(first.superview == nil && first.motionPanel?.isVisible == false, "closed panel releases its content and remains offscreen")
    first.dismissButton.performClick(nil)
    check(finished == ["close-first"], "repeat close never reports completion twice")
    let followingX = follower.position
    time += 0.1; overlay.tick(now: time)
    check(follower.position < followingX, "following message resumes after its leading panel closes")
    follower.mouseEntered(with: event); follower.resumeMotion()
    check(!follower.motionPaused && follower.openButton.isHidden && !follower.dismissButton.isHidden, "pointer exit resumes flight and leaves close available")
    overlay.paused = true
    follower.dismissButton.performClick(nil)
    check(!overlay.flying.contains { $0 === follower } && finished == ["close-first", "close-next"], "close works while global playback is paused")
    overlay.clear(); overlay.paused = false
    overlay.enqueue("没有飞书会话的合成提醒", demo: true)
    time += 0.1; overlay.tick(now: time)
    let demo = overlay.flying.first!
    demo.mouseEntered(with: event)
    check(demo.openButton.isHidden && !demo.dismissButton.isHidden, "demo and Agent-style notices remain closable without a conversation")
    demo.dismissButton.performClick(nil)
    check(overlay.flying.isEmpty && finished == ["close-first", "close-next"], "closing an anonymous demo never fabricates a message ID")
    check(overlay.window.ignoresMouseEvents && !overlay.window.canBecomeKey && !overlay.window.isVisible,
          "desktop stays pass-through and no test window is shown")

    let defaults = UserDefaults(suiteName: "button-dismiss-check-" + UUID().uuidString)!
    let store = FeishuStore(defaults: defaults, live: false, receivingDefault: true, headlessRenderer: true)
    let content = String(decoding: try JSONSerialization.data(withJSONObject: ["text": "合成消息仍留在岛内"]), as: UTF8.self)
    let message = FeishuMessage(raw: ["message_id": "keep-source", "msg_type": "text", "body": ["content": content]],
                               chatID: "oc_synthetic", chatName: "合成会话", chatKind: "p2p", ownID: "ou_synthetic")
    store.updateDanmu(.init(enabled: true)); store.receive(message)
    let playback = store.playback.overlay!
    playback.verifyUnread = { _, done in done(true) }
    playback.tick(); playback.tick()
    playback.flying.first!.dismissButton.performClick(nil)
    check(store.playback.visible == 0 && store.messages.contains { $0.id == message.id && !$0.viewed && $0.text == message.text },
          "dismissing desktop playback keeps the original island message and reading state")
    store.playback.clear()

    // Measure the product navigation without ordering any window onto the desktop.
    let modules = IslandHost.configuration().makeRegistry().descriptors.filter { IslandHost.moduleIDs.contains($0.id) }
    let switcher = NookTopBarContext.ModuleSwitcher(modules: modules, activeID: IslandHost.feishuID,
                                     attentionIDs: [], switchTo: { _ in })
    let context = NookTopBarContext(title: "消息", moduleSwitcher: switcher)
    let host = NookHostingView(rootView: IntegrationTopBar(bar: context).frame(width: 400))
    let panel = NookPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 27),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false; panel.contentView = host
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(100))
    check(host.fittingSize.width == 400 && host.fittingSize.height == IslandHost.navigationHeight, "navigation preserves its existing layout")
    check(host.acceptsFirstMouse(for: nil) && !panel.isVisible, "host accepts the first click without displaying a test window")
    if let renderDirectory, let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: renderDirectory.appendingPathComponent("navigation.png"))
    }
    panel.close()
}
