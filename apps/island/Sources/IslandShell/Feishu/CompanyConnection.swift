import AppKit
import Foundation
import CryptoKit
import WebKit
import Combine
import SwiftUI

/// The company gateway owns login; this private WebKit store never imports another
/// browser's cookies. Refresh credentials and app secrets stay on the server.
final class CompanyConnection: NSObject, ObservableObject, @unchecked Sendable {
    enum AuthorizationFailure: Error { case expired, loginRequired, forbidden, unavailable }
    enum Purpose: String, CaseIterable { case receive, archive, calendar
        var serviceKey: String { self == .calendar ? "schedule" : rawValue }
        var appID: String { self == .archive ? "cli_aa534c191338dd29" : "cli_aa217b534af89cdc" }
        var scopes:Set<String> {
            if self == .calendar { return Set("auth:user.id:read calendar:calendar:read calendar:calendar.event:read offline_access".split(separator:" ").map(String.init)) }
            let value = self == .receive
                ? "auth:user.id:read im:chat:read im:chat.user_setting:read im:message.group_msg:get_as_user im:message.p2p_msg:get_as_user im:message:readonly offline_access"
                : "auth:user.id:read docx:document:create docx:document:write_only docx:document:readonly docs:document.media:upload drive:file:upload base:record:create base:field:read base:record:read wiki:node:read offline_access"
            return Set(value.split(separator:" ").map(String.init))
        }
    }
    struct Credential {
        let appID: String, access: String, scope: Set<String>, userID: String, openID: String, userName: String
        let expires: Date
        static func decode(_ value: Any, purpose: Purpose, now: Date = Date()) throws -> Credential {
            guard let j=value as? [String:Any], let app=j["appId"] as? String, app == purpose.appID,
                  let access=j["access"] as? String, !access.isEmpty, access.utf8.count < 16384, access.utf8.allSatisfy({ $0 > 32 && $0 < 127 }),
                  let raw=j["scope"] as? String, let user=j["userId"] as? String, !user.isEmpty, user.count < 200,
                  let open=j["openId"] as? String, open.hasPrefix("ou_"), open.count < 200,
                  let ms=j["expires"] as? Double, ms.isFinite,
                  Date(timeIntervalSince1970:ms/1000) > now.addingTimeInterval(30),
                  Date(timeIntervalSince1970:ms/1000) < now.addingTimeInterval(172800) else { throw failure("公司连接返回不完整，请重新打开连接页。") }
            let scope=Set(raw.split(whereSeparator:{$0.isWhitespace}).map(String.init))
            guard scope == purpose.scopes else { throw failure("公司连接权限范围不符，未用于本机。") }
            return Credential(appID:app,access:access,scope:scope,userID:user,openID:open,userName:String((j["userName"] as? String ?? "已连接账号").prefix(120)),expires:Date(timeIntervalSince1970:ms/1000))
        }
        func validateIdentity(boundUser: String?, boundOpenID: String?) throws {
            if let boundUser, boundUser != userID { throw failure("公司账号已切换，已停止连接。请先停用连接，再明确更换账号。") }
            if let boundOpenID, boundOpenID != openID { throw failure("飞书账号已切换，已停止连接。请先停用连接，再明确更换账号。") }
        }
        func checkScopes(_ required: String) -> [String:Any] {
            let missing=required.split(whereSeparator:{$0.isWhitespace}).map(String.init).filter{!scope.contains($0)}
            return ["ok":missing.isEmpty,"missing":missing,"granted":scope.sorted()]
        }
        /// Official lark-cli v1.0.96 supports these token-only variables. No fake
        /// profile, shared app secret, refresh token or credential file is created.
        func environment(_ original: [String:String]) -> [String:String] {
            let auth:Set<String>=["LARKSUITE_CLI_APP_ID","LARKSUITE_CLI_APP_SECRET","LARKSUITE_CLI_USER_ACCESS_TOKEN","LARKSUITE_CLI_TENANT_ACCESS_TOKEN","LARKSUITE_CLI_TENANT_ACCESS_TOKEN_SOURCE","LARKSUITE_CLI_PROFILE","LARKSUITE_CLI_DEFAULT_AS","LARKSUITE_CLI_STRICT_MODE","LARKSUITE_CLI_BRAND","LARKSUITE_CLI_AUTH_PROXY","LARKSUITE_CLI_PROXY_KEY"]
            var env=original.filter{!auth.contains($0.key)}
            env["LARKSUITE_CLI_APP_ID"]=appID; env["LARKSUITE_CLI_USER_ACCESS_TOKEN"]=access
            env["LARKSUITE_CLI_BRAND"]="feishu"; env["LARKSUITE_CLI_DEFAULT_AS"]="user"; env["LARKSUITE_CLI_STRICT_MODE"]="user"
            env["LARKSUITE_CLI_CONFIG_DIR"]=NSHomeDirectory()+"/Library/Application Support/FeishuIsland/CompanyCLI"
            env["LARKSUITE_CLI_NO_UPDATE_NOTIFIER"]="1"; env["LARKSUITE_CLI_NO_SKILLS_NOTIFIER"]="1"
            return env
        }
    }
    static let profile="company"
    static let shared=CompanyConnection()
    static let origin="https://feishu-island.virxact.net"
    static let connectURL=URL(string:origin+"/connect.html")!
    private static let storeID=UUID(uuidString:"0CEFF04D-8688-4341-ADBA-B069D6251F20")!
    private static func failure(_ text:String) -> AccountFailure { AccountFailure(detail:text) }
    static func allowed(_ url:URL?) -> Bool {
        guard let u=url else{return false}
        return u.scheme == "https" && u.host == "feishu-island.virxact.net" && (u.port == nil || u.port == 443) && u.user == nil && u.password == nil
    }
    private let lock=NSLock()
    private let defaults:UserDefaults
    private var storeIdentifier:UUID { defaults.string(forKey:"island.company.store").flatMap(UUID.init(uuidString:)) ?? Self.storeID }
    private var cached:[Purpose:Credential]=[:]
    private var errors:[Purpose:String]=[:]
    // UI and pending state are touched only on the main thread.
    @MainActor @Published private(set) var web:WKWebView?
    @MainActor @Published var authorizationPurpose: Purpose = .receive {
        didSet {
            guard oldValue != authorizationPurpose else { return }
            authorizationConfigured = false; authorizationGranted = false; authorizationConnected = false
            authorizationFeedback = "正在核对这项用途的授权状态…"
        }
    }
    @MainActor @Published private(set) var authorizationPageReady = false
    @MainActor @Published private(set) var authorizationBusy = false
    @MainActor @Published private(set) var authorizationGranted = false
    @MainActor @Published private(set) var authorizationConnected = false
    @MainActor @Published private(set) var authorizationConfigured = false
    @MainActor @Published private(set) var authorizationChecking = false
    @MainActor @Published private(set) var authorizationFeedback = "正在核对当前账号的授权状态…"
    @MainActor @Published private(set) var loginError: String?
    @MainActor private var authorizationFlow: String?
    @MainActor private var authorizationURL: URL?
    @MainActor private var authorizationPolling: Task<Void, Never>?
    @MainActor private var authorizationAttempt = UUID()
    @MainActor private var window:NSWindow?
    @MainActor private var connectAfterStatus = false
    private struct PendingRequest {
        let preparing:Bool
        let complete:(Result<Credential,Error>)->Void
    }
    @MainActor private var pending:[Purpose:[PendingRequest]]=[:]
    @MainActor private var inflight=Set<Purpose>()
    @MainActor private var attempts:[Purpose:UUID]=[:]
    @MainActor private var generation=0
    @MainActor private var loading=false
    @MainActor private var reloadAfterFailure=false
    @MainActor private var retryAfter=Date.distantPast
    private let fetcher:((Purpose,@escaping(Result<Credential,Error>)->Void)->Void)?
    private let authorizationTransport: ((String, [String: String]?) async throws -> [String: Any])?
    @MainActor var authorizationOpenURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    init(defaults:UserDefaults = .standard, fetcher:((Purpose,@escaping(Result<Credential,Error>)->Void)->Void)? = nil,
         authorizationTransport: ((String, [String: String]?) async throws -> [String: Any])? = nil) {
        self.defaults=defaults;self.fetcher=fetcher;self.authorizationTransport=authorizationTransport;super.init()
    }
    private func key(_ p:Purpose) -> String { "island.company."+p.rawValue+".enabled" }
    func isEnabled(_ p:Purpose) -> Bool { defaults.bool(forKey:key(p)) }
    /// Called by the user's explicit Apply action, never by page navigation.
    @MainActor func setEnabled(_ p:Purpose,_ enabled:Bool) {
        precondition(Thread.isMainThread)
        defaults.set(enabled,forKey:key(p)); invalidate(p,"公司连接设置已变化，请重试。")
        if enabled { ensureWeb() }
    }
    func statusJSON() -> [String:Any] {
        lock.lock(); defer{lock.unlock()}
        var result:[String:Any]=[:]
        for p in Purpose.allCases {
            result[p.rawValue]=["enabled":isEnabled(p),"connected":cached[p].map{$0.expires > Date()} ?? false,
                               "error":errors[p] ?? "","bound":defaults.string(forKey:"island.company.user") != nil]
        }
        return result
    }
    static func conversationStorageKey(userID: String, openID: String) -> String {
        SHA256.hash(data: Data((userID + "\u{0}" + openID).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func boundConversationStorageKey() -> String? {
        guard let user = defaults.string(forKey: "island.company.user"),
              let open = defaults.string(forKey: "island.company.receive.openID") else { return nil }
        return Self.conversationStorageKey(userID: user, openID: open)
    }
    func boundAccountKey(_ purpose: Purpose) -> String? {
        defaults.string(forKey: "island.company." + purpose.rawValue + ".openID").map { purpose.appID + ":" + $0 }
    }
    /// Invoked only after the native account-switch confirmation. The old archive
    /// consumer no longer runs in this product; its local switch must not trap the
    /// person behind a removed settings page. Server grants are not revoked here.
    @MainActor func resetForNativeAccountSwitch() throws {
        setEnabled(.receive, false)
        setEnabled(.archive, false)
        setEnabled(.calendar, false)
        try reset()
    }
    /// Explicit account reset is permitted only after both consumers are disabled.
    @MainActor func reset() throws {
        precondition(Thread.isMainThread)
        guard !Purpose.allCases.contains(where:{isEnabled($0)}) else { throw Self.failure("请先停用所有公司连接，再更换账号。") }
        invalidate("公司连接已重置。")
        authorizationPolling?.cancel(); authorizationPolling = nil; authorizationAttempt = UUID()
        authorizationFlow = nil; authorizationURL = nil; authorizationBusy = false; authorizationChecking = false
        authorizationGranted = false; authorizationConnected = false; authorizationConfigured = false; authorizationPageReady = false
        authorizationFeedback = "连接已重置，请登录自己的账号后继续。"
        defaults.removeObject(forKey:"island.company.user")
        for p in Purpose.allCases { defaults.removeObject(forKey:"island.company."+p.rawValue+".openID") }
        let store=WKWebsiteDataStore(forIdentifier:storeIdentifier)
        // A fresh store makes reset immediate even while WebKit asynchronously
        // removes the old private login data.
        defaults.set(UUID().uuidString,forKey:"island.company.store")
        store.removeData(ofTypes:WKWebsiteDataStore.allWebsiteDataTypes(),modifiedSince:.distantPast){}
        web?.stopLoading(); web=nil; window?.close(); window=nil; loading=false
    }
    @MainActor func open(purpose: Purpose = .receive) {
        guard !authorizationBusy || authorizationPurpose == purpose else { window?.makeKeyAndOrderFront(nil); return }
        authorizationPurpose = purpose
        connectAfterStatus = !authorizationBusy
        ensureWeb()
        if window == nil {
            let next = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 620), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            next.title = "连接飞书 · 一切在岛"; next.minSize = NSSize(width: 480, height: 540)
            next.contentView = NSHostingView(rootView: CompanyAuthorizationView(connection: self))
            next.isReleasedWhenClosed = false; next.delegate = self; next.center(); window = next
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate()
        if authorizationPageReady { Task { await refreshAuthorizationStatus() } }
    }
    @MainActor var isConnectionWindowVisible: Bool { window?.isVisible == true }
    @MainActor func refreshAuthorizationStatus() async {
        guard authorizationPageReady || authorizationTransport != nil else { return }
        if authorizationTransport != nil { authorizationPageReady = true }
        let epoch = generation
        let purpose = authorizationPurpose
        do {
            let response = try await authorizationRequest("status")
            guard epoch == generation, purpose == authorizationPurpose else { return }
            guard let state = response[purpose.serviceKey] as? [String: Any] else {
                authorizationConfigured = false
                authorizationFeedback = "日历连接服务正在升级，请稍后重试。无需创建应用或填写配置。"
                return
            }
            authorizationConfigured = state["configured"] as? Bool == true
            authorizationGranted = state["authorized"] as? Bool == true
            let local = statusJSON()[authorizationPurpose.rawValue] as? [String: Any]
            authorizationConnected = authorizationGranted && local?["connected"] as? Bool == true
            if !authorizationBusy {
                authorizationFeedback = !authorizationConfigured ? "这项连接暂不可用，请联系应用维护者。"
                    : authorizationConnected ? "已核实本人授权，Mac连接已完成。"
                    : authorizationGranted ? "飞书授权已保存。点下方按钮核对Mac连接，成功后会显示连接结果。"
                    : "点击下方按钮，在飞书核对自己的账号并确认。完成后这里会自动更新。"
            }
            if connectAfterStatus && authorizationConfigured && !authorizationBusy {
                connectAfterStatus = false
                if authorizationGranted { continueDesktopConnection() } else { beginAuthorization() }
            }
        } catch {
            guard epoch == generation, purpose == authorizationPurpose else { return }
            authorizationConfigured = false
            switch error {
            case AuthorizationFailure.loginRequired:
                authorizationFeedback = "公司登录已过期，请重新登录后继续。"
            case AuthorizationFailure.forbidden:
                authorizationFeedback = "授权服务拒绝访问（403）。请联系应用维护者核对账号访问权限。"
            default:
                authorizationFeedback = "暂时无法核对授权状态，请稍后重新检查。"
            }
        }
    }
    @MainActor func beginAuthorization() {
        guard authorizationPageReady || authorizationTransport != nil, authorizationConfigured, !authorizationBusy else { return }
        authorizationBusy = true; authorizationGranted = false; authorizationConnected = false
        authorizationFeedback = "正在准备飞书授权页…"
        let purpose = authorizationPurpose
        let attempt = UUID(); authorizationAttempt = attempt
        authorizationPolling = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let started = try await authorizationRequest("start", payload: ["purpose": purpose.serviceKey])
                guard !Task.isCancelled, authorizationAttempt == attempt else {
                    if let flow = started["flow"] as? String { _ = try? await authorizationRequest("cancel", payload: ["flow": flow]) }
                    return
                }
                guard let flow = started["flow"] as? String, !flow.isEmpty,
                      let raw = started["url"] as? String, let url = URL(string: raw),
                      url.scheme == "https", url.host == "accounts.feishu.cn", url.port == nil,
                      url.user == nil, url.password == nil else { throw Self.failure("飞书授权信息不完整，请重试。") }
                authorizationFlow = flow; authorizationURL = url
                authorizationFeedback = "请在飞书确认。授权完成后无需复制任何内容。"
                reopenAuthorization()
                var interval = max(5, min(60, (started["interval"] as? Double) ?? 5))
                let deadline = Date().addingTimeInterval(600)
                while !Task.isCancelled, authorizationFlow == flow, Date() < deadline {
                    try await Task.sleep(for: .seconds(interval))
                    let result = try await authorizationRequest("poll", payload: ["flow": flow])
                    guard !Task.isCancelled, authorizationFlow == flow else { return }
                    if result["state"] as? String == "authorized" {
                        authorizationFlow = nil; authorizationURL = nil; authorizationBusy = false
                        await refreshAuthorizationStatus()
                        authorizationFeedback = authorizationConnected ? "已完成飞书授权和Mac连接。" : "飞书授权已完成。Mac正在核对连接，请稍候。"
                        if authorizationGranted && !authorizationConnected { continueDesktopConnection() }
                        window?.makeKeyAndOrderFront(nil); NSApp.activate()
                        return
                    }
                    interval = max(5, min(60, (result["interval"] as? Double) ?? interval))
                }
                if !Task.isCancelled { authorizationFeedback = "本次授权已超时。可以取消后重新开始。" }
            } catch is CancellationError { return }
            catch AuthorizationFailure.expired {
                guard authorizationAttempt == attempt else { return }
                authorizationFlow = nil; authorizationURL = nil; authorizationBusy = false
                authorizationFeedback = "本次授权已过期，请重新开始。"
                return
            }
            catch {
                guard !Task.isCancelled, authorizationAttempt == attempt else { return }
                authorizationFeedback = "授权尚未完成，可能已取消、过期或网络中断。可以重新检查，或取消后重试。"
            }
            guard authorizationAttempt == attempt else { return }
            authorizationBusy = authorizationFlow != nil
        }
    }
    @MainActor func reopenAuthorization() {
        if let url = authorizationURL, !authorizationOpenURL(url) {
            authorizationFeedback = "未能打开浏览器，可点“重新打开飞书授权页”再试。"
        }
    }
    @MainActor func checkAuthorizationProgress() {
        guard let flow = authorizationFlow, !authorizationChecking else { return }
        authorizationChecking = true
        Task { @MainActor in
            defer { authorizationChecking = false }
            do {
                let result = try await authorizationRequest("poll", payload: ["flow": flow])
                guard authorizationFlow == flow else { return }
                if result["state"] as? String == "authorized" {
                    authorizationPolling?.cancel(); authorizationFlow = nil; authorizationURL = nil; authorizationBusy = false
                    await refreshAuthorizationStatus()
                    if authorizationGranted && !authorizationConnected { continueDesktopConnection() }
                } else { authorizationFeedback = "仍在等待飞书确认。完成后会自动核对，也可以稍后再检查。" }
            } catch AuthorizationFailure.expired {
                guard authorizationFlow == flow else { return }
                authorizationPolling?.cancel(); authorizationFlow = nil; authorizationURL = nil; authorizationBusy = false
                authorizationFeedback = "本次授权已过期，请重新开始。"
            } catch {
                guard authorizationFlow == flow else { return }
                authorizationFeedback = "暂未取得授权结果。请检查网络，稍后重新检查或取消。"
            }
        }
    }
    @MainActor func continueDesktopConnection() {
        if authorizationPurpose == .receive, let store = FeishuStore.active, !store.connecting {
            store.completeCompanyConnection()
        } else if authorizationPurpose == .calendar {
            Task {
                await WorkspaceStore.shared.connectCompanyFeishuSchedule()
                await refreshAuthorizationStatus()
            }
        } else { Task { await refreshAuthorizationStatus() } }
    }
    @MainActor func cancelAuthorization() {
        authorizationAttempt = UUID()
        let attempt = authorizationAttempt
        authorizationPolling?.cancel(); authorizationPolling = nil
        guard let flow = authorizationFlow else { authorizationBusy = false; return }
        Task { @MainActor in
            do {
                _ = try await authorizationRequest("cancel", payload: ["flow": flow])
                guard authorizationAttempt == attempt, authorizationFlow == flow else { return }
                authorizationFlow = nil; authorizationURL = nil; authorizationBusy = false
                await refreshAuthorizationStatus()
                authorizationFeedback = "本次授权已取消，已有授权不会被撤销。"
            } catch {
                guard authorizationAttempt == attempt, authorizationFlow == flow else { return }
                authorizationFeedback = "暂时无法取消，请重新检查连接后再试。"
            }
        }
    }
    @MainActor func returnToSettings() {
        window?.orderOut(nil)
        if IslandOnboardingPolicy.isNewUser { return }
        UnifiedSettingsWindow.shared.open(section: authorizationPurpose == .calendar ? .todos : .messages)
    }
    @MainActor func reloadLoginPage() {
        loginError = nil; authorizationPageReady = false
        ensureWeb()
        web?.load(URLRequest(url: Self.connectURL, cachePolicy: .reloadIgnoringLocalCacheData))
    }
    @MainActor private func authorizationRequest(_ route: String, payload: [String: String]? = nil) async throws -> [String: Any] {
        if let authorizationTransport { return try await authorizationTransport(route, payload) }
        guard ["status", "start", "poll", "cancel"].contains(route), let web,
              Self.allowed(web.url), web.url?.path == "/connect.html" else {
            throw Self.failure("请先完成公司账号登录。")
        }
        let epoch = generation
        let code = """
        if (location.origin !== 'https://feishu-island.virxact.net' || location.pathname !== '/connect.html') throw new Error('origin');
        const controller = new AbortController(); const timer = setTimeout(() => controller.abort(), 16000);
        try {
          const response = await fetch('/api/auth/' + route, {method: payload ? 'POST' : 'GET', credentials: 'same-origin', cache: 'no-store', redirect: 'error', headers: payload ? {'Content-Type': 'application/json', 'X-Island-Auth': '1'} : {}, body: payload ? JSON.stringify(payload) : undefined, signal: controller.signal});
          if (!response.ok) return {authorizationFailure: response.status};
          return await response.json();
        } finally { clearTimeout(timer); }
        """
        let response = try await Self.evaluateAuthorizationObject(code, arguments: ["route": route, "payload": payload as Any? ?? NSNull()], web: web)
        guard epoch == generation, self.web === web, Self.allowed(web.url), web.url?.path == "/connect.html" else {
            throw Self.failure("登录状态已变化，请重新检查授权。")
        }
        if let status = response["authorizationFailure"] as? Int {
            if route == "cancel", status == 404 { return ["cancelled": true] }
            if route == "poll", status == 404 || status == 410 { throw AuthorizationFailure.expired }
            if status == 401 {
                authorizationPageReady = false; authorizationConnected = false
                loginError = "公司登录已过期，请重新登录后继续。"
                throw AuthorizationFailure.loginRequired
            }
            if status == 403 { throw AuthorizationFailure.forbidden }
            throw AuthorizationFailure.unavailable
        }
        return response
    }
    /// Use the completion overload explicitly: with this SDK, an untyped
    /// `try await callAsyncJavaScript(...)` selects the fire-and-forget Void
    /// overload. Its result can never decode, even when HTTP succeeds.
    @MainActor static func evaluateAuthorizationObject(_ code: String, arguments: [String: Any], web: WKWebView) async throws -> [String: Any] {
        let result: Any = try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript(code, arguments: arguments, in: nil, in: .page) {
                continuation.resume(with: $0)
            }
        }
        guard let response = result as? [String: Any] else {
            throw Self.failure("授权服务返回不完整，请重试。")
        }
        return response
    }
    /// The first-run UI waits for the user's own login without changing any server
    /// grants or importing cookies from another browser.
    @MainActor func prepareReceive() async throws -> Credential {
        try await prepareAuthorization(.receive)
    }
    @MainActor func prepareAuthorization(_ purpose: Purpose) async throws -> Credential {
        try await withCheckedThrowingContinuation { continuation in
            enqueue(purpose, preparing: true) { continuation.resume(with: $0) }
        }
    }
    /// Explicit activation first prepares without changing the running mode,
    /// persisted identity or cache. The caller rechecks jobs/settings, then activates.
    func prepare(_ p:Purpose) throws -> Credential { try waitForCredential(p,preparing:true) }
    @MainActor func activate(_ credential:Credential,purpose:Purpose) throws {
        guard credential.appID == purpose.appID,credential.scope == purpose.scopes,
              credential.expires > Date().addingTimeInterval(30) else { throw Self.failure("公司连接已过期或用途不符，请重新核对。") }
        try validateBoundIdentity(credential,purpose:purpose)
        defaults.set(credential.userID,forKey:"island.company.user")
        defaults.set(credential.openID,forKey:"island.company."+purpose.rawValue+".openID")
        defaults.set(true,forKey:key(purpose))
        lock.lock();cached[purpose]=credential;errors[purpose]=nil;lock.unlock()
        if authorizationPurpose == purpose {
            authorizationGranted = true; authorizationConnected = true
            authorizationFeedback = "已核实本人授权，Mac连接已完成。消息是否接收以设置中的开关为准。"
        }
    }
    /// Background callers wait with a deadline. WebKit work always runs on main;
    /// a main-thread caller fails instead of deadlocking the running receiver.
    func credential(_ p:Purpose) throws -> Credential { try waitForCredential(p,preparing:false) }
    private func waitForCredential(_ p:Purpose,preparing:Bool) throws -> Credential {
        guard !Thread.isMainThread else { throw Self.failure("公司连接需在后台读取。") }
        guard preparing || isEnabled(p) else { throw Self.failure("尚未启用此项公司连接。") }
        let waiter=Waiter()
        DispatchQueue.main.async { self.enqueue(p,preparing:preparing) { waiter.finish($0) } }
        guard waiter.semaphore.wait(timeout:.now()+25) == .success else { waiter.cancel(); throw Self.failure("公司连接超时，请打开连接页检查登录。") }
        return try waiter.value()
    }
    private final class Waiter:@unchecked Sendable {
        let semaphore=DispatchSemaphore(value:0); let lock=NSLock(); var result:Result<Credential,Error>?; var cancelled=false
        func finish(_ value:Result<Credential,Error>){lock.lock();guard !cancelled else{lock.unlock();return};result=value;lock.unlock();semaphore.signal()}
        func cancel(){lock.lock();cancelled=true;lock.unlock()}
        func value() throws -> Credential{lock.lock();let r=result;lock.unlock();return try r!.get()}
    }
    @MainActor private func ensureWeb() {
        guard web == nil, fetcher == nil, authorizationTransport == nil else { return }
        let config = WKWebViewConfiguration(); config.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeIdentifier)
        let next = WKWebView(frame: .zero, configuration: config); next.navigationDelegate = self; next.uiDelegate = self
        next.allowsBackForwardNavigationGestures = false; web = next; loading = true
        next.load(URLRequest(url: Self.connectURL, cachePolicy: .reloadIgnoringLocalCacheData))
    }
    @MainActor private func invalidate(_ purpose:Purpose,_ message:String) {
        lock.lock();cached[purpose]=nil;errors[purpose]=nil;lock.unlock()
        let requests=pending.removeValue(forKey:purpose) ?? []
        inflight.remove(purpose);attempts[purpose]=nil
        for request in requests {request.complete(.failure(Self.failure(message)))}
    }
    @MainActor private func invalidate(_ message:String) {
        precondition(Thread.isMainThread)
        generation += 1; lock.lock();cached.removeAll();lock.unlock()
        let jobs=pending;pending.removeAll();inflight.removeAll();attempts.removeAll()
        for requests in jobs.values {for request in requests{request.complete(.failure(Self.failure(message)))}}
    }
    @MainActor private func enqueue(_ p:Purpose,preparing:Bool,completion:@escaping(Result<Credential,Error>)->Void) {
        guard preparing || isEnabled(p) else{completion(.failure(Self.failure("此项公司连接已停用。")));return}
        lock.lock();let hit=cached[p];lock.unlock()
        if !preparing,let hit,hit.expires > Date().addingTimeInterval(120){completion(.success(hit));return}
        if pending[p] == nil { attempts[p]=UUID() }
        let attempt=attempts[p]!
        pending[p,default:[]].append(PendingRequest(preparing:preparing,complete:completion));ensureWeb()
        let epoch=generation
        if reloadAfterFailure,!loading,Date() >= retryAfter {
            reloadAfterFailure=false;loading=true
            web?.load(URLRequest(url:Self.connectURL,cachePolicy:.reloadIgnoringLocalCacheData))
        }
        if !loading {fetch(p)}
        DispatchQueue.main.asyncAfter(deadline:.now()+22){[weak self] in
            guard let self,self.generation == epoch,self.attempts[p] == attempt,self.pending[p] != nil else{return}
            self.finish(p,.failure(Self.failure("公司登录未就绪，请打开连接页完成登录。")))
        }
    }
    @MainActor private func fetch(_ p:Purpose) {
        guard pending[p] != nil,!inflight.contains(p) else{return}
        if let fetcher {
            inflight.insert(p);let epoch=generation;let attempt=attempts[p]
            fetcher(p){[weak self] result in
                DispatchQueue.main.async {
                    guard let self,self.generation == epoch,self.attempts[p] == attempt else{return}
                    self.finish(p,result)
                }
            }
            return
        }
        guard let web,Self.allowed(web.url),web.url?.path == "/connect.html" else {finish(p,.failure(Self.failure("公司登录已过期，请打开连接页完成登录。")));return}
        inflight.insert(p);let epoch=generation;let attempt=attempts[p]
        let code="""
        if (location.origin !== 'https://feishu-island.virxact.net') throw new Error('origin');
        const controller = new AbortController(); const timer=setTimeout(()=>controller.abort(),16000);
        try { const r=await fetch('/api/auth/access',{method:'POST',credentials:'same-origin',cache:'no-store',redirect:'error',headers:{'Content-Type':'application/json','X-Island-Auth':'1'},body:JSON.stringify({purpose}),signal:controller.signal});
          if(!r.ok) {
            let j; try { j=await r.json(); } catch { j={}; }
            return {failure:r.status,scopeMismatch:typeof j.error==='string' && j.error.startsWith('飞书返回权限与本次用途不一致')};
          } return await r.json();
        } finally { clearTimeout(timer); }
        """
        web.callAsyncJavaScript(code,arguments:["purpose":p.serviceKey],in:nil,in:.page) { [weak self] result in
            guard let self,self.generation == epoch,self.attempts[p] == attempt,self.pending[p] != nil else{return}
            guard Self.allowed(web.url),web.url?.path == "/connect.html",self.isEnabled(p) || self.pending[p]?.contains(where:{$0.preparing}) == true else {self.finish(p,.failure(Self.failure("公司连接页面已变化，请重试。")));return}
            do {
                let json=try result.get()
                if let failure=(json as? [String:Any])?["failure"] as? Int {
                    let mismatch = (json as? [String: Any])?["scopeMismatch"] as? Bool == true
                    throw Self.failure(mismatch
                        ? "授权服务返回了超出当前用途的权限，Mac已拒绝连接。请维护者修复服务端权限收窄，无需反复登录。"
                        : failure == 401 ? "公司登录或飞书授权已失效，请打开连接页重新连接。"
                        : failure == 403 ? "授权服务拒绝Mac连接（403），请维护者检查访问权限。"
                        : "公司连接暂时不可用，请稍后重试。")
                }
                let credential=try Credential.decode(json,purpose:p)
                self.finish(p,.success(credential))
            } catch {self.finish(p,.failure(error as? AccountFailure ?? Self.failure("公司连接未完成，请打开连接页检查。")))}
        }
    }
    @MainActor private func validateBoundIdentity(_ c:Credential,purpose:Purpose) throws {
        try c.validateIdentity(boundUser:defaults.string(forKey:"island.company.user"),boundOpenID:defaults.string(forKey:"island.company."+purpose.rawValue+".openID"))
    }
    @MainActor private func finish(_ p:Purpose,_ result:Result<Credential,Error>) {
        inflight.remove(p);attempts[p]=nil;let requests=pending.removeValue(forKey:p) ?? []
        for request in requests {
            let checked:Result<Credential,Error>
            do {
                let credential=try result.get()
                try validateBoundIdentity(credential,purpose:p)
                if !request.preparing {
                    guard isEnabled(p),defaults.string(forKey:"island.company.user") != nil,
                          defaults.string(forKey:"island.company."+p.rawValue+".openID") != nil else {
                        throw Self.failure("公司连接未完成启用，请从设置页确认。")
                    }
                    lock.lock();cached[p]=credential;errors[p]=nil;lock.unlock()
                }
                checked = .success(credential)
            } catch {
                // A preparation failure must not alter another running consumer.
                if !request.preparing {
                    lock.lock();cached[p]=nil;errors[p]=(error as? AccountFailure)?.detail ?? "公司连接暂不可用。";lock.unlock()
                }
                checked = .failure(error)
            }
            request.complete(checked)
        }
    }
}

