import AppKit
import SwiftUI
@testable import NookSurface

// Isolated native fixture: synthetic content, no account stores or preferences.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let folder = URL(fileURLWithPath: CommandLine.arguments[1])
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main!
    let nook = Nook {
        VStack(spacing: 16) {
            Text("飞书消息    Agent 状态    待办    中台")
            Text("展开布局验收 · 合成内容").font(.title2)
            Text("两种形态共用同一个展开区域")
        }.foregroundStyle(.white).frame(width: 520, height: 240)
    } compactLeading: { Text("Agent").foregroundStyle(.white) }
      compactTrailing: { Text("就绪").foregroundStyle(.white) }
    nook.edgeDocked = true
    nook.hoverIntent = NookHoverIntent(action: .none)
    nook.staysExpandedOnHoverExit = true
    Task { @MainActor in
        var frames: [CGRect] = []
        var report: [String: String] = ["physicalNotchHeight": String(describing: screen.safeAreaInsets.top)]
        func settle() async { try? await Task.sleep(for: .milliseconds(850)) }
        @MainActor func capture(_ name: String) {
            guard let view = nook.window?.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No window") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + ".png"))
        }
        for mode in [NookPresentation(rawValue: CommandLine.arguments[2])!] {
            nook.presentation = mode
            await nook.compact(on: screen)
            nook.configureWindow { $0.orderOut(nil) }
            if CommandLine.arguments.contains("--simulated-notch") {
                nook.updateScreenGeometry(notch: CGSize(width: 180, height: 32), physicalHeight: 32, menuHeight: 32)
                report["physicalNotchHeight"] = "32 (simulated)"
            }
            nook.setHoveringWithoutTransition(false)
            await settle()
            capture(mode.rawValue + "-rest")
            nook.setHoveringWithoutTransition(true)
            await settle()
            capture(mode.rawValue + "-hover")
            await nook.expand(on: screen)
            nook.configureWindow { $0.orderOut(nil) }
            await settle()
            frames.append(nook.chromeFrameInWindow)
            report[mode.rawValue] = NSStringFromRect(nook.chromeFrameInWindow)
            capture(mode.rawValue + "-expanded")
            nook.configureWindow { $0.orderOut(nil) }
        }

        report["result"] = "Native geometry captured"
        try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent(CommandLine.arguments[2] + "-result.json"))
        print(report)
        app.terminate(nil)
    }
    app.run()
}
