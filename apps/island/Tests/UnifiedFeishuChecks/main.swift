import AppKit
import Foundation
import SwiftUI
@testable import IslandShell

@main
struct UnifiedFeishuChecks {
    @MainActor static func main() async {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        var total = 0, failures: [String] = []
        func check(_ condition: Bool, _ label: String) { total += 1; if !condition { failures.append(label) } }
        let suite = "local.feibao.unified-feishu-check." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        do {
            check(FeishuConnectionBootPolicy.shouldOffer(savedEnabled: nil, hasConnection: false), "fresh install offers authorization")
            check(!FeishuConnectionBootPolicy.shouldOffer(savedEnabled: false, hasConnection: false), "explicit pause preserved")
            check(!FeishuConnectionBootPolicy.shouldOffer(savedEnabled: true, hasConnection: false), "enabled installation does not reopen onboarding")
            check(!FeishuConnectionBootPolicy.shouldOffer(savedEnabled: nil, hasConnection: true), "saved connection restores without prompt")

            check(FeishuConnectionBootPolicy.needsAuthorization("连接失败：公司登录或飞书授权已失效"), "expired authorization prompts a native recovery")
            check(!FeishuConnectionBootPolicy.needsAuthorization("快查暂缓：接口未有效返回"), "network failure does not reopen login")
            check(!FeishuConnectionBootPolicy.needsAuthorization("账号接收中"), "healthy receiver has no login prompt")

            var old = FeishuCustomRules()
            old.groups = [.init(target: .init(id: "oc_legacy_group", name: "旧群规则"), mode: .mentions)]
            old.people = [.init(target: .init(id: "ou_muted", name: "旧联系人"), mode: .all)]
            old.blockedPeople = [.init(id: "ou_muted", name: "旧联系人")]
            old.blockedGroups = [.init(id: "oc_muted", name: "旧静音群")]
            var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
            legacyJSON.removeValue(forKey: "conversations")
            defaults.set(try JSONSerialization.data(withJSONObject: legacyJSON), forKey: "customRules")
            defaults.set(["oc_muted", "oc_followed"], forKey: "followed")
            defaults.set(false, forKey: "enabled")
            let store = FeishuStore(defaults: defaults, live: false, receivingDefault: false, headlessRenderer: true)
            check(store.followed.isEmpty, "old followed state consolidated")
            check(!store.rules.followedChats, "legacy followed branch disabled")
            check(store.customRules.blockedPeople.isEmpty && store.customRules.blockedGroups.isEmpty, "no separate block list after migration")
            check(store.customRules.groups.isEmpty, "legacy groups consolidated")
            check(store.customRules.people.first?.mode == .quiet, "blocked person migrates to quiet")
            check(store.customRules.conversations.first(where: { $0.id == "oc_muted" })?.mode == .quiet, "quiet wins over former follow")
            check(store.customRules.conversations.first(where: { $0.id == "oc_followed" })?.mode == .all, "former followed reminder retained")
            check(store.customRules.conversations.first(where: { $0.id == "oc_legacy_group" })?.mode == .mentions, "legacy group reminder retained")
            check(store.customRules.validationError == nil, "migrated configuration validates")
            let reloaded = FeishuStore(defaults: defaults, live: false, receivingDefault: true, headlessRenderer: true)
            check(reloaded.customRules == store.customRules && !reloaded.enabled, "rules and user pause survive restart")
            reloaded.beginAutomaticConnectionIfNeeded()
            check(!reloaded.connecting, "synthetic mode never opens authorization")

            let corruptSuite = "local.feibao.corrupt-rules-check." + UUID().uuidString
            let corruptDefaults = UserDefaults(suiteName: corruptSuite)!
            defer { corruptDefaults.removePersistentDomain(forName: corruptSuite) }
            let broken = Data("{broken-original-json".utf8)
            let originalRules = try JSONEncoder().encode(FeishuReminderRules())
            corruptDefaults.set(originalRules, forKey: "reminderRules")
            corruptDefaults.set(broken, forKey: "customRules")
            corruptDefaults.set(true, forKey: "enabled")
            let damaged = FeishuStore(defaults: corruptDefaults, live: false, headlessRenderer: true)
            check(!damaged.rulesConfigurationReadable && !damaged.enabled, "unreadable rules suspend in-memory reception")
            check(corruptDefaults.data(forKey: "customRules") == broken && corruptDefaults.data(forKey: "reminderRules") == originalRules, "bad custom JSON and good companion rules preserved byte-for-byte")
            check(corruptDefaults.bool(forKey: "enabled") && !corruptDefaults.bool(forKey: "unifiedConversationsV1"), "bad-rule startup does not overwrite preference or mark migration complete")
            damaged.toggleReceiving(); damaged.updateSettings(enabled: true, rules: .init(), custom: .init())
            check(!damaged.enabled && corruptDefaults.data(forKey: "customRules") == broken, "bad-rule UI cannot silently overwrite originals")
            corruptDefaults.set(try JSONEncoder().encode(FeishuCustomRules()), forKey: "customRules")
            corruptDefaults.set(broken, forKey: "reminderRules")
            let damagedDefaults = FeishuStore(defaults: corruptDefaults, live: false, headlessRenderer: true)
            check(!damagedDefaults.rulesConfigurationReadable && corruptDefaults.data(forKey: "reminderRules") == broken, "bad default-rule JSON also retained")
            corruptDefaults.set("unexpected-type", forKey: "customRules")
            let wrongType = FeishuStore(defaults: corruptDefaults, live: false, headlessRenderer: true)
            check(!wrongType.rulesConfigurationReadable && corruptDefaults.string(forKey: "customRules") == "unexpected-type", "wrong stored type is not treated as a new installation")

            let accountA = CompanyConnection.conversationStorageKey(userID: "synthetic-user-a", openID: "ou_synthetic_a")
            let accountB = CompanyConnection.conversationStorageKey(userID: "synthetic-user-b", openID: "ou_synthetic_b")
            check(accountA != accountB && accountA.count == 64, "per-account rule key is a stable identity digest")
            let originalCustom = store.customRules
            store.saveConversationSnapshot(key: accountA)
            store.updateSettings(enabled: false, rules: store.rules, custom: .init())
            store.restoreConversationSnapshot(key: accountB)
            check(store.customRules == FeishuCustomRules(), "another account never inherits old conversation rules")
            store.restoreConversationSnapshot(key: accountA)
            check(store.customRules == originalCustom, "returning account restores its own conversation rules")
            let snapshotReload = FeishuStore(defaults: defaults, live: false, headlessRenderer: true)
            snapshotReload.updateSettings(enabled: false, rules: snapshotReload.rules, custom: .init())
            snapshotReload.restoreConversationSnapshot(key: accountA)
            check(snapshotReload.customRules == originalCustom, "account rule snapshot survives application restart")

            let privateChat = FeishuRuleTarget(id: "oc_private", name: "合成私聊", detail: "私聊")
            store.setConversation(privateChat, mode: .quiet)
            func message(_ id: String, sender: String = "ou_example", chat: String = "oc_private", kind: String = "p2p") -> FeishuMessage {
                FeishuMessage(raw: ["message_id": id, "sender": ["id": sender, "sender_name": "合成发送者"], "msg_type": "text", "body": ["content": "{\"text\":\"合成消息，仅用于本机验证。\"}"]], chatID: chat, chatName: "合成会话", chatKind: kind, ownID: "ou_me")
            }
            store.updateSettings(enabled: true, rules: store.rules)
            store.updateDanmu(.init(enabled: true))
            store.receive(message("quiet-one"))
            check(store.messages.count == 1 && store.playback.accepted == 0, "quiet retains recent message without notification")
            store.setConversation(privateChat, mode: .all)
            store.receive(message("show-one")); store.receive(message("show-one"))
            check(store.messages.count == 2 && store.playback.accepted == 1, "one event not duplicated")
            store.setConversation(privateChat, mode: nil)
            check(!store.conversationRules.contains(where: { $0.id == privateChat.id }), "follow-default removes custom rule")
            store.receive(message("blocked-person", sender: "ou_muted", chat: "oc_followed", kind: "group"))
            check(store.playback.accepted == 1, "migrated quiet person remains quiet in loud conversation")

            var appearance = AppearanceMCP.defaults
            appearance["speed"] = 170; appearance["fontSize"] = 36; appearance["bubble"] = "dark"
            appearance["foreground"] = "#FFFFFF"; appearance["background"] = "#15171C"
            check(store.updateAppearance(appearance), "appearance accepts safe style")
            check(store.playback.overlay?.movementSpeed == 170 && store.playback.overlay?.fontSize == 36, "renderer receives exact speed and font size")
            check(store.playback.overlay?.backdrop == true, "bubble reaches renderer")
            var lightOnDarkName = appearance
            lightOnDarkName["background"] = "#FFFFFF"; lightOnDarkName["foreground"] = "#18202A"
            check(store.updateAppearance(lightOnDarkName), "safe imported palette accepted")
            check(store.playback.overlay?.skinBackground?.usingColorSpace(.sRGB)?.redComponent == 1, "renderer honors validated color pair rather than overriding background")
            _ = store.updateAppearance(appearance)
            check(store.playback.overlay?.window.isVisible == false && store.playback.overlay?.window.ignoresMouseEvents == true, "hidden renderer remains pass-through")
            appearance["speed"] = 0
            check(!store.updateAppearance(appearance), "zero speed rejected")
            appearance["speed"] = 250
            check(!store.updateAppearance(appearance), "unbounded speed rejected")
            appearance["speed"] = 170; appearance["foreground"] = "#15171C"
            check(!store.updateAppearance(appearance), "illegible color pair rejected")
            appearance["foreground"] = "#FFFFFF"; appearance["script"] = "alert(1)"
            check(!store.updateAppearance(appearance), "unknown style fields rejected")
            var oldAppearance = AppearanceMCP.defaults
            oldAppearance.removeValue(forKey: "speed"); oldAppearance.removeValue(forKey: "bubble")
            let upgraded = AppearanceMCP.validate(oldAppearance)
            check(upgraded?["speed"] as? Int == 100 && upgraded?["bubble"] as? String == "none", "old appearances gain compatible defaults")
            let restored = FeishuStore(defaults: defaults, live: false, headlessRenderer: true)
            check(restored.appearance["speed"] as? Int == 170 && restored.appearance["bubble"] as? String == "dark", "appearance persists after reopen")

            let page = try FeishuDirectory.conversationPage(["chats": [
                ["chat_id": "oc_person", "chat_mode": "p2p", "name": "合成私聊"],
                ["chat_id": "oc_group", "chat_mode": "group", "name": "合成群聊"],
                ["chat_id": "oc_topic", "chat_mode": "topic", "name": "合成话题群"],
                ["chat_id": "oc_group", "chat_mode": "group", "name": "重复项"],
                ["chat_id": "not-a-chat", "chat_mode": "p2p", "name": "错误 ID"]
            ], "has_more": true, "page_token": "next"])
            check(page.items.count == 3 && page.items[0].detail == "私聊" && page.items[1].detail == "群聊", "one picker includes all supported conversation kinds")
            check(page.hasMore && page.pageToken == "next", "conversation cursor retained")
            do { _ = try FeishuDirectory.conversationPage(["chats": [], "has_more": true]); check(false, "missing pagination rejected") }
            catch { check(true, "missing pagination rejected") }
            var invalid = store.customRules
            invalid.conversations = [.init(target: .init(id: "file_bad", name: "错误目标"), mode: .all)]
            check(invalid.validationError != nil, "only stable chat IDs accepted")

            // Rendering is limited to an off-screen native settings window and synthetic stores.
            let view = ScrollView { UnifiedFeishuSettings(store: store).padding(24) }.frame(width: 760, height: 680)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host; window.isReleasedWhenClosed = false
            host.layoutSubtreeIfNeeded()
            check(!window.isVisible && host.fittingSize.width <= 780, "native settings layout stays hidden and fits")
            window.close()
        } catch { failures.append("Unexpected synthetic test error: \(error)") }
        if failures.isEmpty { print("PASS: \(total) unified Feishu assertions; no account calls or visible windows") }
        else { print("FAIL: " + failures.joined(separator: "; ")); exit(1) }
    }
}
