import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AVKit

struct ScreenReminderChoice: View {
    @ObservedObject var store: WorkspaceStore
    @Binding var selection: ScreenReminderStyle?
    var body: some View {
        Picker("提醒方式",selection:Binding(get:{selection?.materialID ?? "off"},set:{selection = $0 == "off" ? nil : ScreenReminderStyle(materialID:$0,durationSeconds:15)})) {
            Text("仅岛内提示，不冲屏").tag("off")
            ForEach(store.screenMaterials) { Text("冲屏 · "+$0.name).tag($0.id) }
        }.font(.system(size:12)).accessibilityLabel("提醒方式")
    }
}

private struct ReminderEditorPresentation: Identifiable {
    let id=UUID()
    let schedule: WorkScreenSchedule?
}
struct WorkspaceReminderShelf: View {
    @ObservedObject var store: WorkspaceStore
    var compact=false
    @State private var editor: ReminderEditorPresentation?
    var body: some View {
        if compact, let context=editor {
            VStack(alignment:.leading,spacing:12) {
                Button { editor=nil } label: { Label("返回待办",systemImage:"chevron.left") }.buttonStyle(.plain).font(.system(size:13))
                WorkspaceReminderEditor(store:store,schedule:context.schedule,onSave:{editor=nil})
            }.padding(12).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:12))
        } else {
            shelf
        }
    }
    private var shelf: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Label("冲屏提醒",systemImage:"timer").font(.system(size:compact ? 13 : 17,weight:.semibold)); Spacer(); Button { editor=ReminderEditorPresentation(schedule:nil) } label:{ Image(systemName:"plus") }.buttonStyle(.plain).help("新建倒计时或计划提醒").accessibilityLabel("新建冲屏提醒") }
            HStack(spacing:8) {
                Button("倒计时") { editor=ReminderEditorPresentation(schedule:nil) }
                Button("久坐 · 30分") { preset(title:"起来活动一下",minutes:30) }
                Button("吃饭提醒") { editor=ReminderEditorPresentation(schedule:WorkScreenSchedule(title:"该吃饭了",fireAt:Date().addingTimeInterval(3600))) }
            }.font(.system(size:compact ? 11 : 12)).controlSize(.small)
            ForEach(store.screenSchedules) { schedule in
                HStack(spacing:8) {
                    Toggle(isOn:Binding(get:{schedule.enabled},set:{store.setScreenScheduleEnabled(schedule.id,enabled:$0)})) { EmptyView() }.labelsHidden().toggleStyle(.switch).controlSize(.mini).accessibilityLabel("启用："+schedule.title)
                    VStack(alignment:.leading,spacing:3) {
                        Text(schedule.title).lineLimit(1).font(.system(size:12))
                        Text(schedule.enabled ? schedule.fireAt.formatted(date:.omitted,time:.shortened)+(schedule.repeatMinutes.map{" · 每\($0)分"} ?? " · 一次") : "已暂停").font(.system(size:10)).foregroundStyle(.secondary)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    Button { editor=ReminderEditorPresentation(schedule:schedule) } label:{ Image(systemName:"pencil") }.buttonStyle(.plain).accessibilityLabel("编辑提醒："+schedule.title)
                    Button(role:.destructive) { store.deleteScreenSchedule(schedule.id) } label:{ Image(systemName:"trash") }.buttonStyle(.plain).accessibilityLabel("删除提醒："+schedule.title)
                }.padding(.vertical,4)
            }
            if !compact { Button("管理素材与自己的视频") { UnifiedSettingsWindow.shared.open(section: .rest) }.font(.system(size:12)).buttonStyle(.plain).foregroundStyle(.secondary) }
        }.padding(compact ? 10 : 16).background(Color.cyan.opacity(0.055),in:RoundedRectangle(cornerRadius:12))
            .popover(item:Binding(get:{compact ? nil : editor},set:{editor=$0})) { context in WorkspaceReminderEditor(store:store,schedule:context.schedule,onSave:{editor=nil}).frame(width:320).padding(20) }
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
            HStack { ForEach([5,20,30,60],id:\.self) { n in Button("\(n)分") { firstFire=Date().addingTimeInterval(Double(n)*60) }.buttonStyle(IslandButtonStyle()) } }
            DatePicker("提醒时间",selection:$firstFire,displayedComponents:[.date,.hourAndMinute]).datePickerStyle(.field)
            Toggle("循环提醒",isOn:$repeats)
            if repeats { Stepper("每 \(minutes) 分钟",value:$minutes,in:1...10080) }
            Picker("冲屏素材",selection:$material) { ForEach(store.screenMaterials) { Text($0.name).tag($0.id) } }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
            Button("保存提醒") {
                do { try store.upsertScreenSchedule(id:schedule.flatMap { value in store.screenSchedules.contains(where:{$0.id==value.id}) ? value.id : nil },title:title,firstFire:firstFire,repeatMinutes:repeats ? minutes : nil,style:.init(materialID:material,durationSeconds:15),enabled:schedule?.enabled ?? true,lightOnly:schedule?.lightOnly ?? false); onSave() } catch { self.error=error.localizedDescription }
            }.buttonStyle(.borderedProminent).tint(.orange)
        }.font(.system(size:14)).controlSize(.regular).onAppear { if let schedule { title=schedule.title; firstFire=schedule.fireAt; repeats=schedule.repeatMinutes != nil; minutes=schedule.repeatMinutes ?? 30; material=schedule.style.materialID } }
    }
}

