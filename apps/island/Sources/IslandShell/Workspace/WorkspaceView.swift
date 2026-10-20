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
        c.setCompactLeading { WorkspaceDropMark(store:.shared) }
        c.setCompactTrailing { WorkspaceCompact(store:.shared) }
        c.setHome { WorkspaceView(store:.shared) }
        c.onReady = { [context] coordinator in
            let store = WorkspaceStore.shared
            store.openBoard = { [weak coordinator] in coordinator?.switchModule(to:IslandHost.workspaceID); coordinator?.showNook() }
            store.notify = { title in
                var activity = NookLiveActivity(id:"work-result",priority:.high,lifetime:.transient(.seconds(20)),alert:.peek(.seconds(5)),accessibilityLabel:title) {
                    WorkspaceDropMark(store:store)
                } compactTrailing: { Text("待查看").font(.system(size:10)) } minimal: { Image(systemName:"checkmark.circle") }
                activity.setPeek { Text(title).font(.system(size:13)).padding(8) }
                activity.setExpanded { WorkspaceView(store:store) }
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
    @State private var swallow = false
    @State private var consumed = false
    var body: some View {
        ZStack {
            VirxactMark().fill(.white).frame(width:20,height:20).rotationEffect(.degrees(swallow ? 100 : 0)).scaleEffect(target ? 1.2 : 1)
            if swallow { Image(systemName:"doc.fill").font(.system(size:14)).scaleEffect(consumed ? 0.01 : 1).opacity(consumed ? 0 : 1).offset(x:consumed ? 0 : 18,y:consumed ? 0 : -8) }
        }.frame(width:30,height:26).contentShape(Rectangle())
            .onDrop(of:[UTType.fileURL.identifier,UTType.utf8PlainText.identifier,UTType.url.identifier],isTargeted:$target) { providers in WorkspaceDrop.accept(providers,store:store) }
            .onChange(of:store.accepted) { _,_ in animateAcceptance() }
            .onAppear { if Date().timeIntervalSince(store.acceptedAt)<1 { animateAcceptance() } }
            .help("拖入文件、文字或链接，先存为待办")
    }
    private func animateAcceptance() {
        consumed = false; swallow = true
        DispatchQueue.main.async { withAnimation(.easeIn(duration:0.45)) { consumed = true } }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.7) { withAnimation(.spring(response:0.3,dampingFraction:0.7)) { swallow = false } }
    }
}
@MainActor
enum WorkspaceDrop {
    static func accept(_ providers: [NSItemProvider], store: WorkspaceStore) -> Bool {
        guard !providers.isEmpty, providers.count <= 20 else { store.error = "一次最多放入20份材料。"; return false }
        Task {
            do {
                var text: [String] = [], files: [URL] = []
                for provider in providers {
                    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                        let data = try await load(provider,type:UTType.fileURL.identifier)
                        guard let url = URL(dataRepresentation:data,relativeTo:nil), url.isFileURL else { throw WorkError.message("文件地址无效。") }; files.append(url)
                    } else {
                        let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url.identifier : UTType.utf8PlainText.identifier
                        let data = try await load(provider,type:type)
                        guard let s = String(data:data,encoding:.utf8) else { throw WorkError.message("无法读取拖入的文字。") }; text.append(s)
                    }
                }
                // Parsing is off the UI thread; files are never uploaded or executed by dropping alone.
                let captured = text.joined(separator:"\n"), urls = files
                let material = try await Task.detached { () -> String in
                    var pieces = captured.isEmpty ? [] : [captured]
                    for url in urls { let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; pieces.append("文件：\(url.lastPathComponent)\n" + (try WorkMaterial.read(url))) }
                    return pieces.joined(separator:"\n\n")
                }.value
                _ = try store.add(text:material)
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
    @State private var input = ""
    @State private var recipe = "feedback"
    @State private var minutes = 20
    @State private var target = false
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                ForEach(Array(["材料","待办","中台"].enumerated()),id:\.offset) { i,title in
                    Button(title) { store.boardTab = i }.buttonStyle(.plain).padding(.horizontal,10).padding(.vertical,6).background(store.boardTab == i ? Color.white.opacity(0.16) : .clear,in:Capsule())
                }
                Spacer()
                Button { SettingsServer.shared.open() } label:{ Image(systemName:"gearshape") }.buttonStyle(.plain).help("设置与连接")
            }
            if !store.error.isEmpty { Text(store.error).font(.system(size:12)).foregroundStyle(.orange).textSelection(.enabled) }
            Group {
                if store.boardTab == 0 { materials }
                else if store.boardTab == 1 { tasks }
                else { cards }
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.padding(12).frame(width:376).foregroundStyle(.white)
            .onAppear { minutes = store.disk.reminderMinutes }
            .onDrop(of:[UTType.fileURL.identifier,UTType.utf8PlainText.identifier,UTType.url.identifier],isTargeted:$target) { WorkspaceDrop.accept($0,store:store) }
            .overlay { if target { RoundedRectangle(cornerRadius:14).stroke(.white.opacity(0.8),style:StrokeStyle(lineWidth:2,dash:[6])).allowsHitTesting(false) } }
    }
    private var materials: some View {
        VStack(alignment:.leading,spacing:9) {
            HStack { WorkspaceDropMark(store:store).frame(width:32,height:32); Text("放下材料，接着做你的事").font(.system(size:15,weight:.semibold)); Spacer() }
            TextEditor(text:$input).font(.system(size:13)).scrollContentBackground(.hidden).padding(6).frame(height:72).background(.white.opacity(0.08),in:RoundedRectangle(cornerRadius:8)).accessibilityLabel("材料文字或链接")
            Picker("处理方式",selection:$recipe) { ForEach(store.disk.recipes) { r in Text(r.title).tag(r.id) } }.font(.system(size:12))
            HStack {
                Text("提醒").font(.system(size:12))
                Picker("提醒时间",selection:$minutes) { ForEach(Array(Set([0,5,20,60,minutes])).sorted(),id:\.self) { value in Text(value == 0 ? "不提醒" : "\(value)分钟").tag(value) } }.labelsHidden().frame(width:100)
                Spacer()
            }.font(.system(size:12))
            HStack {
                Button("选文件") { store.pickFiles(instruction:store.disk.recipes.first(where:{$0.id == recipe})?.instruction,minutes:minutes); store.boardTab = 1 }
                Button("存待办") { add(run:false) }
                Button("交给AI") { add(run:true) }
            }.font(.system(size:12))
            Button("读取上方飞书文档链接") { store.readFeishuMaterial(input,instruction:store.disk.recipes.first(where:{$0.id == recipe})?.instruction); store.boardTab = 1 }.font(.system(size:11))
            Text("当前处理工具：\(WorkAI.displayName)。拖入只保存本机。点击“交给AI”才把材料交给你本机已登录的AI服务；链接先作为文字，不自动抓取。支持Word、PDF、文字文件。").font(.system(size:10)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal:false,vertical:true)
            HStack { Button("导入材料Skill") { store.importSkill() }; Spacer(); Text("\(store.disk.items.filter{$0.state != "done"}.count)项未完成").foregroundStyle(.secondary) }.font(.system(size:11))
        }
    }
    private func add(run: Bool) {
        do { let id = try store.add(text:input,instruction:store.disk.recipes.first(where:{$0.id == recipe})?.instruction,minutes:minutes); input = ""; store.boardTab = 1; if run { store.run(id) } } catch { store.error = error.localizedDescription }
    }
    private var tasks: some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:10) {
                if store.disk.items.isEmpty { Text("把材料拖进来，或在“材料”里存一条待办。").font(.system(size:13)).foregroundStyle(.secondary).padding(.vertical,20) }
                ForEach(store.disk.items) { item in
                    VStack(alignment:.leading,spacing:7) {
                        Button { store.selected = store.selected == item.id ? nil : item.id } label: {
                            HStack { Text(item.title).lineLimit(2).multilineTextAlignment(.leading); Spacer(); Text(label(item.state)).font(.system(size:10)).foregroundStyle(.secondary) }
                        }.buttonStyle(.plain)
                        if store.selected == item.id {
                            if let due = item.due { DatePicker(item.reminded ? "再次提醒" : "提醒时间",selection:Binding(get:{due},set:{store.setReminder(item.id,date:$0)}),displayedComponents:[.date,.hourAndMinute]).datePickerStyle(.field).font(.system(size:10)) }
                            Text(item.result.isEmpty ? String(item.input.prefix(500)) : item.result).font(.system(size:13)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                            if !item.failure.isEmpty { Text(item.failure).font(.system(size:11)).foregroundStyle(.orange) }
                            HStack {
                                if ["running","queued"].contains(item.state) { Button("取消") { store.cancel(item.id) } }
                                else if item.state != "done" { Button(item.result.isEmpty ? "交给AI" : "重新处理") { store.run(item.id) }; Button("完成") { store.complete(item.id) } }
                                Button("稍后20分") { store.snooze(item.id) }
                                if !item.result.isEmpty { Button("复制结果") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.result,forType:.string) } }
                            }.font(.system(size:11))
                        }
                    }.padding(10).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:10))
                }
            }
        }.frame(height:290)
    }
    private func label(_ state: String) -> String { ["todo":"待办","queued":"排队中","running":"处理中","succeeded":"已完成 · 可取结果","failed":"处理失败","interrupted":"上次中断","done":"已处理"][state] ?? state }
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
