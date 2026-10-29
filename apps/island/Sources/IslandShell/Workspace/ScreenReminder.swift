import AppKit
import AVFoundation
import Foundation

/// Optional on existing tasks: absence preserves the original island-only reminder.
struct ScreenReminderStyle: Codable, Equatable, Sendable {
    var materialID = "cat"
    var durationSeconds = 15
}

struct ScreenReminderMaterial: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    /// A generated basename under this workspace, never an arbitrary path or URL.
    var filename: String?
    var durationSeconds: Double
    var hasAlpha: Bool
    var bundledFilename: String?
    static let builtins = [
        Self(id:"cat",name:"猫咪走动",durationSeconds:11,hasAlpha:true,bundledFilename:"cat-walk.mov"),
        Self(id:"rick",name:"瑞克传送门",durationSeconds:10,hasAlpha:true,bundledFilename:"rick-portal.mov"),
        Self(id:"what-a-day",name:"KUN · What a Day",durationSeconds:60,hasAlpha:true,bundledFilename:"what-a-day-alpha.mov"),
        Self(id:"gemini-greeting",name:"Gemini 人物视频",durationSeconds:10.005,hasAlpha:true,bundledFilename:"gemini-greeting-alpha.mov")
    ]
}

struct WorkScreenSchedule: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var fireAt: Date
    /// nil is a single countdown; repeating reminders advance from the actual check.
    var repeatMinutes: Int?
    var style = ScreenReminderStyle()
    var enabled = true
    var lastFiredAt: Date?
    /// nil preserves the pre-fusion screen reminder behavior.
    var lightOnly: Bool?
}

struct ScreenReminderRequest: Equatable, Sendable {
    var title: String
    var style: ScreenReminderStyle
    var material: ScreenReminderMaterial
    var videoURL: URL?
    var sound=false
    var isRest=false
}

enum ScreenReminderRules {
    static func validate(_ style: ScreenReminderStyle, materials: [ScreenReminderMaterial]) throws {
        guard (2...120).contains(style.durationSeconds),
              let material=materials.first(where:{$0.id == style.materialID}),
              material.durationSeconds.isFinite, (0...120).contains(material.durationSeconds) else {
            throw WorkError.message("请选择可用提醒素材，显示时间设为2到120秒。")
        }
    }
    static func validate(title: String, firstFire: Date, repeatMinutes: Int?, now: Date = Date()) throws {
        guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, title.count <= 80,
              firstFire.timeIntervalSince1970.isFinite, abs(firstFire.timeIntervalSince(now)) <= 366*86400,
              repeatMinutes.map({ (1...10080).contains($0) }) ?? true else {
            throw WorkError.message("提醒名称最多80字；时间限一年内，循环间隔为1到10080分钟。")
        }
    }
    static func advance(_ schedule: inout WorkScreenSchedule, now: Date) {
        schedule.lastFiredAt = now
        if let minutes = schedule.repeatMinutes, (1...10080).contains(minutes) {
            // Wake/restart catches up once, never replays every missed interval.
            schedule.fireAt = now.addingTimeInterval(Double(minutes)*60)
        } else { schedule.enabled = false }
    }
    static func canDismiss(elapsed: TimeInterval) -> Bool { elapsed >= 3 }
    static func playbackSeconds(_ request: ScreenReminderRequest) -> TimeInterval {
        min(120,max(Double(request.style.durationSeconds),ceil(request.material.durationSeconds)+1))
    }
    static func visualFrame(in size: CGSize, hasAlpha: Bool) -> CGRect {
        let factor: CGFloat = hasAlpha ? 0.72 : 0.48
        let width = max(1,min(size.width*factor,1100)), height = max(1,min(size.height*factor,720))
        return CGRect(x:(size.width-width)/2,y:(size.height-height)/2,width:width,height:height)
    }
}

