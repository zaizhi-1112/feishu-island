import AppKit
@testable import IslandShell

@MainActor private var dismissalReview: ReminderDismissReview?
@MainActor func showReminderDismissReview() {
    precondition(IslandRuntime.isSkinPreview)
    dismissalReview = ReminderDismissReview()
    dismissalReview?.show()
}
@MainActor private final class ReminderDismissReview: NSObject {
    let presenter=ScreenReminderPresenter(sessionIsLocked:{false})
    let status=NSTextField(labelWithString:"尚未开始")
    var timer: Timer?
    var started: TimeInterval = 0
    let window=NSWindow(contentRect:NSRect(x:100,y:100,width:460,height:150),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    func show() {
        window.title="一切在岛 · 提醒关闭验收";window.isReleasedWhenClosed=false
        let view=NSView(frame:NSRect(x:0,y:0,width:460,height:150))
        status.frame=NSRect(x:20,y:98,width:420,height:30);view.addSubview(status)
        for (index,title) in ["测试待办动效","测试休息动效"].enumerated() {
            let button=NSButton(title:title,target:self,action:#selector(start(_:)));button.tag=index
            button.frame=NSRect(x:20+index*160,y:40,width:145,height:36);button.bezelStyle = .rounded;view.addSubview(button)
        }
        window.contentView=view;window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true){[weak self] _ in
            MainActor.assumeIsolated {
                guard let self else{return}
                let elapsed=ProcessInfo.processInfo.systemUptime-self.started
                self.status.stringValue=self.started==0 ? "尚未开始" : self.presenter.isPresenting ? "正在显示 · \(String(format:"%.1f",elapsed)) 秒" : "已关闭 · 等待下一次测试"
                if self.started>0 && elapsed>12 {self.presenter.dismissAll()}
            }
        }
    }
    @objc func start(_ button:NSButton) {
        presenter.dismissAll();started=ProcessInfo.processInfo.systemUptime
        let id=button.tag==0 ? "what-a-day":"gemini-greeting"
        let material=ScreenReminderMaterial.builtins.first{$0.id==id}!
        try? presenter.present(.init(title:"合成验收",style:.init(materialID:id),material:material,videoURL:ScreenReminderMedia.bundledURL(id),isRest:button.tag==1))
    }
}
