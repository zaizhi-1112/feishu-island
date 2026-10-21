import Foundation
import AppKit
import SwiftUI
@testable import IslandShell

@MainActor final class MemoryDotCredentials: DotCredentialStore {
    var value: [DotGrant] = []
    var denySave=false
    func load() throws -> [DotGrant] { value }
    func save(_ grants: [DotGrant]) throws { if denySave { throw WorkError.message("synthetic storage failure") }; value=grants }
}
extension FusionTests {
    @MainActor func testDotPairingAndDelegation() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("island-dot-check-"+UUID().uuidString)
        let s=WorkspaceStore(root:root,startTimers:false)
        let vault=MemoryDotCredentials()
        var date=Date()
        let auth=DotPairing(credentials:vault,now:{date})
        let token=try auth.pair(project:"Dot合成联调")
        XCTAssertEqual(try auth.pair(project:"Dot合成联调"),token)
        XCTAssertNil(try auth.authenticate("invalid"))
        date=date.addingTimeInterval(1801)
        let grant=try auth.authenticate(token)!
        XCTAssertTrue(grant.expires>date.addingTimeInterval(29*86400))
        let reload=DotPairing(credentials:vault,now:{date})
        XCTAssertEqual(try reload.authenticate(token)?.id,grant.id)
        let note=try s.add(text:"本项目普通待办，不发送",minutes:0,project:grant.project,service:"dot")
        let outsider=try s.add(text:"其他项目不共享",minutes:0,project:"其他项目",service:"dot")
        let codex=try s.add(text:"Codex资料不共享",minutes:0,project:grant.project,service:"codex")
        let pending=try PendingWorkImage.decode(syntheticWorkImage(),name:"合成红蓝色块")
        let id=try s.add(text:"合成材料：搜索需要日期筛选；导出需要显示进度。",instruction:"归纳两条反馈。",minutes:0,images:[pending],project:grant.project,service:"dot")
        s.run(id)
        XCTAssertEqual(s.disk.items.first(where:{$0.id==id})?.state,"dot_waiting")
        var alerts=0; s.notify={_ in alerts+=1}
        func call(_ name: String,_ args: [String:Any] = [:], grant override: DotGrant? = nil) -> [String:Any] {
            DotMCP.rpc(["jsonrpc":"2.0","id":1,"method":"tools/call","params":["name":name,"arguments":args]],grant:override ?? grant,store:s,now:date)!
        }
        for hidden in [note,outsider,codex] { XCTAssertTrue(call("read_work_task",["task_id":hidden.uuidString])["error"] != nil) }
        XCTAssertTrue(call("list_project_tasks",["extra":true])["error"] != nil)
        let list=String(decoding:try JSONSerialization.data(withJSONObject:call("list_project_tasks")),as:UTF8.self)
        XCTAssertTrue(list.contains(id.uuidString)); XCTAssertFalse(list.contains(note.uuidString)); XCTAssertFalse(list.contains(outsider.uuidString))
        let original=s.disk.items.first(where:{$0.id==id})!
        XCTAssertTrue(call("claim_work_task",["task_id":id.uuidString])["result"] != nil)
        let lease=s.disk.items.first(where:{$0.id==id})!.dotClaim!
        XCTAssertEqual(s.disk.items.first(where:{$0.id==id})?.state,"dot_running")
        _=call("claim_work_task",["task_id":id.uuidString]); XCTAssertEqual(s.disk.items.first(where:{$0.id==id})?.dotClaim?.id,lease.id)
        let imageArgs: [String:Any] = ["task_id":id.uuidString,"claim_id":lease.id.uuidString,"image_id":pending.image.id.uuidString]
        XCTAssertTrue(call("read_work_image",imageArgs)["result"] != nil)
        var badImage=imageArgs; badImage["image_id"]=UUID().uuidString
        XCTAssertTrue(call("read_work_image",badImage)["error"] != nil)
        var args: [String:Any] = ["task_id":id.uuidString,"claim_id":lease.id.uuidString,"digest":WorkspaceMCP.digest(original),"text":"合成结果：日期筛选；导出进度。"]
        var wrong=args; wrong["digest"]="invalid"
        XCTAssertTrue(call("submit_work_result",wrong)["error"] != nil)
        wrong=args; wrong["claim_id"]=UUID().uuidString
        XCTAssertTrue(call("submit_work_result",wrong)["error"] != nil)
        let other=DotGrant(project:grant.project,secret:"synthetic",expires:date.addingTimeInterval(86400))
        XCTAssertTrue(call("submit_work_result",args,grant:other)["error"] != nil)
        XCTAssertTrue(call("heartbeat_work_task",["task_id":id.uuidString,"claim_id":lease.id.uuidString])["result"] != nil)
        XCTAssertTrue(call("submit_work_result",args)["result"] != nil)
        _=call("submit_work_result",args); XCTAssertEqual(alerts,1)
        wrong=args; wrong["text"]="不得覆盖已有结果"
        XCTAssertTrue(call("submit_work_result",wrong)["error"] != nil)
        let result=s.disk.items.first(where:{$0.id==id})!
        XCTAssertEqual(result.state,"succeeded"); XCTAssertEqual(result.result,args["text"] as? String); XCTAssertEqual(result.resultSource,"Dot回传")
        XCTAssertTrue(call("read_work_task",["task_id":id.uuidString])["result"] != nil)
        let persisted=WorkspaceStore(root:root,startTimers:false)
        XCTAssertEqual(persisted.disk.items.first(where:{$0.id==id})?.result,result.result)
        // New task after pairing, failure, retry, cancel, and stale late results.
        let retry=try s.add(text:"新派单合成材料",minutes:0,project:grant.project,service:"dot")
        s.run(retry); let claim=try s.claimDot(retry,grant:grant.id,now:date)
        try s.finishDot(retry,grant:grant.id,claim:claim.id,digest:claim.digest,text:"合成失败",failed:true,now:date)
        XCTAssertEqual(s.disk.items.first(where:{$0.id==retry})?.state,"failed"); XCTAssertEqual(alerts,2)
        s.run(retry); let fresh=try s.claimDot(retry,grant:grant.id,now:date)
        XCTAssertFalse(fresh.id==claim.id)
        do { try s.finishDot(retry,grant:grant.id,claim:claim.id,digest:claim.digest,text:"旧结果",now:date); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        s.cancel(retry)
        do { try s.finishDot(retry,grant:grant.id,claim:fresh.id,digest:fresh.digest,text:"取消后的旧结果",now:date); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        s.beginEdit(retry); s.editInput="修改后的新任务"; s.saveEdit()
        XCTAssertEqual(s.disk.items.first(where:{$0.id==retry})?.state,"todo")
        XCTAssertTrue(call("read_work_task",["task_id":retry.uuidString])["error"] != nil)
        s.run(retry); let timeout=try s.claimDot(retry,grant:grant.id,now:date)
        s.expireDotClaims(now:date.addingTimeInterval(1801))
        XCTAssertEqual(s.disk.items.first(where:{$0.id==retry})?.state,"interrupted")
        do { try s.heartbeatDot(retry,grant:grant.id,claim:timeout.id,now:date.addingTimeInterval(1801)); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        // Reconnect is authentication only, not permission to run unsent notes.
        let server=SettingsServer(dotPairing:auth,workspace:s)
        server.start(store:store().0,listen:true,preferredPort:0)
        for _ in 0..<50 { if server.address != nil { break }; try await Task.sleep(for:.milliseconds(20)) }
        guard let address=server.address else { throw WorkError.message("Synthetic listener unavailable") }
        func wire(_ authorization: String, origin: String? = nil, method: String = "POST") async throws -> Int {
            var req=URLRequest(url:URL(string:address+"/mcp/dot")!); req.httpMethod=method
            req.setValue("application/json",forHTTPHeaderField:"Content-Type"); req.setValue("Bearer "+authorization,forHTTPHeaderField:"Authorization")
            if let origin { req.setValue(origin,forHTTPHeaderField:"Origin") }
            if method=="POST" { req.httpBody=try JSONSerialization.data(withJSONObject:["jsonrpc":"2.0","id":1,"method":"initialize"]) }
            let (_,response)=try await URLSession.shared.data(for:req); return (response as! HTTPURLResponse).statusCode
        }
        func rpcWire(_ name: String,_ args: [String:Any] = [:]) async throws -> [String:Any] {
            var req=URLRequest(url:URL(string:address+"/mcp/dot")!); req.httpMethod="POST"
            req.setValue("application/json",forHTTPHeaderField:"Content-Type"); req.setValue("Bearer "+token,forHTTPHeaderField:"Authorization")
            req.httpBody=try JSONSerialization.data(withJSONObject:["jsonrpc":"2.0","id":1,"method":"tools/call","params":["name":name,"arguments":args]])
            let (data,response)=try await URLSession.shared.data(for:req)
            XCTAssertEqual((response as! HTTPURLResponse).statusCode,200)
            let object=try JSONSerialization.jsonObject(with:data) as! [String:Any]
            guard let result=object["result"] as? [String:Any], let blocks=result["content"] as? [[String:Any]], let text=blocks.first?["text"] as? String else { throw WorkError.message("Synthetic RPC did not return content") }
            return try JSONSerialization.jsonObject(with:Data(text.utf8)) as! [String:Any]
        }
        let wireID=try s.add(text:"合成HTTP全流程：日期筛选和导出进度。",minutes:0,project:grant.project,service:"dot")
        s.run(wireID)
        let wireList=try await rpcWire("list_project_tasks")
        XCTAssertTrue((wireList["tasks"] as? [[String:Any]])?.contains(where:{$0["task_id"] as? String==wireID.uuidString}) == true)
        let wireClaim=try await rpcWire("claim_work_task",["task_id":wireID.uuidString])
        let wireRead=try await rpcWire("read_work_task",["task_id":wireID.uuidString])
        XCTAssertEqual(wireRead["state"] as? String,"dot_running")
        let wireArgs: [String:Any] = ["task_id":wireID.uuidString,"claim_id":wireClaim["claim_id"]!,"digest":wireClaim["digest"]!,"text":"HTTP合成验证：日期筛选；导出进度。"]
        let before=alerts
        let receipt=try await rpcWire("submit_work_result",wireArgs)
        XCTAssertEqual(receipt["saved"] as? Bool,true)
        _=try await rpcWire("submit_work_result",wireArgs)
        let verified=try await rpcWire("read_work_task",["task_id":wireID.uuidString])
        XCTAssertEqual(verified["state"] as? String,"succeeded"); XCTAssertEqual(verified["result"] as? String,wireArgs["text"] as? String)
        XCTAssertEqual(alerts,before+1)
        let wireReload=WorkspaceStore(root:root,startTimers:false)
        XCTAssertEqual(wireReload.disk.items.first(where:{$0.id==wireID})?.result,wireArgs["text"] as? String)
        NSWorkspace.shared.notificationCenter.post(name:NSWorkspace.sessionDidResignActiveNotification,object:nil)
        XCTAssertEqual(try await wire(token),403)
        NSWorkspace.shared.notificationCenter.post(name:NSWorkspace.sessionDidBecomeActiveNotification,object:nil)
        XCTAssertEqual(try await wire(token),200)
        XCTAssertEqual(try await wire("wrong"),403)
        XCTAssertEqual(try await wire(token,origin:"https://example.invalid"),403)
        XCTAssertEqual(try await wire(token,origin:address),403)
        XCTAssertEqual(try await wire(token,method:"GET"),403)
        try auth.disconnect(project:grant.project)
        XCTAssertEqual(try await wire(token),403)
        XCTAssertNil(try DotPairing(credentials:vault).authenticate(token))
        let replacement=try auth.pair(project:grant.project)
        XCTAssertFalse(replacement==token)
        vault.denySave=true
        do { _=try auth.authenticate(replacement); XCTAssertTrue(false) } catch { XCTAssertTrue(true) }
        vault.denySave=false; date=date.addingTimeInterval(31*86400)
        XCTAssertNil(try auth.authenticate(replacement))
        args["text"]="unused"
        // Render only, no desktop surface or real account access.
        s.boardTab=0; s.draftService="dot"; s.draftProject="Dot合成联调"
        let renderer=ImageRenderer(content:WorkspaceView(store:s,desktop:true,dotPairing:auth).background(Color.black).preferredColorScheme(.dark))
        renderer.scale=1
        XCTAssertTrue(renderer.cgImage != nil)
        print("PASS: Dot synthetic delegation, restart, >30-minute renewal, expiry, revocation, scoped images, claim and result; real loopback HTTP")
    }
}