enum ScreenReminderMedia {
    static let maximumBytes = 150_000_000
    static func bundledURL(_ id: String) -> URL? {
        guard let filename=ScreenReminderMaterial.builtins.first(where:{$0.id==id})?.bundledFilename else{return nil}
        if let url=Bundle.main.resourceURL?.appendingPathComponent("ScreenReminder").appendingPathComponent(filename), FileManager.default.fileExists(atPath:url.path) {return url}
        // Command-line checks use only the repository's explicitly bundled media.
        guard Bundle.main.bundleIdentifier != "local.zaizhi.feishu-island.preview" else{return nil}
        let source=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/ScreenReminder").appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath:source.path) ? source : nil
    }
    static func validateFile(_ url: URL) throws {
        let properties = try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard url.isFileURL, properties.isRegularFile == true, properties.isSymbolicLink != true,
              ["mp4","mov","m4v"].contains(url.pathExtension.lowercased()),
              let size = properties.fileSize, size > 0, size <= maximumBytes else {
            throw WorkError.message("请选择150MB以内的普通MP4或MOV视频，不支持链接和替身。")
        }
    }
    static func inspect(_ url: URL) async throws -> (duration: Double, alpha: Bool) {
        try validateFile(url)
        let asset = AVURLAsset(url:url)
        guard let track = try await asset.loadTracks(withMediaType:.video).first else { throw WorkError.message("视频没有可播放画面。") }
        let duration = try await asset.load(.duration).seconds
        let size = try await track.load(.naturalSize)
        let characteristics = try await track.load(.mediaCharacteristics)
        guard duration.isFinite, duration > 0, duration <= 120, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0, size.width*size.height <= 16_000_000 else {
            throw WorkError.message("请选择120秒以内、1600万像素以内的视频。")
        }
        return (duration,characteristics.contains(.containsAlphaChannel))
    }
    static func ownedURL(_ material: ScreenReminderMaterial, root: URL) throws -> URL {
        guard let filename=material.filename, filename == URL(fileURLWithPath:filename).lastPathComponent,
              !filename.hasPrefix("."), !filename.contains("/"),
              UUID(uuidString:URL(fileURLWithPath:filename).deletingPathExtension().lastPathComponent) != nil else {
            throw WorkError.message("个人提醒素材记录无效，请重新导入。")
        }
        let url=root.appendingPathComponent("ScreenReminderMedia",isDirectory:true).appendingPathComponent(filename)
        try validateFile(url)
        return url
    }
}

