import AppKit
import NookApp
import SwiftUI
@testable import IslandShell
@testable import NookSurface
@testable import NookKit

/// Opt-in, synthetic-only native fixture for real pointer input. No account reader.
@MainActor private final class ButtonReviewState: ObservableObject {
    @Published var activeID = IslandHost.feishuID
    @Published var locked = true
    @Published var completed = 0
    var manualCloses = 0
    var lastManualCloseX: CGFloat?
    var clicks: [String: Int] = [:]
    var lockClicks = 0
    var onLock: (Bool) -> Void = { _ in }
    let modules = IslandHost.configuration().makeRegistry().descriptors.filter { IslandHost.moduleIDs.contains($0.id) }
    var overlay: Overlay?
    let output: URL
    init(output: URL) { self.output = output }
    var bar: NookTopBarContext {
        .init(title: "合成交互点验", isKeepOpen: locked,
              moduleSwitcher: .init(modules: modules, activeID: activeID, switchTo: { [weak self] id in
                  self?.activeID = id; self?.clicks[id, default: 0] += 1; self?.save()
              }), toggleKeepOpen: { [weak self] in
                  guard let self else { return }; self.locked.toggle(); self.lockClicks += 1
                  self.onLock(self.locked); self.save()
              })
    }
    func play() {
        if overlay == nil {
            let renderer = Overlay(showsWindow: true)
            // Moving messages own their small panels. Hide only the empty anchor
            // canvas so native accessibility tools can inspect the message panel.
            renderer.window.orderOut(nil)
            renderer.multilineMotion = true; renderer.fontSize = 28
            renderer.movementSpeed = 20; renderer.laneCount = 1; renderer.position = 1
            renderer.onFinished = { [weak self] _ in self?.completed += 1; self?.save() }
            overlay = renderer
        }
        overlay?.enqueue("合成交互点验 · 读完点 × 关闭", messageID: "synthetic-review-\(UUID().uuidString)")
        save()
    }
    func save() {
        let views = overlay?.flying ?? []
        let value: [String: Any] = [
            "synthetic": true, "activeID": activeID, "clicks": clicks,
            "locked": locked, "lockClicks": lockClicks, "completed": completed,
            "manualCloses": manualCloses, "lastManualCloseX": lastManualCloseX as Any? ?? NSNull(),
            "settingsVisible": NSApp.windows.contains { $0.identifier?.rawValue == "feibao.settings" && $0.isVisible },
            "settingsSection": UnifiedSettingsWindow.shared.model.section.rawValue,
            "visible": views.count, "queued": overlay?.queue.count ?? 0,
            "motion": views.map { view in ["x": view.position, "paused": view.motionPaused,
                "width": view.bounds.width, "window": view.motionPanel?.windowNumber ?? 0] as [String: Any] }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            try? data.write(to: output.appendingPathComponent("pointer-state.json"), options: .atomic)
        }
    }
}

@MainActor private struct ButtonReviewView: View {
    @ObservedObject var state: ButtonReviewState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            IntegrationTopBar(bar: state.bar)
            Divider()
            Text("合成交互点验").font(.system(size: 20, weight: .semibold))
            Text("只检查按钮和合成弹幕，不连接账号。").font(.system(size: 13))
            Text("当前栏目：\(state.activeID.split(separator: ".").last ?? "")").font(.system(size: 13))
            Button("播放合成弹幕") { state.play() }
                .buttonStyle(IslandButtonStyle()).accessibilityIdentifier("interaction.review.play")
            Text("已关闭：\(state.completed) 条").font(.system(size: 13))
        }.padding(12).frame(width: 424, height: 245, alignment: .topLeading).foregroundStyle(.white)
    }
}

@MainActor func showButtonInteractionReview() async throws {
    let bundled = Bundle.main.bundleIdentifier == "local.youzi.island.skin-preview" && Bundle.main.object(forInfoDictionaryKey: "ButtonInteractionReview") as? Bool == true
    let argument = CommandLine.arguments.firstIndex(of: "--button-interactions-review").flatMap { index in
        CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : nil
    }
    guard IslandRuntime.isSkinPreview, bundled || CommandLine.arguments.contains("--interactive"),
          let path = argument ?? (bundled ? Bundle.main.object(forInfoDictionaryKey: "ReviewOutputDirectory") as? String : nil)
    else { fatalError("Explicit isolated interactive review required") }
    NSApplication.shared.setActivationPolicy(.accessory)
    let output = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    NookPreferenceStorage.defaults = UserDefaults(suiteName: "island-button-review-" + UUID().uuidString)!
    let state = ButtonReviewState(output: output)
    if Bundle.main.object(forInfoDictionaryKey: "MotionOnlyReview") as? Bool == true {
        state.play()
        state.overlay?.onPresented = { [weak overlay = state.overlay] _ in
            guard let overlay, let view = overlay.flying.last else { return }
            view.position = overlay.window.frame.width * 0.52
            view.motionPanel?.title = "合成弹幕关闭点验"
            view.motionPanel?.setFrameOrigin(NSPoint(x: overlay.window.frame.minX + view.position,
                                                     y: overlay.window.frame.minY + view.motionY))
            let dismiss = view.motionDismiss
            view.motionDismiss = { [weak state, weak view] in
                state?.manualCloses += 1; state?.lastManualCloseX = view?.position
                dismiss?(); state?.save()
            }
        }
        let started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated {
                state.save()
                if ProcessInfo.processInfo.systemUptime - started > 180 { state.overlay?.clear(); NSApp.terminate(nil) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return
    }
    UnifiedSettingsWindow.shared.bind(appState: AppState())
    let theme = NookResolvedTheme.resolve(theme: IslandDesign.chrome, preferences: .init(chromePalette: .dark),
                                         effectiveColorScheme: .dark, reduceTransparency: true)
    let nook = Nook(hoverBehavior: []) {
        ButtonReviewView(state: state).environment(\.nookResolvedTheme, theme).preferredColorScheme(.dark)
    } compactLeading: { Text("合成") } compactTrailing: { Text("点击点验") }
    nook.edgeDocked = true; nook.presentation = .floating
    nook.hoverIntent = .init(action: .none); nook.staysExpandedOnHoverExit = true
    nook.backdrop = .solid(.black)
    state.onLock = { [weak nook] in nook?.staysExpandedOnHoverExit = $0 }
    await nook.expand(on: NSScreen.main)
    nook.configureWindow { $0.setAccessibilityIdentifier("interaction.review.island") }
    // Retain the fixture only for this explicit review; the process exits on its own.
    let started = ProcessInfo.processInfo.systemUptime
    let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
        MainActor.assumeIsolated {
            _ = nook.state; state.save()
            if ProcessInfo.processInfo.systemUptime - started > 600 { state.overlay?.clear(); NSApp.terminate(nil) }
        }
    }
    RunLoop.main.add(timer, forMode: .common)
    state.save()
}
