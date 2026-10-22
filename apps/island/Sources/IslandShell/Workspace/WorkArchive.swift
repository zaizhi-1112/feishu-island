import Foundation

final class ArchiveSaveBox: @unchecked Sendable { var saved = false }

/// Archival is a deterministic side effect, never an agent prompt. Only new, explicitly
/// selected tasks get a target; old tasks and chat reception are outside this pipeline.
struct WorkArchiveTarget: Codable, Equatable {
    var mode = "off"
    var url = ""
    var field = ""
    var wiki: String? {
        guard let u=URLComponents(string:url), u.scheme == "https", u.user == nil, u.password == nil, u.port == nil,
              u.host?.hasSuffix(".feishu.cn") == true else { return nil }
        let p=u.path.split(separator:"/")
        return p.count == 2 && p[0] == "wiki" && Self.identifier(String(p[1])) ? String(p[1]) : nil
    }
    var document: String? {
        guard let u = URLComponents(string:url), u.scheme == "https", u.user == nil, u.password == nil,
              u.port == nil, u.host?.hasSuffix(".feishu.cn") == true else { return nil }
        let p = u.path.split(separator:"/")
        guard p.count == 2, p[0] == "docx", Self.identifier(String(p[1])) else { return nil }
        return "https://\(u.host!)/docx/\(p[1])"
    }
    var table: (base:String, table:String)? {
        guard let u = URLComponents(string:url), u.scheme == "https", u.user == nil, u.password == nil,
              u.port == nil, u.host?.hasSuffix(".feishu.cn") == true else { return nil }
        let p = u.path.split(separator:"/")
        guard p.count == 2, p[0] == "base", Self.identifier(String(p[1])),
              let table = u.queryItems?.first(where:{$0.name == "table"})?.value,
              table.hasPrefix("tbl"), Self.identifier(table) else { return nil }
        return (String(p[1]), table)
    }
    static func identifier(_ s:String) -> Bool {
        !s.isEmpty && s.count <= 128 && s.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
    }
    func validate() throws {
        guard ["off","new","append","base"].contains(mode) else { throw WorkError.message("未知归档方式。") }
        if mode == "append", document == nil && wiki == nil { throw WorkError.message("请填写已有飞书云文档链接。") }
        if mode == "base", (table == nil && wiki == nil) || field.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
            throw WorkError.message("请填写含 table 参数的多维表格链接，并指定一个已有的多行文本字段。")
        }
    }
}
struct WorkArchiveReceipt: Codable, Equatable {
    var target: WorkArchiveTarget
    var digest: String
    var operation = UUID()
    var state = "pending"
    var document: String?
    var record: String?
    var written = false
    var uploaded: [String] = []
    var media: [String:ArchiveMedia]?
    var intent: String?
    var error = ""
    var verifiedAt: Date?
}
struct ArchiveMedia: Codable, Equatable { var block: String; var token: String }
struct WorkFile: Codable, Equatable {
    var name: String
    var filename: String
}
struct ArchiveAttachment {
    var key: String
    var name: String
    var url: URL
    var image: Bool
}

