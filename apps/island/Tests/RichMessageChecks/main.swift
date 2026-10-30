import AppKit
import SwiftUI
@testable import NookSurface
@testable import IslandShell

MainActor.assumeIsolated {
    let app = NSApplication.shared; app.setActivationPolicy(.regular)
    if let root = Bundle.main.object(forInfoDictionaryKey: "RichChecksRoot") as? String { FileManager.default.changeCurrentDirectoryPath(root) }
    let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : Bundle.main.object(forInfoDictionaryKey: "RichChecksOutput") as! String)
    try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    var checks: [String: Bool] = [:]
    func check(_ value: Bool, _ name: String) { checks[name] = value; print("\(value ? "PASS" : "FAIL"): \(name)"); fflush(stdout) }
    let image = NSImage(size: NSSize(width: 320, height: 180)); image.lockFocus()
    NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: 160, height: 180).fill()
    NSColor.systemOrange.setFill(); NSRect(x: 160, y: 0, width: 160, height: 180).fill(); image.unlockFocus()
    let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    let fixture = output.appendingPathComponent("synthetic-image.png"); try! png.write(to: fixture)
    setenv("ISLAND_IMAGE_FIXTURE", fixture.path, 1)
    let cli = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/RichMessageChecks/fake-cli.py")
    let account = LocalFeishuAccount(appID: "cli_image_fixture", openID: "ou_image_fixture", userName: "合成图片测试")
    let connection = FeishuConnection(cliPath: cli.path, profile: "synthetic-image", localAccount: account)
    let id = "om_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let raw: [String: Any] = ["message_id": id, "msg_type": "image", "body": ["content": "{\"image_key\":\"img_v3_synthetic\"}"]]
    let message = FeishuMessage(raw: raw, chatID: "oc_synthetic", chatName: "合成图片", chatKind: "p2p", ownID: "ou_image_fixture")
    check(message.imageKeys == ["img_v3_synthetic"] && message.hasImageContent, "standalone image retains its resource key")
    let post: [String: Any] = ["msg_type": "post", "body": ["content": "{\"zh_cn\":{\"content\":[[{\"tag\":\"img\",\"image_key\":\"img_v3_a\"},{\"tag\":\"img\",\"image_key\":\"img_v3_a\"},{\"tag\":\"img\",\"image_key\":\"img_v3_b\"}]]},\"en_us\":{\"content\":[[{\"tag\":\"img\",\"image_key\":\"img_v3_other\"}]]}}"]]
    check(accountMessageImageKeys(post) == ["img_v3_a", "img_v3_b"], "rich-text images preserve order and choose one language")
    check(!validFeishuImageKey("../../image") && !validFeishuImageKey("https://example.com/image") && !FeishuImageResources.validMessageID("../message"), "resource paths and external URLs are rejected")
    var legacy = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as! [String: Any]
    legacy.removeValue(forKey: "imageKeys")
    let restored = try! JSONDecoder().decode(FeishuMessage.self, from: JSONSerialization.data(withJSONObject: legacy))
    check(restored.imageKeys.isEmpty && restored.hasImageContent, "old image history decodes without losing original message")
    check((try? FeishuImageResources.thumbnail(Data("invalid".utf8), maxPixel: 640)) == nil, "invalid image bytes are rejected")
    let thumbnail = try! FeishuImageResources.thumbnail(png, maxPixel: 80)
    check(max(thumbnail.size.width, thumbnail.size.height) <= 80, "image thumbnail is downsampled before display")
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
    let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 3, minute: 28))!
    let edited = TodoTimeValue.applying("15:46", to: date, calendar: calendar)!
    check(TodoTimeValue.text(edited, calendar: calendar) == "15:46" && calendar.isDate(edited, inSameDayAs: date), "editing hour and minute preserves the selected date")
    check(TodoTimeValue.applying("24:00", to: date) == nil && TodoTimeValue.applying("12:60", to: date) == nil && TodoTimeValue.applying("15:", to: date) == nil, "invalid and partially typed times cannot be saved")
    check(TodoTimeValue.applying("00:00", to: date, calendar: calendar) != nil && TodoTimeValue.applying("23:59", to: date, calendar: calendar) != nil, "midnight and final minute are editable")
    let workspace = WorkspaceStore(root: output.appendingPathComponent("workspace"), startTimers: false)
    let todo = try! workspace.addTodo(title: "合成指定时间提醒")
    _ = try! workspace.configureTodoReminder(todo, dates: [edited], now: date)
    let reread = WorkspaceStore(root: output.appendingPathComponent("workspace"), startTimers: false)
    check(reread.disk.items.first(where: { $0.id == todo })?.due == edited, "edited reminder time survives save and reload")
    let motion = Overlay(showsWindow: false, frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
    motion.multilineMotion = true; motion.enqueue("合成文字")
    motion.tickMotion(now: 1, dt: 0)
    let compactHeight = motion.motionRowHeight
    motion.enqueue(message.danmuText, sourceMessage: message)
    motion.tickMotion(now: 2, dt: 0)
    check(motion.queue.count == 1 && motion.motionRowHeight == compactHeight, "image waits for compact text lanes to clear")
    motion.tickMotion(now: 3, dt: 10000)
    check(motion.queue.isEmpty && motion.flying.first?.imageAreaHeight == 110 && motion.motionRowHeight > compactHeight, "image enters a taller nonoverlapping lane")
    motion.clear(); app.setActivationPolicy(.regular)
    Task { @MainActor in
        do {
            let resolved = try await Task.detached { try FeishuImageResources.resolve(restored, connection: connection) }.value
            check(resolved == ["img_v3_synthetic"], "legacy image placeholder resolves through read-only message lookup")
            let scope = FeishuImageResources.scope(connection)!
            let downloaded = try await Task.detached { try FeishuImageResources.load(messageID: id, key: "img_v3_synthetic", connection: connection, accountScope: scope) }.value
            check(downloaded == png, "official CLI image path returns exact resource bytes with user identity")
            let other = FeishuConnection(cliPath: cli.path, profile: "synthetic-image", localAccount: .init(appID: "cli_image_fixture", openID: "ou_other_account", userName: "其他合成账号"))
            check(FeishuImageResources.scope(other) != scope, "image cache is isolated by bound account")
            FeishuImagePreview.shared.open(downloaded)
            try? await Task.sleep(for: .milliseconds(200))
            let preview = NSApp.windows.first { $0.identifier?.rawValue == "feishu.image.preview" }
            check(preview?.isVisible == true && preview!.level.rawValue > 33 && preview!.isKeyWindow, "expanded image is visible and focused above island")
            FeishuImagePreview.shared.close()
        } catch { print(error.localizedDescription); check(false, "synthetic image resource pipeline") }
        let passed = checks.values.allSatisfy { $0 }
        try! JSONSerialization.data(withJSONObject: ["passed": passed, "checks": checks], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("rich-message-result.json"))
        if CommandLine.arguments.contains("--interactive") || Bundle.main.object(forInfoDictionaryKey: "RichChecksInteractive") as? Bool == true {
            let panel = NookPanel(contentRect: NSRect(x: 200, y: 120, width: 520, height: 730), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            let defaults = UserDefaults(suiteName: "local.zaizhi.rich-checks." + UUID().uuidString)!
            defaults.set(try! JSONEncoder().encode(connection), forKey: "connection")
            let messages = FeishuStore(defaults: defaults, live: false, headlessRenderer: false)
            FeishuStore.active = messages; messages.receive(message); messages.closeReader()
            panel.contentView = NSHostingView(rootView: RichChecksFixture(workspace: workspace, todo: todo, messages: messages, message: message, saved: {
                try? JSONSerialization.data(withJSONObject: ["savedTime": workspace.disk.items.first(where: { $0.id == todo })!.due!.timeIntervalSince1970]).write(to: output.appendingPathComponent("interactive-save.json"))
            }))
            panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            // Keep this fixture alive while native UI tools edit its isolated reminder.
            Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { _ in exit(passed ? 0 : 1) }
            RichUIHolder.panel = panel
            return
        }
        print("\(passed ? "PASS" : "FAIL"): \(checks.count) image and reminder checks")
        exit(passed ? 0 : 1)
    }
    app.run()
}

@MainActor private enum RichUIHolder { static var panel: NSPanel? }

private struct RichChecksFixture: View {
    let workspace: WorkspaceStore
    let todo: UUID
    let messages: FeishuStore
    let message: FeishuMessage
    let saved: () -> Void
    @State private var tab = 0
    @State private var overlay: Overlay?
    var body: some View {
        VStack {
            HStack {
                Button("提醒") { tab = 0 }
                Button("灵动岛图片") { tab = 1 }
                Button("弹幕图片") {
                    overlay?.clear()
                    let next = Overlay(showsWindow: true, frame: NSRect(x: 740, y: 200, width: 680, height: 500))
                    next.timer?.invalidate(); next.multilineMotion = true
                    next.enqueue(message.danmuText, sourceMessage: message)
                    next.tickMotion(now: ProcessInfo.processInfo.systemUptime, dt: 0)
                    if let view = next.flying.first {
                        view.position = 0; view.clickedPause = true
                        view.motionPanel?.setFrameOrigin(NSPoint(x: 750, y: 420))
                    }
                    overlay = next
                    RichUIHolder.panel?.orderOut(nil)
                    next.window.orderOut(nil)
                }
            }.padding(8)
            if tab == 0 {
                UnifiedTodoEditor(store: workspace, item: workspace.disk.items.first(where: { $0.id == todo })!, finished: saved)
            } else { FeishuView(store: messages) }
        }.background(Color.white)
    }
}
