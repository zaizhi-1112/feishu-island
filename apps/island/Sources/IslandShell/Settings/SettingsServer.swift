import AppKit
import Network

/// A bundled, loopback-only settings page. No cloud service, external assets or message content.
@MainActor
final class SettingsServer {
    static let shared = SettingsServer()
    private var listener: NWListener?
    private weak var store: FeishuStore?
    private let directory = FeishuDirectory()
    private var port: UInt16 = 18766
    private var ready = false
    private var openWhenReady = false
    private var openSection = ""
    private var connections: [UUID: SettingsConnection] = [:]

    func start(store: FeishuStore) {
        self.store = store
        guard listener == nil else { return }
        listen(port: IslandRuntime.isSkinPreview ? 18776 : 18766)
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
    func open(section: String = "") {
        if !section.isEmpty { openSection = section }
        guard ready else {
            openWhenReady = true
            if listener == nil, let store { start(store: store) }
            return
        }
        if let url = URL(string: "http://127.0.0.1:\(port)/#\(openSection)") { NSWorkspace.shared.open(url) }; openSection = ""
    }
    private func snapshot(_ store: FeishuStore) -> SettingsResponse {
        let ruleData = try! JSONEncoder().encode(store.rules)
        return .json([
            "revision": store.settingsRevision, "enabled": store.enabled,
            "rules": try! JSONSerialization.jsonObject(with: ruleData),
            "customRules": try! JSONSerialization.jsonObject(with: JSONEncoder().encode(store.customRules)),
            "account": store.account, "status": store.status,
            "isMuted": store.isMuted, "mutedUntil": store.mutedUntil?.timeIntervalSince1970 as Any? ?? NSNull(),
            "followedCount": store.followed.count,
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        ])
    }
    private func respond(method: String, path: String, headers: [String: String], body: Data) async -> SettingsResponse {
        let host = "127.0.0.1:\(port)"
        guard headers["host"] == host else { return .error(403, "仅接受本机地址") }
        if let origin = headers["origin"], origin != "http://\(host)" { return .error(403, "来源不匹配") }
        if let site = headers["sec-fetch-site"], site == "cross-site" { return .error(403, "来源不匹配") }
        guard let url = URLComponents(string: path) else { return .error(400, "地址不正确") }
        if url.path == "/api/todos/settings" {
            let todos = TodoStore.shared
            if method == "GET" { return .json(todos.webSnapshot()) }
            guard method == "POST", headers["origin"] == "http://\(host)", headers["x-island-settings"] == "1",
                  headers["content-type"]?.hasPrefix("application/json") == true else { return .error(403, "请从设置页保存") }
            do {
                let input = try JSONDecoder().decode(TodoPreferences.self, from: body)
                guard input.revision == todos.preferences.revision else { return .error(409, "待办设置已改变，请重新载入后保存。") }
                try todos.updatePreferences(input)
                return .json(todos.webSnapshot())
            } catch { return .error(400, error.localizedDescription) }
        }
        if url.path == "/api/agents" || url.path == "/api/agents/refresh" {
            let agents = AgentStore.shared
            if method == "GET", url.path == "/api/agents" { return .json(agents.webSnapshot()) }
            guard method == "POST", headers["origin"] == "http://\(host)", headers["x-island-settings"] == "1",
                  headers["content-type"]?.hasPrefix("application/json") == true else { return .error(403, "请从设置页操作") }
            if url.path == "/api/agents/refresh" { agents.refreshQuotas(); return .json(agents.webSnapshot()) }
            do {
                let input = try JSONDecoder().decode(AgentPreferences.self, from: body)
                if input.revision != agents.preferences.revision { return .error(409, "设置已改变，请重新载入。") }
                try agents.update(input); return .json(agents.webSnapshot())
            } catch { return .error(400, (error as? AgentReadError)?.localizedDescription ?? "Agent设置格式不正确") }
        }
        if url.path == "/api/directory" {
            guard method == "GET" else { return .error(405, "不支持的操作") }
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
            store.updateSettings(enabled: input.enabled, rules: input.rules, custom: input.customRules)
            return snapshot(store)
        }
        guard method == "GET" else { return .error(405, "不支持的操作") }
        let files = ["/todos.js": ("todos.js", "application/javascript; charset=utf-8"), "/brand-flow.json": ("brand-flow.json", "application/json"), "/skins.json": ("skins.json", "application/json"), "/brand-geometry.json": ("brand-geometry.json", "application/json"), "/skin-effects.js": ("skin-effects.js", "application/javascript; charset=utf-8"), "/skin-v2.css": ("skin-v2.css", "text/css; charset=utf-8"), "/pet-codex.png": ("pet-codex.png", "image/png"), "/pet-claude.png": ("pet-claude.png", "image/png"), "/pet-workbuddy.png": ("pet-workbuddy.png", "image/png"), "/avatar-codex.png": ("avatar-codex.png", "image/png"), "/avatar-claude.png": ("avatar-claude.png", "image/png"), "/avatar-workbuddy.png": ("avatar-workbuddy.png", "image/png"), "/avatar-virxact.png": ("avatar-virxact.png", "image/png"), "/virxact-logo.png": ("virxact-logo.png", "image/png"), "/virxact-logo.svg": ("virxact-logo.svg", "image/svg+xml"), "/codex-atlas.webp": ("codex-atlas.webp", "image/webp"), "/pet-codex.svg": ("pet-codex.svg", "image/svg+xml"), "/pet-claude.svg": ("pet-claude.svg", "image/svg+xml"), "/pet-workbuddy.svg": ("pet-workbuddy.svg", "image/svg+xml"), "/": ("index.html", "text/html; charset=utf-8"), "/index.html": ("index.html", "text/html; charset=utf-8"),
                     "/app.js": ("app.js", "application/javascript; charset=utf-8"), "/style.css": ("style.css", "text/css; charset=utf-8"),
                     "/agent-codex.png": ("agent-codex.png", "image/png"), "/agent-claude.png": ("agent-claude.png", "image/png"), "/agent-workbuddy.png": ("agent-workbuddy.png", "image/png")]
        guard let file = files[url.path], let root = Bundle.main.resourceURL,
              let data = try? Data(contentsOf: root.appendingPathComponent("SettingsWeb/\(file.0)")) else { return .error(404, "页面不存在") }
        return SettingsResponse(status: 200, contentType: file.1, body: data)
    }
}

private struct SettingsUpdate: Decodable {
    let revision: Int
    let enabled: Bool
    let rules: FeishuReminderRules
    let customRules: FeishuCustomRules?
}

private struct SettingsResponse {
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
