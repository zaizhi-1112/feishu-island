import AppKit
import SwiftUI
import NookApp
@testable import IslandShell

@MainActor func runIslandTextSizeChecks(check: (Bool, String) -> Void) async throws {
    check(IslandTextSize.scale(.nan) == 1 && IslandTextSize.scale(99) == 1, "invalid text preferences fall back to standard")
    let defaults = UserDefaults(suiteName: "island.text-check." + UUID().uuidString)!
    defaults.set(1.5, forKey: IslandTextSize.preferenceKey)
    check(IslandTextSize.scale(defaults.double(forKey: IslandTextSize.preferenceKey)) == 1.5, "text size preference persists")
    let text = String(repeating: "放大文字后，消息内容需要完整保留。", count: 35)
    let normal = IslandReadingPages.split(text, fontSize: 14)
    let large = IslandReadingPages.split(text, fontSize: 21)
    check(large.count > normal.count && large.joined() == text, "large text repaginates without losing content")
    guard IslandRuntime.isSkinPreview else { return }
    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/text-size-review")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let messages = FeishuStore(defaults: defaults, live: false, headlessRenderer: true)
    messages.loadDemo()
    let agents = AgentStore(defaults: defaults, allowsLiveReads: false)
    let now = Date().timeIntervalSince1970
    agents.previewQuotas([.init(id: "codex/primary", label: "周额度", remainingPercent: 57, resetsAt: now + 3600, updatedAt: now)])
    let workspace = WorkspaceStore.shared
    let prior = workspace.hub
    let disk = workspace.disk
    defer { workspace.hub = prior; _ = workspace.mutate { $0 = disk } }
    workspace.hub = HubSnapshot(connected: true, name: "合成", cards: [.init(id: "font-review", title: "工作计划", kind: "report", text: "今天确认活动安排。\n本周完成社群资料整理，核对所有待办。", href: nil)], readAt: Date())
    _ = workspace.mutate { $0.selectedCards = ["font-review"] }
    let components: [(String, AnyView)] = [
        ("messages", AnyView(FeishuView(store: messages))),
        ("agents", AnyView(AgentPanel(store: agents))),
        ("todos", AnyView(UnifiedTodoPanel(store: workspace))),
        ("platform", AnyView(UnifiedPlatformPanel(workspace: workspace)))
    ]
    for scale in [1.0, 1.25, 1.5] {
        for (name, content) in components {
            let theme = NookResolvedTheme.resolve(theme: IslandDesign.chrome, preferences: .init(chromePalette: .light), effectiveColorScheme: .light, reduceTransparency: true)
            let root = content.environment(\.islandTextScale, scale).font(.system(size: 13 * scale))
                .environment(\.nookResolvedTheme, theme).environment(\.nookSurfaceAnimationActive, false)
                .frame(width: 400).background(Color.white).preferredColorScheme(.light)
            let view = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 336), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = view
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            check(view.fittingSize.width <= 401 && !window.isVisible, "\(name) \(scale) fits island width without showing a window")
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(name)-\(scale).png"))
            }
            window.close()
        }
    }
}
