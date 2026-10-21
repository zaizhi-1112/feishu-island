import Foundation
import Security

struct DotGrant: Codable {
    var id = UUID()
    var project: String
    var secret: String
    var expires: Date
    var lastSeen: Date?
    var subscription: DotSubscription?
}
@MainActor protocol DotCredentialStore {
    func load() throws -> [DotGrant]
    func save(_ grants: [DotGrant]) throws
}
/// The stable signed helper owns Keychain access. Never prompts or reads another service.
@MainActor final class DotKeychain: DotCredentialStore {
    private func request(_ action: String, grants: [DotGrant]? = nil) throws -> [String:Any] {
        guard let bundle=Bundle.main.bundleIdentifier, ["local.zaizhi.feishu-island.preview","local.zaizhi.feishu-island.dot-sandbox"].contains(bundle),
              let base=Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent() else { throw WorkError.message("Dot安全组件仅在本人安装版或独立合成窗口可用。") }
        let helper=base.appendingPathComponent("Helpers/feishu-dot-auth")
        guard FileManager.default.isExecutableFile(atPath:helper.path) else { throw WorkError.message("Dot安全组件未安装，未创建连接。") }
        var payload: [String:Any] = ["action":action]
        if let grants { payload["grants"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(grants)) }
        let p=Process(), input=Pipe(), output=Pipe()
        p.executableURL=helper; p.arguments=bundle.hasSuffix("dot-sandbox") ? ["--sandbox"] : []
        p.standardInput=input; p.standardOutput=output; p.standardError=FileHandle.nullDevice
        defer { try? input.fileHandleForWriting.close(); try? input.fileHandleForReading.close(); try? output.fileHandleForReading.close(); try? output.fileHandleForWriting.close() }
        try p.run()
        let timeout=DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline:.now()+5,execute:timeout); defer { timeout.cancel() }
        try input.fileHandleForWriting.write(contentsOf:JSONSerialization.data(withJSONObject:payload)); try input.fileHandleForWriting.close()
        let data=output.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard p.terminationStatus==0, data.count<=200_000, let reply=try? JSONSerialization.jsonObject(with:data) as? [String:Any], reply["ok"] as? Bool==true else { throw WorkError.message("Dot钥匙串暂不可读写；未要求密码，连接未更改。") }
        return reply
    }
    func load() throws -> [DotGrant] {
        let value=try request("load")
        return try JSONDecoder().decode([DotGrant].self,from:JSONSerialization.data(withJSONObject:value["grants"] ?? []))
    }
    func save(_ grants: [DotGrant]) throws { _ = try request("save",grants:grants) }
}
@MainActor final class DotPairing: ObservableObject {
    @Published private(set) var grants: [DotGrant] = []
    @Published private(set) var error = ""
    private let credentials: any DotCredentialStore
    var now: () -> Date
    private var loaded = false
    static let lifetime: TimeInterval = 30*86400
    init(credentials: (any DotCredentialStore)? = nil, now: @escaping () -> Date = Date.init) { self.credentials=credentials ?? DotKeychain(); self.now=now }
    func load() throws {
        guard !loaded else { return }
        do { grants=try credentials.load(); loaded=true; error="" }
        catch { self.error=error.localizedDescription; throw error }
    }
    func grant(project: String) -> DotGrant? { grants.first { $0.project == project && $0.expires > now() } }
    func pair(project: String) throws -> String {
        try load()
        guard !project.isEmpty, project.count<=60 else { throw WorkError.message("先填写60字以内的项目名称。") }
        if let existing=grant(project:project) { return existing.secret }
        guard grants.filter({$0.expires>now()}).count<20 else { throw WorkError.message("最多连接20个项目，请先断开不再使用的项目。") }
        var bytes=[UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes)==errSecSuccess else { throw WorkError.message("无法生成安全配对。") }
        let secret=Data(bytes).base64EncodedString()
        var next=grants.filter{$0.project != project && $0.expires>now()}
        next.append(DotGrant(project:project,secret:secret,expires:now().addingTimeInterval(Self.lifetime)))
        try credentials.save(next); grants=next; return secret
    }
    func authenticate(_ secret: String) throws -> DotGrant? {
        try load()
        // Compare fixed-size secrets without early content-dependent exit.
        guard let index=grants.firstIndex(where:{ Self.matches($0.secret,secret) && $0.expires>now() }) else { return nil }
        var next=grants
        next[index].lastSeen=now(); next[index].expires=now().addingTimeInterval(Self.lifetime)
        try credentials.save(next); grants=next
        return next[index]
    }
    func disconnect(project: String) throws {
        try load(); let next=grants.filter{$0.project != project}
        try credentials.save(next); grants=next
    }
    func setSubscription(_ subscription: DotSubscription?, grantID: UUID) throws {
        try load()
        guard let i=grants.firstIndex(where:{$0.id==grantID && $0.expires>now()}) else { throw WorkError.message("Dot连接已撤销或过期。") }
        var next=grants; next[i].subscription=subscription
        try credentials.save(next); grants=next
    }
    private static func matches(_ a: String,_ b: String) -> Bool {
        let x=Array(a.utf8),y=Array(b.utf8); guard x.count==y.count else { return false }
        return zip(x,y).reduce(UInt8(0)){$0 | ($1.0 ^ $1.1)} == 0
    }
}
