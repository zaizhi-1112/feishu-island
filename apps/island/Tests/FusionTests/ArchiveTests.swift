import Foundation
@testable import IslandShell

@MainActor extension FusionTests {
    /// Explicit opt-in only. Stores synthetic checkpoints outside Git; never reads reception data.
    func testArchiveLive() async throws {
        let env=ProcessInfo.processInfo.environment
        guard let executable=env["ISLAND_ARCHIVE_CLI"], let directory=env["ISLAND_ARCHIVE_CHECK_DIR"] else { throw WorkError.message("需要显式提供验收CLI和独立检查目录。") }
        let root=URL(fileURLWithPath:directory,isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let file=root.appendingPathComponent("synthetic-material.txt"), image=root.appendingPathComponent("synthetic-red-blue.png")
        try Data("合成材料：客户甲需要日期筛选；客户乙需要导出进度。".utf8).write(to:file)
        try syntheticWorkImage().write(to:image)
        let checkpoint=root.appendingPathComponent("receipt.json"), source=root.appendingPathComponent("item.json")
        var item:WorkItem
        if FileManager.default.fileExists(atPath:source.path) { item=try JSONDecoder().decode(WorkItem.self,from:Data(contentsOf:source)) }
        else {
            item=WorkItem(title:"工作岛统一归档合成验收",input:"合成材料：客户甲需要日期筛选；客户乙需要导出进度。\n来源链接：https://example.com",instruction:"合成归档，不调用AI")
            item.result="1. 客户甲：搜索需要日期筛选。\n2. 客户乙：导出需要显示进度。"
            try JSONEncoder().encode(item).write(to:source)
        }
        let target:WorkArchiveTarget
        if let base=env["ISLAND_ARCHIVE_BASE"] { target=WorkArchiveTarget(mode:"base",url:base,field:env["ISLAND_ARCHIVE_FIELD"] ?? "归档内容") }
        else if let doc=env["ISLAND_ARCHIVE_APPEND"] { target=WorkArchiveTarget(mode:"append",url:doc) }
        else { target=WorkArchiveTarget(mode:"new") }
        let receipt=FileManager.default.fileExists(atPath:checkpoint.path) ? try JSONDecoder().decode(WorkArchiveReceipt.self,from:Data(contentsOf:checkpoint)) : WorkArchiveReceipt(target:target,digest:WorkArchive.digest(item))
        let client=WorkArchiveCLI { args, input in try WorkArchiveCLI.execute(args,input,executable:URL(fileURLWithPath:executable)) }
        let captured=item
        let result=try await Task.detached {
            try WorkArchive.run(item:captured,initial:receipt,attachments:[ArchiveAttachment(key:"image",name:image.lastPathComponent,url:image,image:true),ArchiveAttachment(key:"file",name:file.lastPathComponent,url:file,image:false)],cli:client) { r in
                try JSONEncoder().encode(r).write(to:checkpoint,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:checkpoint.path)
            }
        }.value
        print("PASS: real synthetic archive, mode="+target.mode+", state="+result.state+", attachments="+String(result.uploaded.count))
        print("Document: "+(result.document ?? "missing"))
    }
    func testArchiveAutomation() throws {
        XCTAssertNil(WorkArchiveTarget(mode:"append",url:"https://example.com/docx/x").document)
        XCTAssertNil(WorkArchiveTarget(mode:"append",url:"https://a.feishu.cn.evil.test/docx/x").document)
        XCTAssertNil(WorkArchiveTarget(mode:"base",url:"https://a.feishu.cn/base/x?table=../../x",field:"内容").table)
        XCTAssertEqual(WorkArchive.xml("<source path=\"@/etc/passwd\"/>&"),"&lt;source path=&quot;@/etc/passwd&quot;/&gt;&amp;")
        var item=WorkItem(title:"归档合成",input:"客户甲：日期筛选\nhttps://example.com",instruction:"整理")
        item.result="客户甲需要日期筛选。"
        var saved=WorkArchiveReceipt(target:WorkArchiveTarget(mode:"new"),digest:WorkArchive.digest(item))
        var text="", creates=0, appends=0, calls=0
        let client=WorkArchiveCLI { args, body in
            calls += 1
            if args == ["auth","status","--json"] { return ["appId":"cli_synthetic","identities":["user":["available":true,"openId":"ou_synthetic"]]] }
            if args.contains("+create") { creates += 1; text=String(decoding:body!,as:UTF8.self); return ["data":["document":["url":"https://synthetic.feishu.cn/docx/test123"]]] }
            if args.contains("+update") { appends += 1; text += String(decoding:body!,as:UTF8.self); return ["ok":true] }
            if args.contains("+fetch") { return ["data":["content":text]] }
            return ["ok":true]
        }
        let final=try WorkArchive.run(item:item,initial:saved,attachments:[],cli:client,save:{saved=$0})
        XCTAssertEqual(final.state,"succeeded"); XCTAssertEqual(creates,1); XCTAssertEqual(appends,1)
        XCTAssertEqual(final.connectionIdentity?.count,64)
        var resume=final;resume.state="failed"
        var foreignCalls=0
        let foreign=WorkArchiveCLI { args, _ in
            foreignCalls += 1
            if args == ["auth","status","--json"] { return ["appId":"cli_synthetic","identities":["user":["available":true,"openId":"ou_another"]]] }
            return ["ok":true]
        }
        do{_=try WorkArchive.run(item:item,initial:resume,attachments:[],cli:foreign,save:{_ in});XCTAssertTrue(false)}catch{XCTAssertTrue(true)}
        XCTAssertEqual(foreignCalls,1) // identity only; no existing document is touched
        var legacy=resume;legacy.connectionIdentity=nil
        let legacyBefore=calls
        do{_=try WorkArchive.run(item:item,initial:legacy,attachments:[],cli:client,save:{_ in});XCTAssertTrue(false)}catch{XCTAssertTrue(true)}
        XCTAssertEqual(calls,legacyBefore+1)
        let resumed=try WorkArchive.run(item:item,initial:resume,attachments:[],cli:client,save:{_ in})
        XCTAssertEqual(resumed.state,"succeeded");XCTAssertEqual(creates,1);XCTAssertEqual(appends,1)
        XCTAssertTrue(text.contains("https://example.com")); XCTAssertTrue(text.contains(item.result))
        let before=calls
        _=try WorkArchive.run(item:item,initial:final,attachments:[],cli:client,save:{_ in})
        XCTAssertEqual(calls,before)
        var uncertain=WorkArchiveReceipt(target:WorkArchiveTarget(mode:"new"),digest:WorkArchive.digest(item))
        let failing=WorkArchiveCLI { args, _ in
            if args == ["auth","status","--json"] { return ["appId":"cli_synthetic","identities":["user":["available":true,"openId":"ou_synthetic"]]] }
            if args.contains("+create") { throw WorkError.message("合成断线") }
            return ["ok":true]
        }
        do { _=try WorkArchive.run(item:item,initial:uncertain,attachments:[],cli:failing,save:{uncertain=$0}); XCTAssertTrue(false) } catch {}
        XCTAssertEqual(uncertain.intent,"create")
        do { _=try WorkArchive.run(item:item,initial:uncertain,attachments:[],cli:client,save:{_ in}); XCTAssertTrue(false) } catch {}
        XCTAssertEqual(creates,1)
        var append=WorkArchiveReceipt(target:WorkArchiveTarget(mode:"append",url:"https://synthetic.feishu.cn/docx/test123"),digest:WorkArchive.digest(item))
        _=try WorkArchive.run(item:item,initial:append,attachments:[],cli:client,save:{append=$0})
        XCTAssertEqual(appends,1); XCTAssertEqual(creates,1) // existing completion marker prevents duplicate append
        var changed=item; changed.input="新材料"
        do { _=try WorkArchive.run(item:changed,initial:append,attachments:[],cli:client,save:{_ in}); XCTAssertTrue(false) } catch {}
        let store=WorkspaceStore(root:FileManager.default.temporaryDirectory.appendingPathComponent("archive-fixture-"+UUID().uuidString),startTimers:false)
        let id=try store.add(text:"本机合成待办",minutes:0)
        XCTAssertNil(store.disk.items[0].archiveTarget)
        try store.configureArchive(id,target:WorkArchiveTarget(mode:"new"))
        XCTAssertNil(store.disk.items[0].archive) // choosing a target never uploads a draft
        var busy=item; busy.archive=final; busy.archive?.state="running"
        XCTAssertFalse(WorkspaceStore.canEdit(busy))
        var recordValue="", recordCalls=0, uploads=0, recordToken=""
        var base=WorkArchiveReceipt(target:WorkArchiveTarget(mode:"base",url:"https://synthetic.feishu.cn/base/base123?table=tbl123",field:"收录"),digest:WorkArchive.digest(item))
        let baseClient=WorkArchiveCLI { args, body in
            if args.contains("+media-insert") { uploads += 1; return ["data":["block_id":"block123","file_token":"media123"]] }
            if args.contains(where:{$0.hasSuffix("/blocks/block123")}) { return ["data":["block":["block_type":33,"children":["child123"]]]] }
            if args.contains(where:{$0.hasSuffix("/blocks/child123")}) { return ["data":["block":["file":["token":"media123"]]]] }
            if args.contains(where:{$0.hasSuffix("/fields")}) { return ["data":["items":[["field_name":"收录","type":1]]]] }
            if args.contains("POST") {
                recordCalls += 1
                let payload=try JSONSerialization.jsonObject(with:body!) as! [String:Any]
                recordValue=(payload["fields"] as! [String:String])["收录"]!
                recordToken=args[args.firstIndex(of:"--params")!+1]
                return ["data":["record":["record_id":"rec123"]]]
            }
            if args.contains(where:{$0.hasSuffix("/records/rec123")}) { return ["data":["record":["fields":["收录":recordValue]]]] }
            return try client.call(args,body)
        }
        _=try WorkArchive.run(item:item,initial:base,attachments:[ArchiveAttachment(key:"file",name:"synthetic.txt",url:URL(fileURLWithPath:"/synthetic.txt"),image:false)],cli:baseClient,save:{base=$0})
        XCTAssertEqual(base.state,"succeeded"); XCTAssertEqual(base.uploaded,["file"]); XCTAssertEqual(uploads,1)
        XCTAssertEqual(recordCalls,1); XCTAssertTrue(recordToken.contains(base.operation.uuidString)); XCTAssertTrue(recordValue.contains("归档文档"))
        _=try WorkArchive.run(item:item,initial:base,attachments:[],cli:baseClient,save:{_ in})
        XCTAssertEqual(recordCalls,1)
        let absent=WorkArchiveCLI { _,_ in ["ok":false,"missing":["docx:document:create"]] }
        var wrote=false
        do { _=try WorkArchive.run(item:item,initial:WorkArchiveReceipt(target:WorkArchiveTarget(mode:"new"),digest:WorkArchive.digest(item)),attachments:[],cli:absent,save:{_ in wrote=true}); XCTAssertTrue(false) } catch {}
        XCTAssertFalse(wrote)
        print("PASS: deterministic archive checkpoints, XML escaping, target restrictions, idempotency and no implicit upload")
    }
}
