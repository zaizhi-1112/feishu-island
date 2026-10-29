import AppKit
import SwiftUI
import NookApp
@testable import IslandShell

@MainActor func runBuild82RefinementChecks(check: (Bool, String) -> Void) async throws {
    let suite = "build82-refinement-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = FeishuStore(defaults: defaults, live: false, receivingDefault: true, headlessRenderer: true)
    func message(_ id: String, _ text: String) throws -> FeishuMessage {
        let content = String(decoding: try JSONSerialization.data(withJSONObject: ["text":text]), as: UTF8.self)
        return FeishuMessage(raw: ["message_id":id,"sender":["id":"ou_synthetic","sender_name":"合成同事"],"msg_type":"text","body":["content":content]], chatID: "oc_synthetic", chatName: "合成同事", chatKind: "p2p", ownID: "ou_self")
    }
    let first = try message("open-background", "只用于合成回调")
    check(first.chatURL?.query == "openChatId=oc_synthetic", "open conversation uses oc_ Open Chat ID instead of numeric client chatId")
    store.receive(first)
    store.launchConversation = { _, complete in DispatchQueue.global().async { complete(nil) } }
    store.open(first)
    for _ in 0..<100 where store.messages.first?.viewed != true { try await Task.sleep(for: .milliseconds(10)) }
    check(store.messages.first?.viewed == true && store.actionError == nil, "background AppKit success returns to main actor without crash")
    let failed = try message("open-failed", "失败时保留消息")
    store.receive(failed)
    store.launchConversation = { _, complete in DispatchQueue.global().async { complete("合成打开失败") } }
    store.open(failed)
    for _ in 0..<100 where store.actionError == nil { try await Task.sleep(for: .milliseconds(10)) }
    check(store.actionError == "合成打开失败" && store.messages.first(where: {$0.id == failed.id})?.viewed == false, "failed conversation launch keeps message unread in island")

    let longText = String(repeating: "长段消息保留完整文字与分段。\n第二段包含时间2027年1月2日。\n", count: 20)
    let long = try message("long-paged", longText)
    store.updateDanmu(.init(enabled:true))
    store.receive(long)
    let overlay = store.playback.overlay!
    overlay.tick(); overlay.tick()
    check(store.playback.accepted == 1 && store.playback.presented == 1, "long incoming message reaches desktop renderer")
    let card = overlay.flying.first!
    check(!card.card && card.motionPages.count > 1, "long message uses bounded moving segments")
    check(card.motionPages.joined() == long.danmuText.trimmingCharacters(in: .whitespacesAndNewlines), "paging preserves every paragraph and character")
    check(!overlay.window.isVisible && overlay.window.ignoresMouseEvents && !overlay.window.isOpaque && !overlay.window.canBecomeKey, "synthetic desktop reader stays hidden and transparent")
    store.playback.clear()

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("refined-schedule-"+UUID().uuidString)
    let workspace = WorkspaceStore(root:root,startTimers:false)
    let now=Date(), end=now.addingTimeInterval(2)
    let event=FeishuScheduleEvent(id:"synthetic-expiry",title:"合成日程",start:now,end:end,allDay:false)
    _=workspace.mutate { $0.feishuSchedule=FeishuScheduleState(accountKey:"fixture",events:[event]) }
    workspace.scheduleNow=now
    check(workspace.scheduleEvents.count==1,"ongoing event remains visible")
    workspace.tickFeishuSchedules(now:end)
    check(workspace.scheduleEvents.isEmpty,"event disappears at its end without manual sync")
    var cancelled=event;cancelled.status="cancelled"
    var state=FeishuScheduleState(accountKey:"fixture",events:[event])
    state.apply([cancelled],calendarID:"primary",now:now)
    check(state.events.isEmpty,"cancelled events do not survive a complete snapshot")

    for i in 0..<70 { let id=try workspace.addTodo(title:"合成完成记录 \(i)");workspace.complete(id,now:now) }
    let expanded=NSHostingView(rootView:TodoCompletionHistory(store:workspace,initiallyExpanded:true).frame(width:680))
    let collapsed=NSHostingView(rootView:TodoCompletionHistory(store:workspace).frame(width:680))
    expanded.layoutSubtreeIfNeeded();collapsed.layoutSubtreeIfNeeded()
    check(expanded.fittingSize.height<650 && collapsed.fittingSize.height<140,"completion history scrolls within bounded section and folds")
    check(workspace.todoHistory.count==70 && workspace.todoHistory.allSatisfy{$0.completedAt==now},"folding retains full dated completion history")
    check(HubCardPresentation.displayText("创建人：合成人\n创建时间：2026-10-29\n周计划\n1.完成材料。2.跟进2027年1月2日。") == "周计划\n1.完成材料。\n\n2.跟进2027年1月2日。", "card metadata hidden while planned dates and details remain")
    check(DanmuPaletteEditor.hex("aabbcc\n")=="#AABBCC" && DanmuPaletteEditor.hex("#AB")==nil,"copied colors normalize without accepting incomplete codes")
    let plan = HubCard(id:"plan",title:"工作计划 · 最新周报",kind:"report",text:"工作周报\n\n下周工作计划\n1.完成材料。2.跟进2027年1月2日。",href:nil)
    check(HubCardPresentation.title(plan) == "工作计划" && HubCardPresentation.text(plan) == "1.完成材料。\n\n2.跟进2027年1月2日。", "work plan has one heading while all plan text and dates remain")
    check(plan.text.hasPrefix("工作周报") && plan.title.hasSuffix("最新周报"), "display simplification never mutates the source report")
    for background in [false, true] {
        for border in [false, true] {
            let style: [String:Any] = ["bubble":"custom","foreground":"#FFFFFF","background":"#15171C","border":"#FFAA22","backgroundEnabled":background,"borderEnabled":border]
            check(AppearanceMCP.validate(style) != nil, "independent background/border choice validates \(background)/\(border)")
            let preview = FeishuDanmuPreviewView(frame:NSRect(x:0,y:0,width:600,height:100))
            preview.configure(style,playing:false,started:Date())
            check(preview.text.backdrop == background && (preview.text.borderColor != nil) == border, "native preview renders both visibility switches \(background)/\(border)")
            store.updateAppearance(style)
            store.playback.configure(.init(enabled:true),appearance:style)
            _ = store.playback.enqueue(try message("appearance-\(background)-\(border)","合成弹幕"),demo:true)
            store.playback.overlay?.tick(); store.playback.overlay?.tick()
            let flying = store.playback.overlay?.flying.first
            check(flying?.backdrop == background && (flying?.borderColor != nil) == border, "actual desktop renderer matches preview \(background)/\(border)")
            store.playback.clear()
        }
    }
    check(AppearanceMCP.validate(["backgroundEnabled":1]) == nil, "appearance flags reject numeric substitutes")
    check(AppearanceMCP.validate(["bubble":"custom","background":"#FFFFFF","foreground":"#FFFFFF"]) == nil, "visible backgrounds retain contrast validation")
    var hover=NookAppearancePreferences();hover.openOnHover = .immediately;hover.hoverDelay=1;hover.externalDisplayHoverDelay=2
    check(hover.hoverIntent.delay == .zero && hover.hoverIntent.externalDisplayDelay == nil,"complete expansion has no intentional hover delay on either display")
    hover.openOnHover = .peekFirst
    check(hover.hoverIntent.delay == .seconds(1),"peek-first retains the person's timing")
    check(CompanyConnection.Purpose.calendar.serviceKey=="schedule" && CompanyConnection.Purpose.calendar.scopes==LocalFeishuPurpose.calendar.scopes,"hosted and existing local calendars use the same readonly scope")
    try await runFastDiscoveryRegression(check:check)
}

