import Foundation
import CryptoKit
import Darwin

struct DotWebhookReply: Sendable { var status: Int; var body: Data }
protocol DotWebhookTransport: Sendable {
    func post(url: String, headers: [String:String], body: Data) async throws -> DotWebhookReply
}

/// DNS is resolved for every attempt. curl connects only to the validated IPv4 address,
/// verifies the original TLS hostname, ignores user curl/proxy configuration and never redirects.
/// Secrets and signed payloads travel on stdin, never process arguments or a temporary file.
struct DotPublicWebhook: DotWebhookTransport {
    static func destination(_ value: String) throws -> (String,Int) {
        guard value.utf8.count<=2048, let u=URLComponents(string:value), u.scheme=="https",
              let host=u.host, !host.isEmpty, host.utf8.allSatisfy({(48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0==45 || $0==46}),
              u.user==nil, u.password==nil, u.fragment==nil, u.port==nil || u.port==443,
              !value.contains(where:{$0.isNewline || $0=="\0"}) else { throw WorkError.message("Dot回调必须是公网HTTPS地址（443端口）。") }
        return (host,443)
    }
    static func publicIPv4(_ address: String) -> Bool {
        let p=address.split(separator:".").compactMap{UInt8($0)}
        guard p.count==4 else { return false }
        let a=Int(p[0]), b=Int(p[1]), c=Int(p[2])
        if [0,10,127].contains(a) || a>=224 { return false }
        if a==100 && (64...127).contains(b) { return false }
        if a==169 && b==254 || a==172 && (16...31).contains(b) || a==192 && b==168 { return false }
        if a==192 && (b==0 || b==2 || b==88 && c==99) { return false }
        if a==198 && (b==18 || b==19 || b==51 && c==100) { return false }
        if a==203 && b==0 && c==113 { return false }
        return true
    }
    static func resolve(_ host: String) throws -> String {
        var hints=addrinfo(); hints.ai_family=AF_INET; hints.ai_socktype=SOCK_STREAM
        var first: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host,nil,&hints,&first)==0, let first else { throw WorkError.message("Dot回调DNS解析失败。") }
        defer { freeaddrinfo(first) }
        var current: UnsafeMutablePointer<addrinfo>?=first, addresses: [String]=[]
        while let node=current {
            var bytes=[CChar](repeating:0,count:Int(NI_MAXHOST))
            if getnameinfo(node.pointee.ai_addr,node.pointee.ai_addrlen,&bytes,socklen_t(bytes.count),nil,0,NI_NUMERICHOST)==0 { addresses.append(String(cString:bytes)) }
            current=node.pointee.ai_next
        }
        guard !addresses.isEmpty, addresses.allSatisfy(publicIPv4) else { throw WorkError.message("Dot回调地址不是允许的公网地址。") }
        return addresses[0]
    }
    func post(url: String, headers: [String:String], body: Data) async throws -> DotWebhookReply {
        let (host,port)=try Self.destination(url)
        guard body.count<=262144 else { throw WorkError.message("Dot事件超过大小限制。") }
        return try await Task.detached(priority:.utility) {
            try Task.checkCancellation()
            let ip=try Self.resolve(host)
            func quote(_ text: String) -> String { "\""+text.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"").replacingOccurrences(of:"\n",with:"\\n").replacingOccurrences(of:"\r",with:"\\r")+"\"" }
            var config="url = \(quote(url))\nrequest = \"POST\"\n"
            for (key,value) in headers.sorted(by:{$0.key<$1.key}) {
                guard !key.contains(where:{$0.isNewline}), !value.contains(where:{$0.isNewline}) else { throw WorkError.message("Invalid webhook header") }
                config+="header = \(quote(key+": "+value))\n"
            }
            config+="data-binary = \(quote(String(decoding:body,as:UTF8.self)))\n"
            let p=Process(), input=Pipe(), output=Pipe()
            p.executableURL=URL(fileURLWithPath:"/usr/bin/curl")
            p.arguments=["-q","--config","-","--silent","--noproxy","*","--ipv4","--proto","=https","--max-redirs","0","--connect-timeout","5","--max-time","10","--max-filesize","16384","--resolve","\(host):\(port):\(ip)","--write-out","\n%{http_code}"]
            p.environment=["PATH":"/usr/bin:/bin","HOME":"/var/empty"]
            p.standardInput=input; p.standardOutput=output; p.standardError=FileHandle.nullDevice
            defer { try? input.fileHandleForWriting.close(); try? input.fileHandleForReading.close(); try? output.fileHandleForReading.close(); try? output.fileHandleForWriting.close() }
            try p.run()
            try input.fileHandleForWriting.write(contentsOf:Data(config.utf8)); try input.fileHandleForWriting.close()
            // Bound unknown-length responses too; stop reading and terminate if the receiver floods.
            var bytes=Data()
            while let chunk=try output.fileHandleForReading.read(upToCount:4096), !chunk.isEmpty {
                bytes.append(chunk)
                if bytes.count>20000 { p.terminate(); throw WorkError.message("Dot回调响应过大。") }
            }
            p.waitUntilExit()
            guard p.terminationStatus==0, let split=bytes.lastIndex(of:10), let status=Int(String(decoding:bytes[bytes.index(after:split)...],as:UTF8.self)) else { throw WorkError.message("Dot回调连接失败或超时。") }
            return DotWebhookReply(status:status,body:Data(bytes[..<split]))
        }.value
    }
}

enum DotWebhookSigner {
    static func key(_ secret: String) throws -> Data {
        guard secret.hasPrefix("whsec_"), let data=Data(base64Encoded:String(secret.dropFirst(6))), (24...64).contains(data.count) else { throw WorkError.message("Invalid webhook signing secret") }
        return data
    }
    static func headers(id: String, subscription: DotSubscription, body: Data, now: Date) throws -> [String:String] {
        let timestamp=String(Int(now.timeIntervalSince1970)), input=Data((id+"."+timestamp+".").utf8)+body
        func sign(_ secret: String) throws -> String { "v1,"+Data(HMAC<SHA256>.authenticationCode(for:input,using:SymmetricKey(data:try key(secret)))).base64EncodedString() }
        var signature=try sign(subscription.secret)
        if let old=subscription.previousSecret, let until=subscription.rotationUntil, until>now { signature+=" "+(try sign(old)) }
        return ["Content-Type":"application/json","webhook-id":id,"webhook-timestamp":timestamp,"webhook-signature":signature,"X-MCP-Subscription-Id":subscription.id]
    }
}
