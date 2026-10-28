import AppKit
import NookApp
import SwiftUI
@testable import IslandShell

import WebKit

enum WorkspaceDeskSection: Int, CaseIterable, Identifiable {
    case agents, reminders, connections, processing, appearance
    var id:Int { rawValue }
    var title:String { ["Agent","待办与提醒","中台与飞书","处理与归档","外观与皮肤"][rawValue] }
    var symbol:String { ["sparkles","checklist","square.grid.2x2","tray.and.arrow.down","paintbrush"][rawValue] }
    var pages:[Int] { switch self {
    case .agents: [0,8,9]
    case .reminders: [1,5]
    case .connections: [2,4]
    case .processing: [3]
    case .appearance: [6,7]
    } }
    static func containing(_ page:Int)->Self { allCases.first { $0.pages.contains(page) } ?? .agents }
    static func label(_ page:Int)->String {
        [0:"交给 AI",8:"接入与签到",9:"状态与额度",1:"待办与定时提醒",5:"冲屏素材",2:"我的中台",4:"账号与消息",3:"处理与归档",6:"灵动岛与交互",7:"Agent 皮肤"][page] ?? "交给 AI"
    }
}

@MainActor final class WorkspaceDeskNavigation: ObservableObject {
    @Published var page = 0
    private var recent:[WorkspaceDeskSection:Int]=[:]
    var section:WorkspaceDeskSection { .containing(page) }
    func select(_ section:WorkspaceDeskSection) {
        recent[self.section]=page
        page=recent[section] ?? section.pages[0]
    }
}

struct WorkspaceDesk: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var navigation: WorkspaceDeskNavigation
    @ObservedObject var catalog:AgentCatalogStore = .shared
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:8) {
                HStack(spacing:9) { Image(systemName:"capsule.fill").foregroundStyle(.cyan); Text("一切在岛").font(.system(size:18,weight:.semibold)) }.padding(.bottom,24)
                ForEach(WorkspaceDeskSection.allCases) { section in
                    Button { navigation.select(section) } label: {
                        HStack(spacing:10) { Image(systemName:section.symbol).frame(width:18); Text(section.title); Spacer(minLength:0) }
                            .font(.system(size:14,weight:navigation.section == section ? .semibold : .regular))
                            .padding(.horizontal,10).padding(.vertical,12).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(navigation.section == section ? .white : .secondary)
                        .background(navigation.section == section ? Color.white.opacity(0.10) : .clear,in:RoundedRectangle(cornerRadius:8))
                        .accessibilityLabel(section.title).accessibilityIdentifier("workspace.section.\(section.rawValue)")
                }
                Spacer()
                HStack(spacing:6) { Circle().fill(store.hub.connected ? .green : .gray).frame(width:5,height:5); Text(store.hub.connected ? "中台已连接" : "中台未连接").font(.system(size:11)).foregroundStyle(.secondary) }
            }.padding(18).frame(width:180).frame(maxHeight:.infinity).background(Color.white.opacity(0.025))
            Divider()
            VStack(alignment:.leading,spacing:0) {
                HStack { Text(navigation.section.title).font(.system(size:22,weight:.semibold)); Spacer(); Text("一切在岛").font(.system(size:11)).foregroundStyle(.secondary) }.padding(.horizontal,24).padding(.top,22).padding(.bottom,16)
                if navigation.section.pages.count > 1 {
                    HStack(spacing:6) {
                        ForEach(navigation.section.pages,id:\.self) { page in
                            Button { navigation.page=page } label: {
                                Text(WorkspaceDeskSection.label(page)).font(.system(size:13,weight:.medium))
                                    .padding(.horizontal,14).padding(.vertical,8)
                            }.buttonStyle(.plain).foregroundStyle(navigation.page == page ? .white : .secondary)
                                .background(navigation.page == page ? Color.white.opacity(0.12) : .clear,in:Capsule())
                                .accessibilityAddTraits(navigation.page == page ? [.isSelected] : [])
                                .accessibilityIdentifier("workspace.destination.\(page)")
                        }
                        Spacer(minLength:0)
                    }.padding(.horizontal,24).padding(.bottom,16)
                }
                Divider()
                pageContent
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(minWidth:760,minHeight:500).background(Color(nsColor:.windowBackgroundColor)).preferredColorScheme(.dark)
    }
    @ViewBuilder private var pageContent:some View {
        if navigation.page == 0 { ScrollView { AgentWorkspaceSurface(agents:.shared,workspace:store,catalog:catalog,desktop:true,onTaskCreated:{navigation.page=1}) } }
        else if navigation.page == 4 { WorkspaceAccountSettings() }
        else if navigation.page == 5 { ScrollView { WorkspaceReminderLibrary(store:store).padding(24) } }
        else if navigation.page == 8 { ScrollView { VStack(alignment:.leading,spacing:24) { AgentConnectionsView(catalog:catalog,workspace:store); Divider(); WorkBuddyCheckinSettings() }.padding(24) } }
        else if navigation.page == 9 { ScrollView { IntegrationAgentSettings(showSkins:false).padding(24) } }
        else if navigation.page == 7 { ScrollView { IntegrationAgentSettings(showMonitoring:false).padding(24) } }
        else if navigation.page == 6 { ScrollView { WorkspaceShellSettings().padding(24) } }
        else { ScrollView { WorkspaceView(store:store,desktop:true,pageOverride:navigation.page,onTaskCreated:{navigation.page=1}) } }
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
