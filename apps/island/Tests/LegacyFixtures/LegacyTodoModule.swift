import Combine
import AppKit
import NookApp
import SwiftUI
@testable import IslandShell

/// Starts once after the window is ready; it does not depend on the active module.
@MainActor
final class TodoBridge {
    static let shared = TodoBridge()
    private weak var coordinator: AppCoordinator?
    private var subscriptions = Set<AnyCancellable>()
    private var queuedIDs = Set<String>()
    private var noticeUntil: Date?
    private var noticeIDs = Set<String>()
    var playSound: () -> Void = { NSSound(named: "Pop")?.play() }

    func attach(_ coordinator: AppCoordinator) {
        guard self.coordinator == nil else { return }
        self.coordinator = coordinator
        IslandModuleAttention.shared.attach(coordinator)
        let store = TodoStore.shared
        store.onDue = { [weak self] items in
            self?.queuedIDs.formUnion(items.map(\.id))
            if store.preferences.soundEnabled { self?.playSound() }
        }
        Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }.store(in: &subscriptions)
        for event in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: event).sink { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }.store(in: &subscriptions)
        }
        tick()
        TodoVerification.startIfRequested(coordinator: coordinator)
    }

    func tick() {
        guard let coordinator else { return }
        let store = TodoStore.shared
        store.checkDue()
        IslandModuleAttention.shared.refresh()
        let dueIDs = Set(store.pending.filter { $0.dueAt.map { $0 <= Date() } ?? false }.map(\.id))
        queuedIDs.formIntersection(dueIDs)
        let activities = coordinator.moduleHost.registry.liveActivities
        let scope = activities.activities(for: IslandHost.todoID)
        if let until = noticeUntil, until <= Date() || noticeIDs.isDisjoint(with: dueIDs) {
            // Keep the activity while the person is reading its details.
            if !coordinator.appState.isNookVisible || coordinator.activeModuleID == IslandHost.todoID {
                scope.end("todo-reminder"); noticeUntil = nil; noticeIDs = []
            }
        }
        guard !queuedIDs.isEmpty, noticeUntil == nil,
              !coordinator.appState.isNookVisible, !coordinator.appState.isDragInFlight, !coordinator.isUserEngaged,
              !activities.activities.contains(where: \.isAlerting) else { return }
        let count = queuedIDs.count
        let first = store.pending.first { queuedIDs.contains($0.id) }
        let label = count == 1 ? first?.title ?? "待办到时间了" : "\(count)项待办到时间了"
        var activity = NookLiveActivity(id: "todo-reminder", priority: .high, alert: .compact(.seconds(5)), accessibilityLabel: label) {
            Image(systemName: "checklist").foregroundStyle(.orange).font(.system(size: 12))
        } compactTrailing: {
            HStack(spacing: 5) {
                Circle().fill(.orange).frame(width: 6, height: 6)
                Text(label).lineLimit(1).frame(maxWidth: 200)
            }.font(.system(size: 10, weight: .medium))
        } minimal: {
            Label("\(count)", systemImage: "checklist").font(.system(size: 10)).foregroundStyle(.orange)
        }
        activity.setExpanded { TodoPanel(store: .shared) }
        noticeIDs = queuedIDs; queuedIDs = []; noticeUntil = Date().addingTimeInterval(5)
        scope.start(activity)
    }
}

struct TodoCompactView: View {
    @ObservedObject var store: TodoStore
    var body: some View {
        Text(store.overdueCount > 0 ? "\(store.overdueCount)项到期" : "\(store.pending.count)项待办")
            .foregroundStyle(store.overdueCount > 0 ? Color.orange : Color.secondary)
            .font(.system(size: 10, weight: .medium))
    }
}

/// Product bar keeps all three destinations and their pending reminders visible.
struct IslandTopBar: View {
    let bar: NookTopBarContext
    @ObservedObject var todos = TodoStore.shared
    @ObservedObject var attention = IslandModuleAttention.shared
    @Environment(\.nookNotchCutout) private var cutout
    @EnvironmentObject private var appState: AppState
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            if !cutout.isEmpty { Color.clear.frame(height: cutout.height) }
            HStack {
                if bar.canGoBack {
                    Button { bar.goBack() } label: { Image(systemName: "chevron.left").frame(width: 24, height: 24) }
                        .help("返回").accessibilityLabel("返回")
                } else {
                    moduleButtons
                }
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Button { bar.toggleKeepOpen() } label: { Image(systemName: bar.isKeepOpen ? "lock.fill" : "lock.open").frame(width: 24, height: 24) }
                        .help("保持展开").accessibilityLabel("保持展开")
                    if bar.showsSettings {
                        Button { bar.toggleSettings() } label: { Image(systemName: "gearshape").frame(width: 24, height: 24) }
                            .help("设置").accessibilityLabel("设置")
                    }
                }
            }
            if appState.isDragInFlight {
                Label("松开以添加待办", systemImage: "tray.and.arrow.down").font(.system(size: 12)).foregroundStyle(theme.accent)
                    .frame(maxWidth: .infinity).padding(10).background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            } else {
                TodoCaptureFeedback(store: todos) {
                    bar.moduleSwitcher?.switchTo(IslandHost.todoID)
                }
            }
        }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
    }
    @ViewBuilder private var moduleButtons: some View {
        if let switcher = bar.moduleSwitcher {
            HStack(spacing: 2) {
                ForEach(switcher.modules) { module in
                    Button { switcher.switchTo(module.id) } label: {
                        Image(systemName: module.icon).frame(width: 24, height: 24)
                            .foregroundStyle(switcher.activeID == module.id || attention.hints[module.id] != nil ? theme.accent : theme.secondaryLabel)
                            .background(theme.accent.opacity(switcher.activeID == module.id ? 0.16 : attention.hints[module.id] != nil ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(alignment: .bottom) {
                                if attention.hints[module.id] != nil {
                                    Capsule().fill(theme.accent).frame(width: 10, height: 2)
                                        .offset(y: 3).accessibilityHidden(true)
                                }
                            }
                    }.help(module.displayName + (attention.hints[module.id].map { "：" + $0 } ?? "") + "；双指左右滑动切换")
                        .accessibilityLabel(module.displayName)
                        .accessibilityValue([switcher.activeID == module.id ? "当前功能" : nil, attention.hints[module.id]].compactMap { $0 }.joined(separator: "，"))
                        .accessibilityIdentifier("island.module.\(module.id)")
                }
            }
        }
    }

}

struct TodoCaptureFeedback: View {
    @ObservedObject var store: TodoStore
    var openTodo: () -> Void
    var body: some View {
        Group {
            if let error = store.error {
                HStack(alignment: .top) {
                    Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button { store.error = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("关闭错误提示")
                }.padding(8)
            } else if store.importingCount > 0 {
                HStack { ProgressView().controlSize(.small); Text("正在保存待办…").font(.system(size: 11)) }.padding(6)
            } else if let id = store.savedID {
                HStack(spacing: 10) {
                    Label("已保存待办", systemImage: "checkmark.circle").foregroundStyle(.green)
                    Spacer(minLength: 0)
                    Button("修改") { store.selectedID = id; store.savedID = nil; openTodo() }
                    Button("撤销") { store.undoCapture() }
                    Button { store.savedID = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("关闭保存提示")
                }.font(.system(size: 11)).padding(8)
                    .task(id: id) {
                        do { try await Task.sleep(for: .seconds(8)) } catch { return }
                        if store.savedID == id { store.savedID = nil }
                    }
            }
        }.accessibilityIdentifier("island.todo.captureFeedback")
    }
}
