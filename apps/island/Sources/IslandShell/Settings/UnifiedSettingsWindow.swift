import AppKit
import NookApp
import SwiftUI

/// Native settings, adapted from 佑哥 0.9.2. One owner, one window, five destinations.
@MainActor final class UnifiedSettingsWindow: NSObject, NSWindowDelegate {
    static let shared = UnifiedSettingsWindow()
    let model = UnifiedSettingsModel()
    private var window: NSWindow?
    func bind(appState: AppState) { model.appState = appState }
    func open(section: String = "messages") {
        model.section = UnifiedSettingsSection.resolve(section)
        if window == nil {
            let next = NSWindow(contentRect: NSRect(x:0,y:0,width:1020,height:760), styleMask:[.titled,.closable,.miniaturizable,.resizable], backing:.buffered,defer:false)
            next.title = "一切在岛 · 设置"; next.identifier = .init("feibao.settings")
            next.minSize = NSSize(width:840,height:620); next.isReleasedWhenClosed = false
            next.delegate = self; next.setFrameAutosaveName("FeibaoUnifiedSettings")
            next.contentView = NSHostingView(rootView: UnifiedSettingsRoot(model:model))
            next.center(); window = next
        }
        model.visible = true; window?.makeKeyAndOrderFront(nil); NSApp.activate()
    }
    func windowWillClose(_ notification: Notification) { model.visible = false }
    func windowDidMiniaturize(_ notification: Notification) { model.visible = false }
    func windowDidDeminiaturize(_ notification: Notification) { model.visible = true }
}

