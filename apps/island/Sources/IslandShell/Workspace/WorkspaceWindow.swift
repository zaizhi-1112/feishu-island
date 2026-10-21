import AppKit
import SwiftUI

/// A normal, user-opened work window; never a desktop overlay or automatic popup.
@MainActor
final class WorkspaceWindow {
    static let shared = WorkspaceWindow()
    private var window: NSWindow?
    func open(store: WorkspaceStore) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        let w = NSWindow(contentRect:NSRect(x:0,y:0,width:808,height:700),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        w.title = "飞书工作岛 · 个人工作台"; w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView:WorkspaceDesk(store:store)); w.center(); window = w
        w.makeKeyAndOrderFront(nil); NSApp.activate()
    }
}
struct WorkspaceDesk: View {
    @ObservedObject var store: WorkspaceStore
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text("你的工作台").font(.system(size:23,weight:.semibold))
                    Text("记录、材料、处理结果和项目进展，放在一起。").foregroundStyle(.secondary)
                }
                Spacer()
                Text("AI："+(store.draftService == "dot" ? "Dot" : store.draftService == "doubao" ? "豆包工作" : WorkAI.displayName)+"  ·  中台："+(store.hub.connected ? "已连接" : "待连接")).font(.system(size:12)).foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            ScrollView { WorkspaceView(store:store,desktop:true) }
        }.frame(minWidth:808,minHeight:620).background(Color(nsColor:.windowBackgroundColor)).preferredColorScheme(.dark)
    }
}
