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

    func start(store: FeishuStore, listen: Bool = true, preferredPort: UInt16 = 18766) {
        self.store = store
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
        if !section.isEmpty { openSection = section }
        guard ready else {
            openWhenReady = true
            if listener == nil, let store { start(store: store) }
            return
        }
        if openSection == "agents" { WorkspaceWindow.shared.openAgentStatus(store:.shared) }
        else if openSection == "skins" { WorkspaceWindow.shared.openAgents(store:.shared) }
        else { WorkspaceWindow.shared.openSettings(store:.shared) }
        openSection = ""
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
        if url.path == "/api/chrome-import" {
            guard headers["origin"] == WorkChromeImport.origin, !sessionLocked else { return .error(403,"请解锁并使用工作岛Chrome收录扩展。") }
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
            guard !sessionLocked, let store else { return .error(403,"请解锁并打开工作岛。") }
            let company=CompanyConnection.shared
            if method == "GET" {
                return .json(["state":company.statusJSON(),"message":store.connection.profile == CompanyConnection.profile ? "当前消息使用公司连接；材料归档单独授权。" : "现有本机接收保持原配置。首次使用请先连接自己的飞书。"])
            }
            guard method == "POST", headers["origin"] == "http://\(host)",headers["x-island-settings"] == "1",headers["content-type"]?.hasPrefix("application/json") == true,
                  let input=try? JSONSerialization.jsonObject(with:body) as? [String:Any],let action=input["action"] as? String else { return .error(403,"请从本机设置页操作。") }
            guard store.allowsDirectoryLookup else { return .error(403,"合成模式不打开真实公司连接。") }
            if action == "open" { company.open(); return .json(["message":"已打开独立连接窗口。在窗口中登录自己的中台账号，并分别授权消息与归档；完成后回到这里启用。"] ) }
            guard ["receive","archive","disableReceive","disableArchive","reset"].contains(action) else { return .error(400,"不支持的连接操作。") }
            guard !companyActionBusy else { return .error(409,"连接正在核对，请稍候。") }
            companyActionBusy=true
            defer { companyActionBusy=false }
            if action == "disableReceive" {
                guard !(store.enabled && store.connection.profile == CompanyConnection.profile) else { return .error(409,"请先停止接收并保存，再停用公司接收连接。") }
                company.setEnabled(.receive,false)
                return .json(["message":"公司接收连接已停用。其他接收配置未改变。"])
            }
            if action == "disableArchive" || action == "reset" {
                guard !WorkspaceStore.shared.disk.items.contains(where:{["running","queued","dot_waiting","dot_running"].contains($0.state) || ["running","pending"].contains($0.archive?.state ?? "") || $0.archive?.intent != nil}) else { return .error(409,"仍有任务或归档待完成，请完成后再更改连接。") }
                if action == "disableArchive" {
                    company.setEnabled(.archive,false)
                    return .json(["message":"公司归档连接已停用。后续归档将使用已有本机配置（如有）；历史归档仍须原账号完成。"])
                }
                do { try company.reset();company.open();return .json(["message":"已清除本机公司登录，请在连接窗口登录自己的账号。"] ) }
                catch { return .error(409,(error as? AccountFailure)?.detail ?? "请先停用两项公司连接。") }
            }
            let revision=store.settingsRevision
            if action == "receive", store.enabled { return .error(409,"现有接收正在运行，已保持不变。如需切换，请先停止接收并保存。") }
            if action == "archive", WorkspaceStore.shared.disk.items.contains(where:{["running","queued","dot_waiting","dot_running"].contains($0.state) || ["running","pending"].contains($0.archive?.state ?? "") || $0.archive?.intent != nil}) { return .error(409,"仍有任务或归档待完成，请完成后再切换归档连接。") }
            let purpose:CompanyConnection.Purpose=action == "receive" ? .receive : .archive
            do {
                let credential=try await Task.detached { try company.prepare(purpose) }.value
                if action == "receive" {
                    guard !sessionLocked, !store.enabled, store.settingsRevision == revision else { throw AccountFailure(detail:"接收设置已变化，保留当前配置；请核对后再连接。") }
                    if let conflict=store.receiveConflict { throw AccountFailure(detail:conflict) }
                    try company.activate(credential,purpose:purpose)
                    _=store.updateConnection(FeishuConnection(profile:CompanyConnection.profile))
                    store.updateSettings(enabled:true,rules:store.rules)
                } else {
                    guard !sessionLocked, !WorkspaceStore.shared.disk.items.contains(where:{["running","queued","dot_waiting","dot_running"].contains($0.state) || ["running","pending"].contains($0.archive?.state ?? "") || $0.archive?.intent != nil}) else { throw AccountFailure(detail:"已有任务开始处理，保留原归档连接；完成后再切换。") }
                    try company.activate(credential,purpose:purpose)
                }
                return .json(["message":action == "receive" ? "已核对 \(credential.userName) 的公司授权，开始接收新消息。" : "已核对 \(credential.userName) 的归档授权。之后主动提交的材料可自动归档。"])
            } catch {
                return .error(409,(error as? AccountFailure)?.detail ?? "公司连接未完成，请打开连接窗口核对本人授权。")
            }
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
private final class SettingsConnection {
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
