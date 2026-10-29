import AppKit
import NookApp
import SwiftUI

/// A utility panel can take text input without activating the app and jumping
/// back to the Space that previously owned its settings window.
private final class IslandSettingsPanel: NSPanel {
    var inputMethodChanged: ((Bool) -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 48 {
            inputMethodChanged?(true)
        } else if event.type == .leftMouseDown || event.type == .rightMouseDown {
            inputMethodChanged?(false)
        }
        super.sendEvent(event)
    }
}

/// Native settings, adapted from 佑哥 0.9.2. One owner, one window, five destinations.
@MainActor final class UnifiedSettingsWindow: NSObject, NSWindowDelegate {
    static let shared = UnifiedSettingsWindow()
    let model = UnifiedSettingsModel()
    private var window: NSWindow?
    func bind(appState: AppState) {
        model.appState = appState
    }
    func open(section: UnifiedSettingsSection = .messages) {
        model.section = section
        model.keyboardNavigation = false
        if window == nil {
            let next = IslandSettingsPanel(contentRect: NSRect(x:0,y:0,width:1020,height:760), styleMask:[.titled,.closable,.miniaturizable,.resizable,.nonactivatingPanel], backing:.buffered,defer:false)
            next.title = "一切在岛 · 设置"; next.identifier = .init("feibao.settings")
            next.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .canJoinAllApplications]
            next.level = .floating
            next.hidesOnDeactivate = false
            next.minSize = NSSize(width:840,height:620); next.isReleasedWhenClosed = false
            next.delegate = self; next.setFrameAutosaveName("FeibaoUnifiedSettings")
            next.inputMethodChanged = { [weak model] in model?.keyboardNavigation = $0 }
            next.contentView = NSHostingView(rootView: UnifiedSettingsRoot(model:model))
            next.center(); window = next
        }
        model.visible = true
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        // Order onto the user's current Space before taking keyboard focus. Do not
        // activate NSApp: activation can bring an old desktop/fullscreen Space back.
        window?.makeKeyAndOrderFront(nil)
    }
    // Settings and the island are independent windows. Keep the live surface and
    // its current interaction state intact while preferences are being edited.
    func windowWillClose(_ notification: Notification) { model.visible = false }
    func windowDidMiniaturize(_ notification: Notification) { model.visible = false }
    func windowDidDeminiaturize(_ notification: Notification) { model.visible = true }
}

