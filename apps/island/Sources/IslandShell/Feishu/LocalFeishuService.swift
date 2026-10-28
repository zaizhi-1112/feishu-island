import AppKit
import Foundation
import SwiftUI
import CoreImage.CIFilterBuiltins

/// Every distributed copy discovers only this Mac's official CLI profiles.
/// This model stores identity bindings, never application secrets or tokens.
enum LocalFeishuPurpose: String, CaseIterable, Identifiable {
    case receive, calendar, archive
    var id: String { rawValue }
    var title: String { switch self { case .receive: return "消息接收"; case .calendar: return "飞书日程"; case .archive: return "文档归档" } }
    var scopes: Set<String> { CompanyConnection.Purpose(rawValue: rawValue)!.scopes }
}

final class LocalCLIJob: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; let p = process; lock.unlock(); if let p, p.isRunning { p.terminate(); DispatchQueue.global().asyncAfter(deadline: .now()+1) { if p.isRunning { kill(p.processIdentifier, SIGKILL) } } } }
    func run(_ connection: FeishuConnection, _ arguments: [String], input: Data? = nil,
             timeout: Double = 30, output: ((String) -> Void)? = nil) throws -> Data {
        guard connection.valid, connection.profile != "company" else { throw AccountFailure(detail: "请选择本机飞书配置，旧公司连接已停用。") }
        let p = Process(), pipe = Pipe(), errors = Pipe(), stdin = Pipe()
        p.executableURL = URL(fileURLWithPath: connection.cliPath)
        p.arguments = (connection.profile.isEmpty ? [] : ["--profile", connection.profile]) + arguments
        p.environment = LocalFeishuAccount.environment(ProcessInfo.processInfo.environment)
        p.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        p.standardInput = stdin; p.standardOutput = pipe; p.standardError = errors
        defer { for h in [pipe.fileHandleForReading, pipe.fileHandleForWriting, errors.fileHandleForReading, errors.fileHandleForWriting, stdin.fileHandleForReading, stdin.fileHandleForWriting] { try? h.close() } }
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        process = p
        do { try p.run(); lock.unlock() } catch { lock.unlock(); throw AccountFailure(detail: "无法启动内置飞书组件，请重新安装完整应用。") }
        let timer = DispatchWorkItem { if p.isRunning { p.terminate(); DispatchQueue.global().asyncAfter(deadline: .now()+1) { if p.isRunning { kill(p.processIdentifier, SIGKILL) } } } }
        DispatchQueue.global().asyncAfter(deadline: .now()+timeout, execute: timer)
        defer { timer.cancel(); lock.lock(); process = nil; lock.unlock() }
        DispatchQueue.global().async { if let input { try? stdin.fileHandleForWriting.write(contentsOf: input) }; try? stdin.fileHandleForWriting.close() }
        let errorGroup = DispatchGroup(); errorGroup.enter()
        DispatchQueue.global().async {
            defer { errorGroup.leave() }
            var safeBuffer = Data()
            while true {
                let chunk = errors.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                if safeBuffer.count + chunk.count <= 64_000 { safeBuffer.append(chunk); output?(String(decoding: safeBuffer, as: UTF8.self)) }
            }
        }
        var bytes = Data(), oversized = false
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            if oversized { continue }
            if bytes.count + chunk.count > 4_000_000 {
                oversized = true; p.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now()+1) { if p.isRunning { kill(p.processIdentifier, SIGKILL) } }
                continue
            }
            bytes.append(chunk)
            if let output { output(String(decoding: bytes, as: UTF8.self)) }
        }
        p.waitUntilExit(); errorGroup.wait()
        lock.lock(); let stopped = cancelled; lock.unlock()
        if stopped { throw CancellationError() }
        if oversized { throw AccountFailure(detail: "飞书响应过大，操作已停止。") }
        guard p.terminationStatus == 0 else { throw AccountFailure(detail: "飞书操作未完成，请检查登录、应用权限或网络后重试。") }
        return bytes
    }
    static func json(_ connection: FeishuConnection, _ args: [String], input: Data? = nil) throws -> [String: Any] {
        let bytes = try LocalCLIJob().run(connection, args, input: input)
        guard let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], value["ok"] as? Bool != false else { throw AccountFailure(detail: "飞书返回无效，未继续操作。") }
        return value
    }
    static func verified(_ connection: FeishuConnection, purpose: LocalFeishuPurpose) throws -> LocalFeishuAccount {
        let json = try self.json(connection, ["auth", "status", "--json", "--verify"])
        return try LocalFeishuAccount.verified(json, expected: connection.localAccount, required: purpose.scopes)
    }
    static func request(_ connection: FeishuConnection, purpose: LocalFeishuPurpose, arguments: [String], input: Data? = nil) throws -> [String:Any] {
        guard connection.localAccount != nil else { throw AccountFailure(detail: "请先核对并连接本人的飞书账号。") }
        _ = try verified(connection, purpose: purpose)
        let result = try json(connection, arguments, input: input)
        if arguments.first != "auth" {
            guard result["ok"] as? Bool == true, result["identity"] as? String == "user" else { throw AccountFailure(detail: "飞书未返回本人用户身份，操作已停止。") }
        }
        return result
    }
}

