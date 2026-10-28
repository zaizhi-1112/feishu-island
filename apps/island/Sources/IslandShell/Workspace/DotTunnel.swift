import AppKit

struct DotTunnelConfiguration: Codable {
    var tunnel: String
    var project: String
    var enabled: Bool
    static func read(_ url: URL) throws -> Self {
        let attributes=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard attributes.isRegularFile==true, attributes.isSymbolicLink != true, (attributes.fileSize ?? 0)<8192 else { throw WorkError.message("Invalid tunnel configuration") }
        let value=try JSONDecoder().decode(Self.self,from:Data(contentsOf:url))
        guard value.tunnel.range(of:"^tunnel_[a-z0-9]{32}$",options:.regularExpression) != nil, !value.project.isEmpty, value.project.count<=60 else { throw WorkError.message("Invalid tunnel identity") }
        return value
    }
}

struct DotTunnelHealth {
    private(set) var failures=0
    mutating func observe(ready: Bool) -> Bool {
        failures=ready ? 0 : failures+1
        return failures>=3
    }
}

/// Follows the app's lifetime, uses a separate stable helper and never opens ChatGPT UI.
/// Configuration contains only tunnel ID, project and enabled; runtime key stays in Keychain.
@MainActor final class DotTunnel: ObservableObject {
    static let shared=DotTunnel()
    @Published private(set) var status="私人插件尚未配置"
    private(set) var isReady=false
    private var process: Process?
    private var identity=""
    private var nextStart=Date.distantPast
    private var checking=false
    private var health=DotTunnelHealth()
    var configurationURL: URL {
        if Bundle.main.bundleIdentifier=="local.zaizhi.feishu-island.dot-sandbox" { return Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("dot-tunnel.json") }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FeishuIsland/DotTunnel/config.json")
    }
    func stop() {
        if let process, process.isRunning { process.terminate() }
        process=nil; identity=""; isReady=false; health=DotTunnelHealth(); status="私人连接已暂停"
    }
    func maintain(pairing: DotPairing, port: UInt16, unlocked: Bool) {
        guard ["local.zaizhi.feishu-island.preview","local.zaizhi.feishu-island.dot-sandbox"].contains(Bundle.main.bundleIdentifier ?? "") else { return }
        guard unlocked else { if process != nil { stop() }; return }
        guard let config=try? DotTunnelConfiguration.read(configurationURL), config.enabled else {
            if process != nil { stop() }
            status="私人连接未启用"
            return
        }
        do { try pairing.load() } catch { status="Dot安全凭据暂不可用"; return }
        guard let grant=pairing.grant(project:config.project) else { if process != nil { stop() }; status="请先配对「\(config.project)」"; return }
        let key=config.tunnel+":"+grant.id.uuidString+":"+String(port)
        if let process, process.isRunning, key==identity {
            if !checking {
                checking=true
                Task { [weak self, weak process] in
                    defer { self?.checking=false }
                    var request=URLRequest(url:URL(string:"http://127.0.0.1:18769/readyz")!); request.timeoutInterval=2
                    let reply=try? await URLSession.shared.data(for:request)
                    guard let self, self.process===process, process?.isRunning==true else { return }
                    let ready=(reply?.1 as? HTTPURLResponse)?.statusCode==200
                    self.isReady=ready
                    if self.health.observe(ready:ready) {
                        self.stop()
                        self.nextStart=Date().addingTimeInterval(10)
                        self.status="私人隧道连接中断，正在自动重连"
                    } else {
                        self.status=ready ? "私人隧道已就绪（Dot订阅状态见下方）" : "私人隧道未就绪，正在连接"
                    }
                }
            }
            return
        }
        if process != nil { stop() }
        guard Date()>=nextStart else { return }
        nextStart=Date().addingTimeInterval(60)
        guard let base=Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent(),
              ["local.zaizhi.feishu-island.preview","local.zaizhi.feishu-island.dot-sandbox"].contains(Bundle.main.bundleIdentifier ?? "") else { return }
        let executable=base.appendingPathComponent("Helpers/feishu-tunnel-auth")
        guard FileManager.default.isExecutableFile(atPath:executable.path) else { status="私人连接组件未安装"; return }
        do {
            let p=Process(), input=Pipe()
            p.executableURL=executable; p.standardInput=input; p.standardOutput=FileHandle.nullDevice; p.standardError=FileHandle.nullDevice
            p.terminationHandler={ [weak self, weak p] _ in Task { @MainActor in if let self, self.process===p { self.process=nil; self.isReady=false; self.status="私人连接未就绪，稍后重试" } } }
            try p.run(); process=p; identity=key
            defer { try? input.fileHandleForWriting.close(); try? input.fileHandleForReading.close() }
            try input.fileHandleForWriting.write(contentsOf:JSONSerialization.data(withJSONObject:["action":"run","tunnel":config.tunnel,"port":Int(port),"token":grant.secret]))
            status="私人隧道连接中（尚未代表Dot已订阅）"
        } catch { status="私人连接启动失败，未更改飞书接收"; stop() }
    }
}