/// The dedicated CLI profile must be configured independently. Never fall back to
/// the reception profile, infer credentials from another client, or request scopes here.
struct WorkArchiveCLI {
    static let profile = "feishu-island-archive"
    var call: ([String], Data?) throws -> [String:Any]
    init(call: @escaping ([String],Data?) throws -> [String:Any]) { self.call = call }
    init() { call = Self.execute }
    static func execute(_ args:[String], _ input:Data?) throws -> [String:Any] {
        try execute(args,input,executable:Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/lark-cli"))
    }
    static func execute(_ args:[String], _ input:Data?, executable exe:URL) throws -> [String:Any] {
        guard FileManager.default.isExecutableFile(atPath:exe.path) else { throw WorkError.message("归档组件未安装。") }
        let p = Process(), out = Pipe(), stdin = Pipe()
        p.executableURL = exe; p.arguments = ["--profile",profile] + args
        p.standardOutput = out; p.standardError = FileHandle.nullDevice; p.standardInput = stdin
        p.environment = FeishuTransport.shared.environment(ProcessInfo.processInfo.environment)
        defer { try? out.fileHandleForReading.close(); try? out.fileHandleForWriting.close(); try? stdin.fileHandleForReading.close(); try? stdin.fileHandleForWriting.close() }
        try p.run()
        let timeout = DispatchWorkItem { if p.isRunning { p.terminate(); DispatchQueue.global().asyncAfter(deadline:.now()+2) { if p.isRunning { kill(p.processIdentifier,SIGKILL) } } } }
        DispatchQueue.global().asyncAfter(deadline:.now()+90,execute:timeout)
        defer { timeout.cancel() }
        DispatchQueue.global().async { if let input { try? stdin.fileHandleForWriting.write(contentsOf:input) }; try? stdin.fileHandleForWriting.close() }
        var data = Data()
        while true {
            let chunk = out.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            guard data.count + chunk.count <= 4_000_000 else { p.terminate(); throw WorkError.message("归档响应过大，保留进度等待核对。") }
            data.append(chunk)
        }
        p.waitUntilExit()
        guard p.terminationStatus == 0, let json = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              json["ok"] as? Bool != false, (json["code"] as? Int ?? 0) == 0 else {
            // CLI output can contain sensitive metadata. Never persist it as an error.
            throw WorkError.message("飞书归档请求未成功，请检查独立归档授权及目标权限；已完成的AI结果保留。")
        }
        return json
    }
    func request(_ args:[String], body:String? = nil) throws -> [String:Any] { try call(args,body.map{Data($0.utf8)}) }
    func api(_ method:String,_ path:String, body:[String:Any]? = nil, params:[String:Any]? = nil) throws -> [String:Any] {
        var args = ["api",method,path,"--as","user"]
        if body != nil { args += ["--data","-"] }
        if let params { args += ["--params",String(decoding:try JSONSerialization.data(withJSONObject:params),as:UTF8.self)] }
        return try request(args,body:body.map{String(decoding:try JSONSerialization.data(withJSONObject:$0),as:UTF8.self)})
    }
}

enum WorkArchive {
    static func resolve(_ target:WorkArchiveTarget,cli:WorkArchiveCLI) throws -> WorkArchiveTarget {
        guard let wiki=target.wiki else { return target }
        let result=data(try cli.api("GET","/open-apis/wiki/v2/spaces/get_node",params:["token":wiki]))
        guard let node=result["node"] as? [String:Any], let token=node["obj_token"] as? String, WorkArchiveTarget.identifier(token),
              node["obj_type"] as? String == (target.mode == "base" ? "bitable" : "docx") else { throw WorkError.message("链接指向的不是所选文档或多维表格类型。") }
        var u=URLComponents(string:target.url)!, resolved=target
        u.path="/"+(target.mode == "base" ? "base" : "docx")+"/"+token
        resolved.url=u.string!; try resolved.validate(); return resolved
    }
    static func xml(_ s:String) -> String {
        s.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;")
    }
    static func digest(_ item:WorkItem) -> String {
        WorkspaceStore.exportHash(item.title + "\u{0}" + (item.project ?? "") + "\u{0}" + item.input + "\u{0}" + item.result + "\u{0}" + (item.images ?? []).map{$0.id.uuidString}.joined(separator:",") + (item.archiveFiles ?? []).map{$0.filename}.joined(separator:","))
    }
    static func marker(_ item:WorkItem,_ receipt:WorkArchiveReceipt) -> String { "工作岛归档 \(item.id.uuidString) \(receipt.digest)" }
    static func body(_ item:WorkItem,_ receipt:WorkArchiveReceipt) -> String {
        let parts = [marker(item,receipt),item.title,"原始材料",item.input,"处理结果",item.result.isEmpty ? "直接归档，未调用AI。" : item.result]
        return parts.flatMap{$0.components(separatedBy:"\n")}.map{"<p>"+xml($0)+"</p>"}.joined()
    }
    static func strings(_ value:Any) -> [String] {
        if let s = value as? String { return [s] }
        if let d = value as? [String:Any] { return d.values.flatMap{strings($0)} }
        if let a = value as? [Any] { return a.flatMap{strings($0)} }
        return []
    }
    static func data(_ response:[String:Any]) -> [String:Any] { response["data"] as? [String:Any] ?? response }
    static func run(item:WorkItem, initial:WorkArchiveReceipt, attachments:[ArchiveAttachment], cli:WorkArchiveCLI,
                    save:(WorkArchiveReceipt) throws -> Void) throws -> WorkArchiveReceipt {
        var r = initial
        try r.target.validate()
        guard r.digest == digest(item), r.target.mode != "off" else { throw WorkError.message("材料已变化，请重新选择归档。") }
        if r.state == "succeeded" { return r }
        // An unacknowledged non-idempotent write requires checking its existing destination.
        // Never re-create a document or re-upload a file after an ambiguous response.
        guard r.intent == nil else { throw WorkError.message("上次写入结果待核对，未重复归档。") }
        r.target = try resolve(r.target,cli:cli)
        var scopes = "docx:document:create docx:document:write_only docx:document:readonly"
        if !attachments.isEmpty { scopes += " docs:document.media:upload" }
        if r.target.mode == "base" { scopes += " base:field:read base:record:create base:record:read" }
        let permission = try cli.request(["auth","check","--scope",scopes,"--json"])
        guard permission["ok"] as? Bool == true else { throw WorkError.message("独立飞书归档授权未就绪；AI结果已保留，连接后可只重试归档。") }
        r.state = "running"; r.error = ""; try save(r)
        if r.target.mode == "base", let t = r.target.table {
            let fields = data(try cli.api("GET","/open-apis/bitable/v1/apps/\(t.base)/tables/\(t.table)/fields",params:["page_size":100]))
            guard let rows = fields["items"] as? [[String:Any]], rows.contains(where:{$0["field_name"] as? String == r.target.field && $0["type"] as? Int == 1}) else {
                throw WorkError.message("指定字段不存在或不是多行文本，未写入或修改表结构。")
            }
        }
        if r.document == nil {
            if r.target.mode == "append" { r.document = r.target.document; try save(r) }
            else {
                r.intent = "create"; try save(r)
                let response = try cli.request(["docs","+create","--as","user","--title",item.title,"--content","-","--doc-format","xml"],body:"<p>"+xml(marker(item,r))+"</p>")
                let doc = data(response)["document"] as? [String:Any]
                guard let url = doc?["url"] as? String, WorkArchiveTarget(mode:"append",url:url).document != nil else { throw WorkError.message("创建响应缺少可核对的文档链接，未重复创建。") }
                r.document = url; r.intent = nil; try save(r)
            }
        }
        guard let doc = r.document else { throw WorkError.message("缺少归档目标。") }
        let end = "归档正文完成 " + item.id.uuidString + " " + r.digest
        if !r.written {
            let before = strings(try cli.request(["docs","+fetch","--as","user","--doc",doc])).joined(separator:"\n")
            if !before.contains(end) {
                r.intent = "append"; try save(r)
                _ = try cli.request(["docs","+update","--as","user","--doc",doc,"--command","append","--doc-format","xml","--content","-"],body:body(item,r)+"<p>"+end+"</p>")
            }
            let after = strings(try cli.request(["docs","+fetch","--as","user","--doc",doc])).joined(separator:"\n")
            let expected = [item.input,item.result].flatMap{$0.components(separatedBy:"\n")}.filter{!$0.isEmpty}
            guard after.contains(end), after.contains(marker(item,r)), expected.allSatisfy({after.contains($0) || after.contains(xml($0))}) else { throw WorkError.message("文档回读不一致，未标记归档完成。") }
            r.written = true; r.intent = nil; try save(r)
        }
        for a in attachments where !r.uploaded.contains(a.key) {
            if r.media?[a.key] == nil {
                r.intent = "attachment:"+a.key; try save(r)
                let response = data(try cli.request(["docs","+media-insert","--as","user","--doc",doc,"--file",a.url.path,"--type",a.image ? "image" : "file"]))
                guard let block=response["block_id"] as? String, let token=response["file_token"] as? String,
                      WorkArchiveTarget.identifier(block), WorkArchiveTarget.identifier(token) else { throw WorkError.message("附件上传回执不完整，未重复上传。") }
                if r.media == nil { r.media=[:] }
                r.media?[a.key]=ArchiveMedia(block:block,token:token); r.intent=nil; try save(r)
            }
            let media=r.media![a.key]!, token=URL(string:doc)!.lastPathComponent
            let block=try cli.api("GET","/open-apis/docx/v1/documents/\(token)/blocks/\(media.block)")
            var found = strings(block).contains(media.token)
            if !found, let content=data(block)["block"] as? [String:Any], content["block_type"] as? Int == 33,
               let children=content["children"] as? [String], children.count<=10 {
                for child in children where WorkArchiveTarget.identifier(child) {
                    let nested=try cli.api("GET","/open-apis/docx/v1/documents/\(token)/blocks/\(child)")
                    if strings(nested).contains(media.token) { found=true; break }
                }
            }
            guard found else { throw WorkError.message("附件回读不一致，保留上传回执，未重复上传。") }
            r.uploaded.append(a.key); r.intent = nil; try save(r)
        }
        if r.target.mode == "base", let t = r.target.table {
            let path = "/open-apis/bitable/v1/apps/\(t.base)/tables/\(t.table)/records"
            let value = item.title+"\n"+marker(item,r)+"\n归档文档："+doc
            if r.record == nil {
                // Raw endpoint is intentional: typed upsert has no client_token and can duplicate.
                let created = data(try cli.api("POST",path,body:["fields":[r.target.field:value]],params:["client_token":r.operation.uuidString]))
                guard let record = created["record"] as? [String:Any], let id = record["record_id"] as? String, WorkArchiveTarget.identifier(id) else { throw WorkError.message("表格响应缺少记录编号，保留幂等编号供重试。") }
                r.record = id; try save(r)
            }
            let result = data(try cli.api("GET",path+"/"+r.record!))
            guard strings(result).contains(value) else { throw WorkError.message("表格记录回读不一致，未标记完成。") }
        }
        r.state = "succeeded"; r.verifiedAt = Date(); r.error = ""; try save(r); return r
    }
}