enum LocalFeishuBindings {
    static func connection(_ purpose: LocalFeishuPurpose, defaults: UserDefaults = .standard) -> FeishuConnection? {
        defaults.data(forKey: "island.local."+purpose.rawValue).flatMap { try? JSONDecoder().decode(FeishuConnection.self, from: $0) }.flatMap { $0.valid && $0.localAccount != nil && $0.profile != "company" ? $0 : nil }
    }
}

@MainActor final class LocalFeishuService: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = LocalFeishuService()
    struct Profile: Identifiable { let id: String; let label: String }
    @Published var purpose: LocalFeishuPurpose = .receive {
        didSet {
            guard oldValue != purpose, !busy else { return }
            authorizationURL = nil
            if let saved = connection(purpose) { selected = saved.profile }
            feedback = "请为“" + purpose.title + "”核对本机账号和授权。其他用途的连接不会自动启用此项。"
        }
    }
    @Published var selected = "" {
        didSet { if oldValue != selected, !busy { authorizationURL = nil; feedback = "配置已选择，请授权所选用途或核对账号并连接。" } }
    }
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var busy = false
    @Published private(set) var feedback = "选择本机配置，核对自己的飞书账号。"
    @Published private(set) var authorizationURL: URL?
    @Published private(set) var messageConnectionRevision = 0
    private let defaults: UserDefaults
    private let cliPath: String?
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    private var job: LocalCLIJob?
    private var attempt = UUID()
    private var window: NSWindow?
    init(defaults: UserDefaults = .standard, cliPath: String? = nil) { self.defaults = defaults; self.cliPath = cliPath; super.init() }
    private func makeConnection(_ profile: String) -> FeishuConnection { FeishuConnection(cliPath: cliPath, profile: profile) }
    func connection(_ purpose: LocalFeishuPurpose) -> FeishuConnection? {
        defaults.data(forKey: "island.local."+purpose.rawValue).flatMap { try? JSONDecoder().decode(FeishuConnection.self, from: $0) }.flatMap { $0.valid && $0.localAccount != nil && $0.profile != "company" ? $0 : nil }
    }
    func save(_ connection: FeishuConnection, purpose: LocalFeishuPurpose) throws {
        guard connection.valid, connection.localAccount != nil, connection.profile != "company" else { throw AccountFailure(detail: "本机账号未核验。") }
        defaults.set(try JSONEncoder().encode(connection), forKey: "island.local."+purpose.rawValue)
    }
    func open(_ purpose: LocalFeishuPurpose = .receive) {
        if !busy { self.purpose = purpose }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 560,height: 620), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
            w.title = "连接自己的飞书 · 一切在岛"; w.minSize = NSSize(width: 480,height: 540)
            w.contentView = NSHostingView(rootView: LocalFeishuConnectionView(service: self)); w.isReleasedWhenClosed = false; w.delegate = self; w.center(); window = w
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if !busy { Task { await refresh() } }
    }
    func windowWillClose(_ notification: Notification) { cancel() }
    func cancel() { attempt = UUID(); job?.cancel(); job = nil; busy = false; authorizationURL = nil; feedback = "操作已取消；已有连接和其他CLI配置保留。" }
    nonisolated static func allowedAuthorizationURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host,
              (host == "feishu.cn" || host.hasSuffix(".feishu.cn")), url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return nil }
        return url
    }
    nonisolated static func setupURL(_ text: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: "https://[^\\s\\\"<>\\x1B]+(?=[\\s\\\"<>\\x1B])") else { return nil }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }.compactMap(allowedAuthorizationURL).first { $0.path.contains("device") || $0.path.contains("verify") || $0.path.contains("cli") }
    }
    func refresh() async {
        guard !busy else { return }
        busy = true; let epoch = UUID(); attempt = epoch
        defer { if attempt == epoch { busy = false } }
        do {
            let listing = makeConnection("")
            let bytes = try await Task.detached { try LocalCLIJob().run(listing, ["profile", "list"]) }.value
            guard attempt == epoch else { return }
            let rows = (try? JSONSerialization.jsonObject(with: bytes) as? [[String:Any]]) ?? []
            profiles = rows.compactMap { row in
                guard row["brand"] as? String == "feishu", let name = row["name"] as? String, !name.isEmpty, name != "company", FeishuConnection(profile: name).valid else { return nil }
                return Profile(id: name, label: (row["user"] as? String).flatMap { $0.isEmpty ? nil : $0 }.map { $0 + " · " + name } ?? name)
            }
            if !profiles.contains(where: { $0.id == selected }) {
                let saved = connection(purpose)?.profile ?? (purpose == .receive ? FeishuStore.active?.connection.profile : nil)
                selected = profiles.first(where: { $0.id == saved })?.id ?? ""
            }
            feedback = profiles.isEmpty ? "这台Mac还没有飞书配置。请先完成首次配置，再授权个人账号。" : "请选择并核对本人的账号；不会自动使用CLI当前账号。"
        } catch { if attempt == epoch { feedback = (error as? AccountFailure)?.detail ?? "无法读取本机配置。" } }
    }
    func configure() {
        guard !busy else { return }
        let alert = NSAlert(); alert.messageText = "为这台Mac创建飞书CLI应用配置？"
        alert.informativeText = "将打开飞书官方页面，由你确认创建应用及其权限。公司若限制创建应用，需要管理员处理。此操作新增独立配置，不覆盖其他CLI配置。"
        alert.addButton(withTitle: "打开官方配置"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = "island-" + UUID().uuidString.prefix(8).lowercased()
        let setup = makeConnection("")
        runFlow { job, epoch, _ in
            _ = try await Task.detached { try job.run(setup, ["config", "init", "--new", "--name", name, "--brand", "feishu", "--lang", "zh_cn"], timeout: 600) { text in
                guard let url = Self.setupURL(text) else { return }
                Task { @MainActor in self.showURL(url, epoch: epoch) }
            } }.value
            guard self.attempt == epoch else { return }
            self.profiles.append(Profile(id: name, label: name)); self.selected = name; self.feedback = "应用配置已保存，请授权所需用途，再核对账号并连接。"
        }
    }
    private func showURL(_ url: URL, epoch: UUID) {
        guard attempt == epoch, authorizationURL == nil else { return }
        authorizationURL = url; feedback = "请在飞书官方页面完成操作，完成后本窗口会继续。"; openURL(url)
    }
    private func runFlow(_ action: @escaping (LocalCLIJob, UUID, LocalFeishuPurpose) async throws -> Void) {
        guard !busy else { return }
        let job = LocalCLIJob(), epoch = UUID(), purpose = self.purpose
        self.job = job; attempt = epoch; busy = true; authorizationURL = nil; feedback = "正在连接飞书…"
        Task {
            defer { if attempt == epoch { busy = false; self.job = nil; authorizationURL = nil } }
            do { try await action(job, epoch, purpose) }
            catch { if attempt == epoch { feedback = (error as? AccountFailure)?.detail ?? "连接未完成，请重试。" } }
        }
    }
    func authorize() {
        guard !selected.isEmpty else { return }
        let connection = makeConnection(selected)
        runFlow { job, epoch, purpose in
            let bytes = try await Task.detached { try job.run(connection, ["auth", "login", "--scope", purpose.scopes.sorted().joined(separator: " "), "--no-wait", "--json"]) }.value
            guard self.attempt == epoch, let json = try JSONSerialization.jsonObject(with: bytes) as? [String:Any],
                  let code = json["device_code"] as? String, !code.isEmpty,
                  let raw = (json["verification_url"] ?? json["verification_uri_complete"]) as? String,
                  let url = Self.allowedAuthorizationURL(raw) else { throw AccountFailure(detail: "没有取得有效的飞书授权链接。") }
            self.showURL(url, epoch: epoch)
            _ = try await Task.detached { try job.run(connection, ["auth", "login", "--device-code", code], timeout: 600) }.value
            guard self.attempt == epoch else { return }
            self.feedback = "授权已完成。请点击“核对账号并连接”，确认后才用于本应用。"
        }
    }
    /// The message settings sheet owns this flow. It never activates another
    /// settings window or changes a calendar/archive connection.
    func connectMessages(store: FeishuStore, authorize: Bool) {
        guard !busy, purpose == .receive, !selected.isEmpty, store.rulesConfigurationReadable else { return }
        let selected = makeConnection(self.selected)
        let original = store.connection
        runFlow { job, epoch, _ in
            if authorize {
                let bytes = try await Task.detached {
                    try job.run(selected, ["auth", "login", "--scope", LocalFeishuPurpose.receive.scopes.sorted().joined(separator: " "), "--no-wait", "--json"])
                }.value
                guard self.attempt == epoch else { return }
                guard let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                      let code = json["device_code"] as? String, !code.isEmpty,
                      let raw = (json["verification_url"] ?? json["verification_uri_complete"]) as? String,
                      let url = Self.allowedAuthorizationURL(raw) else { throw AccountFailure(detail: "没有取得有效的飞书授权链接，请重试。") }
                self.showURL(url, epoch: epoch)
                _ = try await Task.detached { try job.run(selected, ["auth", "login", "--device-code", code], timeout: 600) }.value
            }
            guard self.attempt == epoch, store.connection == original else { return }
            self.feedback = "正在核对账号与消息读取权限…"
            let account = try await Task.detached { try LocalCLIJob.verified(selected, purpose: .receive) }.value
            guard self.attempt == epoch, store.connection == original else { return }
            var bound = selected; bound.localAccount = account
            let same = original.localAccount?.appID == account.appID && original.localAccount?.openID == account.openID
            if !same {
                let alert = NSAlert()
                alert.messageText = "连接“\(account.userName)”的飞书消息？"
                alert.informativeText = "请确认这是你要连接的账号。只读取消息，不发送消息或修改已读状态。原账号的提醒规则会单独保留。"
                alert.addButton(withTitle: "确认连接"); alert.addButton(withTitle: "取消")
                guard alert.runModal() == .alertFirstButtonReturn, self.attempt == epoch, store.connection == original else {
                    self.feedback = "未更换账号，已有连接与提醒设置保持不变。"; return
                }
            }
            let wasReceiving = store.enabled
            try store.bindLocalConnection(bound, resumeReceiving: same ? wasReceiving : true)
            try self.save(bound, purpose: .receive)
            self.feedback = same && !wasReceiving ? "账号已连接，仍保留暂停接收的选择。" : "账号授权已确认，正在恢复消息接收。"
            self.messageConnectionRevision += 1
        }
    }
    func connect() {
        guard !selected.isEmpty else { return }
        let selected = makeConnection(self.selected)
        runFlow { _, epoch, purpose in
            let account = try await Task.detached { try LocalCLIJob.verified(selected, purpose: purpose) }.value
            guard self.attempt == epoch else { return }
            var bound = selected; bound.localAccount = account
            let alert = NSAlert(); alert.messageText = "连接“" + account.userName + "”的" + purpose.title + "？"
            alert.informativeText = "配置：\(bound.profile)\n应用：\(account.appID)\n仅在这台Mac保存账号绑定，凭据由官方CLI保管。更换账号会停止旧连接，旧数据保留。"
            alert.addButton(withTitle: "确认连接"); alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn, self.attempt == epoch else { return }
            if purpose == .receive {
                guard let store = FeishuStore.active else { throw AccountFailure(detail: "消息模块尚未就绪。") }
                try store.bindLocalConnection(bound)
                try self.save(bound, purpose: .receive)
            } else if purpose == .calendar {
                guard !WorkspaceStore.shared.calendarSyncing else { throw AccountFailure(detail: "日历正在同步，请稍后再更换连接。") }
                let client = FeishuScheduleClient(localConnection: bound)
                _ = try await client.primary()
                guard self.attempt == epoch else { return }
                try self.save(bound, purpose: purpose)
                guard WorkspaceStore.shared.activateFeishuSchedule(bound) else { throw AccountFailure(detail: "日历连接已保存，但同步设置未能保存，请重试。") }
                WorkspaceStore.shared.calendarStatus = "已连接 · 本机直连 · " + account.userName
                Task { await WorkspaceStore.shared.syncFeishuSchedule() }
            } else { try self.save(bound, purpose: purpose) }
            self.feedback = "已连接 · " + account.userName + " · " + purpose.title
        }
    }
}