struct WorkspaceReminderLibrary: View {
    @ObservedObject var store: WorkspaceStore
    @State private var importing = false
    @Binding var selected:String
    init(store:WorkspaceStore,selected:Binding<String> = .constant("cat")){self.store=store;self._selected=selected}
    @State private var rename=""
    @State private var renaming=false
    @State private var removing=false
    @State private var removeID:String?
    @State private var previewGeneration = 0
    @State private var playing = false
    @State private var importError = ""
    @Environment(\.nookResolvedTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.screenMaterials.first { $0.id == selected }?.name ?? "提醒预览").font(.system(size: 18, weight: .semibold))
                    Text("先在窗口内看看效果，再用于待办或生活提醒。")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                }
                Spacer()
                Button(playing ? "停止预览" : "播放预览") { playing.toggle(); previewGeneration += 1 }
                    .buttonStyle(IslandButtonStyle(prominent: true))
            }
            WorkspaceReminderMediaPreview(store: store, materialID: selected, generation: previewGeneration, playing: $playing)
                .frame(height: 210).frame(maxWidth: .infinity)
                .background(theme.subtleFill, in: RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .bottomLeading) { Text("窗口内预览").font(.system(size: 10)).foregroundStyle(theme.secondaryLabel).padding(12) }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                ForEach(store.screenMaterials) { material in
                    Button {
                        selected = material.id; playing = false; previewGeneration += 1
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: material.id == "cat" ? "cat.fill" : "play.rectangle.fill").font(.system(size: 25)).foregroundStyle(theme.accent)
                                Spacer()
                                if selected == material.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent) }
                            }
                            Text(material.name).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.primaryLabel)
                            Text((material.filename == nil ? "内置素材" : "个人视频") + " · \(Int(material.durationSeconds.rounded()))秒")
                                .font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(selected == material.id ? theme.accent.opacity(0.08) : theme.subtleFill, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected == material.id ? theme.accent.opacity(0.5) : theme.subtleStroke))
                    }.buttonStyle(.plain).accessibilityAddTraits(selected == material.id ? .isSelected : [])
                    .contextMenu {if material.filename != nil {Button("移除视频…",role:.destructive){removeID=material.id;removing=true}.disabled(store.materialIsUsed(material.id))}}
                }
            }
            HStack {
                Button(importing ? "正在导入…" : "添加自己的视频") { pickVideo() }.disabled(importing).buttonStyle(IslandButtonStyle())
                Spacer()
                Button("停止桌面提醒") { store.dismissAllScreenReminders() }.buttonStyle(.plain).font(.system(size: 12))
            }
            if let material=store.screenMaterials.first(where:{$0.id==selected}), material.filename != nil {
                HStack {Button("重命名"){rename=material.name;renaming=true};Button("移除视频…",role:.destructive){removeID=material.id;removing=true}.disabled(store.materialIsUsed(material.id))}
                if store.materialIsUsed(material.id) {Text("正在用于：" + store.materialUsage(material.id).joined(separator:"、") + "。换用其他效果后可移除。").font(.caption).foregroundStyle(.secondary)}
            }
            if renaming {HStack {TextField("视频名称",text:$rename);Button("保存"){store.renameScreenMaterial(selected,name:rename);renaming=false};Button("取消"){renaming=false}}}
            if !importError.isEmpty { Text(importError).font(.system(size: 12)).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true) }
            Text("支持MP4、MOV，最长2分钟。透明视频直接呈现，普通视频保留原画面。素材只保存在这台Mac；此处播放不会触发桌面提醒。")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
        }.onDisappear { playing = false }
        .confirmationDialog("从素材列表移除这个视频？原视频和本机副本均保留。",isPresented:$removing) {Button("移除",role:.destructive){if let removeID {store.removeScreenMaterial(removeID)}}}
        .task(id: previewGeneration) {
            guard playing, selected == "cat" else { return }
            let duration = store.screenMaterials.first { $0.id == selected }?.durationSeconds ?? 8
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            if !Task.isCancelled { playing = false }
        }
    }
    private func pickVideo() {
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.mpeg4Movie,.quickTimeMovie,.movie]; panel.allowsMultipleSelection=false; panel.canChooseDirectories=false
        panel.begin { response in guard response == .OK, let url=panel.url else { return }; importing=true; importError=""
            Task { do { let result=try await store.importScreenReminderVideo(url); selected=result.id; playing=false; previewGeneration += 1 } catch { importError=error.localizedDescription }; importing=false }
        }
    }

}
struct WorkspaceReminderMediaPreview: NSViewRepresentable {
    let store: WorkspaceStore
    let materialID: String
    var generation = 0
    @Binding var playing: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        for child in view.subviews {
            (child as? ReminderVideoPreview)?.stop()
            (child as? ScreenReminderCatView)?.stop()
        }
    }
    func updateNSView(_ view: NSView, context: Context) {
        let identity = materialID + "-" + String(generation) + "-" + String(playing)
        guard view.identifier?.rawValue != identity else { return }
        view.identifier = NSUserInterfaceItemIdentifier(identity)
        Self.dismantleNSView(view, coordinator: ())
        view.subviews.forEach { $0.removeFromSuperview() }
        let child: NSView
        if materialID == "cat" {
            let cat = ScreenReminderCatView(frame: view.bounds)
            if playing { cat.start() }
            child = cat
        } else {
            let video = ReminderVideoPreview(frame: view.bounds)
            let url: URL?
            if materialID == "rick" {
                let bundled = Bundle.main.url(forResource: "rick-portal", withExtension: "mov", subdirectory: "ScreenReminder")
                let development = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/ScreenReminder/rick-portal.mov")
                url = bundled ?? (FileManager.default.fileExists(atPath: development.path) ? development : nil)
            } else {
                url = try? store.screenReminderRequest(style: .init(materialID: materialID, durationSeconds: 15), title: "预览").videoURL
            }
            video.load(url, playing: playing) { self.playing = false }
            child = video
        }
        child.autoresizingMask = [.width, .height]
        view.addSubview(child)
    }
}

