import AppKit
import NookApp
import SwiftUI

struct HubShortcutRecorder: View {
    @ObservedObject var store: UnifiedPlatformStore
    @State private var recording = false
    @State private var monitor: Any?
    @State private var hint = ""
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("唤出快捷轮盘").font(.system(size: 14, weight: .medium))
                Text(hint.isEmpty ? "点击右侧修改，Esc取消。" : hint).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(recording ? "按下组合键…" : store.hotkey.display) { recording ? stop() : start() }
                .buttonStyle(IslandButtonStyle(prominent: recording)).frame(minWidth: 120)
                .accessibilityIdentifier("platform.hotkey.recorder")
        }
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
    }
    private func start() {
        guard !recording else { return }
        recording = true; hint = "请按包含⌘、⌥或⌃的组合键。"
        HubPingLauncher.shared.suspendForRecording()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            if let value = NookHotkey(event: event) {
                hint = store.setHotkey(value)
                    ? (store.registerHotkey == nil ? "已保存；当前未启用全局快捷键。" : "已保存，立即生效。")
                    : store.error
                stop()
            } else { hint = "需要同时按住⌘、⌥或⌃中的至少一个。" }
            return nil
        }
    }
    private func stop() {
        guard recording else { return }
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        recording = false; HubPingLauncher.shared.resumeAfterRecording()
    }
}
