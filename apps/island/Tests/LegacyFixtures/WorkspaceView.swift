import AppKit
import NookApp
import SwiftUI
@testable import IslandShell

import UniformTypeIdentifiers

@MainActor
final class WorkspaceModule: NookModule {
    nonisolated static let info: NookModuleDescriptor = {
        var d = NookModuleDescriptor(id:IslandHost.workspaceID,displayName:"工作台",icon:"tray.and.arrow.down.fill",backgroundPolicy:.stayResident)
        d.loadsAtLaunch = true; return d
    }()
    var descriptor: NookModuleDescriptor { Self.info }
    private let context: NookModuleContext
    init(context: NookModuleContext) { self.context = context }
    func makeConfiguration() -> NookConfiguration {
        var c = IslandHost.baseConfiguration(title:"工作台",symbol:"tray.and.arrow.down.fill")
        c.expandedWidth = 400
        c.allowsHorizontalModuleSwipe = false
        c.topBar.showsStatusBanner = false
        c.topBar.showsSettings = false
        c.onFileDrop = { WorkspaceDrop.acceptFiles($0,store:.shared) }
        c.setCompactLeading { WorkspaceDropMark(store:.shared) }
        c.setCompactTrailing { WorkspaceCompact(store:.shared) }
        c.setHome { WorkspaceHomeSurface() }
        c.onReady = { [context] coordinator in
            let store = WorkspaceStore.shared
            IslandModuleNavigation.shared.bind(coordinator:coordinator)
            IslandModuleAttention.shared.attach(coordinator)
            store.openBoard = { [weak coordinator] in coordinator?.switchModule(to:IslandHost.workspaceID); coordinator?.showNook() }
            store.notify = { title in
                var activity = NookLiveActivity(id:"work-result",priority:.high,lifetime:.transient(.seconds(20)),alert:.peek(.seconds(5)),accessibilityLabel:title) {
                    WorkspaceDropMark(store:store)
                } compactTrailing: { Text("待查看").font(.system(size:10)) } minimal: { Image(systemName:"checkmark.circle") }
                activity.setPeek { Text(title).font(.system(size:13)).padding(8) }
                activity.setExpanded { WorkspaceDropSurface(store:store) { WorkspaceView(store:store) } }
                context.services.resolve(NookLiveActivitiesKey.self).start(activity)
            }
        }
        return c
    }
}
struct WorkspaceCompact: View {
    @ObservedObject var store: WorkspaceStore
    var body: some View { Text(store.disk.items.contains(where:{$0.state == "running"}) ? "处理中" : "工作台").font(.system(size:10)) }
}
struct WorkspaceView: View {
    @ObservedObject var store: WorkspaceStore
    var desktop = false
    var pageOverride: Int? = nil
    var onTaskCreated: (() -> Void)? = nil
    var agentComposer = false
    private var currentTab: Int { pageOverride ?? store.boardTab }
    @ObservedObject var dotPairing = SettingsServer.shared.dotPairing
    @ObservedObject var dotTunnel = DotTunnel.shared
    @State private var confirmDot = false
    @State private var confirmedProject = ""
    @State private var dotCopied = false
    private var input: String { store.draftText }
    @State private var agentCopied = false
    @State private var recoveryURL = ""
    @State private var taskFilter = 0
    private var shownTasks:[WorkItem] { store.disk.items.filter { item in taskFilter == 2 ? item.archivedAt != nil : item.archivedAt == nil && (taskFilter == 1 ? item.state == "done" : item.state != "done") } }
    var body: some View {
        Group {
            if agentComposer {
                VStack(alignment:.leading,spacing:8) { errorMessage; if desktop { materials } else { quickMaterials } }
                    .font(.system(size:12)).frame(maxWidth:.infinity,alignment:.leading)
            } else if desktop {
                VStack(alignment:.leading,spacing:10) {
                    if pageOverride == nil { navigation }
                    errorMessage
                    page
                }.padding(24).frame(maxWidth:.infinity,alignment:.leading)
            } else {
                WorkspaceIslandFrame(preferredHeight:islandHeight) { bodyHeight in
                    VStack(alignment:.leading,spacing:10) {
                        navigation.frame(height:32)
                        ScrollView {
                            VStack(alignment:.leading,spacing:8) {
                                errorMessage
                                page
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }.frame(height:bodyHeight)
                    }.padding(12)
                }.font(.system(size:12))
                .islandHorizontalSwipe { direction in
                    if direction == .previous {
                        if store.boardTab == 0 { IslandModuleNavigation.shared.openFeishu() } else { store.boardTab -= 1 }
                    } else {
                        if store.boardTab == 2 { IslandModuleNavigation.shared.openFeishu() } else { store.boardTab += 1 }
                    }
                }
            }
        }.foregroundStyle(.white)
            .onChange(of:store.boardTab) { _,tab in
                if !desktop && !agentComposer && tab == 0 { IslandModuleNavigation.shared.openAgent() }
            }
            .onAppear { if Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview", !IslandRuntime.isSkinPreview, !ProcessInfo.processInfo.arguments.contains("--self-test") { do { try dotPairing.load() } catch { store.error=error.localizedDescription } } }
            .onChange(of:store.draftProject) { _,_ in dotCopied=false; agentCopied=false }
            .confirmationDialog("连接Dot到「\(confirmedProject)」？",isPresented:$confirmDot,titleVisibility:.visible) {
                Button("允许此项目长期连接并复制") {
                    guard confirmedProject==store.draftProject else { store.error="项目已变化，请重新确认。"; return }
                    SettingsServer.shared.copyDotConnection(store:store); dotCopied=store.error.isEmpty
                }
                Button("取消",role:.cancel) {}
            } message: { Text("仅能领取你主动交给Dot的本项目任务和附件、回传结果。凭据放本机钥匙串，连接时自动续期；30天不连接失效。锁屏暂停，可随时断开。不会读取飞书消息或其他项目。") }
    }
    private var navigation: some View {
            HStack(spacing:4) {
                ForEach([1,2],id:\.self) { i in
                    let title = i == 1 ? "待办" : "中台"
                    Button(title) { store.boardTab = i }.buttonStyle(.plain).padding(.horizontal,10).padding(.vertical,6).background(store.boardTab == i ? Color.white.opacity(0.16) : .clear,in:Capsule())
                }
                Spacer()
                if !desktop { Button { WorkspaceWindow.shared.open(store:store) } label: { Label("工作台",systemImage:"macwindow") }.buttonStyle(.plain).help("打开完整工作台，继续当前草稿").accessibilityLabel("打开完整工作台") }
                else { Button { SettingsServer.shared.open() } label:{ Image(systemName:"gearshape") }.buttonStyle(.plain).help("设置与连接") }
            }
    }
    @ViewBuilder private var errorMessage: some View {
        if !store.error.isEmpty { Text(store.error).font(.system(size:12)).foregroundStyle(.orange).textSelection(.enabled).fixedSize(horizontal:false,vertical:true) }
    }
    @ViewBuilder private var page: some View {
        if currentTab == 0 { if desktop { materials } else { quickMaterials } }
        else if currentTab == 1 { tasks }
        else if currentTab == 3 { processingSettings }
        else { cards }
    }
    private var archiveSummary: String {
        ["off":"仅保留本机","new":"新建飞书文档","append":"追加飞书文档","base":"收录到多维表格"][store.draftArchive.mode] ?? "归档设置"
    }
    private var dotNeedsAttention: Bool {
        store.draftService == "dot" && dotPairing.grant(project:store.draftProject)?.subscription.map({$0.expires>Date()}) != true
    }
    private var islandHeight: CGFloat {
        guard store.boardTab == 0, store.error.isEmpty else { return WorkspaceLayout.maximumHeight }
        return 236 + ((!store.draftFiles.isEmpty || !store.draftImages.isEmpty) ? 42 : 0) + (dotNeedsAttention ? 24 : 0)
    }
    private var quickMaterials: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:8) {
                TextField("项目",text:$store.draftProject).textFieldStyle(.roundedBorder).accessibilityLabel("当前项目")
                if !agentComposer { Picker("交给谁",selection:$store.draftService) {
                    Text(WorkAI.displayName).tag("codex"); Text("豆包工作").tag("doubao"); Text("Dot").tag("dot"); Text("WorkBuddy").tag("workbuddy")
                }.labelsHidden().frame(width:110).accessibilityLabel("处理工具") }
            }
            WorkInputEditor(text:$store.draftText,pasteImage:{store.attachImage($0)})
                .padding(6).frame(height:82).background(.white.opacity(0.08),in:RoundedRectangle(cornerRadius:8)).accessibilityLabel("材料输入")
            if !store.draftFiles.isEmpty || !store.draftImages.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing:6) {
                        ForEach(store.draftFiles,id:\.self) { file in
                            HStack(spacing:4) {
                                Image(systemName:"doc")
                                Text(file.lastPathComponent).lineLimit(1).frame(maxWidth:112)
                                Button { store.draftFiles.removeAll{$0==file} } label: { Image(systemName:"xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("移除附件："+file.lastPathComponent)
                            }.padding(5).background(.white.opacity(0.08),in:RoundedRectangle(cornerRadius:6))
                        }
                        ForEach(store.draftImages) { image in
                            HStack(spacing:4) {
                                if let ns=NSImage(data:image.data) { Image(nsImage:ns).resizable().scaledToFit().frame(width:30,height:24) }
                                Button { store.draftImages.removeAll{$0.id==image.id} } label: { Image(systemName:"xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("移除图片："+image.image.name)
                            }.padding(3).background(.white.opacity(0.08),in:RoundedRectangle(cornerRadius:6))
                        }
                    }.font(.system(size:11))
                }.frame(height:34)
            }
            Button { WorkspaceWindow.shared.openProcessing(store:store) } label: {
                HStack(spacing:4) {
                    Text(archiveSummary).lineLimit(1)
                    Text("· "+(store.draftReminderMinutes == 0 ? "不提醒" : "\(store.draftReminderMinutes)分钟提醒")).lineLimit(1)
                    Spacer(minLength:0)
                    Image(systemName:"slider.horizontal.3")
                }.font(.system(size:11)).foregroundStyle(.secondary)
            }.buttonStyle(.plain).help("配置处理方式、归档位置和提醒").accessibilityLabel("处理与归档设置")
            if dotNeedsAttention {
                Button("检查 Dot 连接") { WorkspaceWindow.shared.openProcessing(store:store) }.font(.system(size:11)).foregroundStyle(.orange)
            }
            HStack(spacing:7) {
                Button { store.pickFiles() } label: { Image(systemName:"paperclip") }.help("添加附件").accessibilityLabel("添加附件")
                Button { store.pasteMaterial() } label: { Image(systemName:"doc.on.clipboard") }.help("粘贴文字或图片").accessibilityLabel("粘贴")
                Spacer(minLength:0)
                Button("存待办") { add(run:false) }
                if store.draftArchive.mode != "off" { Button("归档") { add(run:false,archiveOnly:true) }.help("直接归档，不调用AI").accessibilityLabel("直接归档，不调用AI").disabled(store.webBusy) }
                Button(store.webBusy ? "提取中…" : "交给AI") { add(run:true) }.disabled(store.webBusy).buttonStyle(.borderedProminent).tint(.orange)
            }.controlSize(.small)
        }
    }
    private var materials: some View {
        VStack(alignment:.leading,spacing:9) {
            HStack {
                TextField("项目",text:$store.draftProject).textFieldStyle(.roundedBorder).frame(maxWidth:desktop ? 280 : 170)
                if desktop { Button("归纳这个项目") { store.summarizeProject() }; Button(agentCopied ? "已复制连接" : "接入Agent") { SettingsServer.shared.copyWorkspaceConnection(store:store); agentCopied = SettingsServer.shared.workspaceAgent.active }.help("复制当前项目已有任务的MCP连接，30分钟有效；不包含聊天、凭据或其他项目。") }
                Spacer()
            }.font(.system(size:12))
            HStack { WorkspaceDropMark(store:store).frame(width:32,height:32); Text("放下材料，接着做你的事").font(.system(size:15,weight:.semibold)); Spacer() }
            WorkInputEditor(text:$store.draftText,pasteImage:{store.attachImage($0)}).padding(6).frame(height:desktop ? 160 : 72).background(.white.opacity(0.08),in:RoundedRectangle(cornerRadius:8))
            ForEach(store.draftFiles,id:\.self) { file in
                HStack { Text(file.lastPathComponent).lineLimit(1); Button("移除") { store.draftFiles.removeAll{$0==file} } }.font(.system(size:11))
            }
            if !store.draftImages.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing:8) {
                        ForEach(store.draftImages) { image in
                            VStack(spacing:3) {
                                if let ns = NSImage(data:image.data) { Image(nsImage:ns).resizable().scaledToFit().frame(width:54,height:38) }
                                Button("移除") { store.draftImages.removeAll{$0.id == image.id} }.font(.system(size:10)).accessibilityLabel("移除图片："+image.image.name)
                            }.help(image.image.name)
                        }
                    }
                }.frame(height:62)
            }
            HStack(spacing:12) {
                if !agentComposer { Picker("交给谁",selection:$store.draftService) {
                    Text(WorkAI.displayName).tag("codex"); Text("豆包工作").tag("doubao"); Text("Dot").tag("dot"); Text("WorkBuddy").tag("workbuddy")
                } }
                Picker("处理方式",selection:$store.draftRecipe) { ForEach(store.disk.recipes) { Text($0.title).tag($0.id) } }
            }.font(.system(size:13))
            Button { WorkspaceWindow.shared.openProcessing(store:store) } label: {
                HStack { Text(archiveSummary); Text("· \(store.draftReminderMinutes)分钟提醒"); Spacer(); Image(systemName:"slider.horizontal.3") }
            }.buttonStyle(.plain).font(.system(size:12)).foregroundStyle(.secondary).padding(.vertical,8)
            if store.chromeDraft { Text("网页正文已放入，可直接编辑。").font(.system(size:12)).foregroundStyle(.secondary) }
            if dotNeedsAttention { Button("检查 Dot 连接") { WorkspaceWindow.shared.openProcessing(store:store) }.font(.system(size:12)).foregroundStyle(.orange) }
            HStack {
                Button("添加附件") { store.pickFiles() }
                Button("粘贴") { store.pasteMaterial() }
                Button("存待办") { add(run:false) }
                Spacer()
                if store.draftArchive.mode != "off" { Button("直接归档") { add(run:false,archiveOnly:true) }.disabled(store.webBusy) }
                Button(store.webBusy ? "提取中…" : "交给AI") { add(run:true) }.disabled(store.webBusy).buttonStyle(.borderedProminent).tint(.orange)
            }.font(.system(size:13)).padding(.vertical,6)
            Button("读取上方飞书文档链接") { store.readFeishuMaterial(input,instruction:store.disk.recipes.first(where:{$0.id == store.draftRecipe})?.instruction); store.boardTab = 1; onTaskCreated?() }.font(.system(size:11))
            HStack { Text("\(store.disk.items.filter{$0.state != "done"}.count)项未完成").foregroundStyle(.secondary); Spacer() }.font(.system(size:11))
        }
    }
    private var processingSettings: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("网页收录").font(.system(size:16,weight:.semibold))
            Toggle("接收Chrome当前网页",isOn:$store.chromeImportEnabled).font(.system(size:12))
            if store.chromeImportEnabled { Text("在Chrome点一切在岛收录按钮，预览后送入此处；只收录当前页面，不读取登录凭据。").font(.system(size:10)).foregroundStyle(.secondary) }
            if store.chromeDraft { Text("已从Chrome读取正文，可编辑后分析或直接归档；不会再次联网抓取其中链接。").font(.system(size:11)).foregroundStyle(.secondary) }
            Toggle("读取公开链接正文",isOn:$store.readWebLinks).font(.system(size:12)).disabled(store.webBusy)
            if store.readWebLinks {
                HStack {
                    Button(store.webBusy ? "正在提取…" : "提取并查看正文") { store.previewLinks() }.disabled(store.webBusy)
                    Text("仅公开网页；不带登录信息，不执行网页脚本").font(.system(size:10)).foregroundStyle(.secondary)
                }
                ForEach(store.webPages,id:\.source) { page in
                    DisclosureGroup(page.title+" · "+String(page.text.count)+"字") {
                        ScrollView { Text(page.material).font(.system(size:12)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }.frame(maxHeight:desktop ? 220 : 100)
                    }.font(.system(size:12))
                }
                Text("交给AI或直接归档时，会先提取正文；失败时保留输入，不提交。存待办只保存原材料。").font(.system(size:10)).foregroundStyle(.secondary)
            }
            Divider().padding(.vertical,8)
            Text("AI 连接与处理").font(.system(size:16,weight:.semibold))
            Text(store.draftService == "dot" ? "Dot 在后台领取任务，完整结果回到待办，成功摘要出现在自己的 Dot 主对话。" : store.draftService == "doubao" ? "豆包在你的专属工作伙伴中新建任务；处理后可从待办打开原任务继续查看。" : store.draftService == "workbuddy" ? "WorkBuddy 在后台处理，完整结果保存在本项目待办，并按你选择的位置归档。" : "Codex 在后台逐条处理材料，不打开桌面聊天窗口；每次为独立任务，完整结果保存在本项目待办。").font(.system(size:13)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Picker("交给谁",selection:$store.draftService) {
                Text(WorkAI.displayName+" · 本机").tag("codex")
                Text("豆包工作 · 本人已登录网页").tag("doubao")
                Text("Dot · 已配对项目").tag("dot")
                Text("WorkBuddy · 本机已登录客户端").tag("workbuddy")
            }.font(.system(size:12))
            if store.draftService == "dot" {
                HStack {
                    Text(dotPairing.grant(project:store.draftProject) == nil ? "Dot待配对" : "Dot已配对").font(.system(size:11))
                    if desktop {
                        Button(dotCopied ? "已复制Dot连接" : "连接Dot") { confirmedProject=store.draftProject; confirmDot=true }
                        Button("断开") { do { try dotPairing.disconnect(project:store.draftProject); DotTunnel.shared.stop(); dotCopied=false } catch { store.error=error.localizedDescription } }.disabled(dotPairing.grant(project:store.draftProject)==nil)
                    } else { Button("连接设置") { WorkspaceWindow.shared.open(store:store) } }
                }.font(.system(size:11))
                DisclosureGroup("连接详情") {
                if let seen=dotPairing.grant(project:store.draftProject)?.lastSeen { Text("最后连接："+seen.formatted(date:.abbreviated,time:.shortened)).font(.system(size:10)).foregroundStyle(.secondary) }
                Text(dotTunnel.status).font(.system(size:10)).foregroundStyle(.secondary)
                Text(dotPairing.grant(project:store.draftProject)?.subscription.map { $0.expires>Date() ? "任务通知已订阅：交给AI后自动通知Dot；通知送达后仍需Dot领取处理。Mac和ChatGPT须在线。" : "Dot通知订阅已过期，需在Dot中恢复订阅。" } ?? "尚未订阅自动通知：需先在Dot安装私人插件并订阅本项目；配对本身不会唤醒Dot。").font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }.font(.system(size:12))
            }
            Picker("处理方式",selection:$store.draftRecipe) { ForEach(store.disk.recipes) { r in Text(r.title).tag(r.id) } }.font(.system(size:12))
            Divider().padding(.vertical,8)
            Text("归档到哪里").font(.system(size:16,weight:.semibold))
            Picker("处理后归档",selection:$store.draftArchive.mode) {
                Text("仅保留本机").tag("off")
                Text("新建飞书文档").tag("new")
                Text("追加到已有文档").tag("append")
                Text("多维表格新增记录").tag("base")
            }.font(.system(size:12))
            if ["append","base"].contains(store.draftArchive.mode) {
                TextField(store.draftArchive.mode == "base" ? "多维表格链接（含 table）" : "飞书云文档链接",text:$store.draftArchive.url).textFieldStyle(.roundedBorder)
            }
            if store.draftArchive.mode == "base" {
                Button(store.archiveFieldsBusy ? "正在读取…" : "读取表格，选择收录列") { store.loadArchiveFields() }.disabled(store.archiveFieldsBusy)
                if !store.archiveFields.isEmpty { Picker("收录到",selection:$store.draftArchive.field) { ForEach(store.archiveFields,id:\.self) { Text($0).tag($0) } } }
                else { TextField("收录列名称",text:$store.draftArchive.field).textFieldStyle(.roundedBorder) }
                Text("新增一条记录，附归档文档链接；完整材料与图片附件保存在该文档。不会修改已有记录。").font(.system(size:10)).foregroundStyle(.secondary)
            }
            if store.draftArchive.mode != "off" {
                Text("归档由程序执行，不调用AI分类。需要独立飞书归档授权。").font(.system(size:10)).foregroundStyle(.secondary)
                Button("直接归档，不调用AI") { add(run:false,archiveOnly:true) }.disabled(store.webBusy).font(.system(size:12))
            }
            Divider().padding(.vertical,8)
            Text("新待办的默认提醒").font(.system(size:16,weight:.semibold))
            HStack {
                Text("提醒").font(.system(size:12))
                Picker("提醒时间",selection:$store.draftReminderMinutes) { ForEach(Array(Set([0,5,20,60,store.draftReminderMinutes])).sorted(),id:\.self) { value in Text(value == 0 ? "不提醒" : "\(value)分钟").tag(value) } }.labelsHidden().frame(width:100)
                Spacer()
            }.font(.system(size:12))

            ScreenReminderChoice(store:store,selection:$store.draftScreenReminder)
            Button("导入材料 Skill") { store.importSkill() }
        }.frame(maxWidth:680,alignment:.leading)
    }
    private func add(run: Bool,archiveOnly:Bool = false) {
        guard !store.webBusy else { return }
        let original=input, target=store.draftArchive, files=store.draftFiles, images=store.draftImages, screenStyle=store.draftScreenReminder
        let project=store.draftProject, service=store.draftService, reminder=store.draftReminderMinutes, recipe=store.draftRecipe
        let instruction=store.disk.recipes.first(where:{$0.id == recipe})?.instruction
        Task {
            do {
                try target.validate()
                let material = (run || archiveOnly) ? try await store.preparedLinkInput() : original
                guard store.draftText==original, store.draftArchive==target, store.draftProject==project,
                      store.draftService==service, store.draftRecipe==recipe, store.draftReminderMinutes==reminder, store.draftScreenReminder==screenStyle,
                      store.draftFiles==files, store.draftImages.map(\.id)==images.map(\.id) else { throw WorkError.message("材料或选项已变化，本次未提交。") }
                let id = try store.add(text:material,files:files,instruction:instruction,minutes:reminder,images:images,project:project,service:service)
                try store.configureArchive(id,target:target)
                store.draftText = ""; store.draftImages = []; store.draftFiles = []; store.boardTab = 1
                onTaskCreated?()
                if archiveOnly { store.queueArchive(id) } else if run { store.run(id) }
            } catch { store.error = error.localizedDescription }
        }
    }
    private var tasks: some View {
            VStack(alignment:.leading,spacing:12) {
                WorkspaceReminderShelf(store:store,compact:!desktop)
                HStack { Text("待办").font(.system(size:desktop ? 17 : 13,weight:.semibold)); Spacer(); Text("\(store.disk.items.filter{$0.state != "done"}.count)项待处理").font(.system(size:11)).foregroundStyle(.secondary) }.padding(.top,4)
                Picker("待办范围",selection:$taskFilter) { Text("进行中").tag(0); Text("已完成").tag(1); Text("已归档").tag(2) }.pickerStyle(.segmented)
                if shownTasks.isEmpty { Text("把材料拖进来，或在“材料”里存一条待办。").font(.system(size:13)).foregroundStyle(.secondary).padding(.vertical,20) }
                ForEach(shownTasks) { item in
                    VStack(alignment:.leading,spacing:7) {
                        HStack(alignment:.top,spacing:8) {
                            Button { store.selected = store.selected == item.id ? nil : item.id } label: {
                                VStack(alignment:.leading,spacing:5) {
                                    Text(item.title).font(.system(size:desktop ? 15 : 12,weight:.medium)).lineLimit(2).multilineTextAlignment(.leading)
                                    Text(label(item.state)+(item.screenReminder == nil ? "" : " · 冲屏提醒")).font(.system(size:10)).foregroundStyle(.secondary)
                                }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if item.archivedAt != nil {
                                Button { store.unarchiveItem(item.id) } label: { Image(systemName:"arrow.uturn.backward") }.buttonStyle(.plain).padding(4).help("移回已完成")
                            } else if item.state == "done" {
                                Button { store.archiveItem(item.id) } label: { Image(systemName:"archivebox") }.buttonStyle(.plain).padding(4).help("归档待办（保留材料）")
                            }
                            Button { store.selected=item.id; store.beginEdit(item.id) } label: { Image(systemName:"pencil") }.buttonStyle(.plain).padding(4).disabled(!WorkspaceStore.canEdit(item) || item.archivedAt != nil).help("编辑待办").accessibilityLabel("编辑："+item.title)
                            Button(role:.destructive) { store.deleteItem(item.id) } label: { Image(systemName:"trash") }.buttonStyle(.plain).padding(4).disabled(["running","queued","dot_running"].contains(item.state)).help("删除待办（可恢复）").accessibilityLabel("删除："+item.title)
                        }
                        if store.selected == item.id {
                            Divider().padding(.vertical,4)
                            ScreenReminderChoice(store:store,selection:Binding(get:{item.screenReminder},set:{store.setTaskScreenReminder(item.id,style:$0)}))
                            if item.due == nil && item.state != "done" { Button("设置提醒时间") { store.setReminder(item.id,date:Date().addingTimeInterval(1200)) }.font(.system(size:11)) }
                            if let due = item.due { DatePicker(item.reminded ? "再次提醒" : "提醒时间",selection:Binding(get:{due},set:{store.setReminder(item.id,date:$0)}),displayedComponents:[.date,.hourAndMinute]).datePickerStyle(.field).font(.system(size:10)) }
                            Text((item.project ?? "日常工作")+" · "+item.created.formatted(date:.abbreviated,time:.shortened)).font(.system(size:10)).foregroundStyle(.secondary)
                            if store.editingID == item.id {
                                TextField("标题",text:$store.editTitle).textFieldStyle(.roundedBorder).accessibilityLabel("待办标题")
                                TextField("项目",text:$store.editProject).textFieldStyle(.roundedBorder).accessibilityLabel("待办项目")
                                Text("内容").font(.system(size:11))
                                WorkInputEditor(text:$store.editInput,pasteImage:{_ in}).frame(height:110).accessibilityLabel("待办内容")
                                TextField("处理要求",text:$store.editInstruction).textFieldStyle(.roundedBorder).accessibilityLabel("待办处理要求")
                                Text("修改内容或处理要求后，需重新交给AI处理。").font(.system(size:10)).foregroundStyle(.secondary)
                                HStack { Button("保存修改") { store.saveEdit() }; Button("取消修改") { store.cancelEdit() } }.font(.system(size:11))
                            } else {
                                Text(item.result.isEmpty ? String(item.input.prefix(500)) : item.result).font(.system(size:13)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                            }
                            if let images = item.images, !images.isEmpty {
                                HStack {
                                    ForEach(images) { image in
                                        Button { NSWorkspace.shared.open(store.imageURL(item:item,image:image)) } label: {
                                            if let ns = NSImage(contentsOf:store.imageURL(item:item,image:image)) { Image(nsImage:ns).resizable().scaledToFit().frame(width:48,height:40) }
                                            else { Image(systemName:"photo") }
                                        }.help(image.name)
                                    }
                                }
                            }
                            if item.service == "doubao", item.remoteSubmissionPending == true, item.remoteTaskURL == nil, !["running","queued"].contains(item.state) {
                                TextField("豆包原任务链接",text:$recoveryURL).textFieldStyle(.roundedBorder)
                                Button("关联原任务") {
                                    let value = recoveryURL.trimmingCharacters(in:.whitespacesAndNewlines)
                                    if WorkBrowser.validTask(value) { store.recordRemoteURL(item.id,url:value); recoveryURL = "" }
                                    else { store.error = "请使用豆包原任务的完整链接。" }
                                }.font(.system(size:11))
                            }
                            if let link = item.remoteTaskURL, WorkBrowser.validTask(link), let url = URL(string:link) { Link("打开豆包原任务",destination:url).font(.system(size:11)) }
                            ForEach(item.cloudDocuments ?? [],id:\.self) { link in if WorkBrowser.validDocument(link), let url=URL(string:link) { Link(item.exportVerifiedAt == nil ? "查看飞书文档（待回读核对）" : "打开飞书文档（已回读核对）",destination:url).font(.system(size:11)) } }
                            if let timing=WorkTaskTiming.summary(item) { Text(timing).font(.system(size:12)).foregroundStyle(.secondary) }
                            if let source = item.resultSource { Text("结果来源："+source).font(.system(size:10)).foregroundStyle(.secondary) }
                            if item.service == "dot", !item.result.isEmpty { Text("Dot 后台结果已返回；成功摘要同步到你自己的 Dot 主对话。").font(.system(size:10)).foregroundStyle(.secondary) }
                            if let archive=item.archive {
                                Text(archive.state == "succeeded" ? "飞书归档已完成" : archive.state == "running" ? "正在归档到飞书…" : archive.state == "pending" ? "等待归档" : "归档未完成："+archive.error).font(.system(size:11)).foregroundStyle(archive.state == "failed" ? .orange : .secondary)
                                if let doc=archive.document, let url=URL(string:doc) { Link("打开归档文档",destination:url).font(.system(size:11)) }
                                if archive.target.mode == "base", archive.record != nil, let url=URL(string:archive.target.url) { Link("打开多维表格",destination:url).font(.system(size:11)) }
                                if archive.state == "failed", archive.intent == nil { Button("只重试归档") { store.retryArchive(item.id) }.font(.system(size:11)) }
                            }
                            if !item.failure.isEmpty { Text(item.failure).font(.system(size:11)).foregroundStyle(.orange) }
                            if item.service=="dot", item.state=="dot_waiting", let deliveries=item.dotDeliveries, !deliveries.isEmpty {
                                if deliveries.values.contains(where:{$0.accepted}) { Text("通知已送达 · 等待Dot领取").font(.system(size:11)).foregroundStyle(.secondary) }
                                else if deliveries.values.allSatisfy({$0.stopped}) { HStack { Text(deliveries.values.contains(where:{DotEvents.transient($0.status)}) ? "断线等待恢复，稍后自动重试" : "通知被拒绝，需检查Dot连接"); Button("重试通知") { store.retryDotNotification(item.id) } }.font(.system(size:11)).foregroundStyle(.orange) }
                                else { Text("通知正在重试").font(.system(size:11)).foregroundStyle(.secondary) }
                            }
                            HStack {
                                if ["running","queued","dot_waiting","dot_running"].contains(item.state) { Button(item.service == "doubao" ? "停止等候" : "取消") { store.cancel(item.id) } }
                                else if item.state != "done" { Button(item.result.isEmpty ? "交给AI" : "重新处理") { store.run(item.id) }; Button("完成") { store.complete(item.id) } }
                                Button("稍后20分") { store.snooze(item.id) }
                            }.font(.system(size:11))
                            if !item.result.isEmpty { HStack { Button("复制结果") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.result,forType:.string) }; Button("存文档") { store.exportDocument(item) }; Button("存到飞书") { store.saveToFeishu(item) } }.font(.system(size:11)) }
                        }
                    }.padding(10).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:10))
                }
                if let trash=store.disk.trash, !trash.isEmpty {
                    DisclosureGroup("已删除（\(trash.count)）") {
                        ForEach(trash) { item in HStack { Text(item.title).lineLimit(2); Spacer(); Button("恢复") { store.restoreItem(item.id) }.accessibilityLabel("恢复："+item.title) }.font(.system(size:11)).padding(.vertical,4) }
                    }.font(.system(size:12)).padding(8)
                }
            }
    }
    private func label(_ state: String) -> String { ["dot_waiting":"等待Dot领取","dot_running":"Dot处理中","todo":"待办","queued":"排队中","running":"处理中","succeeded":"已完成 · 可取结果","failed":"处理失败","interrupted":"上次中断","done":"已处理"][state] ?? state }
    private var cards: some View { WorkspaceHubView(store:store,desktop:desktop) }
}

/// A concrete root keeps the macOS 15 Sendable boundary at the module closure.
struct WorkspaceHomeSurface: View, Sendable {
    var body:some View {
        WorkspaceDropSurface(store:.shared) { WorkspaceView(store:.shared) }
            .modifier(IslandReadingModule(moduleID:IslandHost.workspaceID))
            .onAppear { if WorkspaceStore.shared.boardTab == 0 { WorkspaceStore.shared.boardTab = 1 } }
    }
}
