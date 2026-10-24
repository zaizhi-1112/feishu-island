import Combine
import NookApp
import SwiftUI

/// Persistent navigation hints, independent of the short-lived capsule alerts.
@MainActor
final class IslandModuleAttention: ObservableObject {
    static let shared = IslandModuleAttention()
    @Published private(set) var hints: [String: String] = [:]
    private weak var coordinator: AppCoordinator?
    private weak var feishu: FeishuStore?
    private let agents: AgentStore
    private let todos: TodoStore?
    private let workspace: WorkspaceStore
    private var subscriptions = Set<AnyCancellable>()
    private var acknowledged: [String: Set<String>] = [:]

    init(agents: AgentStore? = nil, todos: TodoStore? = nil, feishu: FeishuStore? = nil) {
        self.agents = agents ?? .shared; self.todos = todos; self.workspace = .shared
        self.feishu = feishu
    }

    func attach(_ coordinator: AppCoordinator) {
        guard self.coordinator == nil else { return }
        self.coordinator = coordinator
        feishu = (coordinator.moduleHost.registry.module(for: IslandHost.feishuID) as? FeishuModule)?.store
        let publishers = [agents.objectWillChange, workspace.objectWillChange] + (todos.map { [$0.objectWillChange] } ?? []) + (feishu.map { [$0.objectWillChange] } ?? [])
        for publisher in publishers {
            publisher.sink { [weak self] _ in
                // objectWillChange arrives before the new value is committed.
                Task { @MainActor [weak self] in self?.refresh() }
            }.store(in: &subscriptions)
        }
        refresh()
    }

    func refresh() {
        let events = currentEvents()
        for moduleID in [IslandHost.feishuID, IslandHost.agentID, IslandHost.todoID, IslandHost.workspaceID] {
            acknowledged[moduleID, default: []].formIntersection(Set(events[moduleID, default: [:]].keys))
        }
        let next = Self.makeHints(events: events, acknowledged: acknowledged)
        if hints != next { hints = next }
    }

    func acknowledge(_ moduleID: String) {
        let events = currentEvents()
        acknowledged[moduleID, default: []].formUnion(events[moduleID, default: [:]].keys)
        if moduleID == IslandHost.agentID { agents.acknowledgeCompletions() }
        refresh()
    }

    private func currentEvents() -> [String:[String:String]] {
        var result=Self.events(feishu:feishu,agents:agents,todos:todos)
        for item in workspace.disk.items where item.archivedAt == nil && item.state != "done" {
            if item.state == "succeeded" || (item.due.map{$0 <= Date()} ?? false) {
                result[IslandHost.workspaceID,default:[:]][item.id.uuidString+":"+item.state]="任务待查看"
            }
        }
        return result
    }
    static func hints(feishu: FeishuStore?, agents: AgentStore, todos: TodoStore,
                      acknowledged: [String: Set<String>] = [:]) -> [String: String] {
        makeHints(events:events(feishu:feishu,agents:agents,todos:todos),acknowledged:acknowledged)
    }
    private static func makeHints(events:[String:[String:String]], acknowledged:[String:Set<String>]) -> [String:String] {
        var result: [String: String] = [:]
        for (module, entries) in events {
            let pending = entries.filter { !(acknowledged[module] ?? []).contains($0.key) }
            guard !pending.isEmpty else { continue }
            if module == IslandHost.feishuID { result[module] = "\(pending.count)条新消息待查看" }
            else if module == IslandHost.todoID { result[module] = "\(pending.count)项新到期待办" }
            else { result[module] = pending.sorted { $0.key < $1.key }.map(\.value).joined(separator: "；") }
        }
        return result
    }

    private static func events(feishu: FeishuStore?, agents: AgentStore, todos: TodoStore?) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        if let feishu, feishu.enabled {
            for message in feishu.important where !message.viewed && message.remindAt == nil {
                result[IslandHost.feishuID, default: [:]][message.id + ":\(message.reminded)"] = "新消息"
            }
        }
        for alert in agents.lowQuotaAlerts { result[IslandHost.agentID, default: [:]][alert.id] = alert.message }
        if agents.preferences.enabled, agents.preferences.completionAlerts,
           !agents.unviewedCompletionProfiles.isDisjoint(with: Set(agents.preferences.visibleIDs)) {
            for profile in agents.preferences.visibleProfiles where agents.unviewedCompletionProfiles.contains(profile.id) {
                result[IslandHost.agentID, default: [:]]["completion:\(profile.id)"] = "\(profile.name)有已完成任务待查看"
            }
        }
        for item in todos?.pending ?? [] where item.dueAt.map({ $0 <= Date() }) == true {
            result[IslandHost.todoID, default: [:]][item.id + ":\(item.dueAt!.timeIntervalSince1970)"] = "待办已到期"
        }
        return result
    }
}

/// A navigation hint means new information, not a permanent unresolved-state light.
/// The source message, quota warning and todo remain intact after a visit.
struct IslandReadingModule: ViewModifier {
    let moduleID: String
    @ObservedObject private var attention = IslandModuleAttention.shared
    @State private var isReading = false
    func body(content: Content) -> some View {
        content.onAppear { isReading = true; attention.acknowledge(moduleID) }
            .onDisappear { isReading = false }
            .onReceive(attention.$hints) { hints in
                guard hints[moduleID] != nil else { return }
                Task { @MainActor in
                    guard isReading else { return }
                    attention.acknowledge(moduleID)
                }
            }
    }
}