/// Reuses the original reminder's AVPlayerLayer approach, while excluding its opaque
/// full-screen backdrop, key-window activation and event interception.
@MainActor final class ScreenReminderPresenter: NSObject {
    static let shared = ScreenReminderPresenter()
    private struct Entry {
        var id=UUID()
        var request:ScreenReminderRequest
        var screen:NSScreen?
        var testFrame:CGRect?
    }
    private var pending:[Entry]=[]
    private var current:Entry?
    private var resumeTimer:Timer?
    private var sleepObservers:[NSObjectProtocol]=[]
    private var sleeping=false
    private var deliveryPaused:Bool {sleeping || sessionIsLocked()}
    private(set) var deliveredTitles:[String]=[]
    var deliveryFailed:(ScreenReminderRequest,Error)->Void = {_,_ in}
    var pendingCount:Int {pending.count}
    private var windows: [NSPanel] = []
    private var player: AVPlayer?
    private var expiry: Timer?
    private var dismissalWatchdog: DispatchWorkItem?
    private var interactionStarted: TimeInterval = 0
    private var localEscape: Any?
    private var globalEscape: Any?
    private var lockObserver: NSObjectProtocol?
    private(set) var isPresenting = false
    private(set) var presentationCount = 0
    private(set) var lastPresentedAt: Date?
    var diagnostics: [String: Any] {
        ["isPresenting": isPresenting, "presentationCount": presentationCount, "pendingCount":pending.count,
         "lastPresentedAt": lastPresentedAt.map { ISO8601DateFormatter().string(from:$0) } ?? "",
         "windows": windows.map { ["visible":$0.isVisible,"opaque":$0.isOpaque,"mousePassThrough":$0.ignoresMouseEvents,"canBecomeKey":$0.canBecomeKey,"width":$0.frame.width,"height":$0.frame.height,"x":$0.frame.minX,"y":$0.frame.minY] as [String:Any] }]
    }
    /// Tests construct and inspect real windows without ordering them on screen.
    let displaysWindows: Bool
    private let sessionIsLocked: () -> Bool
    init(displaysWindows: Bool = true, sessionIsLocked: @escaping () -> Bool = { ScreenReminderSession.isLocked }) {
        self.displaysWindows=displaysWindows; self.sessionIsLocked=sessionIsLocked; super.init()
        if displaysWindows {
            sleepObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) {[weak self] _ in Task { @MainActor in self?.sleeping=true;self?.suspendForLock() }})
            sleepObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) {[weak self] _ in Task { @MainActor in self?.sleeping=false;self?.resumePending() }})
        }
    }

    func present(_ request: ScreenReminderRequest, screen: NSScreen? = nil, testFrame: CGRect? = nil) throws {
        guard !deliveryPaused else {throw WorkError.message("锁屏期间暂停冲屏提醒。")}
        try validateDelivery(request)
        let entry=Entry(request:request,screen:screen,testFrame:testFrame)
        if current != nil || !pending.isEmpty {
            guard pending.count < 32 else {throw WorkError.message("屏幕提醒较多，已改为岛内提示。")}
            pending.append(entry)
            return
        }
        try display(entry)
    }
    private func validateDelivery(_ request:ScreenReminderRequest) throws {
        guard let url=request.videoURL,url.isFileURL,FileManager.default.fileExists(atPath:url.path) else {throw WorkError.message("提醒视频不可用，请重新选择素材。")}
    }
    private func display(_ entry:Entry) throws {
        let request=entry.request,screen=entry.screen,testFrame=entry.testFrame
        try validateDelivery(request)
        guard !deliveryPaused else { throw WorkError.message("锁屏期间暂停冲屏提醒。") }
        guard !displaysWindows || testFrame == nil else { throw WorkError.message("屏幕检查坐标仅限离屏验证。") }
        guard let bounds = testFrame ?? (screen ?? NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)}) ?? NSScreen.main)?.visibleFrame else { throw WorkError.message("当前没有可用显示器。") }
        let panel=ScreenReminderPanel(contentRect:bounds,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title="一切在岛冲屏画面"
        panel.isReleasedWhenClosed=false; panel.level = .floating
        panel.backgroundColor = .clear; panel.isOpaque=false; panel.hasShadow=false
        panel.ignoresMouseEvents=true; panel.hidesOnDeactivate=false
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
        let root=NSView(frame:CGRect(origin:.zero,size:bounds.size)); root.wantsLayer=true
        root.layer?.backgroundColor=NSColor.clear.cgColor; panel.contentView=root
        let frame=ScreenReminderRules.visualFrame(in:bounds.size,hasAlpha:request.material.hasAlpha)
        guard let url=request.videoURL else { throw WorkError.message("提醒视频不可用，请重新选择素材。") }
        let view=ScreenReminderVideoView(frame:frame), media=AVPlayer(url:url)
        media.isMuted = !request.sound; media.actionAtItemEnd = .pause; view.videoLayer.player=media
        root.addSubview(view); player=media
        if displaysWindows { media.play() }
        let caption=NSTextField(wrappingLabelWithString:request.title)
        caption.isSelectable=false; caption.alignment = .center
        caption.font = .systemFont(ofSize:min(32,max(18,bounds.width/45)),weight:.semibold)
        caption.textColor = .white; caption.drawsBackground=false
        let shadow=NSShadow(); shadow.shadowColor=NSColor.black.withAlphaComponent(0.8); shadow.shadowBlurRadius=5
        caption.attributedStringValue=NSAttributedString(string:request.title,attributes:[.font:caption.font!,.foregroundColor:NSColor.white,.shadow:shadow])
        caption.frame=CGRect(x:bounds.width*0.15,y:24,width:bounds.width*0.7,height:72)
        root.addSubview(caption)
        let close=ScreenReminderPanel(contentRect:CGRect(x:bounds.maxX-146,y:bounds.maxY-50,width:130,height:34),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        close.title="一切在岛冲屏关闭"
        close.isReleasedWhenClosed=false; close.level = .floating; close.isOpaque=false
        close.backgroundColor = .clear; close.hidesOnDeactivate=false
        close.collectionBehavior=panel.collectionBehavior
        let button=NSButton(title:"关闭提醒 ×",target:self,action:#selector(dismiss)); button.bezelStyle = .rounded
        button.frame=CGRect(origin:.zero,size:close.frame.size); button.setAccessibilityLabel("关闭冲屏提醒")
        close.contentView=button
        if request.isRest {
            close.setFrame(CGRect(x:bounds.midX-215,y:bounds.minY+16,width:430,height:36),display:false)
            let actions=NSStackView();actions.orientation = .horizontal;actions.spacing=8
            for (title,selector) in [("开始休息",#selector(restDone)),("10分钟后提醒",#selector(restLater)),("跳过本次",#selector(dismiss))] {let b=NSButton(title:title,target:self,action:selector);b.bezelStyle = .rounded;actions.addArrangedSubview(b)}
            close.contentView=actions
        }
        windows=[panel,close];current=entry
        deliveredTitles.append(request.title)
        if deliveredTitles.count>64 {deliveredTitles.removeFirst()}
        if displaysWindows {
            panel.orderFrontRegardless(); close.orderFrontRegardless(); isPresenting=true
            presentationCount += 1; lastPresentedAt=Date(); interactionStarted=ProcessInfo.processInfo.systemUptime
            expiry=Timer.scheduledTimer(withTimeInterval:ScreenReminderRules.playbackSeconds(request),repeats:false) { [weak self] _ in Task { @MainActor in guard self?.current?.id == entry.id else{return};self?.dismiss() } }
            if let expiry { RunLoop.main.add(expiry,forMode:.common) }
            let watchdog=DispatchWorkItem { [weak self] in guard self?.current?.id == entry.id else{return};self?.dismiss() }
            dismissalWatchdog=watchdog
            DispatchQueue.main.asyncAfter(deadline:.now()+ScreenReminderRules.playbackSeconds(request)+1,execute:watchdog)
            localEscape=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.leftMouseDown,.rightMouseDown,.otherMouseDown]) { [weak self] event in
                guard let self, self.current?.id == entry.id, ScreenReminderRules.canDismiss(elapsed:ProcessInfo.processInfo.systemUptime-self.interactionStarted) else { return event }
                if event.window === self.windows.last { return event } // Keep the explicit rest actions usable.
                self.dismiss(); return nil
            }
            // Global key monitoring may be unavailable without system permission. The
            // visible close control and bounded timeout do not depend on that permission.
            globalEscape=NSEvent.addGlobalMonitorForEvents(matching:[.keyDown,.leftMouseDown,.rightMouseDown,.otherMouseDown]) { [weak self] event in
                Task { @MainActor in
                    guard let self, self.current?.id == entry.id, ScreenReminderRules.canDismiss(elapsed:ProcessInfo.processInfo.systemUptime-self.interactionStarted) else { return }; self.dismiss()
                }
            }
            lockObserver=DistributedNotificationCenter.default().addObserver(forName:NSNotification.Name("com.apple.screenIsLocked"),object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.suspendForLock() } }
        }
    }
    @objc private func restDone(){WorkspaceStore.shared.changeRest{$0.restart(now:Date())};dismiss()}
    @objc private func restLater(){WorkspaceStore.shared.postponeRest()}
    var verificationWindows: [NSPanel] { windows }
    @objc func dismiss() {
        clearCurrent()
        showNext()
    }
    func dismissAll() {
        pending=[];resumeTimer?.invalidate();resumeTimer=nil;clearCurrent()
    }
    func suspendForLock() {
        if let current {pending.insert(current,at:0)}
        clearCurrent()
        guard resumeTimer == nil, !pending.isEmpty else{return}
        resumeTimer=Timer.scheduledTimer(withTimeInterval:1,repeats:true) {[weak self] _ in
            Task { @MainActor in
                guard let self,!self.deliveryPaused else{return}
                self.resumeTimer?.invalidate();self.resumeTimer=nil;self.showNext()
            }
        }
        if let resumeTimer {RunLoop.main.add(resumeTimer,forMode:.common)}
    }
    func resumePending() {
        guard !deliveryPaused,current == nil else{return}
        resumeTimer?.invalidate();resumeTimer=nil;showNext()
    }
    private func showNext() {
        guard current == nil else{return}
        guard !deliveryPaused else {suspendForLock();return}
        while !pending.isEmpty {
            let entry=pending.removeFirst()
            do {try display(entry);return} catch {deliveryFailed(entry.request,error)}
        }
    }
    func removeMaterial(_ id:String) {
        pending.removeAll{$0.request.material.id==id}
        if current?.request.material.id==id {dismiss()}
    }
    private func clearCurrent() {
        current=nil
        expiry?.invalidate(); expiry=nil; dismissalWatchdog?.cancel(); dismissalWatchdog=nil
        player?.pause(); player=nil
        if let localEscape { NSEvent.removeMonitor(localEscape) }; localEscape=nil
        if let globalEscape { NSEvent.removeMonitor(globalEscape) }; globalEscape=nil
        if let lockObserver { DistributedNotificationCenter.default().removeObserver(lockObserver) }; lockObserver=nil
        windows.forEach{$0.orderOut(nil)}; windows=[]; isPresenting=false
    }
}

final class ScreenReminderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class ScreenReminderVideoView: NSView {
    let videoLayer=AVPlayerLayer()
    override init(frame: NSRect) {
        super.init(frame:frame); wantsLayer=true; layer?.backgroundColor=NSColor.clear.cgColor
        videoLayer.backgroundColor=NSColor.clear.cgColor; videoLayer.videoGravity = .resizeAspect
        layer?.addSublayer(videoLayer)
    }
    required init?(coder:NSCoder) { nil }
    override func layout() { super.layout(); videoLayer.frame=bounds }
}
enum ScreenReminderSession {
    static var isLocked: Bool {
        guard let session=CGSessionCopyCurrentDictionary() as? [String:Any] else { return true }
        return session["CGSSessionScreenIsLocked"] as? Bool == true
    }
}
