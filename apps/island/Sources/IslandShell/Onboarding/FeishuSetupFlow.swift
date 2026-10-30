import Foundation

/// One user-initiated setup entry, three independently verified grants.
/// Existing OAuth services keep their own scopes and consent screens.
@MainActor final class FeishuSetupFlow: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var message = ""
    private var task: Task<Void, Never>?
    func start(feishu: FeishuStore, workspace: WorkspaceStore) {
        guard !active, feishu.allowsDirectoryLookup else { return }
        active = true
        task = Task { [weak self] in
            guard let self else { return }
            defer { active = false }
            do {
                if !feishu.canResumeSavedConnection {
                    message = "1 / 3 · 请在飞书确认消息读取"
                    feishu.openMessageConnection()
                    try await wait { feishu.canResumeSavedConnection }
                }
                if workspace.disk.feishuSchedule?.enabled != true || !workspace.scheduleAccountMatches {
                    message = "2 / 3 · 请在飞书确认日历读取"
                    CompanyConnection.shared.open(purpose: .calendar)
                    try await wait { workspace.disk.feishuSchedule?.enabled == true && workspace.scheduleAccountMatches }
                }
                if !workspace.hub.connected {
                    message = "3 / 3 · 请确认虚实中台连接"
                    guard let address = SettingsServer.shared.address else { throw WorkError.message("连接服务尚未就绪，请重新点击连接。") }
                    workspace.connectHub(callback: address + "/oauth/virxact/callback")
                    try await wait { workspace.hub.connected }
                }
                message = "飞书消息、日历和中台均已连接。"
            } catch is CancellationError { message = "已暂停；已完成的连接会保留。" }
            catch { message = error.localizedDescription }
        }
    }
    private func wait(_ complete: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(300)
        while !complete() {
            try Task.checkCancellation()
            guard Date() < deadline else { throw WorkError.message("这一步还未完成。确认授权后，点击连接继续。") }
            try await Task.sleep(for: .milliseconds(500))
        }
        try Task.checkCancellation()
    }
    func cancel() { task?.cancel() }
}