@MainActor private func runFastDiscoveryRegression(check: (Bool,String)->Void) async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("fast-discovery-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let cli=root.appendingPathComponent("fixture-cli")
    let script = #"""
#!/usr/bin/python3
import sys,json,time
from pathlib import Path
args=sys.argv[1:]
if args[:1]==['--profile']:args=args[2:]
start=Path(__file__).with_name('start')
def out(data):print(json.dumps({'ok':True,'identity':'user','data':data}));sys.exit()
if args[:2]==['auth','status']:
 start.write_text(str(time.time()))
 print(json.dumps({'identities':{'user':{'available':True,'openId':'ou_self'}}}));sys.exit()
if '+chat-list' in args:
 if args[args.index('--page-size')+1]=='100':out({'chats':[]})
 ids=(['oc_new'] if time.time()-float(start.read_text())>.3 else [])+['oc_slow'+str(i) for i in range(6)]
 out({'chats':[{'chat_id':i,'chat_mode':'p2p','name':i} for i in ids]})
if '/open-apis/im/v1/messages/read_status' in args:
 out({'items':[{'message_id':'synthetic-new','is_read':False}]})
if '/open-apis/im/v1/messages' in args:
 p=json.loads(args[args.index('--params')+1])
 if p['container_id'].startswith('oc_slow'):time.sleep(.8);out({'items':[],'has_more':False})
 out({'items':[{'message_id':'synthetic-new','create_time':str(int(time.time()*1000)),'sender':{'id':'ou_other'},'body':{'content':json.dumps({'text':'合成新会话'})},'msg_type':'text'}],'has_more':False})
raise Exception('Unexpected synthetic invocation')
"""#
    try script.write(to:cli,atomically:true,encoding:.utf8)
    try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:cli.path)
    let reader=AccountReader(cli:cli,profile:"synthetic-fast",pollDelay:0.1,pageDelay:0,clock:ServerClock(probe:{.local()}))
    var received=false
    reader.onMessage={if $0.id=="synthetic-new"{received=true}}
    let began=Date();reader.start();defer{reader.stop()}
    while !received && Date().timeIntervalSince(began)<5 {try await Task.sleep(for:.milliseconds(20))}
    let elapsed=Date().timeIntervalSince(began)
    check(received && elapsed<2,"new active conversation bypasses a batch of six slow message reads")
    print(String(format:"Synthetic promoted-chat latency: %.2fs (six 0.8s slow conversations)",elapsed))
}
