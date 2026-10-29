import AppKit
import SwiftUI
@testable import IslandShell

@MainActor func runLocalFeishuChecks(check: (Bool,String)->Void, renderTo: URL?) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("island-local-check-"+UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let suite = "island-local-check-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let cli = root.appendingPathComponent("fixture-cli")
    let mode = root.appendingPathComponent("mode")
    let record = root.appendingPathComponent("requests")
    let scopes = LocalFeishuPurpose.allCases.reduce(into: Set<String>()) { $0.formUnion($1.scopes) }.sorted().joined(separator: " ")
    let script = #"""
#!/usr/bin/python3
import os,sys,json,time,signal
from pathlib import Path
root=Path(__file__).parent
mode=(root/'mode').read_text() if (root/'mode').exists() else ''
args=sys.argv[1:]
if '--profile' in args:
    i=args.index('--profile'); profile=args[i+1]; args=args[:i]+args[i+2:]
else: profile=''
with (root/'requests').open('a') as f: f.write(json.dumps({'profile':profile,'args':args})+'\n')
assert os.environ.get('LARKSUITE_CLI_STRICT_MODE')=='user'
assert not os.environ.get('LARKSUITE_CLI_USER_ACCESS_TOKEN')
if mode=='oversized':
    sys.stdout.write('x'*4100000); sys.stdout.flush(); sys.exit()
if mode=='sleep':
    signal.signal(signal.SIGTERM,signal.SIG_IGN)
    time.sleep(20)
if args==['profile','list']:
    print(json.dumps([] if mode=='empty' else [{'name':'fixture-a','brand':'feishu','user':'合成甲'},{'name':'fixture-b','brand':'feishu','user':'合成乙'}])); sys.exit()
if args[:2]==['auth','login']:
    if mode=='login-fail': print(json.dumps({'ok':False}));sys.exit(1)
    if '--no-wait' in args:
        if mode=='late': time.sleep(.2)
        print(json.dumps({'device_code':'synthetic-device','verification_url':'https://accounts.feishu.cn/oauth/v1/device/verify?x=a%2Fb&y=1'}))
    else: print(json.dumps({'ok':True}))
    sys.exit()
if args[:2]==['auth','status']:
    print('synthetic diagnostic on stderr',file=sys.stderr)
    print(json.dumps({'verified':True,'appId':'cli_fixture','identities':{'user':{'available':True,'verified':True,'openId':'ou_other' if mode=='wrong' else 'ou_fixture','userName':'合成甲','scope':SCOPES}}}));sys.exit()
if args[:2]==['api','POST']:
    assert json.loads(sys.stdin.read())=={}
    print(json.dumps({'ok':True,'identity':'user','data':{'calendars':[{'user_id':'ou_fixture','calendar':{'type':'primary','role':'owner','calendar_id':'calendar_fixture'}}]}}));sys.exit()
print(json.dumps({'ok':True,'identity':'user','data':{}}))
"""#.replacingOccurrences(of: "SCOPES", with: String(data: try JSONSerialization.data(withJSONObject: scopes, options: .fragmentsAllowed), encoding: .utf8)!)
    try script.write(to: cli, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
    let account = LocalFeishuAccount(appID: "cli_fixture", openID: "ou_fixture", userName: "合成甲")
    let connection = FeishuConnection(cliPath: cli.path, profile: "fixture-a", localAccount: account)
    let service = LocalFeishuService(defaults: defaults, cliPath: cli.path)
    check(service.connection(.receive) == nil && service.connection(.calendar) == nil, "fresh Mac has no borrowed purpose binding")
    await service.refresh()
    check(service.profiles.count == 2 && service.selected.isEmpty, "fresh onboarding lists local profiles without auto-selecting another user")
    let verified = try await Task.detached { try LocalCLIJob.verified(connection, purpose: .calendar) }.value
    check(verified == account, "real process separates stderr diagnostics from auth JSON")
    try service.save(connection, purpose: .calendar)
    check(service.connection(.calendar) == connection && service.connection(.receive) == nil, "purpose activation is explicit and isolated")
    check(LocalFeishuBindings.connection(.calendar, defaults: defaults) == connection, "non-UI consumers restore identical local binding")
    let serialized = String(decoding: defaults.data(forKey: "island.local.calendar")!, as: UTF8.self)
    check(!serialized.contains("accessToken") && !serialized.contains("appSecret") && !serialized.contains("device_code"), "saved binding contains no credential")
    let primary = try await FeishuScheduleClient(localConnection: connection).primary()
    check(primary == "calendar_fixture", "calendar uses local CLI user API and verifies writable owner")
    try "wrong".write(to: mode, atomically: true, encoding: .utf8)
    let before = try String(contentsOf: record, encoding: .utf8).components(separatedBy: "\n").filter { $0.contains("api") }.count
    do { _ = try await FeishuScheduleClient(localConnection: connection).primary(); check(false, "wrong local account rejected") }
    catch { check(true, "changed CLI identity stops calendar before any business API") }
    let after = try String(contentsOf: record, encoding: .utf8).components(separatedBy: "\n").filter { $0.contains("api") }.count
    check(before == after, "wrong identity never reaches calendar API")
    try "".write(to: mode, atomically: true, encoding: .utf8)
    let url = "https://accounts.feishu.cn/oauth/v1/device/verify?x=a%2Fb&y=1"
    check(LocalFeishuService.setupURL("Open: " + url + "\n")?.absoluteString == url, "official setup URL is forwarded without rewriting")
    check(LocalFeishuService.setupURL("Open: " + url) == nil, "partial streamed URL is not opened early")
    for bad in ["https://accounts.feishu.cn.evil.test/a", "http://accounts.feishu.cn/a", "https://u@accounts.feishu.cn/a", "https://accounts.feishu.cn:444/a"] {
        check(LocalFeishuService.allowedAuthorizationURL(bad) == nil, "reject unsafe authorization destination")
    }
    service.selected = "fixture-a"; service.purpose = .receive
    var opened: [String] = []; service.openURL = { opened.append($0.absoluteString) }
    service.authorize()
    for _ in 0..<100 where service.busy { try await Task.sleep(for: .milliseconds(20)) }
    check(!service.busy && opened == [url] && service.feedback.contains("授权已完成"), "device authorization completes using exact local profile and native continuation")
    check(service.connection(.receive) == nil && service.authorizationURL == nil, "authorization alone neither enables receiving nor retains device link")
    service.purpose = .archive
    check(!service.feedback.contains("授权已完成") && service.feedback.contains("文档归档"), "purpose switch clears previous success state")
    service.selected = "fixture-b"
    check(service.feedback.contains("配置已选择") && !service.feedback.contains("已连接"), "profile switch clears previous connection status")
    service.purpose = .receive; service.selected = "fixture-a"

    // Exercise the exact settings-sheet flow against a process fixture. Keep
    // receiving off so no reader is started and no production defaults are used.
    defaults.set(try JSONEncoder().encode(connection), forKey: "connection")
    defaults.set(false, forKey: "enabled")
    let messageStore = FeishuStore(defaults: defaults, live: true, receivingDefault: false, headlessRenderer: true)
    messageStore.setConversation(.init(id: "oc_preserved", name: "合成已设会话", detail: "群聊"), mode: .quiet)
    let savedRules = messageStore.customRules
    let revision = service.messageConnectionRevision
    service.connectMessages(store: messageStore, authorize: true)
    for _ in 0..<200 where service.busy { try await Task.sleep(for: .milliseconds(20)) }
    check(service.messageConnectionRevision == revision + 1 && !service.busy, "message sheet completes verified reauthorization without a second connect step")
    check(!messageStore.enabled && messageStore.customRules == savedRules, "same-account reauthorization preserves stopped receiving and conversation rules")
    check(service.connection(.receive)?.localAccount == account, "message flow stores binding in its owning service")
    let beforeFailure = service.messageConnectionRevision
    try "login-fail".write(to: mode, atomically: true, encoding: .utf8)
    service.connectMessages(store: messageStore, authorize: true)
    for _ in 0..<200 where service.busy { try await Task.sleep(for: .milliseconds(20)) }
    check(service.messageConnectionRevision == beforeFailure && !service.feedback.contains("已连接"), "failed authorization never emits a connection success")
    check(!messageStore.enabled && messageStore.customRules == savedRules, "failed authorization keeps account preferences untouched")
    try "".write(to: mode, atomically: true, encoding: .utf8)

    let requests = try String(contentsOf: record, encoding: .utf8).split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String:Any] }
    let login = requests.first { ($0["args"] as? [String])?.contains("--no-wait") == true }
    let args = login?["args"] as? [String] ?? []
    let scopeIndex = args.firstIndex(of: "--scope")
    check(login?["profile"] as? String == "fixture-a" && scopeIndex != nil && Set(args[scopeIndex!+1].split(separator: " ").map(String.init)) == LocalFeishuPurpose.receive.scopes,
          "login requests only selected purpose scopes using explicit local profile")
    try "late".write(to: mode, atomically: true, encoding: .utf8)
    let openedBeforeCancel = opened.count
    service.authorize(); try await Task.sleep(for: .milliseconds(30)); service.cancel(); try await Task.sleep(for: .milliseconds(300))
    check(opened.count == openedBeforeCancel && !service.busy && service.authorizationURL == nil, "cancelled flow never opens late authorization URL")
    try "empty".write(to: mode, atomically: true, encoding: .utf8)
    await service.refresh()
    check(service.profiles.isEmpty && service.selected.isEmpty && service.feedback.contains("首次配置"), "empty CLI profile list gives actionable first-install setup")
    do { _ = try await Task.detached { try LocalCLIJob().run(FeishuConnection(cliPath: cli.path, profile: "company"), ["auth","status"]) }.value; check(false,"legacy company profile rejected") }
    catch { check(true, "legacy company profile cannot fall back to a company or arbitrary local account") }
    let unavailable = CompanyConnection(defaults: defaults, fetcher: { _, complete in complete(.failure(AccountFailure(detail: "合成服务不可用"))) })
    do { _ = try await Task.detached { try unavailable.prepare(.calendar) }.value; check(false, "unavailable broker rejected") }
    catch { check(!unavailable.isEnabled(.calendar), "failed hosted authorization does not activate a purpose") }
    try "oversized".write(to: mode, atomically: true, encoding: .utf8)
    do { _ = try await Task.detached { try LocalCLIJob().run(connection,["auth","status"]) }.value; check(false,"oversized helper output rejected") }
    catch { check((error as? AccountFailure)?.detail.contains("响应过大") == true, "oversized output drains and stops cleanly without racing stderr handles") }
    try "sleep".write(to: mode, atomically: true, encoding: .utf8)
    let job = LocalCLIJob(), start = Date()
    let pending = Task.detached { try job.run(connection,["auth","status"],timeout:20) }
    try await Task.sleep(for: .milliseconds(100)); job.cancel()
    do { _ = try await pending.value; check(false, "cancelled process must fail") } catch { check(Date().timeIntervalSince(start)<4, "cancellation terminates uncooperative helper within bounded time") }
    if let renderTo {
        try FileManager.default.createDirectory(at: renderTo, withIntermediateDirectories: true)
        for purpose in LocalFeishuPurpose.allCases {
            service.purpose = purpose
            for width in [480.0,560.0] {
                let view = NSHostingView(rootView: LocalFeishuConnectionView(service:service).frame(width:width,height:620))
                let window = NSWindow(contentRect: NSRect(x:0,y:0,width:width,height:620),styleMask:.borderless,backing:.buffered,defer:false)
                window.isReleasedWhenClosed=false; window.contentView=view
                view.layoutSubtreeIfNeeded(); try await Task.sleep(for:.milliseconds(80))
                let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
                view.cacheDisplay(in:view.bounds,to:bitmap)
                try bitmap.representation(using:.png,properties:[:])!.write(to:renderTo.appendingPathComponent(purpose.rawValue+"-\(Int(width)).png"))
                check(view.fittingSize.width <= width && !window.isVisible, "local authorization fits \(purpose.rawValue) at \(Int(width))")
                window.close()
            }
        }
    }
}
