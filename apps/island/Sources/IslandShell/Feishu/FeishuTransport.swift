import Foundation
import Network

/// Per-process CONNECT tunnel for the official Feishu host when local DNS returns unreachable edges.
/// TLS remains end-to-end between official CLI and open.feishu.cn. No decryption, message parsing or logs.
final class FeishuTransport: @unchecked Sendable {
    static let shared = FeishuTransport()
    private let queue = DispatchQueue(label:"island.feishu.transport")
    private let lock = NSLock()
    private var listener: NWListener?
    private var port: UInt16?
    private var connections: [UUID:Tunnel] = [:]
    private var cached: (String,Date)?
    private let password = UUID().uuidString + UUID().uuidString
    private init() {}
    func resolvedIP() -> String? {
        lock.lock(); let old = cached; lock.unlock()
        if let old, Date().timeIntervalSince(old.1) < 600 { return old.0 }
        let p = Process(), pipe = Pipe(); p.executableURL = URL(fileURLWithPath:"/usr/bin/curl")
        p.arguments = ["--silent","--show-error","--max-time","4","https://dns.google/resolve?name=open.feishu.cn&type=A&edns_client_subnet=0.0.0.0/0"]
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        defer { try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
        guard (try? p.run()) != nil else { return nil }
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard p.terminationStatus == 0, bytes.count < 65536, let d = try? JSONSerialization.jsonObject(with:bytes) as? [String:Any], d["Status"] as? Int == 0,
              let answers = d["Answer"] as? [[String:Any]], let ip = answers.compactMap({ row -> String? in
                  guard row["type"] as? Int == 1, let s = row["data"] as? String, Self.publicIPv4(s) else { return nil }; return s
              }).first else { return nil }
        lock.lock(); cached = (ip,Date()); lock.unlock(); return ip
    }
    static func publicIPv4(_ s: String) -> Bool {
        let a = s.split(separator:".").compactMap{Int($0)}
        guard a.count == 4, a.allSatisfy({(0...255).contains($0)}), a[0] > 0, a[0] < 224 else { return false }
        return !(a[0] == 10 || a[0] == 127 || a[0] == 169 && a[1] == 254 || a[0] == 172 && (16...31).contains(a[1]) || a[0] == 192 && a[1] == 168 || a[0] == 198 && (18...19).contains(a[1]) || a[0] == 100 && (64...127).contains(a[1]))
    }
    func environment(_ original: [String:String], allowLoopback: Bool = Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview") -> [String:String] {
        guard allowLoopback else { return original }
        let ready = DispatchSemaphore(value:0)
        queue.async {
            if self.listener != nil { ready.signal(); return }
            do {
                let parameters = NWParameters.tcp; parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)
                let next = try NWListener(using:parameters); self.listener = next
                next.stateUpdateHandler = { state in
                    switch state { case .ready: self.lock.lock(); self.port = next.port?.rawValue; self.lock.unlock(); ready.signal()
                    case .failed: next.cancel(); self.listener = nil; ready.signal()
                    default: break }
                }
                next.newConnectionHandler = { [weak self] client in
                    guard let self, self.connections.count < 8 else { client.cancel(); return }
                    let id = UUID()
                    let tunnel = Tunnel(client:client,password:self.password,queue:self.queue,resolve:{self.resolvedIP()},finished:{[weak self] in self?.connections[id] = nil})
                    self.connections[id] = tunnel; tunnel.start()
                }
                next.start(queue:self.queue)
            } catch { ready.signal() }
        }
        _ = ready.wait(timeout:.now()+2)
        lock.lock(); let active = port; lock.unlock()
        guard let active else { return original }
        var env = original
        env["HTTPS_PROXY"] = "http://island:\(password)@127.0.0.1:\(active)"
        env["https_proxy"] = env["HTTPS_PROXY"]; env["NO_PROXY"] = "127.0.0.1,localhost"; env["no_proxy"] = env["NO_PROXY"]
        return env
    }
    private final class Tunnel {
        let client: NWConnection
        let password: String
        let queue: DispatchQueue
        let resolve: () -> String?
        let finished: () -> Void
        var remote: NWConnection?
        var bytes = Data()
        var closed = false
        init(client:NWConnection,password:String,queue:DispatchQueue,resolve:@escaping()->String?,finished:@escaping()->Void) {self.client=client;self.password=password;self.queue=queue;self.resolve=resolve;self.finished=finished}
        func start() { client.start(queue:queue);queue.asyncAfter(deadline:.now()+25){[weak self] in self?.close()};header() }
        func close() { guard !closed else{return};closed=true;client.cancel();remote?.cancel();finished() }
        func header() {
            client.receive(minimumIncompleteLength:1,maximumLength:8192) { [weak self] data,_,complete,error in
                guard let self,!self.closed else{return};if let data {self.bytes.append(data)}
                guard self.bytes.count <= 8192 else {self.close();return}
                if let end=self.bytes.range(of:Data("\r\n\r\n".utf8)) {
                    let head=String(decoding:self.bytes[..<end.lowerBound],as:UTF8.self).components(separatedBy:"\r\n")
                    let expected="Basic "+Data("island:\(self.password)".utf8).base64EncodedString()
                    guard head.first == "CONNECT open.feishu.cn:443 HTTP/1.1",head.filter({$0.lowercased().hasPrefix("proxy-authorization:")}).count == 1,
                          head.contains(where:{$0.lowercased().hasPrefix("proxy-authorization:") && $0.split(separator:":",maxSplits:1).last?.trimmingCharacters(in:.whitespaces) == expected}),!head.contains(where:{$0.lowercased().hasPrefix("origin:")}),let ip=self.resolve() else{self.close();return}
                    let extra=Data(self.bytes[end.upperBound...]);self.bytes=Data()
                    let remote=NWConnection(host:NWEndpoint.Host(ip),port:443,using:.tcp);self.remote=remote
                    remote.stateUpdateHandler = { [weak self] state in
                        guard let self,!self.closed else{return}
                        if case .ready = state { self.client.send(content:Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8),completion:.contentProcessed{[weak self] error in
                            guard let self,error == nil else{self?.close();return}
                            if !extra.isEmpty {remote.send(content:extra,completion:.contentProcessed{_ in})}
                            self.pump(self.client,remote);self.pump(remote,self.client)
                        }) }
                        if case .failed = state { self.close() }
                    };remote.start(queue:self.queue);return
                }
                if complete || error != nil{self.close()}else{self.header()}
            }
        }
        func pump(_ from:NWConnection,_ to:NWConnection) {
            guard !closed else{return}
            from.receive(minimumIncompleteLength:1,maximumLength:16384) { [weak self] data,_,complete,error in
                guard let self,!self.closed else{return}
                if let data,!data.isEmpty {to.send(content:data,completion:.contentProcessed{[weak self] sendError in
                    guard let self else{return};if complete || error != nil || sendError != nil{self.close()}else{self.pump(from,to)}
                })}else if complete || error != nil{self.close()}else{self.pump(from,to)}
            }
        }
    }
}
