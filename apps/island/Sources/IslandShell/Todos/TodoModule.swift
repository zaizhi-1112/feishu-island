import AppKit
import Combine
import NookApp
import SwiftUI

@MainActor
final class TodoModule: NookModule {
    nonisolated static let info: NookModuleDescriptor = {
        var descriptor = NookModuleDescriptor(id: IslandHost.todoID, displayName: "待办", icon: "checklist", backgroundPolicy: .stayResident)
        descriptor.loadsAtLaunch = true
        return descriptor
    }()
    var descriptor: NookModuleDescriptor { Self.info }
    private let context:NookModuleContext
    init(context: NookModuleContext) { self.context=context }
    func makeConfiguration() -> NookConfiguration {
        var config = IslandHost.baseConfiguration(title: "待办", symbol: "checklist")
        config.setCompactTrailing { UnifiedTodoCompact(store:.shared) }
        config.setHome { UnifiedTodoPanel(store:.shared).islandTextSize() }
        config.onReady = { [context] coordinator in
            let store=WorkspaceStore.shared
            IslandModuleNavigation.shared.bind(coordinator:coordinator)
            store.openBoard = { [weak coordinator] in coordinator?.switchModule(to:IslandHost.todoID); coordinator?.showNook() }
            store.notify = { title in
                var activity=NookLiveActivity(id:"unified-todo-reminder",priority:.high,lifetime:.transient(.seconds(12)),alert:.compact(.seconds(5)),accessibilityLabel:title) {
                    Image(systemName:"checklist").foregroundStyle(.orange)
                } compactTrailing: { Text(title).font(.system(size:10)).lineLimit(1) } minimal: { Image(systemName:"checklist") }
                activity.setExpanded { UnifiedTodoPanel(store:store) }
                context.services.resolve(NookLiveActivitiesKey.self).start(activity)
            }
        }
        return config
    }
}

private struct UnifiedTodoCompact:View {
    @ObservedObject var store:WorkspaceStore
    var body:some View { Text("\(store.pendingTodos.count)项待办").font(.system(size:10,weight:.medium)) }
}