enum UnifiedSettingsSection: String, CaseIterable, Identifiable {
    case messages, agents, todos, platform, rest, appearance
    var id:String { rawValue }
    var title:String { switch self { case .messages:"飞书消息"; case .agents:"Agent状态"; case .todos:"待办"; case .platform:"中台"; case .rest:"休息提醒"; case .appearance:"外观与交互" } }
    var symbol:String { switch self { case .messages:"paperplane"; case .agents:"sparkles"; case .todos:"checklist"; case .platform:"square.grid.2x2"; case .rest:"cup.and.saucer"; case .appearance:"paintbrush.pointed" } }
    var subtitle:String { switch self {
    case .messages:"接收关心的消息，用喜欢的方式提醒。"
    case .agents:"关注正在运行的 Agent，按需查看状态与额度。"
    case .todos:"管理待办，回看已完成的记录。完成记录长期保存在本机。"
    case .platform:"把常用入口放进信号轮盘，抬手打开。"
    case .rest:"到时间，提醒自己起身活动一下。"
    case .appearance:"主题、悬浮交互与显示屏。"
    } }
    static func resolve(_ value:String) -> Self {
        switch value { case "feishu","account","rules":.messages; case "agent","status":.agents; case "todo","reminders":.todos; case "hub","middle":.platform; case "screens","rest-reminders":.rest; case "skins","skin","general","display","interaction":.appearance; default:Self(rawValue:value) ?? .messages }
    }
}
@MainActor final class UnifiedSettingsModel: ObservableObject {
    @Published var section:UnifiedSettingsSection = .messages
    @Published var appState:AppState?
    @Published var visible = false
    @Published var keyboardNavigation = false
}
struct UnifiedSettingsRoot:View {
    @ObservedObject var model:UnifiedSettingsModel
    @ObservedObject private var agents=AgentStore.shared
    var body:some View {
        Group {
            if let state=model.appState { UnifiedSettingsLayout(model:model,appState:state,agents:agents) }
            else { ContentUnavailableView("设置正在准备",systemImage:"capsule",description:Text("灵动岛就绪后即可继续。")) }
        }
    }
}
private struct UnifiedSettingsLayout:View {
    @ObservedObject var model:UnifiedSettingsModel
    @ObservedObject var appState:AppState
    @ObservedObject var agents:AgentStore
    @State private var appearancePage = "skins"
    @FocusState private var focusedSection: UnifiedSettingsSection?
    private var dark:Bool { appState.appearancePreferences.effectiveColorScheme(systemScheme: NSApp.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? .dark:.light) == .dark }
    private var theme:NookResolvedTheme { NookResolvedTheme.resolve(theme:agents.selectedSkin.theme,preferences:appState.appearancePreferences,effectiveColorScheme:dark ? .dark:.light,reduceTransparency:NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency) }
    var body:some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:6) {
                HStack(spacing: 10) {
                    Image(nsImage: IslandBrandAssets.appIcon).resizable().scaledToFit().frame(width: 40, height: 40).accessibilityHidden(true)
                    Text("一切在岛").font(.system(size: 21, weight: .semibold))
                }.padding(.horizontal, 10).padding(.top, 24).padding(.bottom, 24)
                ForEach(UnifiedSettingsSection.allCases) { section in
                    Button { model.section=section } label: {
                        Label(section.title,systemImage:section.symbol).font(.system(size:14,weight:model.section==section ? .semibold:.regular))
                            .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,12).padding(.vertical,13)
                            .background(model.section==section ? theme.accent.opacity(0.13):.clear,in:RoundedRectangle(cornerRadius:10))
                            .contentShape(RoundedRectangle(cornerRadius:10))
                            .overlay {
                                RoundedRectangle(cornerRadius:10)
                                    .strokeBorder(model.keyboardNavigation && focusedSection == section ? theme.accent : .clear, lineWidth:2)
                            }
                    }.buttonStyle(.plain).foregroundStyle(model.section==section ? theme.accent:theme.secondaryLabel)
                        // AppKit otherwise leaves its label-sized ring on the first
                        // button after pointer navigation. Keep a full-row keyboard cue.
                        .focused($focusedSection, equals: section).focusEffectDisabled()
                        .accessibilityIdentifier("unified.settings.\(section.rawValue)").accessibilityAddTraits(model.section==section ? .isSelected:[])
                }
                Spacer()
                AppUpdateControls().foregroundStyle(theme.secondaryLabel)
                Button { if let store = FeishuStore.active { IslandOnboardingWindow.shared.open(appState: appState, store: store) } } label: {
                    Label("重新体验引导", systemImage: "sparkles").font(.system(size: 12)).padding(10)
                }.buttonStyle(.plain).foregroundStyle(theme.secondaryLabel)
            }.padding(.horizontal,14).padding(.bottom,12).frame(width:208).frame(maxHeight:.infinity)
                .background(Color(skinHex:agents.selectedSkin.palette(dark:dark).sidebar).opacity(agents.selectedSkin == .virxact ? 0.86 : 1))
            Rectangle().fill(theme.subtleStroke).frame(width:1)
            VStack(alignment:.leading,spacing:0) {
                VStack(alignment:.leading,spacing:8) {
                    Text(model.section.title).font(.system(size:26,weight:.semibold))
                    Text(model.section.subtitle).font(.system(size:13)).foregroundStyle(theme.secondaryLabel)
                }.padding(28)
                Rectangle().fill(theme.subtleStroke).frame(height:1)
                ScrollView {
                    VStack(alignment:.leading,spacing:24) { if agents.preferencesReadError != nil {AgentPreferencesRecovery(store:agents)}; page }.frame(maxWidth:780,alignment:.leading).padding(28).frame(maxWidth:.infinity,alignment:.leading)
                }.id(model.section).accessibilityIdentifier("unified.settings.scroll")
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
                .background(agents.selectedSkin == .virxact ? Color.clear : Color(skinHex: agents.selectedSkin.palette(dark: dark).bg))
        }
        .background {
            if agents.selectedSkin == .virxact {
                IslandSkinBackdrop(store:agents,dark:dark,compact:false,notched:false).allowsHitTesting(false)
            }
        }
        .foregroundStyle(theme.primaryLabel).font(.system(size:14)).tint(theme.accent)
        .toggleStyle(.switch).environmentObject(appState)
        .environment(\.nookResolvedTheme,theme).environment(\.nookTheme,agents.selectedSkin.theme)
        .environment(\.nookThemeTokens,agents.selectedSkin.theme.resolvedTokens())
        .environment(\.nookChromeLabels,IslandLabels.chinese).environment(\.nookSurfaceAnimationActive,model.visible)
        .preferredColorScheme(dark ? .dark:.light)
    }
    @ViewBuilder private var page:some View {
        switch model.section {
        case .messages: UnifiedFeishuSettings()
        case .agents: UnifiedAgentSettings(store:agents)
        case .todos: UnifiedTodoSettings(store:.shared)
        case .platform: UnifiedPlatformSettings(workspace:.shared)
        case .rest: UnifiedRestSettings(store:.shared)
        case .appearance:
            Picker("外观设置", selection: $appearancePage) {
                Text("皮肤").tag("skins")
                Text("交互方式").tag("interaction")
                Text("显示屏").tag("display")
            }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("unified.appearance.tabs")
            switch appearancePage {
            case "interaction":
                IslandSettingsCard("快捷键") { IslandShortcutRecorder(appState: appState) }
                IslandSettingsCard("主题与交互") { UnifiedAppearanceControls(appState: appState) }
            case "display": IslandSettingsCard("灵动岛显示在哪里") { UnifiedDisplaySettings(appState: appState) }
            default: IslandSkinStudio(store: agents)
            }
        }
    }
}
enum IslandBrandAssets {
    static var appIcon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) { return image }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/AppIcon.png")
        return NSImage(contentsOf: source) ?? NSImage(systemSymbolName: "capsule", accessibilityDescription: nil)!
    }
}
struct IslandSettingsCard<Content:View>:View {
    let title:String
    @ViewBuilder let content:()->Content
    init(_ title:String,@ViewBuilder content:@escaping()->Content) { self.title=title; self.content=content }
    var body:some View {
        VStack(alignment:.leading,spacing:16) { Text(title).font(.system(size:16,weight:.semibold)); content() }
            .frame(maxWidth:.infinity,alignment:.leading).padding(20).modifier(IslandCard(radius:14))
    }
}
struct UnifiedAppearanceControls:View {
    @ObservedObject var appState:AppState
    @AppStorage("island.showRetractedEdge") private var showRetractedEdge = false
    private func binding<T>(_ key:WritableKeyPath<NookAppearancePreferences,T>)->Binding<T> {
        Binding(get:{appState.appearancePreferences[keyPath:key]},set:{ value in var next=appState.appearancePreferences; next[keyPath:key]=value; appState.replaceAppearancePreferences(next) })
    }
    var body:some View {
        Picker("主题",selection:binding(\.chromePalette)) {
            Text("跟随系统").tag(NookChromePalette.followSystem); Text("深色").tag(NookChromePalette.dark); Text("浅色").tag(NookChromePalette.light)
        }.pickerStyle(.segmented)
        Picker("鼠标移入",selection:Binding(get:{appState.appearancePreferences.openOnHover},set:{ value in
            var next=appState.appearancePreferences; next.openOnHover=value; next.peekDwell=0; next.hoverDelay=0.15; next.externalDisplayHoverDelay=0.2; appState.replaceAppearancePreferences(next)
        })) {
            Text("完整展开").tag(NookOpenOnHover.immediately)
            Text("先露出胶囊，点击展开").tag(NookOpenOnHover.peekFirst)
        }.pickerStyle(.segmented).accessibilityIdentifier("unified.hoverMode")
        Picker("收起时", selection: $showRetractedEdge) {
            Text("完全隐藏").tag(false)
            Text("露出黑边").tag(true)
        }.pickerStyle(.segmented)
        Text("统一使用悬浮胶囊。未锁定时空闲移开即收起，输入或操作菜单时保留展开；点齿轮旁的小锁可始终保持展开。").font(.system(size:12)).foregroundStyle(.secondary)
    }
}
