import Foundation
import AppKit
import CryptoKit
@testable import IslandShell

actor SyntheticDotWebhook: DotWebhookTransport {
    struct Received: Sendable { var headers: [String:String]; var body: Data }
    var received: [Received] = []
    var status=202
    var badChallenge=false
    func set(status: Int) { self.status=status }
    func set(badChallenge: Bool) { self.badChallenge=badChallenge }
    func snapshot() -> [Received] { received }
    func post(url: String, headers: [String:String], body: Data) async throws -> DotWebhookReply {
        received.append(Received(headers:headers,body:body))
        let value=try JSONSerialization.jsonObject(with:body) as! [String:Any]
        if value["type"] as? String=="verification" {
            return DotWebhookReply(status:200,body:try JSONSerialization.data(withJSONObject:["challenge":badChallenge ? "wrong" : value["challenge"]!]))
        }
        return DotWebhookReply(status:status,body:Data())
    }
}
extension FusionTests {
    @MainActor func testDotEvents() async throws {
        var health=DotTunnelHealth()
        XCTAssertFalse(health.observe(ready:false)); XCTAssertFalse(health.observe(ready:false))
        XCTAssertFalse(health.observe(ready:true)); XCTAssertFalse(health.observe(ready:false))
        XCTAssertFalse(health.observe(ready:false)); XCTAssertTrue(health.observe(ready:false))
        for ip in ["0.0.0.0","10.0.0.1","127.1.2.3","100.64.0.1","169.254.169.254","172.16.0.1","192.168.1.1","192.0.0.1","192.0.2.1","192.88.99.1","198.18.0.1","198.51.100.1","203.0.113.1","224.0.0.1","255.255.255.255","::1"] { XCTAssertFalse(DotPublicWebhook.publicIPv4(ip)) }
        for ip in ["1.1.1.1","8.8.8.8","104.18.1.1"] { XCTAssertTrue(DotPublicWebhook.publicIPv4(ip)) }
        var lookups=0
        let resolver: (String) throws -> [String] = { _ in lookups+=1; return ["104.18.1.1"] }
        XCTAssertEqual(try DotPublicWebhook.validatedAddress(host:"receiver.example",addresses:["198.18.0.39"],publicDNS:resolver),"104.18.1.1")
        XCTAssertEqual(lookups,1)
        for (host,addresses) in [("198.18.0.39",["198.18.0.39"]),("receiver.example",["127.0.0.1"]),("receiver.example",["198.18.0.39","10.0.0.1"])] {
            do { _=try DotPublicWebhook.validatedAddress(host:host,addresses:addresses,publicDNS:resolver); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        }
        XCTAssertEqual(lookups,1)
        do { _=try DotPublicWebhook.validatedAddress(host:"receiver.example",addresses:["198.19.0.1"],publicDNS:{_ in ["104.18.1.1","127.0.0.1"]}); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        for url in ["http://receiver.example/", "https://user:pass@receiver.example/", "https://receiver.example:8443/", "https://receiver.example/#fragment", "file:///tmp/a"] {
            do { _=try DotPublicWebhook.destination(url); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        }
        // Real transport rejects numeric loopback before any connection; synthetic transport below never sends network traffic.
        do { _=try DotPublicWebhook.resolve("127.0.0.1"); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("island-dot-events-"+UUID().uuidString)
        let store=WorkspaceStore(root:root,startTimers:false), vault=MemoryDotCredentials()
        store.draftService="dot"
        XCTAssertEqual(WorkspaceStore(root:root,startTimers:false).draftService,"dot")
        var clock=Date(), unlocked=true
        let pairing=DotPairing(credentials:vault,now:{clock}), wire=SyntheticDotWebhook()
        let token=try pairing.pair(project:"合成订阅项目"), grant=try pairing.authenticate(token)!
        let events=DotEvents(pairing:pairing,store:store,transport:wire,allowed:{unlocked},now:{clock})
        let signingKey=Data(repeating:42,count:32), secret="whsec_"+signingKey.base64EncodedString()
        let url="https://receiver.example/mcp-events"
        var params: [String:Any] = ["name":DotEvents.name,"arguments":["project":grant.project],"delivery":["mode":"webhook","url":url,"secret":secret],"cursor":NSNull()]
        func rpc(_ method: String,_ p: [String:Any]) async -> [String:Any] { await events.rpc(["jsonrpc":"2.0","id":1,"method":method,"params":p],grant:grant)! }
        XCTAssertTrue(DotMCP.rpc(["jsonrpc":"2.0","id":1,"method":"server/discover"],grant:grant,store:store)?["result"] != nil)
        XCTAssertTrue(await rpc("events/list",[:])["result"] != nil)
        var invalid=params; invalid["arguments"]=["project":"其他项目"]
        XCTAssertTrue(await rpc("events/subscribe",invalid)["error"] != nil)
        invalid=params; invalid["ttlMs"]=true
        XCTAssertTrue(await rpc("events/subscribe",invalid)["error"] != nil)
        invalid=params; invalid["delivery"]=["mode":"webhook","url":url,"secret":"bad"]
        XCTAssertTrue(await rpc("events/subscribe",invalid)["error"] != nil)
        await wire.set(badChallenge:true)
        XCTAssertTrue(await rpc("events/subscribe",params)["error"] != nil); XCTAssertNil(pairing.grants[0].subscription)
        await wire.set(badChallenge:false)
        let response=await rpc("events/subscribe",params)
        XCTAssertTrue(response["result"] != nil)
        let subscription=pairing.grants[0].subscription!
        XCTAssertEqual(subscription.id,DotEvents.identity(grant:grant.id,url:url,project:grant.project))
        let reload=DotPairing(credentials:vault,now:{clock}); try reload.load()
        XCTAssertEqual(reload.grants[0].subscription,subscription)
        _=await rpc("events/subscribe",params)
        XCTAssertEqual(pairing.grants.count,1); XCTAssertEqual(pairing.grants[0].subscription?.id,subscription.id)
        let note=try store.add(text:"普通待办不通知",minutes:0,project:grant.project,service:"dot")
        let other=try store.add(text:"其他项目不通知",minutes:0,project:"其他项目",service:"dot"); store.run(other)
        let id=try store.add(text:"合成材料不进入事件正文",minutes:0,project:grant.project,service:"dot"); store.run(id)
        await wire.set(status:503)
        await events.pump()
        let item=store.disk.items.first(where:{$0.id==id})!, dispatch=item.dotDispatch!
        XCTAssertEqual(item.dotDeliveries?[subscription.id]?.attempts,1)
        var messages=await wire.snapshot()
        let sent=messages.last!, value=try JSONSerialization.jsonObject(with:sent.body) as! [String:Any]
        XCTAssertEqual(value["eventId"] as? String,dispatch.uuidString)
        let text=String(decoding:sent.body,as:UTF8.self)
        XCTAssertFalse(text.contains("合成材料")); XCTAssertFalse(text.contains(note.uuidString)); XCTAssertFalse(text.contains(other.uuidString)); XCTAssertFalse(text.contains(secret)); XCTAssertFalse(text.contains(token))
        let timestamp=sent.headers["webhook-timestamp"]!
        let expected=Data(HMAC<SHA256>.authenticationCode(for:Data((dispatch.uuidString+"."+timestamp+".").utf8)+sent.body,using:SymmetricKey(data:signingKey))).base64EncodedString()
        XCTAssertEqual(sent.headers["webhook-signature"],"v1,"+expected)
        await events.pump(); XCTAssertEqual((await wire.snapshot()).count,messages.count)
        unlocked=false; clock=clock.addingTimeInterval(30)
        await events.pump(); XCTAssertEqual((await wire.snapshot()).count,messages.count)
        unlocked=true; await wire.set(status:202)
        let restarted=WorkspaceStore(root:root,startTimers:false)
        let restoredEvents=DotEvents(pairing:reload,store:restarted,transport:wire,now:{clock})
        await restoredEvents.pump()
        messages=await wire.snapshot()
        XCTAssertEqual(messages.last?.headers["webhook-id"],dispatch.uuidString)
        XCTAssertTrue(restarted.disk.items.first(where:{$0.id==id})?.dotDeliveries?[subscription.id]?.accepted==true)
        await restoredEvents.pump(); XCTAssertEqual((await wire.snapshot()).count,messages.count)
        // Receipt is not completion. The scoped claim/result path alone completes and alerts.
        XCTAssertEqual(restarted.disk.items.first(where:{$0.id==id})?.state,"dot_waiting")
        var alerts=0; restarted.notify={_ in alerts+=1}
        let claim=try restarted.claimDot(id,grant:grant.id,now:clock)
        try restarted.finishDot(id,grant:grant.id,claim:claim.id,digest:claim.digest,text:"合成通知处理成功",now:clock)
        XCTAssertEqual(alerts,1)
        // Permanent failures stop; refreshing/duplicate events do not re-execute tasks.
        for status in [410,413] {
            let task=try store.add(text:"合成永久失败",minutes:0,project:grant.project,service:"dot"); store.run(task)
            await wire.set(status:status); await events.pump()
            XCTAssertTrue(store.disk.items.first(where:{$0.id==task})?.dotDeliveries?[subscription.id]?.stopped==true)
        }
        let retryID=try store.add(text:"合成限次重试",minutes:0,project:grant.project,service:"dot"); store.run(retryID)
        await wire.set(status:503)
        for _ in 0..<7 { clock=clock.addingTimeInterval(400); await events.pump() }
        XCTAssertEqual(store.disk.items.first(where:{$0.id==retryID})?.dotDeliveries?[subscription.id]?.attempts,6)
        XCTAssertTrue(store.disk.items.first(where:{$0.id==retryID})?.dotDeliveries?[subscription.id]?.stopped==true)
        await wire.set(status:202)
        await wire.set(badChallenge:true)
        clock=clock.addingTimeInterval(901)
        await events.pump()
        XCTAssertTrue(store.disk.items.first(where:{$0.id==retryID})?.dotDeliveries?[subscription.id]?.stopped==true)
        await wire.set(badChallenge:false)
        clock=clock.addingTimeInterval(901)
        await events.pump()
        XCTAssertTrue(store.disk.items.first(where:{$0.id==retryID})?.dotDeliveries?[subscription.id]?.accepted==true)
        XCTAssertEqual(store.disk.items.first(where:{$0.id==retryID})?.dotDeliveries?[subscription.id]?.attempts,1)
        XCTAssertTrue(store.disk.items.filter{$0.dotDeliveries?[subscription.id]?.status==410 || $0.dotDeliveries?[subscription.id]?.status==413}.allSatisfy{$0.dotDeliveries?[subscription.id]?.stopped==true})
        let cancelled=try store.add(text:"取消不通知",minutes:0,project:grant.project,service:"dot"); store.run(cancelled); store.cancel(cancelled)
        let cancelledCount=(await wire.snapshot()).count
        await events.pump(); XCTAssertEqual((await wire.snapshot()).count,cancelledCount)
        let unsubscribe: [String:Any] = ["name":DotEvents.name,"arguments":["project":grant.project],"delivery":["mode":"webhook","url":url]]
        _=await rpc("events/unsubscribe",unsubscribe); _=await rpc("events/unsubscribe",unsubscribe)
        XCTAssertNil(pairing.grants[0].subscription)
        let before=(await wire.snapshot()).count
        await events.pump(); XCTAssertEqual((await wire.snapshot()).count,before)
        // Finite TTL, rotation, secure-storage failure and grant revocation.
        params["ttlMs"]=1000
        _=await rpc("events/subscribe",params)
        XCTAssertTrue(pairing.grants[0].subscription!.expires<=clock.addingTimeInterval(1))
        clock=clock.addingTimeInterval(2); let expiredCount=(await wire.snapshot()).count
        await events.pump(); XCTAssertEqual((await wire.snapshot()).count,expiredCount)
        params["ttlMs"]=NSNull()
        params["delivery"]=["mode":"webhook","url":url,"secret":"whsec_"+Data(repeating:9,count:32).base64EncodedString()]
        _=await rpc("events/subscribe",params)
        let rotated=pairing.grants[0].subscription!
        XCTAssertEqual(rotated.previousSecret,secret)
        XCTAssertEqual(try DotWebhookSigner.headers(id:"test",subscription:rotated,body:Data(),now:clock)["webhook-signature"]?.split(separator:" ").count,2)
        vault.denySave=true
        XCTAssertTrue(await rpc("events/subscribe",params)["error"] != nil)
        vault.denySave=false; try pairing.disconnect(project:grant.project)
        XCTAssertTrue(await rpc("events/subscribe",params)["error"] != nil); XCTAssertEqual(pairing.grants.count,0)
        // Actual loopback HTTP: discovery, subscription, queued event, claim/result and lock.
        let httpToken=try pairing.pair(project:grant.project)
        let server=SettingsServer(dotPairing:pairing,workspace:store,dotTransport:wire)
        server.start(store:self.store().0,preferredPort:0)
        for _ in 0..<50 { if server.address != nil { break }; try await Task.sleep(for:.milliseconds(20)) }
        guard let address=server.address else { throw WorkError.message("Synthetic event listener unavailable") }
        func http(_ method: String,_ p: [String:Any] = [:], origin: String? = nil) async throws -> (Int,[String:Any]) {
            var req=URLRequest(url:URL(string:address+"/mcp/dot")!); req.httpMethod="POST"
            req.setValue("application/json",forHTTPHeaderField:"Content-Type"); req.setValue("Bearer "+httpToken,forHTTPHeaderField:"Authorization")
            req.setValue("2026-07-28",forHTTPHeaderField:"MCP-Protocol-Version")
            if let origin { req.setValue(origin,forHTTPHeaderField:"Origin") }
            req.httpBody=try JSONSerialization.data(withJSONObject:["jsonrpc":"2.0","id":7,"method":method,"params":p])
            let (data,r)=try await URLSession.shared.data(for:req)
            return ((r as! HTTPURLResponse).statusCode,try JSONSerialization.jsonObject(with:data) as! [String:Any])
        }
        let discovery=try await http("server/discover")
        XCTAssertEqual(discovery.0,200); XCTAssertEqual((discovery.1["result"] as? [String:Any])?["cacheScope"] as? String,"private")
        let catalog=try await http("events/list")
        XCTAssertEqual((catalog.1["result"] as? [String:Any])?["resultType"] as? String,"complete")
        XCTAssertEqual(try await http("events/list",origin:address).0,403)
        XCTAssertTrue(try await http("events/subscribe",params).1["result"] != nil)
        await wire.set(status:202)
        let httpID=try store.add(text:"HTTP合成自动通知材料",minutes:0,project:grant.project,service:"dot")
        store.run(httpID)
        for _ in 0..<100 {
            if store.disk.items.first(where:{$0.id==httpID})?.dotDeliveries?.values.contains(where:{$0.accepted})==true { break }
            try await Task.sleep(for:.milliseconds(20))
        }
        XCTAssertTrue(store.disk.items.first(where:{$0.id==httpID})?.dotDeliveries?.values.contains(where:{$0.accepted})==true)
        let claimed=try await http("tools/call",["name":"claim_work_task","arguments":["task_id":httpID.uuidString]])
        XCTAssertEqual((claimed.1["result"] as? [String:Any])?["resultType"] as? String,"complete")
        let lease=store.disk.items.first(where:{$0.id==httpID})!.dotClaim!
        let saved=try await http("tools/call",["name":"submit_work_result","arguments":["task_id":httpID.uuidString,"claim_id":lease.id.uuidString,"digest":lease.digest,"text":"HTTP合成通知回传成功"]])
        XCTAssertTrue(saved.1["result"] != nil)
        XCTAssertEqual(store.disk.items.first(where:{$0.id==httpID})?.state,"succeeded")
        let reread=try await http("tools/call",["name":"read_work_task","arguments":["task_id":httpID.uuidString]])
        XCTAssertTrue(String(decoding:try JSONSerialization.data(withJSONObject:reread.1),as:UTF8.self).contains("HTTP合成通知回传成功"))
        NSWorkspace.shared.notificationCenter.post(name:NSWorkspace.sessionDidResignActiveNotification,object:nil)
        XCTAssertEqual(try await http("events/list").0,403)
        NSWorkspace.shared.notificationCenter.post(name:NSWorkspace.sessionDidBecomeActiveNotification,object:nil)
        XCTAssertTrue(try await http("events/unsubscribe",unsubscribe).1["result"] != nil)
        try pairing.disconnect(project:grant.project)
        try await testDotRenewalAcrossDays()
        print("PASS: Dot MCP2 events via real loopback HTTP and synthetic callback; not a real Dot client")
    }
    @MainActor private func testDotRenewalAcrossDays() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("dot-renewal-"+UUID().uuidString)
        let store=WorkspaceStore(root:root,startTimers:false), vault=MemoryDotCredentials(), wire=SyntheticDotWebhook()
        var clock=Date(), unlocked=true
        let pairing=DotPairing(credentials:vault,now:{clock})
        let token=try pairing.pair(project:"合成跨天"), first=try pairing.authenticate(token)!
        let events=DotEvents(pairing:pairing,store:store,transport:wire,allowed:{unlocked},now:{clock})
        let params: [String:Any] = ["name":DotEvents.name,"arguments":["project":first.project],"delivery":["mode":"webhook","url":"https://receiver.example/events","secret":"whsec_"+Data(repeating:7,count:32).base64EncodedString()]]
        func renew(_ target: DotEvents, _ p: DotPairing) async throws -> [String:Any] {
            let grant=try p.authenticate(token)!
            return await target.rpc(["jsonrpc":"2.0","id":1,"method":"events/subscribe","params":params],grant:grant)!
        }
        XCTAssertTrue(try await renew(events,pairing)["result"] != nil)
        let original=pairing.grants[0].subscription!
        for _ in 0..<3 {
            clock=clock.addingTimeInterval(23*3600)
            XCTAssertTrue(try await renew(events,pairing)["result"] != nil)
            XCTAssertEqual(pairing.grants[0].subscription?.id,original.id)
            XCTAssertTrue(pairing.grants[0].subscription!.expires>clock)
        }
        let expiry=pairing.grants[0].subscription!.expires
        XCTAssertEqual(events.healthSnapshot["refreshCount"],"4")
        XCTAssertFalse(String(describing:events.healthSnapshot).contains(token))
        vault.denySave=true
        // Failed persistence cannot erase or falsely extend the last confirmed subscription.
        let failure=await events.rpc(["jsonrpc":"2.0","id":1,"method":"events/subscribe","params":params],grant:pairing.grants[0])!
        XCTAssertTrue(failure["error"] != nil); XCTAssertEqual(pairing.grants[0].subscription!.expires,expiry)
        vault.denySave=false
        clock=clock.addingTimeInterval(25*3600)
        let task=try store.add(text:"跨天断线后仅补发此合成任务",minutes:0,project:first.project,service:"dot"); store.run(task)
        let count=(await wire.snapshot()).count
        await events.pump(); XCTAssertEqual((await wire.snapshot()).count,count)
        let restored=DotPairing(credentials:vault,now:{clock}); try restored.load()
        let resumed=DotEvents(pairing:restored,store:store,transport:wire,allowed:{unlocked},now:{clock})
        unlocked=false; XCTAssertTrue(try await renew(resumed,restored)["error"] != nil)
        unlocked=true; XCTAssertTrue(try await renew(resumed,restored)["result"] != nil)
        XCTAssertEqual(restored.grants[0].id,first.id)
        resumed.deliveryReady={false}
        let offlineCount=(await wire.snapshot()).count
        await resumed.pump(); XCTAssertEqual((await wire.snapshot()).count,offlineCount)
        resumed.deliveryReady={true}
        await resumed.pump()
        XCTAssertTrue(store.disk.items.first(where:{$0.id==task})?.dotDeliveries?[original.id]?.accepted==true)
        let accepted=(await wire.snapshot()).count
        await resumed.pump(); XCTAssertEqual((await wire.snapshot()).count,accepted)
        print("PASS: simulated 94-hour renewal, expiry, lock, restart and pending recovery with unchanged pairing")
    }
}
