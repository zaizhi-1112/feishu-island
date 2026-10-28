import SwiftUI
import AppKit
@testable import IslandShell
import NookApp

var passed = 0
func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
    passed += 1
    print("PASS: \(name)")
}
typealias Display = NookScreenLocator.DisplayCandidate
let laptop = Display(uuid: "laptop", isBuiltIn: true)
let monitor = Display(uuid: "external", isBuiltIn: false)
let other = Display(uuid: "other", isBuiltIn: false)
func selected(_ preference: NookDisplayPreference, _ screens: [Display], _ main: Int? = 0) -> Int? {
    NookScreenLocator.resolveIndex(preference: preference, displays: screens, mainIndex: main)
}
expect(selected(.automatic, [laptop, monitor]) == 1, "external preferred even when laptop is main")
expect(selected(.automatic, [laptop]) == 0, "unplug falls back to laptop")
expect(selected(.automatic, [monitor, laptop]) == 0, "reconnect survives enumeration reorder")
expect(selected(.automatic, [monitor]) == 0, "clamshell external-only")
expect(selected(.automatic, [laptop, monitor, other], 2) == 2, "multiple externals prefer main external")
expect(selected(.automatic, [laptop, monitor, other], 0) == 1, "multiple externals with laptop main")
expect(selected(.automatic, []) == nil, "temporary empty screen list")
expect(selected(.automatic, [Display(uuid: nil, isBuiltIn: false)], 99) == 0, "virtual display without UUID")
expect(selected(.main, [monitor], -1) == 0, "invalid main index is safely ignored")
expect(selected(.specific("external"), [laptop, monitor]) == 1, "pinned stable UUID")
expect(selected(.specific("external"), [laptop]) == 0, "pinned screen disconnect fallback")
expect(selected(.specific("external"), [other, laptop, monitor]) == 2, "pinned screen reconnect")
expect(selected(.builtIn, [monitor]) == 0, "built-in preference in clamshell")
expect(NookPresentation.auto.isFloating(screenHasNotch: false), "non-notch floating layout")
expect(!NookPresentation.auto.isFloating(screenHasNotch: true), "notched built-in layout")
for hasNotch in [true, false] {
    let forms = NookPresentation.allCases.map { $0.resolvedForm(state: .expanded, edgeDocked: true, screenHasNotch: hasNotch) }
    expect(forms.allSatisfy { $0 == .floating }, "all expanded modes use the floating capsule geometry")
}
expect(NookPresentation.floating.resolvedForm(state: .compact, edgeDocked: true, screenHasNotch: true) == .floating,
       "hovered capsule retains floating compact form")
expect(NookPresentation.floating.resolvedForm(state: .expanded, edgeDocked: false, screenHasNotch: true) == .floating,
       "non-docked clients preserve floating behavior")
for presentation in NookPresentation.allCases {
    for notch in [true, false] {
        expect(presentation.resolvedForm(state: .compact, edgeDocked: true, screenHasNotch: notch, revealed: true) == .floating,
               "second-stage capsule is shared across all presentations and screens")
    }
    expect(presentation.resolvedForm(state: .compact, edgeDocked: true, screenHasNotch: false) == .floating,
           "external screens never invent a hardware notch")
}
expect(NookPresentation.notch.resolvedForm(state: .compact, edgeDocked: true, screenHasNotch: true) == .floating,
       "legacy notch preference now uses floating chrome on physical notches")
let encoded = try JSONEncoder().encode(NookDisplayPreference.automatic)
let decoded = try JSONDecoder().decode(NookDisplayPreference.self, from: encoded)
expect(decoded == .automatic, "automatic preference persistence")

let edge = NookEdgeDockLayout(state: .compact, hovering: false, contentHeight: 30,
                             shownTopInset: 4, physicalNotchHeight: 0)
expect(edge.isRetracted && edge.visibleHeight == 4, "idle draws only four-point edge")
expect(edge.contentOffset == -26 && edge.containerHeight == 4, "external pill retracts above screen")
expect(edge.hitRect(width: 96).contains(CGPoint(x: 48, y: 2)), "top edge remains reachable")
expect(!edge.hitRect(width: 96).contains(CGPoint(x: 48, y: 50)), "old pill location is not interactive while retracted")
let revealed = NookEdgeDockLayout(state: .compact, hovering: true, contentHeight: 30,
                                 shownTopInset: 4, physicalNotchHeight: 0)