enum UnifiedSettingsSection: String, CaseIterable, Identifiable {
    case messages, agents, todos, platform, appearance
    var id:String { rawValue }
    var title:String { switch self { case .messages:"飞书消息"; case .agents:"Agent 状态"; case .todos:"待办"; case .platform:"中台"; case .appearance:"外观与交互" } }
    var symbol:String { switch self { case .messages:"paperplane"; case .agents:"sparkles"; case .todos:"checklist"; case .platform:"square.grid.2x2"; case .appearance:"paintbrush.pointed" } }
    var subtitle:String { switch self {
    case .messages:"连接飞书，统一管理会话与弹幕。"
    case .agents:"关注正在运行的 Agent，按需查看状态与额度。"
    case .todos:"做完一件，划掉一件。完成记录长期保存在本机。"
    case .platform:"把常用入口放进信号轮盘，抬手打开。"
    case .appearance:"主题、形态、悬浮偏好与共用提醒素材。"
    } }
    static func resolve(_ value:String) -> Self {
        switch value { case "feishu","account","rules":.messages; case "agent","status":.agents; case "todo","reminders":.todos; case "hub","middle":.platform; case "skins","skin","screens","general","display","interaction":.appearance; default:Self(rawValue:value) ?? .messages }
    }
}
@MainActor final class UnifiedSettingsModel: ObservableObject {
    @Published var section:UnifiedSettingsSection = .messages
    @Published var appState:AppState?
    @Published var visible = false
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
    private var dark:Bool { appState.appearancePreferences.effectiveColorScheme(systemScheme: NSApp.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? .dark:.light) == .dark }
    private var theme:NookResolvedTheme { NookResolvedTheme.resolve(theme:agents.selectedSkin.theme,preferences:appState.appearancePreferences,effectiveColorScheme:dark ? .dark:.light,reduceTransparency:NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency) }
    var body:some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:6) {
                Label("一切在岛",systemImage:"capsule.fill").font(.system(size:22,weight:.semibold)).padding(.horizontal,12).padding(.top,22)
                Text("宰治 × 柚子").font(.system(size:12)).foregroundStyle(theme.tertiaryLabel).padding(.horizontal,13).padding(.bottom,24)
                ForEach(UnifiedSettingsSection.allCases) { section in
                    Button { model.section=section } label: {
                        Label(section.title,systemImage:section.symbol).font(.system(size:14,weight:model.section==section ? .semibold:.regular))
                            .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,12).padding(.vertical,13)
                            .background(model.section==section ? theme.accent.opacity(0.13):.clear,in:RoundedRectangle(cornerRadius:10))
                    }.buttonStyle(.plain).foregroundStyle(model.section==section ? theme.accent:theme.secondaryLabel)
                        .accessibilityIdentifier("unified.settings.\(section.rawValue)").accessibilityAddTraits(model.section==section ? .isSelected:[])
                }
                Spacer()
                Button("使用说明") { if let url=Bundle.main.url(forResource:"开始使用",withExtension:"html") {NSWorkspace.shared.open(url)} }.buttonStyle(.plain).font(.system(size:12)).padding(.horizontal,12)
                Text("本机保存 · 原生 Mac 应用\n0.9.0 · 融合版 53").font(.system(size:11)).foregroundStyle(theme.tertiaryLabel).lineSpacing(5).padding(12)
            }.padding(.horizontal,14).padding(.bottom,12).frame(width:208).frame(maxHeight:.infinity)
                .background(Color(skinHex:agents.selectedSkin.palette(dark:dark).sidebar))
            Rectangle().fill(theme.subtleStroke).frame(width:1)
            VStack(alignment:.leading,spacing:0) {
                VStack(alignment:.leading,spacing:8) {
                    Text(model.section.title).font(.system(size:26,weight:.semibold))
                    Text(model.section.subtitle).font(.system(size:13)).foregroundStyle(theme.secondaryLabel)
                }.padding(28)
                Rectangle().fill(theme.subtleStroke).frame(height:1)
                ScrollView {
                    VStack(alignment:.leading,spacing:24) { page }.frame(maxWidth:780,alignment:.leading).padding(28).frame(maxWidth:.infinity,alignment:.leading)
                }.id(model.section).accessibilityIdentifier("unified.settings.scroll")
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
                .background { IslandSkinBackdrop(store:agents,dark:dark,compact:false,notched:false) }
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
        case .appearance:
            IslandSkinStudio(store:agents)
            IslandSettingsCard("主题与形态") { UnifiedAppearanceControls(appState:appState) }
            IslandSettingsCard("显示屏") { NookDisplaySettingsSection(appState:appState) }
            IslandSettingsCard("冲屏素材") { WorkspaceReminderLibrary(store:.shared) }
        }
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
    private func binding<T>(_ key:WritableKeyPath<NookAppearancePreferences,T>)->Binding<T> {
        Binding(get:{appState.appearancePreferences[keyPath:key]},set:{ value in var next=appState.appearancePreferences; next[keyPath:key]=value; appState.replaceAppearancePreferences(next) })
    }
    var body:some View {
        Picker("主题",selection:binding(\.chromePalette)) {
            Text("跟随系统").tag(NookChromePalette.followSystem); Text("深色").tag(NookChromePalette.dark); Text("浅色").tag(NookChromePalette.light)
        }.pickerStyle(.segmented)
        Picker("形态",selection:binding(\.presentation)) {
            Text("自动").tag(NookPresentation.auto); Text("刘海").tag(NookPresentation.notch); Text("悬浮胶囊").tag(NookPresentation.floating)
        }.pickerStyle(.segmented)
        Picker("鼠标移入",selection:Binding(get:{appState.appearancePreferences.openOnHover},set:{ value in
            var next=appState.appearancePreferences; next.openOnHover=value; next.peekDwell=0; next.hoverDelay=0.15; next.externalDisplayHoverDelay=0.2; appState.replaceAppearancePreferences(next)
        })) {
            Text("完整展开").tag(NookOpenOnHover.immediately)
            Text("先预览，点击展开").tag(NookOpenOnHover.peekFirst)
        }.pickerStyle(.segmented).accessibilityIdentifier("unified.hoverMode")
        Text("移开自动收起。悬浮预览会留出摄像头位置，点击后再显示完整内容。").font(.system(size:12)).foregroundStyle(.secondary)
    }
}
