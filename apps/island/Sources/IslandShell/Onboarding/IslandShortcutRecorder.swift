import AppKit
import NookApp
import SwiftUI

struct IslandShortcutRecorder: View {
    @ObservedObject var appState: AppState
    @State private var recording = false
    @State private var monitor: Any?
    @State private var hint = "点击按钮，再按下你要使用的组合键。"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("展开或收起灵动岛", systemImage: "keyboard").font(.headline)
            Text("当前快捷键：" + appState.hotkey.displaySymbols.joined(separator: " ")).font(.system(size: 17, weight: .medium))
            Button(recording ? "请按下快捷键…" : "自定义快捷键") { recording ? stop() : start() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("island.shortcut.record")
            Text(hint).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let failure = appState.hotkeyRegistrationFailures["toggle"] {
                Text("这个快捷键被占用，请重新设置：" + failure.combination).font(.caption).foregroundStyle(.orange)
            }
        }
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
    }
    private func start() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.keyWindow?.makeKeyAndOrderFront(nil)
        recording = true; appState.isRecordingHotkey = true
        hint = "按住 Command、Option 或 Control，再按一个键。Esc 取消。"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            if let hotkey = NookHotkey(event: event) {
                appState.replaceHotkey(hotkey); hint = "已保存。之后可在设置中修改。"; stop()
            } else { hint = "请同时按住 Command、Option 或 Control；Esc 取消。" }
            return nil
        }
    }
    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        recording = false; appState.isRecordingHotkey = false
    }
}
