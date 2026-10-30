import AppKit
import Combine
import Sparkle
import SwiftUI

/// Official Sparkle UI validates Ed25519-signed releases before replacement.
/// It never installs in the background and receives no GitHub/account tokens.
@MainActor final class AppUpdater: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    static let shared = AppUpdater()
    @Published private(set) var canCheck = false
    @Published private(set) var automatic = true
    @Published private(set) var available = false
    private var controller: SPUStandardUpdaterController?
    private var observations: [AnyCancellable] = []
    private let windows = UpdateWindowPresenter()
    func start() {
        guard controller == nil, Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview", !IslandRuntime.isSkinPreview else { return }
        let value = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        controller = value
        available = true
        value.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).sink { [weak self] in self?.canCheck = $0 }.store(in: &observations)
        value.updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: RunLoop.main).sink { [weak self] in self?.automatic = $0 }.store(in: &observations)
    }
    func check() {
        start()
        guard let controller else { return }
        windows.beginManualSession()
        controller.checkForUpdates(nil)
        windows.presentExistingWindows()
    }
    func setAutomatic(_ value: Bool) { controller?.updater.automaticallyChecksForUpdates = value }

    nonisolated func standardUserDriverWillShowModalAlert() { MainActor.assumeIsolated { windows.expectModalAlert() } }
    nonisolated func standardUserDriverDidShowModalAlert() { MainActor.assumeIsolated { windows.didCloseModalAlert() } }
    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        MainActor.assumeIsolated { if state.userInitiated { windows.beginManualSession() } }
    }
    nonisolated func standardUserDriverWillFinishUpdateSession() { MainActor.assumeIsolated { windows.endSession() } }
}

struct AppUpdateControls: View {
    @ObservedObject private var updater = AppUpdater.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { updater.check() } label: { Label("检查更新", systemImage: "arrow.triangle.2.circlepath") }
                // Sparkle can refocus an already-open update or progress window.
                // Disabling this button during a session strands a hidden prompt.
                .buttonStyle(.plain).disabled(!updater.available).accessibilityIdentifier("island.checkUpdates")
            Toggle("发现新版时提醒", isOn: Binding(get: { updater.automatic }, set: updater.setAutomatic)).toggleStyle(.checkbox)
            Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.font(.system(size: 12)).padding(10).onAppear { updater.start() }
    }
}
