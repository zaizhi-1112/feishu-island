import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AgentSetupOption: Identifiable {
    let id:String
    let name:String
    let website:String
    let appNames:[String]
    var native:Bool { ["codex","claude","workbuddy","deepseek"].contains(id) }
    static let all:[Self]=[
        .init(id:"codex",name:"Codex",website:"https://chatgpt.com/codex",appNames:["Codex"]),
        .init(id:"claude",name:"Claude Code",website:"https://claude.ai",appNames:["Claude"]),
        .init(id:"workbuddy",name:"WorkBuddy",website:"https://www.codebuddy.cn",appNames:["WorkBuddy"]),
        .init(id:"doubao",name:"豆包工作",website:"https://www.doubao.com/chat/",appNames:["豆包","Doubao"]),
        .init(id:"kimi",name:"Kimi",website:"https://www.kimi.com",appNames:["Kimi","Kimi Work"]),
        .init(id:"deepseek",name:"DeepSeek Harness",website:"https://www.deepseek.com/harness/",appNames:["DeepSeek Harness"]),
        .init(id:"zhipu",name:"智谱 · GLM",website:"https://chat.z.ai",appNames:["智谱清言"]),
        .init(id:"grok",name:"Grok",website:"https://grok.com",appNames:["Grok"]),
        .init(id:"gemini",name:"Google Gemini",website:"https://gemini.google.com",appNames:["Gemini"]),
        .init(id:"stepfun",name:"阶跃星辰",website:"https://www.stepfun.com",appNames:["阶跃AI","跃问"]),
        .init(id:"xiaomi",name:"小米 MiMo",website:"https://mimo.xiaomi.com",appNames:["MiMo"]),
        .init(id:"chatgpt",name:"ChatGPT / Dot",website:"https://chatgpt.com",appNames:["ChatGPT"]),
        .init(id:"other",name:"其他Agent",website:"",appNames:[])
    ]
    var installedApplication:URL? {
        for directory in ["/Applications",FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path] {
            for name in appNames {
                let url=URL(fileURLWithPath:directory).appendingPathComponent(name+".app")
                if Bundle(url:url)?.bundleIdentifier != nil { return url }
            }
        }
        return nil
    }
}

