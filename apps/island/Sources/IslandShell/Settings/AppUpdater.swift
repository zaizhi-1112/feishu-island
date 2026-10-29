import AppKit
import Combine
import Sparkle
import SwiftUI

/// Official Sparkle UI validates Ed25519-signed releases before replacement.
/// It never installs in the background and receives no GitHub/account tokens.
@MainActor final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    @Published private(set) var canCheck = false
    @Published private(set) var automatic = true
    private var controller: SPUStandardUpdaterController?
    private var observations: [AnyCancellable] = []
    func start() {
        guard controller == nil, Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview", !IslandRuntime.isSkinPreview else { return }
        let value = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller = value
        value.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).sink { [weak self] in self?.canCheck = $0 }.store(in: &observations)
        value.updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: RunLoop.main).sink { [weak self] in self?.automatic = $0 }.store(in: &observations)
    }
    func check() { start(); controller?.checkForUpdates(nil) }
    func setAutomatic(_ value: Bool) { controller?.updater.automaticallyChecksForUpdates = value }
}

struct AppUpdateControls: View {
    @ObservedObject private var updater = AppUpdater.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { updater.check() } label: { Label("检查更新", systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(.plain).disabled(!updater.canCheck).accessibilityIdentifier("island.checkUpdates")
            Toggle("发现新版时提醒", isOn: Binding(get: { updater.automatic }, set: updater.setAutomatic)).toggleStyle(.checkbox)
            Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.font(.system(size: 12)).padding(10).onAppear { updater.start() }
    }
}
