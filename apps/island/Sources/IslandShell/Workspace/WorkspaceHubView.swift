import SwiftUI

/// Island reading shows one complete card at a time; management lives in the workbench.
struct WorkspaceHubView: View {
    @ObservedObject var store:WorkspaceStore
    var desktop=false
    @State private var selectedID:String?
    private var cards:[HubCard] { store.visibleCards }
    private var selected:HubCard? { cards.first(where:{$0.id==selectedID}) ?? cards.first }
    var body:some View {
        VStack(alignment:.leading,spacing:desktop ? 20 : 14) {
            HStack {
                VStack(alignment:.leading,spacing:4) {
                    Text("我的中台").font(.system(size:desktop ? 20 : 15,weight:.semibold))
                    if let at=store.hub.readAt { Text("更新于 "+at.formatted(date:.omitted,time:.shortened)).font(.system(size:12)).foregroundStyle(.secondary) }
                }
                Spacer()
                Button { Task { await store.refreshHub() } } label: { Image(systemName:"arrow.clockwise").frame(width:28,height:28) }.buttonStyle(.plain).accessibilityLabel("刷新中台卡片")
                if !desktop { Button { WorkspaceWindow.shared.openHub(store:store) } label: { Image(systemName:"slider.horizontal.3").frame(width:28,height:28) }.buttonStyle(.plain).accessibilityLabel("管理中台卡片") }
            }
            if !store.hub.error.isEmpty { Text(store.hub.error).font(.system(size:14)).foregroundStyle(.orange) }
            if !store.hub.connected {
                Text("把自己的计划和进展，放在随手可看的地方。").font(.system(size:15)).foregroundStyle(.secondary)
                Button("连接虚实中台") { if let a=SettingsServer.shared.address { store.connectHub(callback:a+"/oauth/virxact/callback") } }
            } else if desktop {
                ForEach(cards) { card in
                    VStack(alignment:.leading,spacing:14) {
                        HStack { Text(card.title).font(.system(size:18,weight:.semibold)); Spacer(); Button { store.moveCard(card.id,direction:-1) } label:{Image(systemName:"arrow.up")}.accessibilityLabel("上移："+card.title); Button { store.moveCard(card.id,direction:1) } label:{Image(systemName:"arrow.down")}.accessibilityLabel("下移："+card.title); Button("移出灵动岛") { store.toggleCard(card.id) } }.font(.system(size:12))
                        Text(HubCardPresentation.displayText(card.text)).font(.system(size:17)).lineSpacing(7).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                    }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:14))
                }
                Divider().padding(.vertical,6)
                Text("放入灵动岛").font(.system(size:17,weight:.semibold))
                ForEach(store.hub.cards) { card in
                    Button { store.toggleCard(card.id) } label:{ HStack(spacing:12) { Image(systemName:store.disk.selectedCards.contains(card.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(store.disk.selectedCards.contains(card.id) ? .orange : .secondary); Text(card.title); Spacer() }.font(.system(size:15)).padding(.vertical,8).contentShape(Rectangle()) }.buttonStyle(.plain)
                }
            } else if let card=selected {
                if cards.count>1 {
                    HStack {
                        Button { move(-1) } label:{Image(systemName:"chevron.left").frame(width:28,height:28)}.accessibilityLabel("上一张中台卡片")
                        Spacer(); Text("\((cards.firstIndex(where:{$0.id==card.id}) ?? 0)+1) / \(cards.count)").font(.system(size:12)).foregroundStyle(.secondary); Spacer()
                        Button { move(1) } label:{Image(systemName:"chevron.right").frame(width:28,height:28)}.accessibilityLabel("下一张中台卡片")
                    }.buttonStyle(.plain)
                }
                Text(card.title).font(.system(size:17,weight:.semibold)).fixedSize(horizontal:false,vertical:true)
                Text(HubCardPresentation.displayText(card.text)).font(.system(size:16)).lineSpacing(6).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                Text("完整内容 · 上下滚动阅读").font(.system(size:12)).foregroundStyle(.secondary).padding(.top,4)
            } else {
                Text("还没放入卡片").font(.system(size:17,weight:.semibold))
                Text("选择你常看的计划、进展或数据。").font(.system(size:15)).foregroundStyle(.secondary)
                Button("选择卡片") { WorkspaceWindow.shared.openHub(store:store) }
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func move(_ direction:Int) {
        guard !cards.isEmpty else { return }
        let index=cards.firstIndex(where:{$0.id==selected?.id}) ?? 0
        selectedID=cards[(index+direction+cards.count)%cards.count].id
    }
}

enum HubCardPresentation {
    static func displayText(_ text:String) -> String {
        text.replacingOccurrences(of:#"(?<=[。；;])\s*(?=[0-9]{1,2}[.、](?![0-9]))"#,with:"\n\n",options:.regularExpression)
    }
}