@MainActor extension CompanyConnection: WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        connectAfterStatus = false
        cancelAuthorization()
        if authorizationPurpose == .receive, FeishuStore.active?.connecting == true { FeishuStore.active?.cancelConnection() }
    }
    func webView(_ webView:WKWebView,didStartProvisionalNavigation navigation:WKNavigation!){
        loading=true;reloadAfterFailure=false
        loginError=nil
        authorizationPageReady=false;authorizationConnected=false
        if !inflight.isEmpty { invalidate("公司页面正在切换，请重试。") }
        // Changing account/navigation invalidates access tokens; no old token fallback.
        lock.lock();cached.removeAll();lock.unlock()
    }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){
        loading=false;reloadAfterFailure=false
        authorizationPageReady=Self.allowed(webView.url) && webView.url?.path == "/connect.html"
        if authorizationPageReady, window?.isVisible == true { Task { await refreshAuthorizationStatus() } }
        for p in Array(pending.keys){fetch(p)}
    }
    private func pageFailed(){
        authorizationPageReady=false;loginError="连接页面暂时打不开，请检查网络后重试。"
        loading=false;reloadAfterFailure=true;retryAfter=Date().addingTimeInterval(5)
        invalidate("公司页面暂时离线；网络恢复后会自动重连。")
    }
    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error){pageFailed()}
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error){pageFailed()}
    func webViewWebContentProcessDidTerminate(_ webView:WKWebView){
        loading=false;invalidate("公司连接正在恢复，请稍后重试。")
        self.web=nil
        let epoch=generation
        DispatchQueue.main.asyncAfter(deadline:.now()+3){[weak self] in
            guard let self,self.generation == epoch,self.web == nil,
                  self.purposeEnabledOrWindowVisible else{return}
            self.ensureWeb() // The same private cookie store resumes the company session.
        }
    }
    private var purposeEnabledOrWindowVisible:Bool { Purpose.allCases.contains(where:{isEnabled($0)}) || window?.isVisible == true }
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){
        guard let url=navigationAction.request.url,url.scheme == "https",url.user == nil,url.password == nil else{decisionHandler(.cancel);return}
        decisionHandler(.allow)
    }
    func webView(_ webView:WKWebView,createWebViewWith configuration:WKWebViewConfiguration,for navigationAction:WKNavigationAction,windowFeatures:WKWindowFeatures)->WKWebView? {
        if let url=navigationAction.request.url,url.scheme == "https",url.host == "accounts.feishu.cn",url.user == nil,url.password == nil {NSWorkspace.shared.open(url)}
        return nil
    }
}
