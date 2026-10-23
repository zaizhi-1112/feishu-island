import NookApp
import SwiftUI
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
        c.topBar.showsStatusBanner = false
        c.topBar.showsSettings = false
        c.onFileDrop = { WorkspaceDrop.acceptFiles($0,store:.shared) }
        c.setCompactLeading { WorkspaceDropMark(store:.shared) }
        c.setCompactTrailing { WorkspaceCompact(store:.shared) }
        c.setHome { WorkspaceDropSurface(store:.shared) { WorkspaceView(store:.shared) } }
        c.onReady = { [context] coordinator in
            let store = WorkspaceStore.shared
            IslandModuleNavigation.shared.bind(coordinator:coordinator)
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
struct VirxactMark: Shape {
    static let svgPath = "M592.42 587.09C590.52 589.6 588.42 591.96 586.14 594.24C583.87 596.51 581.51 598.62 578.99 600.52C559.45 615.82 534.17 620.3 511.27 614C504.73 612.22 498.4 609.53 492.43 605.98C490.56 604.87 488.74 603.67 486.95 602.39C481.54 598.51 480.82 590.72 485.53 586.01L518.51 553.03C522.1 549.44 522.1 543.63 518.51 540.04L511.58 533.1L465.56 579.12L431.03 613.65L430.01 614.67L407.01 637.67C403.42 641.26 403.42 647.08 407.01 650.67L413.94 657.61L436.16 635.38C440.07 631.47 446.37 631.1 450.57 634.7C452.95 636.74 455.4 638.68 457.89 640.51C463.2 644.43 468.75 647.86 474.47 650.8C518.77 673.66 573.88 668.24 613.03 634.55C615.41 632.52 617.75 630.35 620 628.1C622.26 625.85 624.4 623.53 626.46 621.12C660.17 581.96 665.58 526.84 642.73 482.54L609.55 515.72C607.39 517.88 606.41 520.98 607.04 523.97C611.58 545.6 606.72 568.84 592.42 587.09Z M649.51 422.03L656.44 428.97C660.03 432.56 660.03 438.38 656.44 441.97L633.46 464.95L632.44 465.97L597.91 500.5L551.87 546.54L544.94 539.6C541.35 536.01 541.35 530.19 544.94 526.61L577.94 493.61C582.65 488.89 581.93 481.11 576.52 477.23C574.73 475.94 572.9 474.75 571.04 473.64C565.06 470.09 558.74 467.4 552.2 465.62C529.3 459.32 504.02 463.8 484.45 479.12C481.94 481.02 479.58 483.13 477.3 485.4C475.03 487.68 472.93 490.04 471.02 492.55C456.75 510.78 451.89 534.02 456.43 555.65C457.06 558.64 456.08 561.74 453.92 563.9L420.74 597.08C397.89 552.77 403.3 497.66 436.99 458.52C439.02 456.13 441.19 453.79 443.44 451.54C445.7 449.29 448.01 447.14 450.42 445.09C489.59 411.38 544.7 405.96 589 428.82C594.72 431.76 600.27 435.18 605.57 439.11C608.07 440.94 610.51 442.88 612.9 444.92C617.1 448.52 623.4 448.14 627.31 444.24Z"
    func path(in rect: CGRect) -> Path {
        // The official mark contains only absolute M/L/C/Z commands.
        let pattern = "[MLCZ]|[-+]?(?:[0-9]*\\.)?[0-9]+"
        let ns = Self.svgPath as NSString
        let tokens = (try! NSRegularExpression(pattern:pattern)).matches(in:Self.svgPath,range:NSRange(location:0,length:ns.length)).map{ns.substring(with:$0.range)}
        var i = 0, path = Path()
        func point() -> CGPoint { let p = CGPoint(x:Double(tokens[i])!,y:Double(tokens[i+1])!); i += 2; return p }
        while i < tokens.count {
            let command = tokens[i]; i += 1
            switch command {
            case "M": path.move(to:point())
            case "L": path.addLine(to:point())
            case "C": let a = point(), b = point(), c = point(); path.addCurve(to:c,control1:a,control2:b)
            case "Z": path.closeSubpath()
            default: break
            }
        }
        let scale = min(rect.width/254.82,rect.height/249.70)
        return path.applying(CGAffineTransform(translationX:-404.31,y:-414.96)).applying(CGAffineTransform(scaleX:scale,y:scale)).applying(CGAffineTransform(translationX:rect.midX-254.82*scale/2,y:rect.midY-249.70*scale/2))
    }
}
struct WorkspaceDropMark: View {
    @ObservedObject var store: WorkspaceStore
    @State private var target = false
    var body: some View {
        ZStack {
            VirxactMark().fill(.white).frame(width:20,height:20)
            if store.ingestActive {
                Circle().trim(from:0.08,to:0.82).stroke(.white,lineWidth:1.5)
                    .frame(width:26,height:26)
            }
        }.frame(width:30,height:26).contentShape(Rectangle())
            .scaleEffect(target ? 1.12 : 1)
            .onDrop(of:[UTType.fileURL.identifier,UTType.image.identifier,UTType.utf8PlainText.identifier,UTType.url.identifier],isTargeted:$target) { providers in WorkspaceDrop.accept(providers,store:store) }
            .help("拖入文件、文字或链接，先存为待办")
    }
}

@MainActor
enum WorkspaceDrop {
    static func acceptFiles(_ urls: [URL], store: WorkspaceStore) -> Bool {
        guard !urls.isEmpty, urls.count <= 20, urls.allSatisfy(\.isFileURL) else {
            store.error = "请选择1到20个本机材料文件。"; return false
        }
        return accept(urls.map { NSItemProvider(item:$0 as NSURL,typeIdentifier:UTType.fileURL.identifier) },store:store)
    }
    static func accept(_ providers: [NSItemProvider], store: WorkspaceStore) -> Bool {
        guard !providers.isEmpty, providers.count <= 20 else { store.error = "一次最多放入20份材料。"; return false }
        guard store.beginMaterialDrop() else { return false }
        Task {
            defer { store.endMaterialDrop() }
            do {
                var text: [String] = [], files: [URL] = [], inlineImages: [PendingWorkImage] = []
                for provider in providers {
                    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                        let data = try await load(provider,type:UTType.fileURL.identifier)
                        guard let url = URL(dataRepresentation:data,relativeTo:nil), url.isFileURL else { throw WorkError.message("文件地址无效。") }; files.append(url)
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                        let data = try await load(provider,type:UTType.image.identifier)
                        inlineImages.append(try PendingWorkImage.decode(data,name:"拖入图片"))
                    } else {
                        let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url.identifier : UTType.utf8PlainText.identifier
                        let data = try await load(provider,type:type)
                        guard let s = String(data:data,encoding:.utf8) else { throw WorkError.message("无法读取拖入的文字。") }; text.append(s)
                    }
                }
                // Parsing is off the UI thread; files are never uploaded or executed by dropping alone.
                let captured = text.joined(separator:"\n"), urls = files
                let material = try await Task.detached { () -> (String,[PendingWorkImage]) in
                    var pieces = captured.isEmpty ? [] : [captured], images: [PendingWorkImage] = []
                    for url in urls {
                        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        if WorkspaceStore.isImage(url) { images.append(try PendingWorkImage.read(url)) }
                        else { pieces.append("文件：\(url.lastPathComponent)\n" + (try WorkMaterial.read(url))) }
                    }
                    return (pieces.joined(separator:"\n\n"),images)
                }.value
                _ = try store.add(text:material.0,images:material.1+inlineImages)
            } catch { store.error = error.localizedDescription }
        }
        return true
    }
    private static func load(_ provider: NSItemProvider, type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { c in provider.loadDataRepresentation(forTypeIdentifier:type) { data,error in if let data, data.count <= 10_000_000 { c.resume(returning:data) } else { c.resume(throwing:error ?? WorkError.message("拖入内容过大或无法读取。")) } } }
    }
}
struct WorkspaceView: View {
    @ObservedObject var store: WorkspaceStore
    var desktop = false
    var pageOverride: Int? = nil
    var onTaskCreated: (() -> Void)? = nil
    private var currentTab: Int { pageOverride ?? store.boardTab }
    @ObservedObject var dotPairing = SettingsServer.shared.dotPairing
    @ObservedObject var dotTunnel = DotTunnel.shared
    @State private var confirmDot = false
    @State private var confirmedProject = ""
    @State private var dotCopied = false
    private var input: String { store.draftText }
    @State private var agentCopied = false
    @State private var recoveryURL = ""
    var body: some View {
        Group {
            if desktop {
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
            .onAppear { if Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview" { do { try dotPairing.load() } catch { store.error=error.localizedDescription } } }
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
                ForEach(Array(["材料","待办","中台"].enumerated()),id:\.offset) { i,title in
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
                Picker("交给谁",selection:$store.draftService) {
                    Text(WorkAI.displayName).tag("codex"); Text("豆包工作").tag("doubao"); Text("Dot").tag("dot")
                }.labelsHidden().frame(width:110).accessibilityLabel("处理工具")
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
                Picker("交给谁",selection:$store.draftService) {
                    Text(WorkAI.displayName).tag("codex"); Text("豆包工作").tag("doubao"); Text("Dot").tag("dot")
                }
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
            if store.chromeImportEnabled { Text("在Chrome点工作岛收录按钮，预览后送入此处；只收录当前页面，不读取登录凭据。").font(.system(size:10)).foregroundStyle(.secondary) }
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
            Picker("交给谁",selection:$store.draftService) {
                Text(WorkAI.displayName+" · 本机").tag("codex")
                Text("豆包工作 · 本人已登录网页").tag("doubao")
                Text("Dot · 已配对项目").tag("dot")
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
                if store.disk.items.isEmpty { Text("把材料拖进来，或在“材料”里存一条待办。").font(.system(size:13)).foregroundStyle(.secondary).padding(.vertical,20) }
                ForEach(store.disk.items) { item in
                    VStack(alignment:.leading,spacing:7) {
                        HStack(alignment:.top,spacing:8) {
                            Button { store.selected = store.selected == item.id ? nil : item.id } label: {
                                VStack(alignment:.leading,spacing:5) {
                                    Text(item.title).font(.system(size:desktop ? 15 : 12,weight:.medium)).lineLimit(2).multilineTextAlignment(.leading)
                                    Text(label(item.state)+(item.screenReminder == nil ? "" : " · 冲屏提醒")).font(.system(size:10)).foregroundStyle(.secondary)
                                }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Button { store.selected=item.id; store.beginEdit(item.id) } label: { Image(systemName:"pencil") }.buttonStyle(.plain).padding(4).disabled(!WorkspaceStore.canEdit(item)).help("编辑待办").accessibilityLabel("编辑："+item.title)
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
                            if let source = item.resultSource { Text("结果来源："+source).font(.system(size:10)).foregroundStyle(.secondary) }
                            if item.service == "dot", !item.result.isEmpty { Text("Dot 后台任务结果已返回这里；当前聊天对话是否显示，取决于 Dot 的任务记录。").font(.system(size:10)).foregroundStyle(.secondary) }
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
    private var cards: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text(store.hub.connected ? store.hub.name : "本人虚实中台").font(.system(size:14,weight:.semibold)); Spacer(); Button("刷新") { Task { await store.refreshHub() } } }
            if !store.hub.error.isEmpty { Text(store.hub.error).font(.system(size:12)).foregroundStyle(.orange) }
            if !store.hub.connected {
                Button("连接虚实中台与飞书数据") { if let a = SettingsServer.shared.address { store.connectHub(callback:a+"/oauth/virxact/callback") } }
                Text("本人在浏览器确认授权，钥匙串保管凭据。只读首页和数据，不改公司业务记录。").font(.system(size:11)).foregroundStyle(.secondary)
            } else {
                if let at = store.hub.readAt { Text("读取于 \(at.formatted(date:.abbreviated,time:.shortened)) · 每10分钟更新").font(.system(size:10)).foregroundStyle(.secondary) }
                    VStack(alignment:.leading,spacing:8) {
                        ForEach(store.visibleCards) { card in
                            VStack(alignment:.leading,spacing:6) {
                                HStack { Text(card.title).font(.system(size:13,weight:.semibold)); Spacer(); Button("↑") { store.moveCard(card.id,direction:-1) }; Button("↓") { store.moveCard(card.id,direction:1) }; Button("移除") { store.toggleCard(card.id) } }.font(.system(size:10))
                                Text(card.text).font(.system(size:12)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                            }.padding(9).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:8))
                        }
                        Text("选择要放进灵动岛的卡片").font(.system(size:11)).foregroundStyle(.secondary)
                        ForEach(store.hub.cards) { card in
                            Button { store.toggleCard(card.id) } label:{ Label(card.title,systemImage:store.disk.selectedCards.contains(card.id) ? "checkmark.square.fill" : "square") }.buttonStyle(.plain).font(.system(size:12))
                        }
                    }
            }
        }
    }
}