struct AgentSetupSheet:View {
    @ObservedObject var store:AgentStore
    @Environment(\.dismiss) private var dismiss
    var editingID:String? = nil
    @State private var choice:AgentSetupOption?
    @State private var query=""
    @State private var application:URL?
    @State private var stateFile:URL?
    @State private var name=""
    @State private var error=""
    @State private var method="desktop"
    @State private var manual=false
    @State private var connection:AgentPromptConnection?
    @State private var connectedName=""
    @State private var copied=false
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text(choice.map{"接入"+$0.name} ?? "接入Agent").font(.title2.bold());Spacer();Button("关闭"){dismiss()} }
            if editingID == nil && !manual {
                promptSetup
            } else if let choice {
                Button("返回工具列表") { self.choice=nil;error="" }.buttonStyle(.plain)
                if choice.native {
                    Text(choice.id == "deepseek" ? "沿用 DeepSeek Harness 的登录，显示账户余额与赠送余额。" : "读取本机已有的任务状态。Codex和WorkBuddy还可读取当前账号额度；Claude Code不提供额度时显示未知。")
                    Text("请先打开工具并登录，再启用状态读取。已有设置和数据会保留。").foregroundStyle(.secondary)
                    Button(choice.id == "deepseek" ? "连接余额" : "启用状态读取") { enable(choice.id) }.buttonStyle(.borderedProminent)
                } else {
                    TextField("工具名称",text:$name).textFieldStyle(.roundedBorder)
                    Picker("使用方式",selection:$method) { Text("桌面客户端").tag("desktop");Text("网页版").tag("web") }.pickerStyle(.segmented)
                    if method == "desktop" {
                        HStack { Text(application?.lastPathComponent ?? "尚未选择客户端");Spacer();Button("选择应用…"){pickApplication()} }
                        Text("优先找到这台Mac的客户端；没有安装时可以使用网页版。").font(.caption).foregroundStyle(.secondary)
                    } else if !choice.website.isEmpty { Link("打开官网",destination:URL(string:choice.website)!) }
                    Divider()
                    Text("任务状态与额度").font(.headline)
                    Text("此工具尚无内置自动读取。添加后可保留入口；要显示任务状态或额度，需要让工具持续更新一个本机状态文件。仅打开客户端或网页登录，不代表数据已接通。").font(.system(size:13)).fixedSize(horizontal:false,vertical:true)
                    HStack { Button("选择状态文件…"){pickState()}; Text(stateFile?.lastPathComponent ?? "可稍后设置").font(.caption).foregroundStyle(.secondary) }
                    Button("导出接入说明与示例…"){exportGuide()}.buttonStyle(.plain)
                    Button(stateFile == nil ? "添加工具入口" : "验证并接入状态") { save(choice) }.buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || (method=="desktop" && application==nil && stateFile==nil) || (method=="web" && choice.website.isEmpty && stateFile==nil))
                }
            } else {
                Text("先选工具，再设置接入方式。桌面客户端优先，网页版作为补充。").foregroundStyle(.secondary)
                TextField("搜索工具名称",text:$query).textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                        ForEach(AgentSetupOption.all.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { item in
                            Button { choice=item;name=item.name;application=item.installedApplication;stateFile=nil;method="desktop";error="" } label: {
                                HStack { AgentIdentityIcon(id:item.id,size:24);VStack(alignment:.leading,spacing:5) { Text(item.name).fontWeight(.semibold);Text(item.native ? "本机状态接入" : "客户端 / 网页 · 可接状态文件").font(.caption).foregroundStyle(.secondary) };Spacer() }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary.opacity(0.3),in:RoundedRectangle(cornerRadius:12))
                            }.buttonStyle(.plain).accessibilityIdentifier("agent.setup.\(item.id)")
                        }
                    }
                }
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true) }
        }.padding(24).frame(width:620).frame(minHeight:440,maxHeight:680)
        .task(id:connection?.id) {
            guard let connection else{return}
            while !Task.isCancelled && connectedName.isEmpty {
                do {
                    if ScreenReminderSession.isLocked {try await Task.sleep(for:.seconds(2));continue}
                    if let name=try connection.connect(to:store) {connectedName=name;error="";return}
                } catch {self.error="接入结果还未通过检查："+error.localizedDescription}
                do {try await Task.sleep(for:.seconds(2))} catch{return}
            }
        }
        .onAppear {if let editingID,let p=store.preferences.profiles.first(where:{$0.id==editingID}) {choice=AgentSetupOption.all.first{$0.id==editingID.replacingOccurrences(of:"custom-tool-",with:"")} ?? AgentSetupOption.all.last;name=p.name;application=p.applicationPath.map{URL(fileURLWithPath:$0)};stateFile=p.kind=="file" ? URL(fileURLWithPath:p.dataPath):nil;method=application == nil ? "web":"desktop"}}

    }
    private var promptSetup:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("把提示词交给你的Agent").font(.system(size:20,weight:.semibold))
            Text("无需选择工具或填写路径。Agent识别自己并完成本机配置后，会自动加入“我的工具”。")
                .font(.system(size:14)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if let connection {
                ScrollView {Text(connection.prompt).font(.system(size:13)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(16)}
                    .frame(height:230).background(.quaternary.opacity(0.3),in:RoundedRectangle(cornerRadius:12))
            }
            HStack {
                Button(copied ? "再次复制接入提示词":"复制通用接入提示词") {
                    do {
                        let value=try connection ?? AgentPromptConnection()
                        connection=value
                        NSPasteboard.general.clearContents();NSPasteboard.general.setString(value.prompt,forType:.string)
                        copied=true;error=""
                    } catch {self.error=error.localizedDescription}
                }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("agent.setup.copyPrompt")
                if !connectedName.isEmpty {Label(connectedName+"已接入",systemImage:"checkmark.circle.fill").foregroundStyle(.green)}
                else if copied {Text("等待Agent完成本机配置…").font(.system(size:13)).foregroundStyle(.secondary)}
            }
            Text("请保持此窗口打开。接入后显示真实可取得的数据；没有本机文件能力的网页Agent无法直接接入。")
                .font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if !connectedName.isEmpty {Button("完成"){dismiss()}.buttonStyle(.borderedProminent)}
            else {Button("手动接入已有工具或状态文件"){manual=true;connection=nil;error=""}.buttonStyle(.plain).font(.system(size:12)).foregroundStyle(.secondary)}
        }
    }
    private func enable(_ id:String) {
        var p=store.preferences;p.enabled=true
        if !p.activeMonitorIDs.contains(id) {p.monitoredIDs=p.activeMonitorIDs+[id]}
        do {try store.update(p);dismiss()} catch {self.error=error.localizedDescription}
    }
    private func pickApplication() { let p=NSOpenPanel();p.allowedContentTypes=[.applicationBundle];p.canChooseDirectories=false;p.allowsMultipleSelection=false;p.directoryURL=URL(fileURLWithPath:"/Applications");p.begin { if $0 == .OK,let url=p.url,Bundle(url:url)?.bundleIdentifier != nil {application=url} } }
    private func pickState() { let p=NSOpenPanel();p.allowedContentTypes=[.json];p.canChooseDirectories=false;p.allowsMultipleSelection=false;p.begin {if $0 == .OK {stateFile=p.url}} }
    private func save(_ choice:AgentSetupOption) {
        let id=editingID ?? (choice.id == "other" ? "custom-"+UUID().uuidString.lowercased() : "custom-tool-"+choice.id)
        let existing=store.preferences.profiles.first{$0.id==id}
        var profile=AgentProfile(id:id,name:name.trimmingCharacters(in:.whitespacesAndNewlines),kind:stateFile == nil ? existing?.kind ?? "launcher":"file",dataPath:stateFile?.path ?? existing?.dataPath ?? "")
        profile.applicationPath=method=="desktop" ? application?.path:nil
        profile.launchURL=choice.website.isEmpty ? nil:choice.website
        do {
            if profile.kind=="file" {_=try CustomAgentReader.read(profile)}
            var p=store.preferences
            if let i=p.profiles.firstIndex(where:{$0.id==id}) {p.profiles[i]=profile} else {p.profiles.append(profile)}
            if profile.kind=="file" {p.enabled=true;if !p.activeMonitorIDs.contains(id) {p.monitoredIDs=p.activeMonitorIDs+[id]}}
            try store.update(p);dismiss()
        } catch {self.error=error.localizedDescription}
    }
    private func exportGuide() {
        let panel=NSSavePanel();panel.allowedContentTypes=[.plainText];panel.nameFieldStringValue="Agent状态接入说明.txt"
        panel.begin { response in guard response == .OK,let url=panel.url else{return}
            do {let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];let example=String(decoding:try encoder.encode(CustomAgentReader.example(now:Date().timeIntervalSince1970)),as:UTF8.self)
                let text="让你的工具或适配脚本持续写入本机JSON文件，再在一切在岛中选择该文件。不要填写API密钥、聊天正文或登录凭据。\n\n只提供能实际取得的字段；拿不到的字段请省略。sessions.state可用working、waiting、completed、failed、unknown；updatedAt为Unix秒数。状态与额度超过15分钟显示待更新。完成事件使用唯一completionID防止重复提醒。quotas为0至100的剩余百分比；有实际积分可填写remainingUnits；未知总量用metrics。请使用原子替换写文件，文件不超过256KB。\n\n示例（仅说明格式，不代表真实数据；使用前替换数值和时间）：\n"+example
                try text.write(to:url,atomically:true,encoding:.utf8)
            } catch {self.error=error.localizedDescription}
        }
    }
}
