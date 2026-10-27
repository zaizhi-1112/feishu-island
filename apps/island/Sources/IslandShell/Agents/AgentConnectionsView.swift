import SwiftUI

/// Configuration is outside the small island. Adding an entry grants no access.
struct AgentConnectionsView:View {
    @ObservedObject var catalog:AgentCatalogStore = .shared
    @ObservedObject var workspace:WorkspaceStore
    @State private var name=""
    @State private var address=""
    @State private var feedback=""
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            Text("常用 Agent").font(.system(size:20,weight:.semibold))
            ForEach(AgentCatalogStore.builtins) { entry in
                HStack {
                    Text(entry.name).font(.system(size:16,weight:.medium))
                    Spacer()
                    Text(entry.taskProvider != nil ? "可交给 AI" : "本机状态提醒 · 可配置项目连接")
                        .font(.system(size:13)).foregroundStyle(.secondary)
                    if ["claude", "workbuddy"].contains(entry.id) {
                        Button("连接状态提醒") { AgentStore.shared.connectStatus(entry.id); feedback="正在配置 "+entry.name+" 状态事件；已打开的客户端若未生效，请新建任务后查看。" }
                    }
                    Button("选择") { catalog.select(entry.id,in:workspace); AgentStore.shared.monitorSelected(entry.id); feedback="已选择 "+entry.name }
                }
            }
            Divider()
            Text("添加其他 Agent").font(.system(size:20,weight:.semibold))
            TextField("名称，例如你的常用助手",text:$name).accessibilityLabel("Agent名称")
            TextField("网页版入口（选填，HTTPS地址）",text:$address).accessibilityLabel("Agent入口地址")
            Text("这里只保存名称和入口。连接在对应 Agent 中配置；不会自动获得飞书、其他项目或账号的访问权限。")
                .font(.system(size:14)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Button("添加到 Agent 列表") {
                if let error=catalog.add(name:name,url:address) { feedback=error }
                else { name=""; address=""; feedback="已添加，可从岛内“更多 Agent”选择。" }
            }.buttonStyle(.borderedProminent)
            if !feedback.isEmpty { Text(feedback).font(.system(size:14)).accessibilityLabel(feedback) }
            ForEach(catalog.custom) { entry in
                HStack {
                    VStack(alignment:.leading,spacing:4) { Text(entry.name).font(.system(size:16)); if !entry.launchURL.isEmpty { Text(entry.launchURL).font(.system(size:12)).foregroundStyle(.secondary).lineLimit(1) } }
                    Spacer()
                    Button("选择") { catalog.select(entry.id,in:workspace); AgentStore.shared.monitorSelected(entry.id); feedback="已选择 "+entry.name }
                    Button("移除入口") { catalog.remove(entry.id); feedback="已移除入口，已有任务保持。" }
                }
            }
        }.textFieldStyle(.roundedBorder).frame(maxWidth:680,alignment:.leading)
    }
}