expect(!revealed.isRetracted && revealed.contentOffset == 4, "revealed pill stays four points below screen edge")
expect(revealed.containerHeight == 34, "hover does not allocate expanded-panel height")
expect(revealed.hitRect(width: 96).contains(CGPoint(x: 48, y: 2)), "reveal retains the top-edge trigger")
expect(revealed.hitRect(width: 96).contains(CGPoint(x: 48, y: 3)), "pointer can cross the gap to the pill")
expect(revealed.hitRect(width: 96).contains(CGPoint(x: 48, y: 20)), "revealed pill can be clicked")
let notchedEdge = NookEdgeDockLayout(state: .compact, hovering: false, contentHeight: 32,
                                    shownTopInset: 36, physicalNotchHeight: 32)
expect(notchedEdge.visibleTop == 32 && notchedEdge.visibleHeight == 4, "hardware notch gets a lip immediately below it")
expect(notchedEdge.hitRect(width: 96).contains(CGPoint(x: 48, y: 34)), "notched lip is reachable below camera area")
let panel = NookEdgeDockLayout(state: .expanded, hovering: false, contentHeight: 300,
                              shownTopInset: 4, physicalNotchHeight: 0)
expect(!panel.isRetracted && panel.containerHeight == 304, "expanded panel preserves full content even without hover")
expect(panel.contentOffset == revealed.contentOffset, "revealed and expanded floating states share the top anchor")
let activity = NookEdgeDockLayout(state: .compact, hovering: false, peeking: true, contentHeight: 80,
                                 shownTopInset: 4, physicalNotchHeight: 0)
expect(!activity.isRetracted, "explicit activity peek stays visible")

var quotaActivity = NookLiveActivity(id:"quota-fixture",accessibilityLabel:"Synthetic quota") { Text("Codex") } compactTrailing: { Text("93%") } minimal: { Text("C") }
expect(!quotaActivity.keepsCompactVisible,"ordinary activities retain edge retraction")
quotaActivity.keepsCompactVisible=true
let quotaDock=NookNotchDockLayout(state:.compact,hovering:quotaActivity.keepsCompactVisible,notchSize:CGSize(width:179,height:32))
expect(!quotaDock.isRetracted,"quota activity reveals camera side slots without expanding")
quotaActivity.keepsCompactVisible=false
let hiddenQuotaDock=NookNotchDockLayout(state:.compact,hovering:quotaActivity.keepsCompactVisible,notchSize:CGSize(width:179,height:32))
expect(hiddenQuotaDock.isRetracted,"turning off quota restores retraction")

let hardware = CGSize(width: 179, height: 32)
let notchRest = NookNotchDockLayout(state: .compact, hovering: false, notchSize: hardware)
expect(notchRest.isRetracted && notchRest.frameWidth == 179 && notchRest.frameHeight == 32,
       "notch standby reserves only its invisible pointer target")
let notchReady = NookNotchDockLayout(state: .compact, hovering: true, notchSize: hardware)
expect(!notchReady.isRetracted && notchReady.frameHeight == nil && notchReady.frameWidth == nil,
       "notch ready state reveals natural side slots")
let notchPanel = NookNotchDockLayout(state: .expanded, hovering: false, notchSize: hardware)
expect(!notchPanel.isRetracted && notchPanel.frameHeight == nil,
       "notch expanded panel cannot be clipped to the 32-point trigger")
let notchActivity = NookNotchDockLayout(state: .compact, hovering: false, peeking: true, notchSize: hardware)
expect(!notchActivity.isRetracted && notchActivity.frameHeight == nil,
       "notch activity peek retains its full content height")

let stableHover = NookEdgeDockLayout(state: .expanded, hovering: true, contentHeight: 459, shownTopInset: 36, physicalNotchHeight: 32)
let stableRegions = stableHover.hitRects(width: 472, bridgeWidth: 150, physicalNotchHeight: 32)
expect(stableRegions.contains { $0.contains(CGPoint(x: 236, y: 34)) }, "original entry lip remains in the expanded hover bridge")
expect(!stableRegions.contains { $0.contains(CGPoint(x: 236, y: 15)) }, "floating island does not intercept menu bar above camera")
expect(!stableRegions.contains { $0.contains(CGPoint(x: 20, y: 34)) }, "hover bridge never widens across menu bar apps")
expect(stableRegions.contains { $0.contains(CGPoint(x: 20, y: 50)) }, "expanded content remains interactive below camera")
let retainedHover = stableHover.hoverRects(width: 472, bridgeWidth: 150, physicalNotchHeight: 32)
expect(retainedHover.contains { $0.contains(CGPoint(x: 236, y: 15)) }, "hover stays active over the hardware camera")
expect(retainedHover.contains { $0.contains(CGPoint(x: 236, y: 0)) }, "hover stays active at the top screen edge")
expect(!retainedHover.contains { $0.contains(CGPoint(x: 20, y: 15)) }, "hover retention excludes menu bar items beside the camera")


