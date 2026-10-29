import AppKit
import Carbon
import NookApp
@testable import IslandShell

@MainActor func runMessageContinuityChecks(check: (Bool, String) -> Void) throws {
    func message(_ id: String, _ text: String, age: TimeInterval = 0) throws -> FeishuMessage {
        let data = try JSONSerialization.data(withJSONObject: ["text": text])
        return FeishuMessage(raw: ["message_id": id, "create_time": String(Int(Date().addingTimeInterval(-age).timeIntervalSince1970 * 1000)), "msg_type": "text", "body": ["content": String(decoding: data, as: UTF8.self)]], chatID: "oc_synthetic", chatName: "合成会话", chatKind: "p2p", ownID: "ou_synthetic")
    }
    func card(_ body: [String: Any]) throws -> String {
        accountMessageText(["msg_type":"interactive", "body":["content":String(decoding:try JSONSerialization.data(withJSONObject:body),as:UTF8.self)]])
    }
    check(try card(["schema":"2.0", "header":["title":["tag":"plain_text","content":"合成标题"]], "body":["elements":[["tag":"markdown","content":"第一段\n第二段"]]]]) == "合成标题\n第一段\n第二段", "Card 2.0 original body keeps title and paragraphs")
    check(try card(["header":["title":["content":"合成"]],"i18n_elements":["zh_cn":[["tag":"div","text":["content":"中文"]]],"en_us":[["tag":"div","text":["content":"English"]]]]]) == "合成\n中文", "Card 1.0 selects one locale")
    let formatted = try message("markdown", "**重点**和 *强调*，代码 `a*b`，公式 2*3")
    check(formatted.text.contains("**重点**") && formatted.displayText == "重点和 强调，代码 a*b，公式 2*3", "message display removes Markdown emphasis while preserving source and literal stars")
    check(feishuDisplayText("# 标题\n* **重点**\n```\n* 原样\n```") == "标题\n• 重点\n```\n* 原样\n```", "Markdown headings and lists are readable without changing code blocks")
    check(MotionTextLayout.scrollFraction(position: 820, screenWidth: 1440, panelWidth: 620) == 0 && MotionTextLayout.scrollFraction(position: 0, screenWidth: 1440, panelWidth: 620) == 1, "long-message text starts and finishes scrolling while its whole panel is visible")
    let text = String(repeating: "这是一段合成消息，包含日期与链接。\nhttps://example.com/\n", count: 8)
    let overlay = Overlay(showsWindow:false, frame:NSRect(x:0,y:0,width:1440,height:900))
    overlay.multilineMotion = true; overlay.fontSize = 28; overlay.movementSpeed = 500
    overlay.verifyUnread = { _, done in done(true) }
    var completed = Set<String>(), presented = Set<String>()
    overlay.onFinished = { completed.insert($0) }
    overlay.onPresented = { if let id = $0.messageID { presented.insert(id) } }
    for index in 0..<8 { overlay.enqueue(text, messageID:"synthetic_\(index)") }
    var time = overlay.last
    for _ in 0..<8 { time += 0.02; overlay.tick(now:time) }
    let first = overlay.flying.first!
    check(!first.card && first.motionPages.joined() == text.trimmingCharacters(in: .whitespacesAndNewlines), "multiline flight retains every character and never creates a fixed card")
    check(first.frame.width <= 620 && first.frame.height < 250 && first.motionPanel?.ignoresMouseEvents == false && !first.motionPanel!.canBecomeKey && overlay.window.ignoresMouseEvents, "only message rectangles receive clicks; desktop remains pass-through")
    let event = NSEvent.mouseEvent(with:.leftMouseDown, location:.zero, modifierFlags:[], timestamp:0, windowNumber:0, context:nil,eventNumber:0,clickCount:1,pressure:1)!
    first.mouseDown(with:event); let x = first.position
    for _ in 0..<20 { time += 0.05; overlay.tick(now:time) }
    check(first.clickedPause && first.position == x && !first.openButton.isHidden, "click pauses motion and exposes conversation action")
    if CommandLine.arguments.contains("--render-message-motion"), let bitmap = first.bitmapImageRepForCachingDisplay(in:first.bounds) {
        first.cacheDisplay(in:first.bounds,to:bitmap)
        let url = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/multiline-message-preview.png")
        try bitmap.representation(using:.png,properties:[:])?.write(to:url)
    }
    var opened = false; overlay.onOpenConversation = { _ in opened = true }; first.openMotionConversation()
    check(opened,"paused message conversation action reaches the correct message callback")
    first.resumeMotion(); time += 0.05; overlay.tick(now:time)
    check(first.position < x && first.openButton.isHidden, "pointer exit resumes motion and hides actions")
    for _ in 0..<4000 where completed.count < 8 { time += 0.1; overlay.tick(now:time) }
    check(presented.count == 8 && completed.count == 8 && overlay.queue.isEmpty && overlay.flying.isEmpty, "eight long messages complete all segments without fixed-card head blocking")
    overlay.clear()
    overlay.verifyUnread = { id,done in done(id == "unknown" ? nil : true) }
    overlay.enqueue("暂不可核验",messageID:"unknown");overlay.enqueue("后面的合成消息",messageID:"ready")
    for _ in 0..<40 {time += 0.1;overlay.tick(now:time)}
    check(overlay.flying.contains { $0.motionMessage?.messageID == "ready" }, "one unavailable read state does not block the next message")
    overlay.clear()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("island-history-check-"+UUID().uuidString)
    let key = String(repeating:"a",count:64), archive = MessageArchive(root:root,key:key)
    let now = Date(), a = try message("completed", "合成已播放"), b = try message("pending", "合成待播放"), old = try message("expired", "合成过期",age:9*86400)
    var snapshot = MessageArchiveSnapshot(accountKey:key,startedAt:now.addingTimeInterval(-10*86400),messages:[a,b,old],pending:[b.id,old.id],checkpoints:["oc_synthetic":now.addingTimeInterval(-60)])
    try archive.save(snapshot)
    let restored = try archive.load(days:7,now:now)
    check(restored.messages.map(\.id) == [a.id,b.id] && restored.pending == [b.id], "restart restores history and only unfinished desktop messages, expires old content")
    check(restored.checkpoints["oc_synthetic"] == snapshot.checkpoints["oc_synthetic"], "per-conversation completed read progress survives restart")
    let other = MessageArchive(root:root,key:String(repeating:"b",count:64))
    check(try other.load(days:7,now:now).messages.isEmpty,"another verified account never receives prior history")
    let permissions = try FileManager.default.attributesOfItem(atPath:archive.file.path)[.posixPermissions] as? NSNumber
    check(permissions?.intValue == 0o600,"message file is readable by owner only")
    snapshot.accountKey = String(repeating:"b",count:64)
    do { try archive.save(snapshot); check(false,"account mismatch rejected") } catch {check(true,"account mismatch rejected")}
    check(try archive.load(days:0,now:now).messages.isEmpty, "session-only mode does not restore previous bodies")
    let policy = MessageRetention(days:7,cleanupMinute:180)
    check(policy.cleanupSlot(now:now) <= now && now.timeIntervalSince(policy.cleanupSlot(now:now)) < 90000,"daily cleanup slot remains valid before and after today's chosen time")
    check(UnifiedPlatformStore.validHotkey(.init(keyCode:122,carbonModifiers:0,keySymbol:"F1")),"single function key accepted")
    check(UnifiedPlatformStore.validHotkey(.init(keyCode:50,carbonModifiers:0,keySymbol:"`")),"single punctuation key accepted")
    check(!UnifiedPlatformStore.validHotkey(.init(keyCode:53,carbonModifiers:0,keySymbol:"Esc")),"Escape remains cancellation")
    let keyEvent = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:1,windowNumber:0,context:nil,characters:"`",charactersIgnoringModifiers:"`",isARepeat:false,keyCode:50)!
    check(HubShortcutInput.matches(keyEvent,.init(keyCode:50,carbonModifiers:0,keySymbol:"`")), "app-directed single key uses the same wheel path")
    check(!HubShortcutInput.matches(keyEvent,.init(keyCode:50,carbonModifiers:UInt32(cmdKey),keySymbol:"`")), "unmodified typing cannot trigger a configured chord")
    let store = FeishuStore(defaults:UserDefaults(suiteName:"motion-check-"+UUID().uuidString)!,headlessRenderer:true)
    store.updateDanmu(.init(enabled:true));store.receive(b);store.markViewed(b.id)
    var stillUnread: Bool?;store.playback.checkUnread?(b.id) {stillUnread=$0}
    check(stillUnread == true,"reading inside island no longer discards pending desktop output")
    store.playback.clear()
    print("Message continuity checks use synthetic text only; no live account, no shown windows")
}
