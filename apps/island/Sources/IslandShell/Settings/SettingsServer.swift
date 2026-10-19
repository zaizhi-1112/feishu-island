import AppKit
import Network

/// A bundled, loopback-only settings page. No cloud service, external assets or message content.
@MainActor
final class SettingsServer {
    static let shared = SettingsServer()
    private var listener: NWListener?
    private weak var store: FeishuStore?
    private let agent = AppearanceMCP()
    private let assetsRoot: URL?
    init(assetsRoot: URL? = nil) { self.assetsRoot = assetsRoot }
    var address: String? { ready ? "http://127.0.0.1:\(port)" : nil }
    private var lockObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?
    private var sessionLocked = false
    private var port: UInt16 = 18766
    private var ready = false
    private var openWhenReady = false
    private var connections: [UUID: SettingsConnection] = [:]

    func start(store: FeishuStore, listen: Bool = true, preferredPort: UInt16 = 18766) {
        self.store = store
        agent.appearance = store.appearance
        agent.onChange = { [weak self, weak store] value in
            if store?.updateAppearance(value) == true { self?.agent.savedRevision = self?.agent.revision ?? 0 }
        }
        if lockObserver == nil {
            lockObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.sessionDidResignActiveNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.sessionLocked = true; self?.agent.revoke() } }
        }
        if unlockObserver == nil {
            unlockObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.sessionDidBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.sessionLocked = false } }
        }
        guard listen else { return }
        guard listener == nil else { return }
        self.listen(port: preferredPort)
    }
    private func listen(port: UInt16) {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
            let next = try NWListener(using: parameters)
            listener = next
            next.stateUpdateHandler = { [weak self, weak next] state in
                MainActor.assumeIsolated {
                guard let self, self.listener === next else { return }
                switch state {
                case .ready:
                    self.port = next?.port?.rawValue ?? port; self.ready = true
                    if self.openWhenReady { self.openWhenReady = false; self.open() }
                case .failed:
                    next?.cancel(); self.listener = nil; self.ready = false
                    if port != 0 { self.listen(port: 0) }
                    else { self.store?.actionError = "设置页面未能启动，请重新打开柚子岛。" }
                default: break
                }
                }
            }
            next.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated {
                guard let self else { connection.cancel(); return }
                let id = UUID()
                let client = SettingsConnection(connection: connection, handle: { [weak self] method, path, headers, body in
                    await self?.respond(method: method, path: path, headers: headers, body: body) ?? .error(503, "应用未就绪")
                }, finished: { [weak self] in self?.connections[id] = nil })
                self.connections[id] = client
                client.start()
                }
            }
            next.start(queue: .main)
        } catch {
            if port != 0 { listen(port: 0) }
            else { store?.actionError = "设置页面未能启动，请重新打开柚子岛。" }
        }
    }
    func open() {
        guard ready else {
            openWhenReady = true
            if listener == nil, let store { start(store: store) }
            return
        }
        if let url = URL(string: "http://127.0.0.1:\(port)/") { NSWorkspace.shared.open(url) }
    }
    private func snapshot(_ store: FeishuStore) -> SettingsResponse {
        let ruleData = try! JSONEncoder().encode(store.rules)
        return .json([
            "revision": store.settingsRevision, "enabled": store.enabled, "synthetic": !store.allowsDirectoryLookup,
            "danmu": try! JSONSerialization.jsonObject(with: JSONEncoder().encode(store.danmu)),
            "connection": try! JSONSerialization.jsonObject(with: JSONEncoder().encode(store.connection)),
            "appearance": store.appearance,
            "rules": try! JSONSerialization.jsonObject(with: ruleData),
            "customRules": try! JSONSerialization.jsonObject(with: JSONEncoder().encode(store.customRules)),
            "account": store.account, "status": store.status,
            "isMuted": store.isMuted, "mutedUntil": store.mutedUntil?.timeIntervalSince1970 as Any? ?? NSNull(),
            "followedCount": store.followed.count,
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        ])
    }
    func respond(method: String, path: String, headers: [String: String], body: Data) async -> SettingsResponse {
        let host = "127.0.0.1:\(port)"
        guard headers["host"] == host else { return .error(403, "仅接受本机地址") }
        if let origin = headers["origin"], origin != "http://\(host)" { return .error(403, "来源不匹配") }
        if let site = headers["sec-fetch-site"], site == "cross-site" { return .error(403, "来源不匹配") }
        guard let url = URLComponents(string: path) else { return .error(400, "地址不正确") }
        if url.path == "/mcp" {
            guard headers["origin"] == nil, !sessionLocked, agent.active, headers["authorization"] == "Bearer " + (agent.token ?? "") else { return .error(403,"仅接受有效的个人外观连接") }
            guard method == "POST" else { return .error(405,"不支持的操作") }
            guard headers["content-type"]?.hasPrefix("application/json") == true,
                  let object = try? JSONSerialization.jsonObject(with:body) as? [String:Any] else { return .error(400,"格式不正确") }
            if let result = agent.rpc(object) { return .json(result) }
            return SettingsResponse(status:202,contentType:"application/json",body:Data())
        }
        if ["/api/agent","/api/appearance","/api/demo"].contains(url.path) {
            guard let store else { return .error(503,"应用未就绪") }
            guard method == "POST", headers["origin"] == "http://\(host)", headers["x-island-settings"] == "1", headers["content-type"]?.hasPrefix("application/json") == true else { return .error(403,"请从本机设置页操作") }
            if url.path == "/api/agent" {
                guard !sessionLocked else { return .error(403,"锁屏期间不创建连接") }
                agent.appearance = store.appearance
                return .json(["endpoint":"http://\(host)/mcp","token":agent.authorize()])
            }
            if url.path == "/api/appearance" {
                guard let value = try? JSONSerialization.jsonObject(with:body) as? [String:Any], store.updateAppearance(value) else { return .error(400,"仅接受有效的个人外观配置") }
                agent.appearance = store.appearance
            } else { store.playSynthetic() }
            return snapshot(store)
        }
        if url.path == "/api/directory" {
            guard method == "GET" else { return .error(405, "不支持的操作") }
            guard let store, store.allowsDirectoryLookup else { return .error(403,"合成模式不查询真实联系人或群聊") }
            let directory = FeishuDirectory(connection:store.connection)
            let items = url.queryItems ?? []
            guard Set(items.map(\.name)).count == items.count else { return .error(400, "查询参数重复") }
            let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
            let kind = query["kind"] ?? ""
            let keyword = (query["q"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let token = query["pageToken"] ?? ""
            guard ["people", "groups"].contains(kind), keyword.count <= 50, token.count <= 4096 else { return .error(400, "请输入50字以内的姓名或群名。") }
            do {
                let page = try await directory.search(kind: kind, query: keyword, pageToken: token)
                return .json(["items": try JSONSerialization.jsonObject(with: JSONEncoder().encode(page.items)),
                              "hasMore": page.hasMore, "pageToken": page.pageToken,
                              "source": kind == "people" && keyword.isEmpty ? "近期聊过的联系人" : kind == "people" ? "飞书可见联系人" : "已加入的飞书群聊"])
            } catch { return .error(502, (error as? AccountFailure)?.detail ?? "飞书查询失败，请重试。") }
        }
        if url.path == "/api/settings" {
            guard let store else { return .error(503, "应用未就绪") }
            if method == "GET" { return snapshot(store) }
            guard method == "POST" else { return .error(405, "不支持的操作") }
            guard headers["origin"] == "http://\(host)", headers["x-island-settings"] == "1",
                  headers["content-type"]?.hasPrefix("application/json") == true else { return .error(403, "请从设置页保存") }
            guard let input = try? JSONDecoder().decode(SettingsUpdate.self, from: body) else { return .error(400, "设置格式不正确") }
            guard input.revision == store.settingsRevision else { return .error(409, "设置已在其他位置改变，请重新载入后再保存。") }
            if let error = input.customRules?.validationError { return .error(400, error) }
            if input.enabled, !store.enabled, let conflict = store.receiveConflict { return .error(409,conflict) }
            let raw = (try? JSONSerialization.jsonObject(with:body)) as? [String:Any] ?? [:]
            var appearance: [String:Any]?
            if let rawStyle = raw["appearance"] {
                guard let style = rawStyle as? [String:Any], let valid = AppearanceMCP.validate(style) else { return .error(400,"外观配置无效，只允许外观白名单") }
                appearance = valid
            }
            let connection = input.connection ?? store.connection
            guard connection.valid else { return .error(400,"请填写绝对路径和有效的账号配置名") }
            let switching = connection != store.connection
            if switching && input.enabled { return .error(400,"切换账号配置前，请关闭接收并保存；授权后再开启") }
            if switching { _ = store.updateConnection(connection) }
            store.updateSettings(enabled: input.enabled, rules: input.rules, custom: switching ? .init() : input.customRules)
            if let value = input.danmu { store.updateDanmu(value) }
            if let appearance { _ = store.updateAppearance(appearance); agent.appearance = store.appearance }
            return snapshot(store)
        }
        guard method == "GET" else { return .error(405, "不支持的操作") }
        let files = ["/": ("index.html", "text/html; charset=utf-8"), "/index.html": ("index.html", "text/html; charset=utf-8"),
                     "/app.js": ("app.js", "application/javascript; charset=utf-8"), "/style.css": ("style.css", "text/css; charset=utf-8")]
        guard let file = files[url.path], let root = assetsRoot ?? Bundle.main.resourceURL?.appendingPathComponent("SettingsWeb"),
              let data = try? Data(contentsOf: root.appendingPathComponent(file.0)) else { return .error(404, "页面不存在") }
        return SettingsResponse(status: 200, contentType: file.1, body: data)
    }
}

private struct SettingsUpdate: Decodable {
    let revision: Int
    let enabled: Bool
    let rules: FeishuReminderRules
    let customRules: FeishuCustomRules?
    let danmu: DanmuOptions?
    let connection: FeishuConnection?
}

struct SettingsResponse {
    let status: Int
    let contentType: String
    let body: Data
    static func json(_ object: [String: Any], status: Int = 200) -> Self {
        Self(status: status, contentType: "application/json; charset=utf-8", body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
    }
    static func error(_ status: Int, _ message: String) -> Self { .json(["error": message], status: status) }
    var data: Data {
        let reason = status == 200 ? "OK" : "Error"
        let headers = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'\r\n\r\n"
        return Data(headers.utf8) + body
    }
}

@MainActor
private final class SettingsConnection {
    private let connection: NWConnection
    private let handle: (String, String, [String: String], Data) async -> SettingsResponse
    private let finished: () -> Void
    private var buffer = Data()
    private var done = false
    init(connection: NWConnection, handle: @escaping (String, String, [String: String], Data) async -> SettingsResponse, finished: @escaping () -> Void) {
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
