import AppKit
import NookApp
import SwiftUI

/// Only the first launch of a new installation is automatic. Upgrades keep every
/// existing choice; an unfinished first run stays pending until all choices are done.
@MainActor enum IslandOnboardingPolicy {
    static let key = "island.onboarding.v1"
    static private(set) var isNewUser = false
    static func initialState(saved: String?, hasExistingData: Bool) -> String {
        saved ?? (hasExistingData ? "existing" : "pending")
    }
    static func prepareAtLaunch() {
        guard Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview", !IslandRuntime.isSkinPreview,
              !ProcessInfo.processInfo.arguments.contains("--self-test") else { return }
        let defaults = UserDefaults.standard
        let workspace = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FeishuIsland/Workspace/workspace.json")
        let agents = UserDefaults(suiteName: IslandHost.agentID)!
        let messages = UserDefaults(suiteName: IslandHost.feishuID)!
        let existing = FileManager.default.fileExists(atPath: workspace.path)
            || agents.object(forKey: "preferences") != nil || messages.object(forKey: "connection") != nil
            || defaults.object(forKey: "opennook.appearance.choices.v2") != nil
            || defaults.object(forKey: "opennook.appearance.v1") != nil
        let state = ProcessInfo.processInfo.arguments.contains("--onboarding") ? "pending" : initialState(saved: defaults.string(forKey: key), hasExistingData: existing)
        isNewUser = state == "pending"
        defaults.set(state, forKey: key)
    }
    static func unselectedAgents(_ preferences: AgentPreferences) -> AgentPreferences {
        var next = preferences
        next.setVisibleIDs([]); next.monitoredIDs = []; next.enabled = false; next.quotaDisplayEnabled = false
        return next
    }
    static func finish(defaults: UserDefaults = .standard, skipped: Bool) {
        defaults.set(skipped ? "skipped" : "complete", forKey: key)
        isNewUser = false
    }
}

@MainActor final class IslandOnboardingWindow: NSObject, NSWindowDelegate {
    static let shared = IslandOnboardingWindow()
    private var window: NSWindow?
    private var finished = false
    private weak var coordinator: AppCoordinator?
    func showIfNeeded(coordinator: AppCoordinator, store: FeishuStore) {
        self.coordinator = coordinator
        let appState = coordinator.appState
        let requested = ProcessInfo.processInfo.arguments.contains("--onboarding")
        guard requested || IslandOnboardingPolicy.isNewUser else { return }
        open(appState: appState, store: store)
    }
    func open(appState: AppState, store: FeishuStore) {
        if let window, window.isVisible { window.makeKeyAndOrderFront(nil); return }
        finished = false
        let next = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 640), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        next.title = "欢迎来到一切在岛"; next.identifier = .init("island.onboarding")
        next.isReleasedWhenClosed = false; next.delegate = self
        next.contentView = NSHostingView(rootView: IslandOnboardingView(appState: appState, feishu: store, agents: .shared, workspace: .shared) { [weak self] skipped in
            self?.finish(skipped: skipped); self?.window?.close()
        })
        next.center(); window = next; next.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func finish(skipped: Bool) {
        guard !finished else { return }; finished = true
        if !IslandRuntime.isSkinPreview {
            if skipped && IslandOnboardingPolicy.isNewUser { NSApp.terminate(nil); return }
            IslandOnboardingPolicy.finish(skipped: false)
            HubPingLauncher.shared.start()
            coordinator?.showNook()
        }
    }
    func windowWillClose(_ notification: Notification) { finish(skipped: true) }
}

enum IslandOnboardingStep: Int, CaseIterable, Identifiable {
    case hover, theme, feishu, danmu, reminder, shortcut, agents
    var id: Int { rawValue }
    var name: String { ["展开", "外观", "飞书", "弹幕", "提醒", "快捷键", "Agent"][rawValue] }
    var title: String { ["你靠近时，岛怎么回应？", "选一个舒服的明暗", "把飞书带到岛上", "消息，要不要从桌面划过？", "到时间，怎样叫你？", "按一下，打开灵动岛", "选择你的 Agent"][rawValue] }
    var detail: String { ["在左侧的小岛上试试鼠标移入和点击。", "点击即预览，之后也能随时换。", "一个入口，依次连接消息、日历和虚实中台。", "岛内照常保留消息，弹幕由你决定。", "用于新待办和日程；已有提醒保持原样。", "点击设置按钮，再按下组合键。", "先获取本机工具，再选择连接；也可以以后再设置。"][rawValue] }
}
private struct GuideTargets: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) { value.merge(nextValue()) { _, new in new } }
}

