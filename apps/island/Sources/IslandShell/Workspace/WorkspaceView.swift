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
        c.onFileDrop = { WorkspaceDrop.acceptFiles($0,store:.shared) }
        c.setCompactLeading { WorkspaceDropMark(store:.shared) }
        c.setCompactTrailing { WorkspaceCompact(store:.shared) }
        c.setHome { WorkspaceDropSurface(store:.shared) { WorkspaceView(store:.shared) } }
        c.onReady = { [context] coordinator in
            let store = WorkspaceStore.shared
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
    @ObservedObject var dotPairing = SettingsServer.shared.dotPairing
    @ObservedObject var dotTunnel = DotTunnel.shared
    @State private var confirmDot = false
    @State private var confirmedProject = ""
    @State private var dotCopied = false
    private var input: String { store.draftText }
    @State private var agentCopied = false
    @State private var recoveryURL = ""
    @State private var recipe = "work"
    @State private var minutes = 20
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                ForEach(Array(["材料","待办","中台"].enumerated()),id:\.offset) { i,title in
                    Button(title) { store.boardTab = i }.buttonStyle(.plain).padding(.horizontal,10).padding(.vertical,6).background(store.boardTab == i ? Color.white.opacity(0.16) : .clear,in:Capsule())
                }
                Spacer()
                if !desktop { Button { WorkspaceWindow.shared.open(store:store) } label: { Image(systemName:"macwindow") }.help("打开独立工作台") }
                Button { SettingsServer.shared.open() } label:{ Image(systemName:"gearshape") }.buttonStyle(.plain).help("设置与连接")
            }
            if !store.error.isEmpty { Text(store.error).font(.system(size:12)).foregroundStyle(.orange).textSelection(.enabled) }
            Group {
                if store.boardTab == 0 { materials }
                else if store.boardTab == 1 { tasks }
                else { cards }
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.padding(desktop ? 24 : 12).frame(width:desktop ? 760 : 376).foregroundStyle(.white)
            .onAppear { minutes = store.disk.reminderMinutes; if Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview" { do { try dotPairing.load() } catch { store.error=error.localizedDescription } } }
            .onChange(of:store.draftProject) { _,_ in dotCopied=false; agentCopied=false }
            .confirmationDialog("连接Dot到「\(confirmedProject)」？",isPresented:$confirmDot,titleVisibility:.visible) {
                Button("允许此项目长期连接并复制") {
                    guard confirmedProject==store.draftProject else { store.error="项目已变化，请重新确认。"; return }
                    SettingsServer.shared.copyDotConnection(store:store); dotCopied=store.error.isEmpty
                }
                Button("取消",role:.cancel) {}
            } message: { Text("仅能领取你主动交给Dot的本项目任务和附件、回传结果。凭据放本机钥匙串，连接时自动续期；30天不连接失效。锁屏暂停，可随时断开。不会读取飞书消息或其他项目。") }

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
                if let seen=dotPairing.grant(project:store.draftProject)?.lastSeen { Text("最后连接："+seen.formatted(date:.abbreviated,time:.shortened)).font(.system(size:10)).foregroundStyle(.secondary) }
                Text(dotTunnel.status).font(.system(size:10)).foregroundStyle(.secondary)
                Text(dotPairing.grant(project:store.draftProject)?.subscription.map { $0.expires>Date() ? "任务通知已订阅：交给AI后自动通知Dot；通知送达后仍需Dot领取处理。Mac和ChatGPT须在线。" : "Dot通知订阅已过期，需在Dot中恢复订阅。" } ?? "尚未订阅自动通知：需先在Dot安装私人插件并订阅本项目；配对本身不会唤醒Dot。").font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Picker("处理方式",selection:$recipe) { ForEach(store.disk.recipes) { r in Text(r.title).tag(r.id) } }.font(.system(size:12))
            HStack {
                Text("提醒").font(.system(size:12))
                Picker("提醒时间",selection:$minutes) { ForEach(Array(Set([0,5,20,60,minutes])).sorted(),id:\.self) { value in Text(value == 0 ? "不提醒" : "\(value)分钟").tag(value) } }.labelsHidden().frame(width:100)
                Spacer()
            }.font(.system(size:12))
            HStack {
                Button("添加附件") { store.pickFiles() }
                Button("粘贴") { store.pasteMaterial() }
                Button("存待办") { add(run:false) }
                Button("交给AI") { add(run:true) }
            }.font(.system(size:12))
            Button("读取上方飞书文档链接") { store.readFeishuMaterial(input,instruction:store.disk.recipes.first(where:{$0.id == recipe})?.instruction); store.boardTab = 1 }.font(.system(size:11))
            Text("当前处理工具：\(store.draftService == "dot" ? "Dot（项目派单）" : store.draftService == "doubao" ? "豆包工作（本人网页）" : WorkAI.displayName)。拖入只保存本机。点击“交给AI”才把材料交给你本机已登录的AI服务；链接先作为文字，不自动抓取。支持图片/截图（⌘V粘贴）、Word、PDF、文字；最多6张图片，交给AI前可移除。").font(.system(size:10)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal:false,vertical:true)
            HStack { Button("导入材料Skill") { store.importSkill() }; Spacer(); Text("\(store.disk.items.filter{$0.state != "done"}.count)项未完成").foregroundStyle(.secondary) }.font(.system(size:11))
        }
    }
    private func add(run: Bool) {
        do { let id = try store.add(text:input,instruction:store.disk.recipes.first(where:{$0.id == recipe})?.instruction,minutes:minutes,images:store.draftImages,project:store.draftProject); store.draftText = ""; store.draftImages = []; store.boardTab = 1; if run { store.run(id) } } catch { store.error = error.localizedDescription }
    }
    private var tasks: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:10) {
                if store.disk.items.isEmpty { Text("把材料拖进来，或在“材料”里存一条待办。").font(.system(size:13)).foregroundStyle(.secondary).padding(.vertical,20) }
                ForEach(store.disk.items) { item in
                    VStack(alignment:.leading,spacing:7) {
                        Button { store.selected = store.selected == item.id ? nil : item.id } label: {
                            HStack { Text(item.title).lineLimit(2).multilineTextAlignment(.leading); Spacer(); Text(label(item.state)).font(.system(size:10)).foregroundStyle(.secondary) }
                        }.buttonStyle(.plain)
                        if store.selected == item.id {
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
                            if !item.failure.isEmpty { Text(item.failure).font(.system(size:11)).foregroundStyle(.orange) }
                            if item.service=="dot", item.state=="dot_waiting", let deliveries=item.dotDeliveries, !deliveries.isEmpty {
                                if deliveries.values.contains(where:{$0.accepted}) { Text("通知已送达 · 等待Dot领取").font(.system(size:11)).foregroundStyle(.secondary) }
                                else if deliveries.values.allSatisfy({$0.stopped}) { HStack { Text("通知未送达"); Button("重试通知") { store.retryDotNotification(item.id) } }.font(.system(size:11)).foregroundStyle(.orange) }
                                else { Text("通知正在重试").font(.system(size:11)).foregroundStyle(.secondary) }
                            }
                            HStack {
                                if ["running","queued","dot_waiting","dot_running"].contains(item.state) { Button(item.service == "doubao" ? "停止等候" : "取消") { store.cancel(item.id) } }
                                else if item.state != "done" { Button(item.result.isEmpty ? "交给AI" : "重新处理") { store.run(item.id) }; Button("完成") { store.complete(item.id) } }
                                Button("稍后20分") { store.snooze(item.id) }
                            }.font(.system(size:11))
                            HStack {
                                Button("编辑") { store.beginEdit(item.id) }.disabled(!WorkspaceStore.canEdit(item))
                                Button("删除",role:.destructive) { store.deleteItem(item.id) }.disabled(["running","queued","dot_running"].contains(item.state))
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
        }.frame(height:desktop ? 440 : 290)
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
                ScrollView {
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
                }.frame(height:240)
            }
        }
    }
}
