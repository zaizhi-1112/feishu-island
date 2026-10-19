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
        XCTAssertEqual(s.messages.count,2);XCTAssertEqual(s.playback.accepted,1);XCTAssertEqual(s.playback.queued,1)
        XCTAssertFalse(s.playback.windowVisible)
    }
    func testMutePauseStopAndRulesAreSeparate() async {
        let (s,d,suite)=store();defer { d.removePersistentDomain(forName:suite) }
        s.updateDanmu(.init(enabled:true,paused:true));s.receive(fixture("paused"))
        XCTAssertEqual(s.playback.queued,1);s.playback.overlay?.tick();XCTAssertEqual(s.playback.visible,0)
        s.toggleMute();XCTAssertEqual(s.playback.queued,0);s.receive(fixture("muted"));XCTAssertEqual(s.messages.count,2);XCTAssertEqual(s.playback.accepted,1)
        s.toggleMute();s.updateDanmu(.init(enabled:true));s.receive(fixture("active"));XCTAssertEqual(s.playback.queued,1)
        s.toggleReceiving();s.receive(fixture("late"));XCTAssertEqual(s.messages.count,3);XCTAssertEqual(s.playback.queued,0)
        s.playback.suspend(true);XCTAssertFalse(s.playback.windowVisible)
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
        XCTAssertEqual(s.playback.accepted,s.important.count)
        XCTAssertGreaterThan(s.playback.accepted,0);XCTAssertFalse(s.playback.windowVisible)
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
        let tests = FusionTests()
        do {
            await tests.testFreshInstallIsStoppedAndRendererIsLazy()
            await tests.testOneEventFeedsListAndOptionalRendererWithoutDuplicates()
            await tests.testMutePauseStopAndRulesAreSeparate()
            await tests.testOrdinaryAndBlockedMessagesDoNotBecomeDanmu()
            await tests.testConnectionSwitchStopsAndClearsOldAccount()
            await tests.testHiddenRealRendererMovesAndPreservesCompleteLongText()
            await tests.testUnreadIsRecheckedAndQueueIsBounded()
            try await tests.testSettingsConflictValidationAndAppearanceCapability()
            try await tests.testSyntheticCLIThroughStoreToBothOutputs()
        } catch { failures.append("Synthetic settings request failed") }
        if failures.isEmpty { print("PASS: \(checks) fusion assertions; all renderer windows remained hidden; no real account calls") }
        else { print("FAIL: " + failures.joined(separator:", ")); exit(1) }
    }
}
