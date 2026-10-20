private var failures: [String] = []
private var checks = 0
private func record(_ value:Bool, _ line:UInt) { checks += 1; if !value { failures.append("Assertion at line \(line)") } }
func XCTAssertTrue(_ value:Bool,line:UInt = #line) { record(value,line) }
func XCTAssertFalse(_ value:Bool,line:UInt = #line) { record(!value,line) }
func XCTAssertNil<T>(_ value:T?,line:UInt = #line) { record(value == nil,line) }
func XCTAssertEqual<T:Equatable>(_ a:T,_ b:T,line:UInt = #line) { record(a == b,line) }
func XCTAssertGreaterThan<T:Comparable>(_ a:T,_ b:T,line:UInt = #line) { record(a > b,line) }
func XCTAssertGreaterThanOrEqual<T:Comparable>(_ a:T,_ b:T,line:UInt = #line) { record(a >= b,line) }
func XCTAssertLessThan<T:Comparable>(_ a:T,_ b:T,line:UInt = #line) { record(a < b,line) }
import Foundation
import AppKit
import SwiftUI
import NookApp
@testable import IslandShell

@MainActor
final class FusionTests {
    func fixture(_ id:String = UUID().uuidString, text:String = "合成短消息", kind:String = "p2p") -> FeishuMessage {
        FeishuMessage(raw:["message_id":id,"sender":["id":"ou_synthetic","sender_name":"示例"],"msg_type":"text","body":["content":String(data:try! JSONSerialization.data(withJSONObject:["text":text]),encoding:.utf8)!]],chatID:"oc_synthetic",chatName:"合成",chatKind:kind,ownID:"ou_me")
    }
    func store() -> (FeishuStore,UserDefaults,String) {
        let suite = "local.fusion.synthetic." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        return (FeishuStore(defaults:defaults),defaults,suite)
    }
    func testWorkspacePersistenceRemindersAndOAuthBoundary() async throws {
        verifyNativeDragPreview()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("island-work-check-"+UUID().uuidString)
        XCTAssertEqual(SettingsResponse.json(["url":URL(string:"https://example.invalid")!]).status,500)
        XCTAssertEqual(SettingsResponse.json(["url":"https://example.invalid"]).status,200)
        let s = WorkspaceStore(root:root,startTimers:false)
        let id = try s.add(text:"合成客户反馈：搜索结果没有日期。",minutes:1)
        XCTAssertEqual(s.disk.items.count,1); XCTAssertEqual(s.disk.items[0].state,"todo")
        var alerts = 0; s.notify = {_ in alerts += 1}
        s.boardTab = 2
        s.tick(now:Date().addingTimeInterval(61)); s.tick(now:Date().addingTimeInterval(62))
        XCTAssertEqual(alerts,1); XCTAssertTrue(s.disk.items[0].reminded)
        XCTAssertEqual(s.boardTab,1); XCTAssertEqual(s.selected,id)
        let loaded = WorkspaceStore(root:root,startTimers:false)
        XCTAssertEqual(loaded.disk.items[0].id,id); XCTAssertTrue(loaded.disk.items[0].reminded)
        let render = ImageRenderer(content:WorkspaceView(store:s).background(Color.black).preferredColorScheme(.dark))
        render.scale = 2
        if let image = render.cgImage {
            XCTAssertLessThan(image.height,1100)
            let png = NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!
            try png.write(to:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/workspace-check.png"))
        } else { XCTAssertTrue(false) }
        let mode = try FileManager.default.attributesOfItem(atPath:root.appendingPathComponent("workspace.json").path)[.posixPermissions] as? Int
        XCTAssertEqual(mode,0o600)
        loaded.complete(id); XCTAssertEqual(loaded.disk.items[0].state,"done"); XCTAssertNil(loaded.disk.items[0].due)
        do { _ = try s.add(text:""); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        do { _ = try WorkMaterial.read(root); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        do { _ = try await s.hubClient.begin(callback:"https://example.invalid/callback"); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        do { try await s.hubClient.finish(query:[URLQueryItem(name:"state",value:"fake"),URLQueryItem(name:"code",value:"fake")]); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        let corrupt = FileManager.default.temporaryDirectory.appendingPathComponent("island-work-corrupt-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:corrupt,withIntermediateDirectories:true)
        let raw = Data("invalid-original-synthetic".utf8); try raw.write(to:corrupt.appendingPathComponent("workspace.json"))
        let broken = WorkspaceStore(root:corrupt,startTimers:false)
        do { _ = try broken.add(text:"cannot overwrite"); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        XCTAssertEqual(try Data(contentsOf:corrupt.appendingPathComponent("workspace.json")),raw)
        let workFile = root.appendingPathComponent("sample.txt");try Data("原文合成材料".utf8).write(to:workFile)
        XCTAssertEqual(try WorkMaterial.read(workFile),"原文合成材料")
        XCTAssertTrue(HubClient.readable(["forbidden":true]).contains("权限"))
        XCTAssertTrue(HubClient.readable(["auth":true]).contains("授权"))
        let before=s.accepted
        XCTAssertTrue(WorkspaceDrop.acceptFiles([workFile],store:s))
        for _ in 0..<100 where s.accepted==before { try await Task.sleep(nanoseconds:20_000_000) }
        XCTAssertEqual(s.accepted,before+1);XCTAssertTrue(s.disk.items.first?.input.contains("原文合成材料") == true)
        XCTAssertTrue(s.ingestActive)
        XCTAssertFalse(WorkspaceDrop.acceptFiles([URL(string:"https://example.invalid/material.txt")!],store:s))
        let receipt = s.accepted
        do { _ = try s.add(text:""); XCTAssertTrue(false) } catch { XCTAssertEqual(s.accepted,receipt) }
        XCTAssertEqual(IngestMotion.progress(elapsed:-1),0)
        XCTAssertEqual(IngestMotion.progress(elapsed:9),1)
        XCTAssertGreaterThan(IngestMotion.fileRadius(0.1),IngestMotion.fileRadius(0.5))
        XCTAssertEqual(IngestMotion.fileRadius(0.8),0)
        // Long-running hover and every collapse endpoint remain finite and inside the island.
        var bounded = true
        for time in [0.0, 0.5, 100_000_000.0] {
            for collapse in [0.0, 0.5, 1.0] {
                for index in 0..<144 {
                    let p = PortalFlow.point(index:index,time:time,collapse:collapse)
                    bounded = bounded && p.x.isFinite && p.y.isFinite && abs(p.x)<=169 && abs(p.y)<=80
                }
            }
        }
        XCTAssertTrue(bounded)
        XCTAssertEqual(PortalFlow.point(index:7,time:1,collapse:1),.zero)
        XCTAssertFalse(PortalFlow.point(index:7,time:0) == PortalFlow.point(index:7,time:0.5))
        let frames = root.appendingPathComponent("ingest-frames")
        try FileManager.default.createDirectory(at:frames,withIntermediateDirectories:true)
        let waiting = ImageRenderer(content:IngestPortalScene(phase:.waiting,elapsed:0.25).background(Color.black))
        waiting.scale = 2
        if let img=waiting.cgImage { try NSBitmapImageRep(cgImage:img).representation(using:.png,properties:[:])!.write(to:frames.appendingPathComponent("waiting.png")); XCTAssertEqual(img.width,696) } else { XCTAssertTrue(false) }
        let waitingStore = WorkspaceStore(root:root.appendingPathComponent("drag-surface"),startTimers:false)
        XCTAssertTrue(waitingStore.beginMaterialDrop()); XCTAssertTrue(waitingStore.ingestSaving)
        XCTAssertFalse(waitingStore.beginMaterialDrop()); waitingStore.endMaterialDrop(); XCTAssertFalse(waitingStore.ingestSaving)
        let shell = AppState(preferenceDefaults:NookPreferenceDefaults())
        shell.isDragInFlight = true
        let surface = WorkspaceDropSurface(store:waitingStore) { Text("SYNTHETIC RESTING CARD").frame(width:376,height:260) }
            .environmentObject(shell).background(Color.black)
        let host = NSHostingView(rootView:surface)
        host.frame = NSRect(x:0,y:0,width:376,height:260)
        let window = NSWindow(contentRect:host.frame,styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for:.milliseconds(80))
        if let rep = host.bitmapImageRepForCachingDisplay(in:host.bounds) {
            host.cacheDisplay(in:host.bounds,to:rep)
            try rep.representation(using:.png,properties:[:])!.write(to:frames.appendingPathComponent("native-drag-state.png"))
            XCTAssertGreaterThan(rep.pixelsWide,0); XCTAssertFalse(window.isVisible)
        } else { XCTAssertTrue(false) }
        window.close()
        var previous: Data?
        for (index,progress) in [0.12,0.4,0.65,0.9].enumerated() {
            let renderer = ImageRenderer(content:IngestBlackHole(progress:progress).background(Color.black))
            renderer.scale = 2
            if let image = renderer.cgImage {
                XCTAssertEqual(image.width,696); XCTAssertEqual(image.height,328)
                let png = NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!
                if let previous { XCTAssertFalse(previous == png) }
                previous = png
                try png.write(to:frames.appendingPathComponent("frame-\(index).png"))
            } else { XCTAssertTrue(false) }
        }
        if CommandLine.arguments.contains("--ingest-frames") { print("Ingestion frame evidence: \(frames.path)") }
        for _ in 0..<100 where s.ingestActive { try await Task.sleep(for:.milliseconds(25)) }
        XCTAssertFalse(s.ingestActive)

        XCTAssertEqual(try String(contentsOf:workFile,encoding:.utf8),"原文合成材料")
        XCTAssertTrue(HubClient.readable(["type":"report","rule":"合成周报","committedAt":"2026-10-18T16:36:02.000Z","items":[["name":"下周工作计划","value":"合成计划"]]]).contains("合成计划"))
        for ip in ["127.0.0.1","198.18.0.1","192.168.1.1","10.0.0.1","169.254.1.1"] { XCTAssertFalse(FeishuTransport.publicIPv4(ip)) }
        XCTAssertTrue(FeishuTransport.publicIPv4("139.177.246.206"))
    }
    func testFreshInstallIsStoppedAndRendererIsLazy() async {
        let (_,defaults,suite)=store();defer { defaults.removePersistentDomain(forName:suite) }
        let s = FeishuStore(defaults:defaults,receivingDefault:false)
        XCTAssertFalse(s.enabled);XCTAssertFalse(s.danmu.enabled);XCTAssertNil(s.playback.overlay)
        XCTAssertFalse(IslandHost.feishuID.hasPrefix("local.youzi."))
        s.receive(fixture());XCTAssertEqual(s.messages.count,0)
    }
    func testOneEventFeedsListAndOptionalRendererWithoutDuplicates() async {
        let (s,d,suite)=store();defer { d.removePersistentDomain(forName:suite) }
        let m=fixture("one")
        s.receive(m);XCTAssertEqual(s.messages.count,1);XCTAssertNil(s.playback.overlay)
        s.updateDanmu(.init(enabled:true));let second=fixture("two");s.receive(second);s.receive(second)
        XCTAssertEqual(s.messages.count,2);XCTAssertEqual(s.readingAccepted,2);XCTAssertEqual(s.readingQueue.count,2)
        XCTAssertEqual(s.playback.accepted,0);XCTAssertNil(s.playback.overlay)
        XCTAssertFalse(s.playback.windowVisible)
    }
    func testMutePauseStopAndRulesAreSeparate() async {
        let (s,d,suite)=store();defer { d.removePersistentDomain(forName:suite) }
        s.updateDanmu(.init(enabled:true,paused:true));s.receive(fixture("paused"))
        XCTAssertEqual(s.readingQueue.count,1);XCTAssertFalse(s.danmu.enabled);XCTAssertNil(s.playback.overlay)
        s.toggleMute();XCTAssertEqual(s.readingQueue.count,0);s.receive(fixture("muted"));XCTAssertEqual(s.messages.count,2);XCTAssertEqual(s.readingAccepted,1)
        s.toggleMute();s.updateDanmu(.init(enabled:true));s.receive(fixture("active"));XCTAssertEqual(s.readingQueue.count,1)
        s.toggleReceiving();s.receive(fixture("late"));XCTAssertEqual(s.messages.count,3);XCTAssertEqual(s.playback.queued,0)
        s.playback.suspend(true);XCTAssertFalse(s.playback.windowVisible)
    }
    func testExpandedIslandStillReceivesAndPresentsDesktopDanmu() async {
        let (s,d,suite)=store();defer { d.removePersistentDomain(forName:suite) }
        s.canAlert = { false } // Expanded island: suppress peek, not desktop messages.
        s.updateDanmu(.init(enabled:true));let message=fixture("while-reading")
        s.receive(message);s.receive(message)
        XCTAssertEqual(s.messages.count,1);XCTAssertEqual(s.readingAccepted,1)
        XCTAssertEqual(s.readingID,"while-reading");XCTAssertNil(s.playback.overlay)
        XCTAssertFalse(s.playback.windowVisible)
        s.toggleMute();s.receive(fixture("reading-muted"))
        XCTAssertEqual(s.messages.count,2);XCTAssertEqual(s.readingAccepted,1)
    }
    func testOrdinaryAndBlockedMessagesDoNotBecomeDanmu() async {
        let (s,d,suite)=store();defer { d.removePersistentDomain(forName:suite) }
        s.updateDanmu(.init(enabled:true));s.receive(fixture("quiet",kind:"group"));XCTAssertEqual(s.messages.count,1);XCTAssertEqual(s.playback.accepted,0)
        var custom=FeishuCustomRules();custom.blockedGroups=[.init(id:"oc_synthetic",name:"合成")]
        s.updateSettings(enabled:true,rules:.init(),custom:custom);s.receive(fixture("blocked"));XCTAssertEqual(s.messages.count,1);XCTAssertEqual(s.playback.accepted,0)
    }
    func testConnectionSwitchStopsAndClearsOldAccount() async {
        let (s,d,suite)=store();defer { d.removePersistentDomain(forName:suite) }
        s.updateDanmu(.init(enabled:true));s.receive(fixture());s.toggleFollow("oc_synthetic")
        XCTAssertTrue(s.updateConnection(.init(cliPath:"/tmp/synthetic-cli",profile:"other")))
        XCTAssertFalse(s.enabled);XCTAssertTrue(s.messages.isEmpty);XCTAssertTrue(s.followed.isEmpty);XCTAssertEqual(s.playback.queued,0)
        let restored=FeishuStore(defaults:d);XCTAssertEqual(restored.connection.profile,"other");XCTAssertFalse(restored.enabled)
        XCTAssertFalse(s.updateConnection(.init(cliPath:"relative",profile:"other")))
        XCTAssertTrue(legacyDanmuConflict(["/tmp/FeishuDanmuWeb/launcher"]))
        XCTAssertFalse(legacyDanmuConflict(["/tmp/飞书工作岛预览版.app/Contents/MacOS/YuIsland"]))
    }
    func testHiddenRealRendererMovesAndPreservesCompleteLongText() async {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let overlay=Overlay(showsWindow:false,frame:NSRect(x:0,y:0,width:640,height:480))
        XCTAssertFalse(overlay.window.isVisible);XCTAssertFalse(overlay.window.isOpaque);XCTAssertEqual(overlay.window.backgroundColor?.alphaComponent,0)
        XCTAssertTrue(overlay.window.ignoresMouseEvents);XCTAssertFalse(overlay.window.canBecomeKey)
        overlay.enqueue("短合成",demo:true);let t=ProcessInfo.processInfo.systemUptime;overlay.tick(now:t)
        let x=overlay.flying.first!.frame.minX;overlay.tick(now:t+0.1);XCTAssertLessThan(overlay.flying.first!.frame.minX,x)
        overlay.paused=true;let pausedX=overlay.flying.first!.frame.minX;overlay.tick(now:t+0.2);XCTAssertEqual(overlay.flying.first!.frame.minX,pausedX)
        overlay.clear();overlay.paused=false
        let long=String(repeating:"完整合成文本🌱不会丢失",count:120)
        overlay.enqueue(long,demo:true);overlay.tick(now:t+0.3)
        let view=overlay.flying.first!;XCTAssertGreaterThan(view.pages.count,1)
        XCTAssertEqual(view.pages.map(\.string).joined(),"[演示] " + long);XCTAssertGreaterThanOrEqual(view.remaining,12)
        XCTAssertFalse(overlay.window.isVisible)
    }
    func testUnreadIsRecheckedAndQueueIsBounded() async {
        let o=Overlay(showsWindow:false,frame:NSRect(x:0,y:0,width:640,height:480));var state:Bool?=nil
        o.verifyUnread={_,completion in completion(state)};o.enqueue("合成",messageID:"om_synthetic")
        let t=ProcessInfo.processInfo.systemUptime;o.tick(now:t);XCTAssertEqual(o.queue.count,1);XCTAssertEqual(o.flying.count,0)
        state=false;o.tick(now:t+6);XCTAssertEqual(o.queue.count,0);XCTAssertEqual(o.flying.count,0)
        for _ in 0..<510 { o.enqueue("合成") };XCTAssertEqual(o.queue.count,500);XCTAssertEqual(o.overflow,10)
        o.clear();XCTAssertEqual(o.queue.count,0)
    }
    func testManualCardPagingAndSenderLabels() async throws {
        let o=Overlay(showsWindow:false,frame:NSRect(x:0,y:0,width:900,height:700))
        let original=String(repeating:"这是一段用于检查手动翻页的合成内容。",count:100)
        o.enqueue(original,demo:true)
        let t=ProcessInfo.processInfo.systemUptime;o.tick(now:t)
        let card=o.flying.first!
        XCTAssertGreaterThan(card.pages.count,2)
        XCTAssertEqual(card.pages.map(\.string).joined(),"[演示] " + original)
        XCTAssertEqual(o.pagingButtons.count,4)
        XCTAssertFalse(o.pagingButtons[0].isEnabled)
        o.pagingButtons[1].performClick(nil)
        XCTAssertEqual(card.pageIndex,1);XCTAssertTrue(card.manualPaging)
        XCTAssertEqual(card.content,card.pages[1])
        let remaining=card.remaining;o.tick(now:t+1)
        XCTAssertEqual(card.pageIndex,1);XCTAssertEqual(card.remaining,remaining)
        o.pagingButtons[0].performClick(nil);XCTAssertEqual(card.pageIndex,0)
        o.pagingButtons[0].performClick(nil);XCTAssertEqual(card.pageIndex,0)
        o.pagingButtons[2].performClick(nil);XCTAssertFalse(card.manualPaging)
        card.remaining=0;o.tick(now:t+2);XCTAssertEqual(card.pageIndex,1)
        while card.pageIndex + 1 < card.pages.count { o.pagingButtons[1].performClick(nil) }
        XCTAssertFalse(o.pagingButtons[1].isEnabled)
        XCTAssertFalse(o.controlsWindow!.isVisible);XCTAssertFalse(o.controlsWindow!.canBecomeKey)
        XCTAssertFalse(o.controlsWindow!.ignoresMouseEvents)
        XCTAssertLessThan(o.controlsWindow!.frame.height,40)
        XCTAssertTrue(o.window.ignoresMouseEvents);XCTAssertFalse(o.window.isVisible)
        // Render only synthetic content off-screen, including actual native button views.
        o.pagingButtons[0].performClick(nil)
        let image=NSImage(size:card.bounds.size)
        image.lockFocus()
        if let bitmap=card.bitmapImageRepForCachingDisplay(in:card.bounds) {
            card.cacheDisplay(in:card.bounds,to:bitmap);bitmap.draw(in:card.bounds)
        }
        if let footer=o.controlsWindow?.contentView,let bitmap=footer.bitmapImageRepForCachingDisplay(in:footer.bounds) {
            footer.cacheDisplay(in:footer.bounds,to:bitmap)
            bitmap.draw(in:NSRect(x:16,y:10,width:footer.bounds.width,height:footer.bounds.height))
        }
        image.unlockFocus()
        let png=NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
        try png.write(to:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/card-paging-check.png"))
        o.pagingButtons[3].performClick(nil);XCTAssertEqual(o.flying.count,0)
        XCTAssertFalse(o.controlsWindow!.isVisible)
        o.enqueue(original,demo:true);o.tick(now:t+3);o.clear()
        XCTAssertEqual(o.flying.count,0);XCTAssertFalse(o.controlsWindow!.isVisible)
        let direct=fixture("sender",text:"正文")
        XCTAssertEqual(direct.danmuText,"示例：正文")
        let same=FeishuMessage(raw:["message_id":"same","sender":["sender_name":"宰治"],"msg_type":"text","body":["content":"{\"text\":\"正文\"}"]],chatID:"oc_synthetic",chatName:"宰治",chatKind:"group",ownID:"")
        XCTAssertEqual(same.danmuText,"宰治：正文")
        XCTAssertEqual(fixture("group",text:"正文",kind:"group").danmuText,"合成 · 示例：正文")
    }
    func testLongMessagesUseIslandAndKeepReaderUntilFinished() async throws {
        let (s,d,suite)=store();defer { d.removePersistentDomain(forName:suite) }
        var opened=0,closed=0
        s.onOpenReader={opened += 1};s.onCloseReader={closed += 1}
        s.updateDanmu(.init(enabled:true))
        let text=String(repeating:"这是岛内阅读的合成长消息。\n换行与表情🌱都要保留。",count:45)
        s.receive(fixture("island-long-1",text:text))
        XCTAssertEqual(s.readingID,"island-long-1");XCTAssertEqual(opened,1)
        XCTAssertNil(s.playback.overlay);XCTAssertEqual(s.playback.accepted,0)
        let pages=IslandReadingPages.split(text)
        XCTAssertGreaterThan(pages.count,1);XCTAssertEqual(pages.joined(),text)
        XCTAssertEqual(IslandReadingPages.split(""),[""])
        s.receive(fixture("island-long-2",text:text));s.receive(fixture("island-long-2",text:text))
        XCTAssertEqual(s.readingID,"island-long-1");XCTAssertEqual(s.readingQueue.count,2)
        XCTAssertEqual(opened,1);XCTAssertEqual(s.readingAccepted,2)
        let render=ImageRenderer(content:FeishuView(store:s).frame(width:356).padding(12).background(Color.black).preferredColorScheme(.dark))
        render.scale=2
        if let image=render.cgImage {
            XCTAssertLessThan(image.height,1100) // Do not size a window from the entire unpaged message.
            let png=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!
            try png.write(to:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/island-reader-check.png"))
        } else { XCTAssertTrue(false) }
        s.finishReading();XCTAssertEqual(s.readingID,"island-long-2")
        XCTAssertTrue(s.messages.first(where:{$0.id == "island-long-1"})!.viewed)
        s.finishReading();XCTAssertNil(s.readingID);XCTAssertEqual(closed,1)
        s.openReader("island-long-1");s.rememberReadingPage(2,for:"island-long-1")
        s.closeReader();s.openReader("island-long-1")
        XCTAssertEqual(s.readingPages["island-long-1"],2);s.closeReader()
        s.receive(fixture("short-island",text:"短消息"));XCTAssertEqual(s.readingAccepted,3)
        XCTAssertEqual(s.readingID,"short-island");XCTAssertNil(s.playback.overlay)
        XCTAssertEqual(s.playback.accepted,0)
        s.toggleMute();s.receive(fixture("muted-long",text:text))
        XCTAssertNil(s.readingID);XCTAssertEqual(s.readingAccepted,3)
        s.toggleMute();s.receive(fixture("stoppable-long",text:text));s.toggleReceiving()
        XCTAssertNil(s.readingID);XCTAssertTrue(s.readingQueue.isEmpty)
        let (demo,dd,ds)=store();defer { dd.removePersistentDomain(forName:ds) }
        demo.loadDemo();XCTAssertEqual(demo.readingID,"demo1")
        XCTAssertEqual(demo.readingQueue.count,2)
        XCTAssertGreaterThan(IslandReadingPages.split(demo.messages.first(where:{$0.id == "demo1"})!.text).count,1)
    }
    func testSyntheticCLIThroughStoreToBothOutputs() async throws {
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent("fusion-reader-" + UUID().uuidString)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
        setenv("DANMU_TEST_STATE",temp.appendingPathComponent("state.json").path,1)
        let reader=AccountReader(cli:root.appendingPathComponent("Tests/FeishuReaderChecks/fake-cli.py"),profile:"synthetic-island",pollDelay:0.01,pageDelay:0,clock:ServerClock(probe:{.local()}))
        reader.setRules(gray:["chat3"],hidden:["chat4"])
        let (s,d,suite)=store();defer { reader.stop();d.removePersistentDomain(forName:suite) }
        s.updateDanmu(.init(enabled:true));s.startSyntheticReader(reader)
        let deadline=Date().addingTimeInterval(30)
        while s.messages.count < 7 && Date() < deadline { try await Task.sleep(nanoseconds:50_000_000) }
        XCTAssertEqual(s.messages.count,7)
        XCTAssertTrue(s.messages.contains(where:{$0.id == "unknown"}))
        XCTAssertEqual(s.readingAccepted,s.important.count)
        XCTAssertGreaterThan(s.readingAccepted,0);XCTAssertEqual(s.playback.accepted,0);XCTAssertFalse(s.playback.windowVisible)
        let state=try JSONSerialization.jsonObject(with:Data(contentsOf:temp.appendingPathComponent("state.json"))) as! [String:Any]
        XCTAssertEqual((state["bad"] as! [String]).count,0)
        s.toggleReceiving();let count=s.messages.count
        try await Task.sleep(nanoseconds:200_000_000)
        XCTAssertEqual(s.messages.count,count);XCTAssertEqual(s.playback.queued,0)
    }
    func testSettingsConflictValidationAndAppearanceCapability() async throws {
        let (s,d,suite)=store();defer { d.removePersistentDomain(forName:suite) }
        let server=SettingsServer();server.start(store:s,listen:false)
        let host="127.0.0.1:18766",headers=["host":"127.0.0.1:18766","origin":"http://127.0.0.1:18766","x-island-settings":"1","content-type":"application/json"]
        let initial=await server.respond(method:"GET",path:"/api/settings",headers:["host":host],body:Data())
        var payload=try JSONSerialization.jsonObject(with:initial.body) as! [String:Any]
        payload["revision"] = -1
        let conflict=await server.respond(method:"POST",path:"/api/settings",headers:headers,body:try JSONSerialization.data(withJSONObject:payload));XCTAssertEqual(conflict.status,409)
        payload["revision"]=s.settingsRevision;payload["appearance"]=["fontSize":90];payload["enabled"]=false
        let bad=await server.respond(method:"POST",path:"/api/settings",headers:headers,body:try JSONSerialization.data(withJSONObject:payload));XCTAssertEqual(bad.status,400);XCTAssertTrue(s.enabled)
        let capability=await server.respond(method:"POST",path:"/api/agent",headers:headers,body:Data("{}".utf8))
        let token=(try JSONSerialization.jsonObject(with:capability.body) as! [String:Any])["token"] as! String
        let rpc:[String:Any] = ["jsonrpc":"2.0","id":1,"method":"tools/call","params":["name":"update_appearance","arguments":["patch":["fontSize":36]]]]
        let auth=["host":host,"content-type":"application/json","authorization":"Bearer " + token]
        let applied=await server.respond(method:"POST",path:"/mcp",headers:auth,body:try JSONSerialization.data(withJSONObject:rpc));XCTAssertEqual(applied.status,200);XCTAssertEqual(s.appearance["fontSize"] as? Int,36)
        let result=try JSONSerialization.jsonObject(with:applied.body) as! [String:Any];let content=(result["result"] as! [String:Any])["content"] as! [[String:Any]];let saved=try JSONSerialization.jsonObject(with:Data((content[0]["text"] as! String).utf8)) as! [String:Any];XCTAssertEqual(saved["saved"] as? Bool,true)
        var core = rpc; core["params"] = ["name":"update_appearance","arguments":["patch":["poll":1]]]
        let deniedCore=await server.respond(method:"POST",path:"/mcp",headers:auth,body:try JSONSerialization.data(withJSONObject:core))
        let deniedBody=try JSONSerialization.jsonObject(with:deniedCore.body) as! [String:Any]
        XCTAssertTrue(deniedBody["error"] != nil)
        let missing=await server.respond(method:"POST",path:"/mcp",headers:["host":host,"content-type":"application/json"],body:try JSONSerialization.data(withJSONObject:rpc));XCTAssertEqual(missing.status,403)
        var foreign=auth;foreign["origin"]="https://example.invalid";let blocked=await server.respond(method:"POST",path:"/mcp",headers:foreign,body:try JSONSerialization.data(withJSONObject:rpc));XCTAssertEqual(blocked.status,403)
        let directory=await server.respond(method:"GET",path:"/api/directory?kind=people",headers:["host":host],body:Data());XCTAssertEqual(directory.status,403)
    }
}

@main struct FusionRunner {
    @MainActor static func main() async {
        if CommandLine.arguments.contains("--serve-settings-fixture") {
            NSApplication.shared.setActivationPolicy(.prohibited)
            let suite="local.fusion.settings.fixture." + UUID().uuidString
            let defaults=UserDefaults(suiteName:suite)!
            let store=FeishuStore(defaults:defaults,receivingDefault:false)
            let server=SettingsServer(assetsRoot:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("SettingsWeb/dist"))
            server.start(store:store,preferredPort:18767)
            for _ in 0..<100 where server.address == nil { try? await Task.sleep(nanoseconds:50_000_000) }
            guard let address=server.address else { print("Synthetic settings server failed");exit(1) }
            print("Synthetic-only settings fixture: " + address);fflush(stdout)
            while !Task.isCancelled { try? await Task.sleep(nanoseconds:1_000_000_000) }
            defaults.removePersistentDomain(forName:suite);return
        }
        if CommandLine.arguments.contains("--feishu-network-check") {
            let success = await Task.detached { () -> Bool in
                let p = Process(), pipe = Pipe();p.executableURL = URL(fileURLWithPath:ProcessInfo.processInfo.environment["ISLAND_LARK_CLI"] ?? FeishuConnection().cliPath)
                p.arguments = ["im","+chat-list","--page-size","1","--as","user","--format","json"]
                var env = ProcessInfo.processInfo.environment;env["LARKSUITE_CLI_NO_UPDATE_NOTIFIER"] = "1";env["LARKSUITE_CLI_NO_SKILLS_NOTIFIER"] = "1"
                p.environment = FeishuTransport.shared.environment(env,allowLoopback:true)
                p.standardInput = FileHandle.nullDevice;p.standardOutput=pipe;p.standardError=pipe
                defer {try? pipe.fileHandleForReading.close();try? pipe.fileHandleForWriting.close()}
                do {try p.run();let bytes=pipe.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit();let d = try JSONSerialization.jsonObject(with:bytes) as? [String:Any];return p.terminationStatus == 0 && d?["ok"] as? Bool == true} catch{return false}
            }.value
            print(success ? "PASS: real Feishu user read-only connection, metadata only; no message bodies" : "FAIL: Feishu scoped connection unavailable");exit(success ? 0 : 1)
        }
        if CommandLine.arguments.contains("--work-ai-check") {
            do {
                let ai = WorkAI()
                let result = try await Task.detached { try ai.run(input:"合成材料：客户A反馈搜索缺少日期，客户B反馈导出慢。",instruction:"按问题列出两项，保留日期和导出这两个关键词，不超过100字。") }.value
                guard result.contains("日期"),result.contains("导出") else { print("FAIL: synthetic AI result incomplete");exit(1) }
                print("PASS: real local AI completed synthetic material, command/MCP/browser tools disabled; no real messages or credentials printed")
            } catch { print("FAIL: "+error.localizedDescription);exit(1) }; return
        }
        let tests = FusionTests()
        do {
            try await tests.testWorkspacePersistenceRemindersAndOAuthBoundary()
            await tests.testFreshInstallIsStoppedAndRendererIsLazy()
            await tests.testOneEventFeedsListAndOptionalRendererWithoutDuplicates()
            await tests.testMutePauseStopAndRulesAreSeparate()
            await tests.testExpandedIslandStillReceivesAndPresentsDesktopDanmu()
            await tests.testOrdinaryAndBlockedMessagesDoNotBecomeDanmu()
            await tests.testConnectionSwitchStopsAndClearsOldAccount()
            await tests.testHiddenRealRendererMovesAndPreservesCompleteLongText()
            await tests.testUnreadIsRecheckedAndQueueIsBounded()
            try await tests.testManualCardPagingAndSenderLabels()
            try await tests.testLongMessagesUseIslandAndKeepReaderUntilFinished()
            try await tests.testSettingsConflictValidationAndAppearanceCapability()
            try await tests.testSyntheticCLIThroughStoreToBothOutputs()
        } catch { failures.append("Synthetic settings request failed") }
        if failures.isEmpty { print("PASS: \(checks) fusion assertions; all renderer windows remained hidden; no real account calls") }
        else { print("FAIL: " + failures.joined(separator:", ")); exit(1) }
    }
}
