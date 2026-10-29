import AppKit
import Network

/// A bundled, loopback-only settings page. No cloud service, external assets or message content.
@MainActor
final class SettingsServer {
    static let shared = SettingsServer()
    private var listener: NWListener?
    private weak var store: FeishuStore?
    private let agent = AppearanceMCP()
    let workspaceAgent = WorkspaceMCP()
    let dotPairing: DotPairing
    private let workspaceOverride: WorkspaceStore?
    private let assetsRoot: URL?
    private let dotTransport: any DotWebhookTransport
    init(assetsRoot: URL? = nil, dotPairing: DotPairing? = nil, workspace: WorkspaceStore? = nil, dotTransport: any DotWebhookTransport = DotPublicWebhook()) { self.assetsRoot = assetsRoot; self.dotPairing = dotPairing ?? DotPairing(); self.workspaceOverride=workspace; self.dotTransport=dotTransport }
    var connectedAccountName: String? { store?.account }
    var address: String? { ready ? "http://127.0.0.1:\(port)" : nil }
    private var lockObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?
    private var sessionLocked = false
    private var dotEventTimer: Timer?
    private lazy var dotEvents = DotEvents(pairing:dotPairing,store:workspaceOverride ?? WorkspaceStore.shared,transport:dotTransport,allowed:{ [weak self] in self?.sessionLocked == false })
    private var port: UInt16 = 18766
    private var ready = false
    private var openWhenReady = false
    private var companyActionBusy = false
    private var openSection = ""
    private var connections: [UUID: SettingsConnection] = [:]

