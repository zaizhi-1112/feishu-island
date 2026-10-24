import AppKit
import SwiftUI
import WebKit

@MainActor final class WorkspaceDeskNavigation: ObservableObject {
    @Published var page = 0
}

/// A normal work window. Automatic reminders never open or activate this window.
@MainActor final class WorkspaceWindow {
    static let shared = WorkspaceWindow()
    private var window: NSWindow?
    private let navigation = WorkspaceDeskNavigation()
    func open(store: WorkspaceStore) { show(store:store,page:store.boardTab) }
    func openSettings(store: WorkspaceStore) { show(store:store,page:4) }
    func openProcessing(store: WorkspaceStore) { show(store:store,page:3) }
    func openHub(store:WorkspaceStore) { show(store:store,page:2) }
    func openReminders(store: WorkspaceStore) { show(store:store,page:5) }
    func openAgents(store: WorkspaceStore) { show(store:store,page:7) }
    private func show(store: WorkspaceStore,page:Int) {
        navigation.page=page
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        let w = NSWindow(contentRect:NSRect(x:0,y:0,width:960,height:680),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        w.title="飞书工作岛 · 工作台"; w.isReleasedWhenClosed=false
        w.minSize=NSSize(width:760,height:540)
        w.contentView=NSHostingView(rootView:WorkspaceDesk(store:store,navigation:navigation)); w.center(); window=w
        w.makeKeyAndOrderFront(nil); NSApp.activate()
    }
}
struct WorkspaceDesk: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var navigation: WorkspaceDeskNavigation
    private let titles=["Agent","待办与提醒","虚实中台","处理与归档","账号与消息","冲屏素材","外观与交互","Agent 与皮肤"]
    private let symbols=["tray.and.arrow.down","checklist","square.grid.2x2","slider.horizontal.3","bubble.left.and.bubble.right","play.rectangle","paintbrush","sparkles"]
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:6) {
                HStack(spacing:9) { Image(systemName:"capsule.fill").foregroundStyle(.cyan); Text("工作岛").font(.system(size:18,weight:.semibold)) }.padding(.bottom,22)
                sidebarSection("工作",items:0...2)
                Text("设置").font(.system(size:11)).foregroundStyle(.secondary).padding(.top,22).padding(.bottom,5)
                ForEach(3...7,id:\.self) { row($0) }
                Spacer()
                HStack(spacing:6) { Circle().fill(store.hub.connected ? .green : .gray).frame(width:5,height:5); Text(store.hub.connected ? "中台已连接" : "中台未连接").font(.system(size:11)).foregroundStyle(.secondary) }
            }.padding(18).frame(width:180).frame(maxHeight:.infinity).background(Color.white.opacity(0.025))
            Divider()
            VStack(alignment:.leading,spacing:0) {
                HStack { Text(titles[navigation.page]).font(.system(size:22,weight:.semibold)); Spacer(); Text("飞书工作岛").font(.system(size:11)).foregroundStyle(.secondary) }.padding(.horizontal,24).padding(.vertical,20)
                Divider()
                if navigation.page == 0 { ScrollView { AgentWorkspaceSurface(agents:.shared,workspace:store,desktop:true,onTaskCreated:{navigation.page=1}) } }
                else if navigation.page == 4 { WorkspaceAccountSettings() }
                else if navigation.page == 5 { ScrollView { WorkspaceReminderLibrary(store:store).padding(24) } }
                else if navigation.page == 7 { ScrollView { IntegrationAgentSettings().padding(24) } }
                else if navigation.page == 6 { ScrollView { WorkspaceShellSettings().padding(24) } }
                else { ScrollView { WorkspaceView(store:store,desktop:true,pageOverride:navigation.page,onTaskCreated:{navigation.page=1}) } }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(minWidth:760,minHeight:500).background(Color(nsColor:.windowBackgroundColor)).preferredColorScheme(.dark)
    }
    private func sidebarSection(_ title:String,items:ClosedRange<Int>) -> some View {
        VStack(alignment:.leading,spacing:6) { Text(title).font(.system(size:11)).foregroundStyle(.secondary).padding(.bottom,5); ForEach(items,id:\.self) { row($0) } }
    }
    private func row(_ index:Int) -> some View {
        Button { navigation.page=index } label: {
            HStack(spacing:9) { Image(systemName:symbols[index]).frame(width:18); Text(titles[index]); Spacer(minLength:0) }.font(.system(size:13,weight:navigation.page == index ? .semibold : .regular)).padding(.horizontal,10).padding(.vertical,10).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(navigation.page == index ? .white : .secondary).background(navigation.page == index ? Color.white.opacity(0.10) : .clear,in:RoundedRectangle(cornerRadius:8)).accessibilityLabel(titles[index])
    }
}

/// The existing loopback settings page stays on its existing nonce/Origin API.
struct WorkspaceAccountSettings: View {
    @State private var address:String?
    @State private var finished=false
    @State private var attempt=0
    var body:some View {
        Group {
            if let address { WorkspaceLocalSettingsWeb(address:address) }
            else { VStack(spacing:14) {
                if !finished { ProgressView() }
                Text(finished ? "设置服务暂未就绪" : "正在连接本机设置…").foregroundStyle(.secondary)
                if finished { Button("重试") { attempt += 1 } }
            }.frame(maxWidth:.infinity,maxHeight:.infinity) }
        }.task(id:attempt) {
            finished=false
            for _ in 0..<40 {
                guard !Task.isCancelled else { return }
                if let ready=SettingsServer.shared.address { address=ready; return }
                try? await Task.sleep(for:.milliseconds(250))
            }
            finished=true
        }
    }
}
struct WorkspaceLocalSettingsWeb: NSViewRepresentable {
    let address:String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context:Context) -> WKWebView {
        let view=WKWebView(); view.navigationDelegate=context.coordinator
        view.setValue(false,forKey:"drawsBackground")
        if let url=URL(string:address+"/?embedded=1#feishu") { view.load(URLRequest(url:url)) }
        return view
    }
    func updateNSView(_ view:WKWebView,context:Context) {}
    final class Coordinator:NSObject,WKNavigationDelegate {
        func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
            guard let url=action.request.url else { decisionHandler(.cancel); return }
            if let address=SettingsServer.shared.address, let local=URL(string:address), url.scheme==local.scheme, url.host==local.host, url.port==local.port { decisionHandler(.allow) }
            else { if action.navigationType == .linkActivated, ["http","https"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }; decisionHandler(.cancel) }
        }
    }
}