MainActor.assumeIsolated {
    let host = IslandHost.configuration()
    expect(host.preferenceDefaults.display == .automatic, "host automatic display default")
    expect(host.preferenceDefaults.appearance.presentation == .floating, "host floating-only layout default")
    expect(host.chromeBehavior.edgeDocked, "host enables three-stage edge interaction")
    expect(host.chromeBehavior.hoverIntent == nil && host.preferenceDefaults.appearance.openOnHover == .immediately, "hover behavior follows persistent user preference")
    let registry = host.makeRegistry()
    expect(registry.descriptors.count == 6, "four product modules and two isolated test modules")
    expect(registry.module(for: IslandHost.workspaceID) == nil, "legacy AI workspace is not registered")
    expect(registry.module(for: IslandHost.feishuID)?.makeConfiguration().onFileDrop == nil, "message module does not accept legacy materials")
    expect(!registry.isLoaded(IslandHost.sampleID), "sample module is lazy")
    let home = registry.context(for: IslandHost.homeID)!
    let sample = registry.context(for: IslandHost.sampleID)!
    expect(home.containerURL != sample.containerURL, "module files isolated")
    expect(home.defaults !== sample.defaults, "module preferences isolated")
    registry.unload(IslandHost.sampleID)
    expect(!registry.isLoaded(IslandHost.sampleID), "module unload")
    expect(registry.module(for: IslandHost.sampleID) != nil, "module reload")
    let suite = "local.youzi.island.check.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let state = SampleState(defaults: defaults)
    state.increment()
    state.increment()
    expect(SampleState(defaults: defaults).count == 2, "module data survives object reconstruction")
}
func fixture(_ id: String, kind: String = "group", mentions: [[String: Any]] = [], text: String = "hello", senderID: String = "ou_other", chatID: String = "oc_123") -> FeishuMessage {
    FeishuMessage(raw: ["message_id": id, "msg_type": "text", "sender": ["id": senderID, "id_type":"open_id", "sender_name": "同事"],
        "create_time": "1792300000000", "mentions": mentions,
        "body": ["content": String(data: try! JSONSerialization.data(withJSONObject: ["text": text]), encoding: .utf8)!]],
        chatID: chatID, chatName: "项目群", chatKind: kind, ownID: "ou_me")
}
let mine = fixture("mine", mentions: [["id": "ou_me", "id_type": "open_id", "key": "@_user_1", "name": "佑哥"]], text: "@_user_1 看一下")
let everyone = fixture("all", mentions: [["id": "all", "key": "@_all", "name": "所有人"]])
let sameName = fixture("other", mentions: [["id": "ou_other", "name": "佑哥"]])
expect(mine.mentionsMe && mine.text == "@佑哥 看一下", "mention ID identifies self and formats placeholder")
expect(!everyone.mentionsMe && !sameName.mentionsMe, "all/name match cannot impersonate direct mention")
expect(mine.isImportant(followed: []), "direct mention is important")
expect(fixture("dm", kind: "p2p").isImportant(followed: []), "private message is important")
expect(everyone.isImportant(followed: []) && everyone.reason == "@所有人", "all mention is important by default")
expect(!fixture("ordinary").isImportant(followed: []), "ordinary group stays quiet")
let tokenAll = FeishuMessage(raw: ["message_id":"token_all", "msg_type":"text", "body":["content":"{\"text\":\"<p>@_all 通知</p><p>下一行 &amp; 内容</p>\"}"]], chatID:"oc_123",chatName:"群",chatKind:"group",ownID:"ou_me")
expect(tokenAll.mentionsAll && tokenAll.text == "@所有人 通知\n下一行 & 内容", "missing mentions field uses exact token and strips edited HTML")
expect(!fixture("false_token", text: "@_alligator 和 @_all_123 和普通@所有人").mentionsAll, "similar token and ordinary label do not cause false all mention")
let richAll = FeishuMessage(raw: ["msg_type":"post", "body":["content": "{\"zh_cn\":{\"content\":[[{\"tag\":\"at\",\"user_id\":\"all\"},{\"tag\":\"text\",\"text\":\"通知\"}]]}}"]], chatID:"oc_123",chatName:"群",chatKind:"group",ownID:"ou_me")
expect(richAll.mentionsAll && richAll.text == "@所有人通知", "post all mention is identified and rendered")
var quietRules = FeishuReminderRules()
quietRules.mentionsAll = false
expect(!everyone.isImportant(followed: [], rules: quietRules), "all rule can be disabled")
expect(everyone.importanceReason(followed: ["oc_123"], rules: quietRules) == "关注", "enabled follow still applies with accurate label")
quietRules.mentionsMe = false; quietRules.directMessages = false; quietRules.followedChats = false
expect(!mine.isImportant(followed: [], rules: quietRules) && !fixture("quiet_dm", kind:"p2p").isImportant(followed: [], rules: quietRules), "each default rule is independently configurable")
expect(everyone.isImportant(followed: ["oc_123"]), "follow stable chat ID")
expect(mine.chatURL?.query == "chatId=oc_123", "official chat AppLink carries chat ID")
MainActor.assumeIsolated {
    let suite = "local.youzi.island.feishu.check.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = FeishuStore(defaults: defaults)
    store.receive(mine); store.receive(mine); store.receive(everyone)
    expect(store.messages.count == 2 && store.waitingCount == 2, "duplicate message cannot alert twice")
    store.markViewed(mine.id); store.markViewed(everyone.id)
    expect(store.waitingCount == 0 && store.messages.count == 2, "local viewing retains history")
    let now = Date()
    store.remindLater(mine.id, now: now)
    store.tick(now: now.addingTimeInterval(599))
    expect(store.waitingCount == 0, "snooze does not fire early")
    store.tick(now: now.addingTimeInterval(601))
    expect(store.waitingCount == 1, "snooze restores local pending state at deadline")
    store.remindLater(everyone.id, now: now)
    store.tick(now: now.addingTimeInterval(601))
    expect(store.important.contains { $0.id == everyone.id && $0.reason == "稍后" }, "manual reminder includes ordinary group at deadline")
    store.toggleMute(); store.receive(fixture("while_muted", kind: "p2p"))
    expect(store.isMuted && store.messages.count == 3, "mute keeps receiving")
    store.toggleFollow("oc_123")
    expect(FeishuStore(defaults: defaults).followed.contains("oc_123"), "follow survives restart")
    expect(FeishuStore(defaults: defaults).isMuted, "mute deadline survives restart")
    let muteDeadline = store.mutedUntil
    let revision = store.settingsRevision
    store.updateSettings(enabled: true, rules: quietRules)
    let restored = FeishuStore(defaults: defaults)
    expect(restored.rules == quietRules && restored.settingsRevision > revision, "web rules persist and revision changes")
    expect(store.mutedUntil == muteDeadline && restored.isMuted, "settings changes cannot clear mute")
    expect(store.important.contains { $0.id == mine.id }, "manual reminder survives all default rules disabled")
    expect(!store.important.contains { $0.id == "while_muted" }, "saved rules recompute important list")
    store.updateSettings(enabled: true, rules: .init())
    store.toggleReceiving(); store.receive(fixture("stopped"))
    expect(store.messages.count == 3 && !store.enabled, "stop ignores late messages")
    store.toggleReceiving()
    store.remindLater(mine.id)
    for i in 0..<110 { store.receive(fixture("bulk\(i)")) }
    expect(store.messages.count == 100, "recent list stays bounded")
    expect(store.messages.contains { $0.id == mine.id && $0.remindAt != nil }, "burst cannot evict scheduled reminder")
}
// Per-target rules use stable IDs and cannot override a block or the receiving gate.
let colleague = FeishuRuleTarget(id: "ou_other", name: "同事", detail: "项目组")
let team = FeishuRuleTarget(id: "oc_123", name: "项目群")
let ordinary = fixture("custom_ordinary")
var custom = FeishuCustomRules()
custom.groups = [.init(target: team, mode: .all)]
expect(ordinary.importanceReason(followed: [], custom: custom) == "群规则", "group all includes ordinary messages")
custom.groups[0].mode = .quiet
expect(!mine.isImportant(followed: ["oc_123"], custom: custom), "group quiet overrides mentions and followed default")
custom.people = [.init(target: colleague, mode: .all)]
expect(ordinary.importanceReason(followed: [], custom: custom) == nil, "explicit quiet keeps migrated conversation muted")
custom.groups[0].mode = .all; custom.people[0].mode = .quiet
expect(!mine.isImportant(followed: [], custom: custom), "person quiet overrides group all")
custom.people[0].mode = .mentions
expect(mine.isImportant(followed: [], rules: quietRules, custom: custom), "person mention mode is independent of defaults")
expect(everyone.isImportant(followed: [], custom: custom), "person mention mode includes all mention")
expect(!fixture("custom_private", kind:"p2p").isImportant(followed: [], custom: custom), "person mention mode suppresses unmentioned private message")
custom.people[0].mode = .all
custom.blockedGroups = [team]
expect(!mine.isImportant(followed: ["oc_123"], custom: custom), "blocked group wins over person and default rules")
var manual = mine; manual.reminded = true
expect(!manual.isImportant(followed: [], custom: custom), "block suppresses manual reminder too")
custom.blockedGroups = []; custom.blockedPeople = [colleague]
expect(custom.blocks(ordinary) && custom.blocks(fixture("blocked_dm",kind:"p2p",chatID:"oc_dm")), "blocked person applies in groups and private chats")
expect(!custom.blocks(fixture("same_name",senderID:"ou_someone_else")), "same display name cannot match blocked stable ID")
expect(custom.validationError == nil, "valid per-target policy accepted")
var invalidCustom = custom; invalidCustom.blockedGroups = [colleague]
expect(invalidCustom.validationError != nil, "person IDs cannot be saved as group IDs")
invalidCustom = custom; invalidCustom.people.append(invalidCustom.people[0])
expect(invalidCustom.validationError != nil, "duplicate per-person entries rejected")
let nestedSender = FeishuMessage(raw:["sender":["id":["open_id":"ou_other"]]],chatID:"oc_123",chatName:"群",chatKind:"group",ownID:"ou_me")
expect(nestedSender.senderID == "ou_other", "nested open ID is retained")
let wrongSenderType = FeishuMessage(raw:["sender":["id":"ou_other","id_type":"user_id"]],chatID:"oc_123",chatName:"群",chatKind:"group",ownID:"ou_me")
expect(wrongSenderType.senderID.isEmpty && !custom.blocks(wrongSenderType), "incompatible sender ID type cannot falsely match")
MainActor.assumeIsolated {
    let suite = "local.youzi.island.custom.check.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(try! JSONEncoder().encode(FeishuReminderRules()), forKey:"reminderRules")
    let store = FeishuStore(defaults: defaults)
    expect(store.customRules == FeishuCustomRules(), "legacy preferences migrate without changing defaults")
    store.receive(ordinary); store.toggleMute()
    let mute = store.mutedUntil
    store.updateSettings(enabled: true, rules: .init(), custom: custom)
    expect(store.visibleMessages.isEmpty && store.messages.count == 1, "block hides existing messages reversibly")
    store.receive(fixture("new_blocked"))
    expect(store.messages.count == 1, "new blocked messages cannot fill history or alert")
    let restored = FeishuStore(defaults: defaults)
    expect(restored.customRules == custom, "custom rules survive restart")
    expect(abs((restored.mutedUntil ?? .distantPast).timeIntervalSince(mute ?? .distantFuture)) < 0.001, "custom rules preserve mute deadline across restart")
    store.updateSettings(enabled: true, rules: quietRules)
    expect(store.customRules == custom, "older settings client preserves custom policy")
    custom.blockedPeople = []
    store.updateSettings(enabled: true, rules: quietRules, custom: custom)
    expect(store.visibleMessages.count == 1 && store.important.count == 1, "unblock restores existing history under person rule")
    store.toggleReceiving(); store.receive(fixture("custom_stopped"))
    expect(store.messages.count == 1 && !store.enabled, "person all cannot bypass stopped receiving")
    let before = store.customRules
    store.updateSettings(enabled: true, rules: .init(), custom: invalidCustom)
    expect(store.customRules == before && !store.enabled, "invalid custom settings make no partial changes")
}
print("\(passed) checks passed.")