    private var nativeOnly = false
    func start(store: FeishuStore, listen: Bool = true, preferredPort: UInt16 = 18766, nativeOnly: Bool = false) {
        self.store = store
        self.nativeOnly = nativeOnly
        agent.appearance = store.appearance
        agent.onChange = { [weak self, weak store] value in
            if store?.updateAppearance(value) == true { self?.agent.savedRevision = self?.agent.revision ?? 0 }
        }
        if lockObserver == nil {
            lockObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.sessionDidResignActiveNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.sessionLocked = true; self?.agent.revoke(); self?.workspaceAgent.revoke(); DotTunnel.shared.stop() } }
        }
        if unlockObserver == nil {
            unlockObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.sessionDidBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.sessionLocked = false } }
        }
        guard listen else { return }
        if !nativeOnly {
        AgentStore.shared.statusNotice = { [weak store] id,source,text in store?.receiveAgentNotice(id:id,source:source,text:text) }
        (workspaceOverride ?? WorkspaceStore.shared).agentNotice = { [weak store] id,source,text in store?.receiveAgentNotice(id:id,source:source,text:text) }
        if dotEventTimer == nil {
            let workspace=workspaceOverride ?? WorkspaceStore.shared
            workspace.dotQueued={ [weak self] in Task { @MainActor in await self?.dotEvents.pump() } }
            dotEvents.deliveryReady={ [weak self] in self?.workspaceOverride != nil || DotTunnel.shared.isReady }
            dotEventTimer=Timer(timeInterval:5,repeats:true) { [weak self] _ in Task { @MainActor in
                guard let self else { return }
                if self.ready { DotTunnel.shared.maintain(pairing:self.dotPairing,port:self.port,unlocked:!self.sessionLocked) }
                await self.dotEvents.pump()
            } }
            if let dotEventTimer { RunLoop.main.add(dotEventTimer,forMode:.common) }
        }
        }
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
    func open(section: String = "") {
        UnifiedSettingsWindow.shared.open(section: .resolve(section))
    }
    func copyWorkspaceConnection(store: WorkspaceStore) {
        guard !sessionLocked, let address else { store.error = "工作台未就绪，请解锁后重试。"; return }
        let token = workspaceAgent.authorize(store:store)
        let config: [String:Any] = ["mcpServers":["feishu-island-workspace":["type":"http","url":address+"/mcp/workspace","headers":["Authorization":"Bearer "+token]]]]
        guard let bytes = try? JSONSerialization.data(withJSONObject:config,options:[.prettyPrinted,.sortedKeys]) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(String(decoding:bytes,as:UTF8.self),forType:.string)
    }
    func copyDotConnection(store: WorkspaceStore) {
        guard !sessionLocked, let address else { store.error="请解锁并等待本机服务就绪。"; return }
        do {
            let token=try dotPairing.pair(project:store.draftProject)
            let config: [String:Any] = ["mcpServers":["feishu-island-dot":["type":"http","url":address+"/mcp/dot","headers":["Authorization":"Bearer "+token]]]]
            let data=try JSONSerialization.data(withJSONObject:config,options:[.prettyPrinted,.sortedKeys])
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(String(decoding:data,as:UTF8.self),forType:.string)
            store.error=""
        } catch { store.error=error.localizedDescription }
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
            "delivery": store.deliveryDiagnostics,
            "presentation": "island",
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        ])
    }
    func respond(method: String, path: String, headers: [String: String], body: Data) async -> SettingsResponse {
        let host = "127.0.0.1:\(port)"
        guard headers["host"] == host else { return .error(403, "仅接受本机地址") }
        guard let url = URLComponents(string: path) else { return .error(400, "地址不正确") }
        if nativeOnly && url.path != "/oauth/virxact/callback" { return .error(404, "请使用原生设置窗口。") }
        if url.path == "/api/chrome-import" {
            guard headers["origin"] == WorkChromeImport.origin, !sessionLocked else { return .error(403,"请解锁并使用一切在岛Chrome收录扩展。") }
            if method == "OPTIONS" { return SettingsResponse(status:200,contentType:"text/plain",body:Data(),chromeCORS:true) }
            let workspace=workspaceOverride ?? WorkspaceStore.shared
            guard method == "POST", headers["content-type"]?.hasPrefix("application/json") == true else { return .error(405,"仅接受网页材料提交").withChromeCORS() }
            do {
                try workspace.importChrome(body)
                return SettingsResponse.json(["saved":true,"destination":"draft"]).withChromeCORS()
            } catch { return SettingsResponse.error(409,error.localizedDescription).withChromeCORS() }
        }
        if url.path == "/oauth/virxact/callback" {
            guard method == "GET", !sessionLocked else { return .error(403,"请解锁Mac后重新连接。") }
            do {
                try await WorkspaceStore.shared.finishHub(query:url.queryItems ?? [])
                return SettingsResponse(status:200,contentType:"text/html; charset=utf-8",body:Data("<!doctype html><meta charset=utf-8><title>已连接</title><p>虚实中台已连接到本机灵动岛。可以关闭此页，回到顶部工作台。</p>".utf8))
            } catch { return .error(400,error.localizedDescription) }
        }
        if let origin = headers["origin"], origin != "http://\(host)" { return .error(403, "来源不匹配") }
        if let site = headers["sec-fetch-site"], site == "cross-site" { return .error(403, "来源不匹配") }
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
        if url.path == "/api/company" {
            guard !sessionLocked, let store else { return .error(403,"请解锁并打开一切在岛。") }
            if method == "GET" { return .json(["state": [:], "message": "飞书功能已改为本机直连，请在原生连接窗口管理本人账号。"] as [String:Any]) }
            guard method == "POST", headers["origin"] == "http://\(host)", headers["x-island-settings"] == "1", headers["content-type"]?.hasPrefix("application/json") == true else { return .error(403,"请从本机设置页操作。") }
            guard store.allowsDirectoryLookup else { return .error(403,"合成模式不连接真实账号。") }
            CompanyConnection.shared.open(purpose: .receive)
            return .json(["message": "已打开飞书授权窗口，确认后自动连接。"])
        }

        if url.path == "/api/workspace" {
            guard !sessionLocked else { return .error(403,"锁屏期间不读取个人工作区。") }
            let workspace = WorkspaceStore.shared
            if method == "POST" {
                guard headers["origin"] == "http://\(host)", headers["x-island-settings"] == "1", headers["content-type"]?.hasPrefix("application/json") == true,
                      let action = try? JSONSerialization.jsonObject(with:body) as? [String:Any] else { return .error(403,"请从本机设置页操作。") }
                do {
                    switch action["action"] as? String {
                    case "connectURL": return .json(["url":try await workspace.hubClient.begin(callback:"http://\(host)/oauth/virxact/callback").absoluteString])
                    case "connect": workspace.connectHub(callback:"http://\(host)/oauth/virxact/callback")
                    case "disconnect": workspace.disconnectHub()
                    case "refresh": Task { await workspace.refreshHub() }
                    case "minutes": guard let minutes = action["minutes"] as? Int, (0...10080).contains(minutes) else { return .error(400,"提醒分钟数不正确。") }; workspace.setMinutes(minutes)
                    case "recipe": try workspace.addRecipe(title:action["title"] as? String ?? "",instruction:action["instruction"] as? String ?? "")
                    case "add": _ = try workspace.add(text:action["text"] as? String ?? "",minutes:action["minutes"] as? Int)
                    case "open": workspace.openBoard()
                    default: return .error(400,"不支持的工作区操作。")
                    }
                } catch { return .error(400,error.localizedDescription) }
            } else if method != "GET" { return .error(405,"不支持的操作。") }
            return .json(["aiTool":WorkAI.displayName,"aiAvailable":WorkAI.executable != nil,"reminderMinutes":workspace.disk.reminderMinutes,"taskCount":workspace.disk.items.count,"hubConnected":workspace.hub.connected,"hubError":workspace.hub.error,"error":workspace.error])
        }
        if url.path == "/api/reminder-diagnostics" {
            guard method=="GET", !sessionLocked else { return .error(403,"Unavailable") }
            return .json(ScreenReminderPresenter.shared.diagnostics)
        }
        if url.path == "/api/dot-diagnostics" {
            guard method=="GET", !sessionLocked else { return .error(403,"Unavailable") }
            return .json(dotEvents.healthSnapshot)
        }
        if url.path == "/mcp/dot" {
            guard headers["origin"] == nil, !sessionLocked, method=="POST",
                  headers["content-type"]?.hasPrefix("application/json")==true,
                  let auth=headers["authorization"], auth.hasPrefix("Bearer ") else { return .error(403,"仅接受本机Dot项目连接") }
            guard let object=try? JSONSerialization.jsonObject(with:body) as? [String:Any] else { return .error(400,"格式不正确") }
            do {
                guard let grant=try dotPairing.authenticate(String(auth.dropFirst(7))) else { return .error(403,"连接已过期或断开，请由本人重新配对") }
                if (object["method"] as? String)?.hasPrefix("events/")==true {
                    if let result=await dotEvents.rpc(object,grant:grant) { return .json(result) }
                    return SettingsResponse(status:202,contentType:"application/json",body:Data())
                }
                if let result=DotMCP.rpc(object,grant:grant,store:workspaceOverride ?? WorkspaceStore.shared,now:dotPairing.now(),modern:headers["mcp-protocol-version"]=="2026-07-28") { return .json(result) }
                return SettingsResponse(status:202,contentType:"application/json",body:Data())
            } catch { return .error(503,"Dot安全凭据暂不可用；未要求密码，未执行任务") }
        }
        if url.path == "/mcp/workspace" {
            guard headers["origin"] == nil, !sessionLocked, workspaceAgent.active,
                  headers["authorization"] == "Bearer "+(workspaceAgent.token ?? "") else { return .error(403,"仅接受有效的个人项目连接") }
            guard method == "POST" else { return .error(405,"不支持的操作") }
            guard headers["content-type"]?.hasPrefix("application/json") == true,
                  let object = try? JSONSerialization.jsonObject(with:body) as? [String:Any] else { return .error(400,"格式不正确") }
            if let result = workspaceAgent.rpc(object,store:WorkspaceStore.shared) { return .json(result) }
            return SettingsResponse(status:202,contentType:"application/json",body:Data())
        }
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
        let files = ["/todos.js": ("todos.js", "application/javascript; charset=utf-8"), "/brand-flow.json": ("brand-flow.json", "application/json"), "/skins.json": ("skins.json", "application/json"), "/brand-geometry.json": ("brand-geometry.json", "application/json"), "/skin-effects.js": ("skin-effects.js", "application/javascript; charset=utf-8"), "/skin-v2.css": ("skin-v2.css", "text/css; charset=utf-8"), "/pet-codex.png": ("pet-codex.png", "image/png"), "/pet-claude.png": ("pet-claude.png", "image/png"), "/pet-workbuddy.png": ("pet-workbuddy.png", "image/png"), "/avatar-codex.png": ("avatar-codex.png", "image/png"), "/avatar-claude.png": ("avatar-claude.png", "image/png"), "/avatar-workbuddy.png": ("avatar-workbuddy.png", "image/png"), "/avatar-virxact.png": ("avatar-virxact.png", "image/png"), "/virxact-logo.png": ("virxact-logo.png", "image/png"), "/virxact-logo.svg": ("virxact-logo.svg", "image/svg+xml"), "/codex-atlas.webp": ("codex-atlas.webp", "image/webp"), "/pet-codex.svg": ("pet-codex.svg", "image/svg+xml"), "/pet-claude.svg": ("pet-claude.svg", "image/svg+xml"), "/pet-workbuddy.svg": ("pet-workbuddy.svg", "image/svg+xml"), "/": ("index.html", "text/html; charset=utf-8"), "/index.html": ("index.html", "text/html; charset=utf-8"),
                     "/app.js": ("app.js", "application/javascript; charset=utf-8"), "/style.css": ("style.css", "text/css; charset=utf-8"),
                     "/agent-codex.png": ("agent-codex.png", "image/png"), "/agent-claude.png": ("agent-claude.png", "image/png"), "/agent-workbuddy.png": ("agent-workbuddy.png", "image/png")]
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

