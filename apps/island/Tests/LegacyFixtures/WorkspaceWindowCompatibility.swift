@testable import IslandShell
import Foundation

/// A normal work window. Automatic reminders never open or activate this window.
@MainActor final class WorkspaceWindow {
    static let shared = WorkspaceWindow()
    func open(store: WorkspaceStore) { show(store:store,page:store.boardTab) }
    func openSettings(store: WorkspaceStore) { show(store:store,page:4) }
    func openProcessing(store: WorkspaceStore) { show(store:store,page:3) }
    func openHub(store:WorkspaceStore) { show(store:store,page:2) }
    func openReminders(store: WorkspaceStore) { show(store:store,page:5) }
    func openAgents(store: WorkspaceStore) { show(store:store,page:7) }
    func openAgentStatus(store:WorkspaceStore) { show(store:store,page:9) }
    func openAgentConnections(store:WorkspaceStore) { show(store:store,page:8) }
    private func show(store: WorkspaceStore,page:Int) {
        let section = [0:"agents",1:"todos",2:"platform",3:"todos",4:"messages",5:"appearance",6:"appearance",7:"appearance",8:"agents",9:"agents"][page] ?? "messages"
        UnifiedSettingsWindow.shared.open(section: .resolve(section))
    }
}
