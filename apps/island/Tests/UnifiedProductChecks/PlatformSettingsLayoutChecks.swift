import AppKit
import NookApp
import SwiftUI
@testable import IslandShell

@MainActor
func runPlatformSettingsLayoutChecks(check: (Bool, String) -> Void) async throws {
    let ideal: [CGFloat] = [180, 210, 550, 130, 140, 720, 170]
    for width: CGFloat in [240, 532, 712] {
        let slots = HubCardOptionsLayout.slots(idealWidths: ideal, width: width)
        check(slots.count == ideal.count && slots.allSatisfy { $0.x >= 0 && $0.x + $0.width <= width }, "card controls stay inside viewport \(width)")
        check(zip(slots, slots.dropFirst()).allSatisfy { a, b in a.row < b.row || (a.row == b.row && a.x + a.width <= b.x) }, "card reading order and nonoverlap \(width)")
    }
    let slots = HubCardOptionsLayout.slots(idealWidths: ideal, width: 532)
    check(slots[0].row == slots[1].row && slots[0].x == 0 && slots[1].x > 0, "short card options share a row")
    check(slots[2].width == 532 && slots[2].row != slots[1].row && slots[2].row != slots[3].row, "long card option owns its row")
    guard let index = CommandLine.arguments.firstIndex(of: "--render-platform-settings") else { return }
    precondition(IslandRuntime.isSkinPreview)
    let output = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let workspace = WorkspaceStore.shared
    let priorHub = workspace.hub
    let priorDisk = workspace.disk
    defer { workspace.hub = priorHub; _ = workspace.mutate { $0 = priorDisk } }
    let titles = ["工作计划 · 最新周报", "选题池 · 当前进展", "我的 OKR · 目标与关键结果", "社群分析与数据资料", "申请与工作文档", "每天与隔日的工作提醒", "对比口径 · 当期累计对上期整期", "部门协作与近期需要跟进的事项和资料归档进展"]
    workspace.hub = HubSnapshot(connected: true, name: "合成体验", cards: titles.enumerated().map { .init(id: "layout-\($0.offset)", title: $0.element, kind: "report", text: "仅用于布局检查", href: nil) }, readAt: Date())
    _ = workspace.mutate { $0.selectedCards = ["layout-0", "layout-1"] }
    let appState = AppState()
    let previousAppearance = appState.appearancePreferences
    defer { appState.replaceAppearancePreferences(previousAppearance) }
    let model = UnifiedSettingsModel(); model.appState = appState; model.section = .platform
    for dark in [false, true] {
        var appearance = previousAppearance; appearance.chromePalette = dark ? .dark : .light
        appState.replaceAppearancePreferences(appearance)
        for width: CGFloat in [840, 1020] {
            let view = NSHostingView(rootView: UnifiedSettingsRoot(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 680), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua); window.contentView = view
            view.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(180))
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw WorkError.message("No settings bitmap") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("platform-\(Int(width))-\(dark ? "dark" : "light").png"))
            check(!window.isVisible, "platform settings rendered without showing a window")
            window.close()
        }
    }
}
