import Foundation
import Network

struct SettingsResponse {
    let status: Int
    let contentType: String
    let body: Data
    var chromeCORS = false
    func withChromeCORS() -> Self { var copy=self; copy.chromeCORS=true; return copy }
    static func json(_ object: [String: Any], status: Int = 200) -> Self {
        guard JSONSerialization.isValidJSONObject(object), let bytes = try? JSONSerialization.data(withJSONObject:object) else {
            return Self(status:500,contentType:"application/json; charset=utf-8",body:Data("{\"error\":\"应用响应格式不正确\"}".utf8))
        }
        return Self(status:status,contentType:"application/json; charset=utf-8",body:bytes)
    }
    static func error(_ status: Int, _ message: String) -> Self { .json(["error": message], status: status) }
    var data: Data {
        let reason = status == 200 ? "OK" : "Error"
        let cors = chromeCORS ? "Access-Control-Allow-Origin: \(WorkChromeImport.origin)\r\nAccess-Control-Allow-Methods: POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nVary: Origin\r\n" : ""
        let headers = "HTTP/1.1 \(status) \(reason)\r\n\(cors)Content-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'\r\n\r\n"
        return Data(headers.utf8) + body
    }
}

@MainActor
final class SettingsConnection {
    private let connection: NWConnection
    private let handle: @MainActor (String, String, [String: String], Data) async -> SettingsResponse
    private let finished: () -> Void
    private var buffer = Data()
    private var done = false
    init(connection: NWConnection, handle: @escaping @MainActor (String, String, [String: String], Data) async -> SettingsResponse, finished: @escaping () -> Void) {
        self.connection = connection; self.handle = handle; self.finished = finished
    }
    func start() {
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.finish() }
        read()
    }
    private func finish() {
        guard !done else { return }; done = true
        connection.cancel(); finished()
    }
    private func read() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            MainActor.assumeIsolated {
            guard let self, !self.done else { return }
            if let data { self.buffer.append(data) }
            guard self.buffer.count <= 262144 else { self.send(.error(413, "请求过大")); return }
            if let end = self.buffer.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: self.buffer[..<end.lowerBound], as: UTF8.self)
                let lines = header.components(separatedBy: "\r\n")
                let request = lines[0].split(separator: " ")
                guard request.count == 3 else { self.send(.error(400, "请求不正确")); return }
                var fields: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { self.send(.error(400, "请求头不正确")); return }
                    let key = line[..<colon].lowercased()
                    guard fields[key] == nil else { self.send(.error(400, "重复请求头")); return }
                    fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
                guard fields["transfer-encoding"] == nil, let length = Int(fields["content-length"] ?? "0"), (0...131072).contains(length) else { self.send(.error(400, "请求长度不正确")); return }
                let body = self.buffer[end.upperBound...]
                if body.count >= length {
                    let method = String(request[0]), path = String(request[1]), payload = Data(body.prefix(length))
                    Task { @MainActor [weak self] in
                        guard let self, !self.done else { return }
                        let response = await self.handle(method, path, fields, payload)
                        guard !self.done else { return }
                        self.send(response)
                    }
                    return
                }
            }
            if complete || error != nil { self.finish() } else { self.read() }
            }
        }
    }
    private func send(_ response: SettingsResponse) {
        connection.send(content: response.data, completion: .contentProcessed { [weak self] _ in MainActor.assumeIsolated { self?.finish() } })
    }
}