private final class ReminderVideoPreview: NSView {
    private let videoLayer = AVPlayerLayer()
    private var statusObserver: NSKeyValueObservation?
    private var completionObserver: NSObjectProtocol?
    private var active = true
    private let unavailable = NSTextField(labelWithString: "预览暂不可用，请重新选择或导入素材。")
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer = videoLayer
        videoLayer.videoGravity = .resizeAspect
        videoLayer.backgroundColor = NSColor.clear.cgColor
        unavailable.alignment = .center; unavailable.textColor = .secondaryLabelColor
        unavailable.font = .systemFont(ofSize: 12); unavailable.isHidden = true
        unavailable.translatesAutoresizingMaskIntoConstraints = false; addSubview(unavailable)
        NSLayoutConstraint.activate([unavailable.centerXAnchor.constraint(equalTo: centerXAnchor), unavailable.centerYAnchor.constraint(equalTo: centerYAnchor), unavailable.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func load(_ url: URL?, playing: Bool, finished: @escaping () -> Void) {
        guard let url else { unavailable.isHidden = false; return }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item); player.isMuted = true; videoLayer.player = player
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            if item.status == .failed { DispatchQueue.main.async { guard let self, self.active else { return }; self.unavailable.isHidden = false; finished() } }
        }
        completionObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in if self?.active == true { finished() } }
        if playing { player.play() }
    }
    func stop() {
        active = false; videoLayer.player?.pause(); statusObserver = nil
        if let completionObserver { NotificationCenter.default.removeObserver(completionObserver); self.completionObserver = nil }
    }
    deinit { if let completionObserver { NotificationCenter.default.removeObserver(completionObserver) } }
}
