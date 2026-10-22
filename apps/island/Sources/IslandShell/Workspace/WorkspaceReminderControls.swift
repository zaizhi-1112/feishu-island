import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AVKit

struct ScreenReminderChoice: View {
    @ObservedObject var store: WorkspaceStore
    @Binding var selection: ScreenReminderStyle?
    var body: some View {
        Picker("提醒方式",selection:Binding(get:{selection?.materialID ?? "off"},set:{selection = $0 == "off" ? nil : ScreenReminderStyle(materialID:$0,durationSeconds:15)})) {
            Text("灵动岛提示").tag("off")
            ForEach(store.screenMaterials) { Text("冲屏 · "+$0.name).tag($0.id) }
        }.font(.system(size:12)).accessibilityLabel("提醒方式")
    }
}

struct WorkspaceReminderShelf: View {
    @ObservedObject var store: WorkspaceStore
    var compact=false
    @State private var editor=false
    @State private var editing:WorkScreenSchedule?
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Label("冲屏提醒",systemImage:"timer").font(.system(size:compact ? 13 : 17,weight:.semibold)); Spacer(); Button { editing=nil; editor=true } label:{ Image(systemName:"plus") }.buttonStyle(.plain).help("新建倒计时或计划提醒").accessibilityLabel("新建冲屏提醒") }
            HStack(spacing:8) {
                Button("倒计时") { editing=nil; editor=true }
                Button("久坐 · 30分") { preset(title:"起来活动一下",minutes:30) }
                Button("吃饭提醒") { editing=WorkScreenSchedule(title:"该吃饭了",fireAt:Date().addingTimeInterval(3600)); editor=true }
            }.font(.system(size:compact ? 11 : 12)).controlSize(.small)
            ForEach(store.screenSchedules) { schedule in
                HStack(spacing:8) {
                    Toggle(isOn:Binding(get:{schedule.enabled},set:{store.setScreenScheduleEnabled(schedule.id,enabled:$0)})) { EmptyView() }.labelsHidden().toggleStyle(.switch).controlSize(.mini).accessibilityLabel("启用："+schedule.title)
                    VStack(alignment:.leading,spacing:3) {
                        Text(schedule.title).lineLimit(1).font(.system(size:12))
                        Text(schedule.enabled ? schedule.fireAt.formatted(date:.omitted,time:.shortened)+(schedule.repeatMinutes.map{" · 每\($0)分"} ?? " · 一次") : "已暂停").font(.system(size:10)).foregroundStyle(.secondary)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    Button { editing=schedule; editor=true } label:{ Image(systemName:"pencil") }.buttonStyle(.plain).accessibilityLabel("编辑提醒："+schedule.title)
                    Button(role:.destructive) { store.deleteScreenSchedule(schedule.id) } label:{ Image(systemName:"trash") }.buttonStyle(.plain).accessibilityLabel("删除提醒："+schedule.title)
                }.padding(.vertical,4)
            }
            if !compact { Button("管理素材与自己的视频") { WorkspaceWindow.shared.openReminders(store:store) }.font(.system(size:12)).buttonStyle(.plain).foregroundStyle(.secondary) }
        }.padding(compact ? 10 : 16).background(Color.cyan.opacity(0.055),in:RoundedRectangle(cornerRadius:12))
            .popover(isPresented:$editor) { WorkspaceReminderEditor(store:store,schedule:editing,onSave:{editor=false}).id(editing?.id).frame(width:320).padding(20) }
    }
    private func preset(title:String,minutes:Int) {
        if let existing=store.screenSchedules.first(where:{$0.title==title && $0.repeatMinutes==minutes}) { store.setScreenScheduleEnabled(existing.id,enabled:!existing.enabled); return }
        do { try store.upsertScreenSchedule(title:title,firstFire:Date().addingTimeInterval(Double(minutes)*60),repeatMinutes:minutes,style:.init()) } catch { store.error=error.localizedDescription }
    }
}
struct WorkspaceReminderEditor:View {
    @ObservedObject var store: WorkspaceStore
    let schedule:WorkScreenSchedule?
    let onSave:()->Void
    @State private var title="提醒我一下"
    @State private var firstFire=Date().addingTimeInterval(1200)
    @State private var repeats=false
    @State private var minutes=30
    @State private var material="cat"
    @State private var error=""
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text(schedule == nil ? "新建提醒" : "编辑提醒").font(.headline)
            TextField("提醒内容",text:$title).textFieldStyle(.roundedBorder)
            HStack { ForEach([5,20,30,60],id:\.self) { n in Button("\(n)分") { firstFire=Date().addingTimeInterval(Double(n)*60) }.controlSize(.small) } }
            DatePicker("提醒时间",selection:$firstFire,displayedComponents:[.date,.hourAndMinute]).datePickerStyle(.field)
            Toggle("循环提醒",isOn:$repeats)
            if repeats { Stepper("每 \(minutes) 分钟",value:$minutes,in:1...10080) }
            Picker("冲屏素材",selection:$material) { ForEach(store.screenMaterials) { Text($0.name).tag($0.id) } }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
            Button("保存提醒") {
                do { try store.upsertScreenSchedule(id:schedule.flatMap { value in store.screenSchedules.contains(where:{$0.id==value.id}) ? value.id : nil },title:title,firstFire:firstFire,repeatMinutes:repeats ? minutes : nil,style:.init(materialID:material,durationSeconds:15)); onSave() } catch { self.error=error.localizedDescription }
            }.buttonStyle(.borderedProminent).tint(.orange)
        }.onAppear { if let schedule { title=schedule.title; firstFire=schedule.fireAt; repeats=schedule.repeatMinutes != nil; minutes=schedule.repeatMinutes ?? 30; material=schedule.style.materialID } }
    }
}