struct LocalFeishuConnectionView: View {
    @ObservedObject var service: LocalFeishuService
    private var qr: NSImage? {
        guard let url = service.authorizationURL else { return nil }
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(url.absoluteString.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 6,y: 6)), let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: 150,height: 150))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("在这台Mac连接自己的飞书", systemImage: "person.crop.circle.badge.checkmark").font(.title2.bold())
                Text("消息、日历和文档通过本机组件直连飞书。每位同事独立配置、独立授权，不经过原公司授权后台。").foregroundStyle(.secondary)
                Picker("连接用途", selection: $service.purpose) { ForEach(LocalFeishuPurpose.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).disabled(service.busy)
                if service.purpose == .receive { Text("只读取消息和免打扰状态，不发送消息、不修改已读。") }
                if service.purpose == .calendar { Text("读取本人主日历未来30天的日程，在岛上查看和设置个人提醒。日程内容与参与人在飞书中管理。") }
                if service.purpose == .archive { Text("仅用于主动选择的文档归档。旧版归档任务仍须核对原账号，授权本身不会上传材料。") }
                Picker("本机配置", selection: $service.selected) {
                    Text("请选择自己的配置").tag("")
                    ForEach(service.profiles) { Text($0.label).tag($0.id) }
                }.disabled(service.busy)
                HStack { Button("刷新配置") { Task { await service.refresh() } }; Button("首次配置…") { service.configure() } }.disabled(service.busy)
                Text("没有配置时，先在飞书官方页面创建应用；若公司限制创建，需要管理员协助。已有配置可直接选择，不会覆盖其他工具的配置。").font(.callout).foregroundStyle(.secondary)
                Divider()
                Text(service.feedback).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("local.feishu.feedback")
                if let url = service.authorizationURL {
                    HStack { if let qr { Image(nsImage: qr).interpolation(.none).frame(width: 150,height: 150) }; Link("打开飞书授权页面", destination: url) }
                }
                HStack {
                    Button("授权所选用途") { service.authorize() }.disabled(service.busy || service.selected.isEmpty)
                    Button("核对账号并连接") { service.connect() }.buttonStyle(.borderedProminent).disabled(service.busy || service.selected.isEmpty)
                    if service.busy { ProgressView().controlSize(.small); Button("取消") { service.cancel() } }
                }
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}
