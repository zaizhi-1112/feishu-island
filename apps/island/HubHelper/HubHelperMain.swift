import Foundation

enum WorkError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
@main
struct HubHelperMain {
    static func main() async {
        let client = HubBackend()
        while let line = readLine() {
            var reply: [String:Any]
            do {
                guard line.utf8.count <= 262144, let bytes = line.data(using:.utf8),
                      let q = try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
                      let method = q["method"] as? String else { throw WorkError.message("中台组件请求无效。") }
                let payload = q["payload"] as? [String:Any] ?? [:]
                var result: Any = [:]
                switch method {
                case "begin": result = ["url":try await client.begin(callback:payload["callback"] as? String ?? "").absoluteString]
                case "finish":
                    let values = payload["query"] as? [[String:String]] ?? []
                    try await client.finish(query:values.map{URLQueryItem(name:$0["name"] ?? "",value:$0["value"])})
                case "snapshot": result = try JSONSerialization.jsonObject(with:JSONEncoder().encode(await client.snapshot()))
                case "document": result = ["text":try await client.document(payload["url"] as? String ?? "")]
                case "disconnect": await client.disconnect()
                default: throw WorkError.message("中台组件不支持此操作。")
                }
                reply = ["ok":true,"value":result]
            } catch { reply = ["ok":false,"error":error.localizedDescription] }
            guard let data = try? JSONSerialization.data(withJSONObject:reply) else { continue }
            try? FileHandle.standardOutput.write(contentsOf:data+Data([10]))
        }
    }
}