struct IslandOnboardingView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var feishu: FeishuStore
    @ObservedObject var agents: AgentStore
    @ObservedObject var workspace: WorkspaceStore
    let complete: (Bool) -> Void
    @State var step: IslandOnboardingStep = .hover
    @State private var target = "choice-0"
    @State private var reachedStep = 0
    @State private var hovered = false
    @State private var clicked = false
    @State private var playing = false
    @State private var generation = 0
    @State private var started = Date()
    @State private var feedback = ""
    @State private var keyboardNavigation = false
    @State private var inputMonitor: Any?
    @FocusState private var focusedStep: IslandOnboardingStep?
    @StateObject private var feishuSetup = FeishuSetupFlow()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var dark: Bool { appState.appearancePreferences.effectiveColorScheme(systemScheme: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua,.aqua]) == .darkAqua ? .dark : .light) == .dark }
    private var accent: Color { Color(skinHex: dark ? "#9BB8FF" : "#3563E9") }
    private var reminder: String { workspace.disk.defaultTodoScreen?.materialID ?? "island" }
    private var connected: Bool { feishu.canResumeSavedConnection }
    private var bubble: String { feishu.appearance["bubble"] as? String ?? "none" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                ForEach(IslandOnboardingStep.allCases) { item in
                    Button { go(item) } label: {
                        HStack(spacing: 7) {
                            Text("\(item.rawValue + 1)").font(.system(size: 11, weight: .semibold)).frame(width: 23, height: 23)
                                .background(step == item ? accent : Color.secondary.opacity(0.12), in: Circle())
                                .foregroundStyle(step == item ? (dark ? Color.black : .white) : .secondary)
                            Text(item.name).font(.system(size: 12, weight: step == item ? .semibold : .regular))
                        }.padding(.vertical, 6).padding(.horizontal, 6).contentShape(Rectangle())
                            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(keyboardNavigation && focusedStep == item ? accent : .clear, lineWidth: 2) }
                    }.buttonStyle(.plain).focused($focusedStep, equals: item).focusEffectDisabled().disabled(item.rawValue > max(reachedStep, step.rawValue)).accessibilityLabel("第\(item.rawValue + 1)步：\(item.name)")
                        .accessibilityAddTraits(step == item ? .isSelected : [])
                    if item != .agents { Capsule().fill(.secondary.opacity(0.15)).frame(width: 13, height: 2) }
                }
                Spacer(minLength: 0)
            }.padding(.bottom, 27)
            Text(step.title).font(.system(size: 28, weight: .semibold)).padding(.bottom, 9)
            Text(step.detail).font(.system(size: 14)).foregroundStyle(.secondary).padding(.bottom, 25)
            HStack(alignment: .center, spacing: 28) {
                preview.frame(width: 345, height: 322)
                    .background(dark ? Color.white.opacity(0.04) : Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 25))
                    .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(.secondary.opacity(0.12)))
                ScrollView { VStack(alignment: .leading, spacing: 12) { choices }.frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxWidth: .infinity, maxHeight: 360)
            }.frame(maxHeight: .infinity)
            Text(feedback.isEmpty ? "选中即保存 · 之后可在设置里调整" : feedback)
                .font(.system(size: 12)).foregroundStyle(feedback.isEmpty ? Color.secondary : accent)
                .frame(height: 31, alignment: .center).padding(.top, 12)
            HStack {
                Button("退出，稍后继续") { complete(true) }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                if step != .hover { Button("上一步") { go(IslandOnboardingStep(rawValue: step.rawValue - 1)!) }.buttonStyle(.bordered).controlSize(.large) }
                Button(step == .agents ? "开始使用" : "下一步") {
                    if step == .agents { complete(false) } else { go(IslandOnboardingStep(rawValue: step.rawValue + 1)!) }
                }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                    .anchorPreference(key: GuideTargets.self, value: .bounds) { ["next": $0] }
                    .onHover { if $0 { target = "next" } }
            }.font(.system(size: 13)).padding(.top, 8)
        }.padding(30).frame(width: 850, height: 640)
            .background(dark ? Color(skinHex: "#161922") : Color(skinHex: "#F3F5FA"))
            .foregroundStyle(dark ? Color(skinHex: "#F2F4FA") : Color(skinHex: "#202634"))
            .tint(accent).preferredColorScheme(dark ? .dark : .light)
            .overlayPreferenceValue(GuideTargets.self) { anchors in
                GeometryReader { geometry in
                    if let anchor = anchors[target] ?? anchors["choice-0"] {
                        let rect = geometry[anchor]
                        GuideCompanion(reduceMotion: reduceMotion)
                            .position(x: rect.minX - 8, y: max(24, rect.minY - 9))
                            .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.74), value: target)
                            .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.74), value: step)
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
            .onAppear {
                keyboardNavigation = false
                inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { event in
                    if event.type == .keyDown, event.keyCode == 48 { keyboardNavigation = true }
                    else if event.type == .leftMouseDown || event.type == .rightMouseDown { keyboardNavigation = false }
                    return event
                }
            }
            .onDisappear {
                playing = false; feishuSetup.cancel()
                if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }; inputMonitor = nil
            }
            .task(id: "\(step.rawValue)-\(generation)") {
                guard playing else { return }
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                playing = false
            }
    }

    private func go(_ value: IslandOnboardingStep) {
        if step == .feishu && value != .feishu { feishuSetup.cancel() }
        playing = false; feedback = ""; hovered = false; clicked = false; target = "choice-0"
        reachedStep = max(reachedStep, value.rawValue)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = value }
    }
    private func replay() { started = Date(); generation += 1; playing = true }
    private func appearance(_ update: (inout NookAppearancePreferences) -> Void) {
        var p = appState.appearancePreferences; update(&p); appState.replaceAppearancePreferences(p)
    }
    private func option(_ id: Int, _ title: String, _ detail: String, _ symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { target = "choice-\(id)"; action() } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 21)).frame(width: 27).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    if !detail.isEmpty { Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? accent : .secondary.opacity(0.3))
            }.padding(16).frame(maxWidth: .infinity, minHeight: 70)
                .background(selected ? accent.opacity(0.09) : Color.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? accent.opacity(0.65) : .secondary.opacity(0.12), lineWidth: selected ? 1.5 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(selected ? "已选" : "未选")
            .anchorPreference(key: GuideTargets.self, value: .bounds) { ["choice-\(id)": $0] }
            .onHover { if $0 { target = "choice-\(id)" } }
    }

    @ViewBuilder private var choices: some View {
        switch step {
        case .hover:
            option(0, "完整展开", "鼠标移入，就能查看和操作。", "rectangle.expand.vertical", selected: appState.appearancePreferences.openOnHover == .immediately) {
                appearance { $0.openOnHover = .immediately; $0.peekDwell = 0; $0.hoverDelay = 0.15; $0.externalDisplayHoverDelay = 0.2 }; clicked = false; hovered = false
            }
            option(1, "先露出胶囊", "轻轻露出，点一下再完整展开。", "capsule", selected: appState.appearancePreferences.openOnHover == .peekFirst) {
                appearance { $0.openOnHover = .peekFirst; $0.peekDwell = 0; $0.hoverDelay = 0.15; $0.externalDisplayHoverDelay = 0.2 }; clicked = false; hovered = false
            }
        case .theme:
            option(0, "深色", "让注意力留在岛上。", "moon.fill", selected: appState.appearancePreferences.chromePalette == .dark) { appearance { $0.chromePalette = .dark } }
            option(1, "浅色", "轻盈、明亮。", "sun.max.fill", selected: appState.appearancePreferences.chromePalette == .light) { appearance { $0.chromePalette = .light } }
            Button("跟随 Mac 的外观") { appearance { $0.chromePalette = .followSystem }; feedback = "已跟随系统" }.buttonStyle(.plain).foregroundStyle(accent).padding(.leading, 16)
        case .feishu:
            Button(feishuSetup.active ? "正在连接…" : "连接飞书") { feishuSetup.start(feishu: feishu, workspace: workspace) }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(feishuSetup.active)
            connectionRow("飞书消息", connected)
            connectionRow("飞书日历", workspace.disk.feishuSchedule?.enabled == true && workspace.scheduleAccountMatches)
            connectionRow("虚实中台", workspace.hub.connected)
            Text("按授权窗口提示确认。每项连接成功后才会显示勾选。").font(.system(size: 12)).foregroundStyle(.secondary)
            Text(feishuSetup.message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            if feishuSetup.active { Button("暂停连接") { feishuSetup.cancel() } }
            Text("也可以先跳过，稍后在设置里连接。").font(.system(size: 12)).foregroundStyle(.secondary)
        case .danmu:
            option(0, "只在岛内看", "桌面保持安静。", "capsule", selected: !feishu.danmu.enabled) { var p = feishu.danmu; p.enabled = false; feishu.updateDanmu(p); playing = false }
            option(1, "也显示桌面弹幕", "消息完整飘过，长文字在同一条弹幕中滚动。", "text.bubble", selected: feishu.danmu.enabled) { var p = feishu.danmu; p.enabled = true; p.paused = false; feishu.updateDanmu(p); replay() }
            if feishu.danmu.enabled {
                HStack(spacing: 8) {
                    ForEach([("none","文字"),("dark","深色气泡"),("light","浅色气泡")], id: \.0) { value, title in
                        Button(title) { setBubble(value); replay() }.buttonStyle(.bordered).tint(bubble == value ? accent : .secondary)
                    }
                }
            }
        case .reminder:
            option(0, "岛内轻提醒", "在屏幕顶部提示。", "capsule", selected: reminder == "island") { _ = workspace.mutate { $0.defaultTodoScreen = nil }; replay() }
            ForEach(Array(workspace.screenMaterials.enumerated()),id:\.element.id) {index,material in
                option(index+1, material.name, "", material.id == "cat" ? "cat" : "play.rectangle", selected: reminder == material.id) { chooseReminder(material.id) }
            }
            ScreenReminderDismissalSettings()
        case .shortcut:
            IslandShortcutRecorder(appState: appState)
        case .agents:
            AgentDiscoveryView(store: agents)
        }
    }
    private func connectionRow(_ title: String, _ ready: Bool) -> some View {
        Label(title + (ready ? " · 已连接" : " · 待连接"), systemImage: ready ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 14)).foregroundStyle(ready ? Color.primary : .secondary)
    }

    @ViewBuilder private var preview: some View {
        VStack(spacing: 18) {
            switch step {
            case .hover, .theme:
                Spacer()
                miniIsland(expanded: step == .theme || clicked || (hovered && appState.appearancePreferences.openOnHover == .immediately), peek: hovered)
                    .offset(y: 32)
                    .opacity(step == .theme || hovered || clicked ? 1 : 0)
                    .frame(width: 301, height: 190, alignment: .top)
                    .background(alignment: .top) { UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10).fill(.black).frame(width: 120, height: 24) }
                    .contentShape(Rectangle())
                    .onHover { value in withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { hovered = value; if !value { clicked = false } } }
                    .onTapGesture { withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { clicked.toggle() } }
                    .accessibilityElement(children: .combine).accessibilityLabel("试用小岛，点击展开或收起").accessibilityAddTraits(.isButton)
                Spacer()
                Label(step == .hover ? "把鼠标移到这座小岛" : "你的岛，现在的样子", systemImage: "cursorarrow").font(.system(size: 12)).foregroundStyle(.secondary)
            case .feishu:
                Spacer()
                Image(systemName: connected ? "checkmark.circle" : "paperplane").font(.system(size: 56, weight: .light)).foregroundStyle(accent)
                Text(connected ? "消息连接已保存" : "消息和日程，都在眼前").font(.system(size: 16, weight: .medium))
                Text("只在你授权后接入").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
            case .danmu:
                miniIsland(expanded: false, peek: true).padding(.top, 12)
                if feishu.danmu.enabled {
                    FeishuDanmuPreview(appearance: feishu.appearance, playing: playing && !reduceMotion, started: started, onFinished: { playing = false }).frame(height: 125)
                        .background(Color(skinHex: "#34434F"), in: RoundedRectangle(cornerRadius: 12))
                } else { Text("新消息，去岛内查看").foregroundStyle(.secondary).frame(height: 125) }
                previewButton
            case .reminder:
                if reminder == "island" { Spacer(); miniIsland(expanded: true, peek: true).scaleEffect(playing ? 1 : 0.94).animation(reduceMotion ? nil : .spring(response: 0.4), value: playing); Spacer() }
                else { WorkspaceReminderMediaPreview(store: workspace, materialID: reminder, generation: generation, playing: $playing).frame(height: 222) }
                previewButton
            case .shortcut:
                Spacer()
                Image(systemName: "keyboard").font(.system(size: 50, weight: .light))
                Text(appState.hotkey.displaySymbols.joined(separator: "  ")).font(.system(size: 24, weight: .medium))
                Text("展开与收起，用同一个快捷键").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
            case .agents:
                Spacer()
                HStack(spacing: 15) {
                    ForEach(agents.preferences.visibleProfiles) { profile in
                        Button { agents.selectPrimary(profile.id) } label: {
                            VStack(spacing: 9) { AgentIdentityIcon(id: profile.id, size: 42); Text(profile.name.replacingOccurrences(of: " Harness", with: "")).font(.system(size: 10)); if agents.primary.id == profile.id { Text("主用").font(.system(size: 10)).foregroundStyle(accent) } }
                        }.buttonStyle(.plain).accessibilityLabel("设为主用：" + profile.name)
                    }
                }
                if agents.preferences.visibleIDs.isEmpty { Image(systemName: "sparkles").font(.system(size: 38)).foregroundStyle(accent); Text("以后再加，也可以").foregroundStyle(.secondary) }
                else { Text("点击上方图标，选一个主用工具").font(.system(size: 12)).foregroundStyle(.secondary) }
                Spacer()
                Text("仅预览位置，不展示你的真实任务").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var previewButton: some View {
        Button { replay() } label: { Label(playing ? "再看一次" : "预览效果", systemImage: "play.fill") }.buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 13))
            .disabled(step == .danmu && !feishu.danmu.enabled)
            .accessibilityHint("示例只在此窗口播放")
    }
    private func miniIsland(expanded: Bool, peek: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(nsImage: IslandBrandAssets.appIcon).resizable().scaledToFit().frame(width: expanded ? 26 : 18, height: expanded ? 26 : 18)
                Text(step == .reminder ? "该处理这件事了" : "一切在岛").font(.system(size: 13, weight: .medium))
                if expanded { Spacer(); Image(systemName: "sparkles").foregroundStyle(accent) }
            }
            if expanded {
                HStack(spacing: 15) { Label("消息", systemImage: "paperplane"); Label("Agent", systemImage: "sparkles"); Label("待办", systemImage: "checklist") }.font(.system(size: 10)).foregroundStyle(.secondary)
                Text(step == .reminder ? "这是提醒预览，今天也记得照顾自己。" : "今天的工作计划\n把重要的事，放在眼前。").font(.system(size: 13)).lineSpacing(7)
            }
        }.padding(expanded ? 20 : 6).frame(width: expanded ? 285 : peek ? 228 : 176, height: expanded ? 170 : 30)
            .background(dark ? Color(skinHex: "#242937") : .white, in: RoundedRectangle(cornerRadius: expanded ? 24 : 29))
            .overlay(RoundedRectangle(cornerRadius: expanded ? 24 : 29).strokeBorder(accent.opacity(0.2)))
            .shadow(color: .black.opacity(dark ? 0.2 : 0.08), radius: 18, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 24))
    }
    private func setBubble(_ value: String) {
        let light = value == "light"
        let patch: [String: Any] = ["bubble": value, "backgroundEnabled": value != "none", "borderEnabled": value != "none", "foreground": light ? "#18202A" : "#FFFFFF", "background": light ? "#FFFFFF" : "#15171C", "border": light ? "#D9DEE5" : "#414753"]
        if !feishu.updateAppearance(feishu.appearance.merging(patch) { _, new in new }) { feedback = "样式未能保存，请在设置中检查。" }
    }
    private func chooseReminder(_ value: String) {
        if workspace.mutate({ $0.defaultTodoScreen = .init(materialID: value) }) { replay() } else { feedback = workspace.error }
    }
    private func toggleAgent(_ id: String) {
        var p = agents.preferences
        if p.isMonitoring(id) { p.monitoredIDs = p.activeMonitorIDs.filter { $0 != id }; p.setVisibleIDs(p.visibleIDs.filter { $0 != id }) }
        else {
            p.monitoredIDs = p.activeMonitorIDs + [id]
            if p.visibleIDs.count < 3 { p.setVisibleIDs(p.visibleIDs + [id]); feedback = "" }
            else { feedback = "岛上已有三个，新增工具会在设置页显示；取消一个可调整。" }
            p.enabled = true; p.quotaDisplayEnabled = true
        }
        if p.activeMonitorIDs.isEmpty { p.enabled = false; p.quotaDisplayEnabled = false }
        do { try agents.update(p) } catch { feedback = error.localizedDescription }
    }
}

private struct GuideCompanion: View {
    let reduceMotion: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { context in
            let wave = reduceMotion ? 0 : sin(context.date.timeIntervalSinceReferenceDate * 2.4)
            Image(nsImage: IslandBrandAssets.appIcon).resizable().scaledToFit().frame(width: 43, height: 43)
                .rotationEffect(.degrees(wave * 4)).offset(y: wave * 3)
                .shadow(color: .blue.opacity(0.12), radius: 6, y: 3)
        }
    }
}
