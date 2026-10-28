import AppKit
import SwiftUI
import NookApp
@testable import IslandShell

@MainActor func runDeepSeekChecks(check: (Bool, String) -> Void) throws {
    let fresh = AgentPreferences()
    check(fresh.profiles.contains { $0.id == "deepseek" && $0.name == "DeepSeek Harness" }, "Harness is a default supported tool")
    check(!fresh.activeMonitorIDs.contains("deepseek"), "new support never silently enables another account read")
    var old = fresh; old.profiles.removeAll { $0.id == "deepseek" }; old.skinID = "claude"
    let migrated = try JSONDecoder().decode(AgentPreferences.self, from: JSONEncoder().encode(old))
    check(migrated.visibleIDs == old.visibleIDs && migrated.activeMonitorIDs == old.activeMonitorIDs && migrated.skinID == "claude", "Harness migration preserves display, monitoring, and theme choices")
    check(migrated.profiles.filter { $0.id == "deepseek" }.count == 1 && migrated.validationError == nil, "legacy preferences gain one valid Harness entry")
    let now = Date().timeIntervalSince1970
    let metric = AgentMetric(id: "balance-CNY", label: "账户余额", value: 42.38, unit: "元", updatedAt: now)
    let bytes = try JSONSerialization.data(withJSONObject: ["ok": true, "metrics": [["id":metric.id,"label":metric.label,"value":metric.value,"unit":metric.unit,"updatedAt":now]]])
    let snapshot = try DeepSeekReader.parse(bytes)
    check(snapshot.metrics.count == 1 && snapshot.quotas.isEmpty && snapshot.sessions.isEmpty, "wallet is a measured amount, never a made-up percentage or task")
    check(snapshot.metrics[0].value == 42.38 && snapshot.metrics[0].unit == "元", "wallet amount and currency survive native decoding")
    for (value, expected) in [(0.0, "0.00"), (0.004, "<0.01"), (-0.004, "-0.01"), (42.389, "42.38"), (-42.381, "-42.38")] {
        let amount = AgentMetric(id: "balance-CNY", label: "余额", value: value, unit: "元", updatedAt: now)
        check(amount.displayNumber == expected, "money formatting keeps cents and distinguishes a sub-cent positive balance")
    }
    for response in ["{\"ok\":true,\"metrics\":[]}", "{\"ok\":false,\"error\":\"login\"}", "{\"ok\":false,\"error\":\"network\"}"] {
        do { _ = try DeepSeekReader.parse(Data(response.utf8)); check(false, "missing balances rejected") }
        catch { check(!error.localizedDescription.contains("synthetic-grant"), "wallet failures stay generic and never become zero") }
    }
    check(AgentSkin(agentID: "deepseek").accentHex == "#4D6BFE", "Harness card uses verified DeepSeek official blue")
    check(SkinResources.images["deepseek-icon.ico"] != nil, "official whale icon loads natively")
    let defaults = UserDefaults(suiteName: "island.deepseek.synthetic." + UUID().uuidString)!
    let store = AgentStore(defaults: defaults, allowsLiveReads: false)
    var prefs = store.preferences; prefs.enabled = true; prefs.monitoredIDs = ["deepseek"]
    prefs.visibleIDs = ["deepseek"]; prefs.primaryID = "deepseek"; prefs.skinID = "deepseek"
    try store.update(prefs); store.ingestSnapshots(["deepseek": snapshot], now: now)
    check(store.primarySnapshot.metrics.first?.value == 42.38 && store.primarySnapshot.sessions.isEmpty, "balance integrates into native Agent snapshots without task monitoring")
    let summary = AgentQuotaCompactSummary(quotas: [], refreshing: false, now: now, agentID: "deepseek", state: .unknown, displayName: "DeepSeek Harness", metrics: [metric])
    check(summary.text(leading: false).contains("42.38元"), "compact island shows the balance amount")
    if let index = CommandLine.arguments.firstIndex(of: "--render"), CommandLine.arguments.indices.contains(index + 1) {
        let folder = URL(fileURLWithPath: CommandLine.arguments[index + 1]); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for dark in [false, true] {
            let theme = NookResolvedTheme.resolve(theme: store.selectedSkin.theme, preferences: .init(chromePalette: dark ? .dark : .light), effectiveColorScheme: dark ? .dark : .light, reduceTransparency: true)
            let root = AgentToolCard(store: store, profile: store.primary, mode: "show", setMode: { _ in }, setup: {}, open: {})
                .padding(16).frame(width: 340, height: 350).environment(\.nookResolvedTheme, theme)
                .foregroundStyle(theme.primaryLabel).tint(theme.accent).preferredColorScheme(dark ? .dark : .light)
            let view = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 340, height: 350), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view; view.layoutSubtreeIfNeeded()
            check(!window.isVisible && view.fittingSize.width <= 341, "Harness fixture stays hidden and fits a settings column")
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(dark ? "deepseek-dark.png" : "deepseek-light.png"))
            }
        }
    }
}
