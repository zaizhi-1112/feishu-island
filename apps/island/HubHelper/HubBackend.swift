import Foundation
import Security
import LocalAuthentication
import CryptoKit


private struct HubGrant: Codable {
    var clientID: String
    var access: String
    var refresh: String?
    var expires: Date
}
actor HubBackend {
    private let service = "local.zaizhi.feishu-island.hub.oauth.helper-v1"
    private var pending: (state:String,verifier:String,client:String,callback:String,date:Date)?
    private var session: String?
    private var rpcID = 0
    private var epoch = UUID()
    init() {}
    private func random() throws -> String {
        var bytes = [UInt8](repeating:0,count:32)
        guard bytes.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault,$0.count,$0.baseAddress!) }) == errSecSuccess else { throw WorkError.message("安全随机数生成失败。") }
        return Data(bytes).base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
    }
    private func readGrant() throws -> HubGrant? {
        var result: CFTypeRef?
        let context = LAContext(); context.interactionNotAllowed = true
        let q: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"personal",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne,kSecUseAuthenticationContext as String:context]
        let status = SecItemCopyMatching(q as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw WorkError.message("中台钥匙串读取暂不可用（状态\(status)），未请求或读取你的密码。") }
        return try? JSONDecoder().decode(HubGrant.self,from:data)
    }
    private func save(_ grant: HubGrant) throws {
        let data = try JSONEncoder().encode(grant)
        let q: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"personal"]
        let attrs: [String:Any] = [kSecValueData as String:data,kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(q as CFDictionary,attrs as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(q.merging(attrs){_,b in b} as CFDictionary,nil) == errSecSuccess else { throw WorkError.message("无法把个人授权保存到钥匙串。") }
        } else if status != errSecSuccess { throw WorkError.message("钥匙串暂不可用，请解锁Mac后重试。") }
    }
    func disconnect() {
        SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"personal"] as CFDictionary)
        pending = nil; session = nil; epoch = UUID()
    }
    private nonisolated static func perform(request: URLRequest) async throws -> (Data,URLResponse) {
        let config = URLSessionConfiguration.ephemeral;config.timeoutIntervalForRequest=30;config.timeoutIntervalForResource=30;config.httpCookieStorage=nil;config.urlCache=nil
        let session = URLSession(configuration:config)
        defer { session.invalidateAndCancel() }
        return try await withCheckedThrowingContinuation { c in
            session.dataTask(with:request) { data,response,error in
                if let error { c.resume(throwing:error) }
                else if let data,let response { c.resume(returning:(data,response)) }
                else { c.resume(throwing:WorkError.message("中台未返回有效响应。")) }
            }.resume()
        }
    }
    private func http(_ url: String, json: [String:Any]? = nil, form: [String:String]? = nil, bearer: String? = nil, extra: [String:String] = [:]) async throws -> (Data,HTTPURLResponse) {
        guard let u = URL(string:url), u.scheme == "https", u.host == "virxact.net" else { throw WorkError.message("中台地址不合法。") }
        var r = URLRequest(url:u); r.httpMethod = "POST"
        r.setValue("application/json, text/event-stream",forHTTPHeaderField:"Accept")
        if let json { r.httpBody = try JSONSerialization.data(withJSONObject:json); r.setValue("application/json",forHTTPHeaderField:"Content-Type") }
        if let form {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn:"-._~"))
            r.httpBody = Data(form.sorted{$0.key < $1.key}.map { $0.key+"="+($0.value.addingPercentEncoding(withAllowedCharacters:allowed) ?? "") }.joined(separator:"&").utf8)
            r.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type")
        }
        if let bearer { r.setValue("Bearer "+bearer,forHTTPHeaderField:"Authorization") }
        for (key,value) in extra { r.setValue(value,forHTTPHeaderField:key) }
        let (data,response) = try await Self.perform(request:r)
        guard let response = response as? HTTPURLResponse else { throw WorkError.message("中台响应无效。") }
        guard response.url?.host == "virxact.net", data.count < 4_000_000 else { throw WorkError.message("中台响应超出范围。") }
        guard (200..<300).contains(response.statusCode) else { throw WorkError.message(response.statusCode == 401 ? "中台授权已失效，请重新连接。" : "中台暂时无法读取（\(response.statusCode)），请稍后重试。") }
        return (data,response)
    }
    func begin(callback: String) async throws -> URL {
        guard let c = URL(string:callback), c.host == "127.0.0.1", c.path == "/oauth/virxact/callback", c.scheme == "http" else { throw WorkError.message("授权回调地址无效。") }
        let (data,_) = try await http("https://virxact.net/oauth/register",json:["client_name":"飞书工作岛 · 本机个人卡片","redirect_uris":[callback],"grant_types":["authorization_code","refresh_token"],"response_types":["code"],"token_endpoint_auth_method":"none"])
        guard let value = try JSONSerialization.jsonObject(with:data) as? [String:Any], let client = value["client_id"] as? String else { throw WorkError.message("中台未返回客户端编号。") }
        let state = try random(), verifier = try random()
        let challenge = Data(SHA256.hash(data:Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        pending = (state,verifier,client,callback,Date())
        var url = URLComponents(string:"https://virxact.net/oauth/authorize")!
        url.queryItems = ["client_id":client,"redirect_uri":callback,"response_type":"code","scope":"hub","state":state,"code_challenge":challenge,"code_challenge_method":"S256","resource":"https://virxact.net/mcp"].map{URLQueryItem(name:$0.key,value:$0.value)}
        return url.url!
    }
    private nonisolated static func sameState(_ a:String,_ b:String) -> Bool {
        let lhs=Array(a.utf8),rhs=Array(b.utf8);guard lhs.count==rhs.count else{return false}
        return zip(lhs,rhs).reduce(UInt8(0)){$0 | ($1.0 ^ $1.1)} == 0
    }
    func finish(query: [URLQueryItem]) async throws {
        let generation=epoch
        guard let p = pending, Date().timeIntervalSince(p.date) < 600 else { throw WorkError.message("授权请求已过期，请重新连接。") }
        guard Set(query.map(\.name)).count == query.count, Self.sameState(query.first(where:{$0.name == "state"})?.value ?? "",p.state) else { throw WorkError.message("授权校验未通过。") }
        pending = nil
        guard let code = query.first(where:{$0.name == "code"})?.value, !code.isEmpty else { throw WorkError.message("未完成中台授权。") }
        let (data,_) = try await http("https://virxact.net/oauth/token",form:["grant_type":"authorization_code","client_id":p.client,"code":code,"redirect_uri":p.callback,"code_verifier":p.verifier,"resource":"https://virxact.net/mcp"])
        guard generation == epoch else{throw WorkError.message("连接已断开，授权未保存。") }
        try save(decodeToken(data,client:p.client,previous:nil)); session = nil; epoch = UUID()
    }
    private func decodeToken(_ data: Data, client: String, previous: String?) throws -> HubGrant {
        guard let v = try JSONSerialization.jsonObject(with:data) as? [String:Any], let token = v["access_token"] as? String, !token.isEmpty else { throw WorkError.message("个人授权未成功。") }
        return HubGrant(clientID:client,access:token,refresh:v["refresh_token"] as? String ?? previous,expires:Date().addingTimeInterval(Double(v["expires_in"] as? Int ?? 3600)))
    }
    private func access() async throws -> String {
        let generation=epoch
        guard var grant = try readGrant() else { throw WorkError.message("请先连接本人虚实中台，读取你的飞书首页与数据。") }
        if grant.expires.timeIntervalSinceNow < 60 {
            guard let refresh = grant.refresh else { throw WorkError.message("中台授权已过期，请重新连接。") }
            let (data,_) = try await http("https://virxact.net/oauth/token",form:["grant_type":"refresh_token","client_id":grant.clientID,"refresh_token":refresh])
            guard generation == epoch else{throw WorkError.message("连接已断开。")};grant = try decodeToken(data,client:grant.clientID,previous:refresh); try save(grant)
        }
        return grant.access
    }
    private func rpc(_ method: String, params: [String:Any], token: String, notification: Bool = false) async throws -> [String:Any] {
        rpcID += 1
        let requestID = rpcID
        var object: [String:Any] = ["jsonrpc":"2.0","method":method,"params":params]
        if !notification { object["id"] = requestID }
        var headers = ["MCP-Protocol-Version":"2025-03-26"]
        if let session { headers["Mcp-Session-Id"] = session }
        let (data,response) = try await http("https://virxact.net/mcp",json:object,bearer:token,extra:headers)
        if let sid = response.value(forHTTPHeaderField:"Mcp-Session-Id") { session = sid }
        if notification { return [:] }
        let raw: Data
        if response.value(forHTTPHeaderField:"Content-Type")?.contains("text/event-stream") == true {
            let lines = String(decoding:data,as:UTF8.self).components(separatedBy:"\n").filter{$0.hasPrefix("data:")}.map{String($0.dropFirst(5)).trimmingCharacters(in:.whitespaces)}
            guard let matching = lines.compactMap({ try? JSONSerialization.jsonObject(with:Data($0.utf8)) as? [String:Any] }).last(where:{($0["id"] as? Int) == requestID}) else { throw WorkError.message("中台未返回请求结果。") }
            raw = try JSONSerialization.data(withJSONObject:matching)
        } else { raw = data }
        guard let v = try JSONSerialization.jsonObject(with:raw) as? [String:Any], v["error"] == nil, let result = v["result"] as? [String:Any] else { throw WorkError.message("中台请求未成功，请重新连接后重试。") }
        return result
    }
    private func tool(_ name: String, _ args: [String:Any], token: String) async throws -> [String:Any] {
        guard ["get_page","get_spec"].contains(name) else { throw WorkError.message("本机仅允许读取个人卡片。") }
        let result = try await rpc("tools/call",params:["name":name,"arguments":args],token:token)
        guard result["isError"] as? Bool != true, let content = result["content"] as? [[String:Any]], let text = content.first(where:{$0["type"] as? String == "text"})?["text"] as? String,
              let value = try? JSONSerialization.jsonObject(with:Data(text.utf8)) as? [String:Any] else { throw WorkError.message("中台数据未读到，请在飞书检查本人权限。") }
        return value
    }
    func document(_ link: String) async throws -> String {
        guard let url = URL(string:link.trimmingCharacters(in:.whitespacesAndNewlines)), url.scheme == "https", let host = url.host,
              (host.hasSuffix(".feishu.cn") || host.hasSuffix(".larksuite.com")), url.path.hasPrefix("/docx/") || url.path.hasPrefix("/wiki/") else { throw WorkError.message("请填入本人可读的飞书文档或知识库链接。") }
        let token = try await access()
        if session == nil {
            _ = try await rpc("initialize",params:["protocolVersion":"2025-03-26","capabilities":[:],"clientInfo":["name":"feishu-island","version":"0.7.0"]],token:token)
            _ = try await rpc("notifications/initialized",params:[:],token:token,notification:true)
        }
        let result = try await rpc("tools/call",params:["name":"read_document","arguments":["url":url.absoluteString]],token:token)
        guard result["isError"] as? Bool != true, let blocks = result["content"] as? [[String:Any]] else { throw WorkError.message("飞书文档读取失败，请检查本人权限。") }
        var text = blocks.compactMap{$0["text"] as? String}.joined(separator:"\n")
        if let envelope = try? JSONSerialization.jsonObject(with:Data(text.utf8)) as? [String:Any] {
            guard envelope["auth"] == nil, envelope["error"] == nil, envelope["forbidden"] == nil else{throw WorkError.message("此飞书文档未读到，请先在中台完成本人授权或申请文档权限。")}
            text = envelope["markdown"] as? String ?? envelope["content"] as? String ?? envelope["text"] as? String ?? text
        }
        guard !text.isEmpty, text.utf8.count <= 200_000 else { throw WorkError.message("文档为空或太长，请选择更小的章节。") }
        return text
    }
    func snapshot() async throws -> HubSnapshot {
        let generation = epoch
        let token = try await access()
        if session == nil {
            _ = try await rpc("initialize",params:["protocolVersion":"2025-03-26","capabilities":[:],"clientInfo":["name":"feishu-island","version":"0.7.0"]],token:token)
            _ = try await rpc("notifications/initialized",params:[:],token:token,notification:true)
        }
        var snapshot = HubSnapshot(); snapshot.connected = true
        for kind in ["page","data"] {
            let page = try await tool("get_page",["scope":"me","kind":kind,"includeData":true],token:token)
            snapshot.name = page["name"] as? String ?? "本人中台"
            for (index,entry) in ((page["data"] as? [[String:Any]]) ?? []).enumerated() {
                let title = entry["title"] as? String ?? "个人卡片"
                let result = entry["result"] as? [String:Any] ?? entry
                snapshot.cards.append(HubCard(id:"\(kind):\(title):\(index)",title:title,kind:result["type"] as? String ?? "",text:Self.readable(result),href:page["view"] as? String))
            }
        }
        guard generation == epoch else { throw WorkError.message("连接已改变，请重新刷新。") }
        snapshot.readAt = Date(); return snapshot
    }
    nonisolated static func readable(_ value: Any, depth: Int = 0) -> String { HubReadable.readable(value,depth:depth) }
}