struct WorkspaceReminderLibrary:View {
    @ObservedObject var store:WorkspaceStore
    @State private var importing=false
    @State private var copied=false
    @State private var selected="cat"
    @State private var previewGeneration=0
    @State private var importError=""
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack { Text("到时间，让它来提醒你。").foregroundStyle(.secondary); Spacer() }
            HStack(spacing:12) {
                Button(importing ? "正在导入…" : "添加自己的视频") { pickVideo() }.disabled(importing)
                Button(copied ? "已复制" : "复制交给 Agent") { copyAgent() }
                Spacer()
            }
            ForEach(store.screenMaterials) { material in
                HStack(spacing:12) {
                    Image(systemName:material.id == "cat" ? "cat" : "play.rectangle").font(.system(size:24)).foregroundStyle(.cyan).frame(width:40)
                    VStack(alignment:.leading,spacing:4) { Text(material.name).font(.system(size:15,weight:.medium)); Text(material.filename == nil ? "内置素材" : "个人视频 · \(Int(material.durationSeconds.rounded()))秒").font(.system(size:11)).foregroundStyle(.secondary) }
                    Spacer()
                    Button("窗口内预览") { selected=material.id; previewGeneration += 1 }
                }.padding(.vertical,8)
                Divider()
            }
            if !importError.isEmpty { Text(importError).font(.system(size:12)).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true) }
            WorkspaceReminderMediaPreview(store:store,materialID:selected,generation:previewGeneration).frame(height:210).frame(maxWidth:.infinity).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:12)).clipped()
            Text("支持 MP4、MOV，最长 2 分钟。透明视频直接呈现；普通视频保留原画面。所有导入素材只保存在这台电脑。").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Button("停止当前冲屏提醒") { store.dismissScreenReminder() }.font(.system(size:12))
        }
    }
    private func pickVideo() {
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.mpeg4Movie,.quickTimeMovie,.movie]; panel.allowsMultipleSelection=false; panel.canChooseDirectories=false
        panel.begin { response in guard response == .OK, let url=panel.url else { return }; importing=true; importError=""
            Task { do { let result=try await store.importScreenReminderVideo(url); selected=result.id; previewGeneration += 1 } catch { importError=error.localizedDescription }; importing=false }
        }
    }
    private func copyAgent() {
        let prompt="请帮我制作飞书工作岛的个人冲屏提醒视频。我会提供我有权使用的素材和想要的效果。输出可导入的 MP4 或 MOV，最长 120 秒、150MB 以内；优先透明 MOV，静音播放一次。请先在普通窗口预览，不要创建遮挡桌面或拦截鼠标的测试。完成后指导我在工作台 → 冲屏素材 → 添加自己的视频导入，再到待办设置提醒。不要改飞书接收、账号、授权或核心功能，不读取其他材料。"
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(prompt,forType:.string); copied=true
    }
}
struct WorkspaceReminderMediaPreview:NSViewRepresentable {
    let store:WorkspaceStore
    let materialID:String
    var generation=0
    func makeNSView(context:Context)->NSView { NSView() }
    static func dismantleNSView(_ view:NSView,coordinator:()) {
        for child in view.subviews { (child as? AVPlayerView)?.player?.pause(); (child as? ScreenReminderCatView)?.stop() }
    }
    func updateNSView(_ view:NSView,context:Context) {
        let identity=materialID+"-"+String(generation)
        guard view.identifier?.rawValue != identity else { return }
        view.identifier=NSUserInterfaceItemIdentifier(identity)
        for child in view.subviews { if let player=child as? AVPlayerView { player.player?.pause() }; (child as? ScreenReminderCatView)?.stop(); child.removeFromSuperview() }
        let child:NSView
        if materialID == "cat" { let cat=ScreenReminderCatView(frame:view.bounds); cat.start(); child=cat }
        else {
            let playerView=AVPlayerView(frame:view.bounds); playerView.controlsStyle = .inline
            if let material=store.screenMaterials.first(where:{$0.id==materialID}) {
                let url:URL?
                if material.id == "rick" { url=Bundle.main.resourceURL?.appendingPathComponent("ScreenReminder/rick-portal.mov") }
                else { url=try? store.screenReminderRequest(style:.init(materialID:material.id,durationSeconds:15),title:"预览").videoURL }
                if let url { let player=AVPlayer(url:url); player.isMuted=true; playerView.player=player; if generation > 0 { player.play() } }
            }; child=playerView
        }
        child.autoresizingMask=[.width,.height]; view.addSubview(child)
    }
}
