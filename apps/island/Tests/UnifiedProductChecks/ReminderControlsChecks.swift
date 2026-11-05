import AppKit
@testable import IslandShell

@MainActor func runReminderControlsChecks(check: (Bool,String)->Void) throws {
    var now:TimeInterval=100,locked=false
    let presenter=ScreenReminderPresenter(displaysWindows:false,sessionIsLocked:{locked},uptime:{now})
    let material=ScreenReminderMaterial(id:"synthetic-countdown",name:"合成倒计时",durationSeconds:19.2,hasAlpha:true)
    let request=ScreenReminderRequest(title:"休息提醒 · 合成检查",style:.init(durationSeconds:15),material:material,
                                      videoURL:ScreenReminderMedia.bundledURL("cat"),isRest:true)
    let frame=NSRect(x:0,y:0,width:900,height:700)
    func children<T:NSView>(_ root:NSView,_ type:T.Type)->[T] {
        (root as? T).map{[$0]} ?? root.subviews.flatMap{children($0,type)}
    }
    func countdown()->NSTextField {
        children(presenter.verificationWindows.last!.contentView!,NSTextField.self)
            .first{$0.accessibilityIdentifier()=="screen.reminder.countdown"}!
    }
    func render(_ name:String) throws {
        guard let index=CommandLine.arguments.firstIndex(of:"--render-screen-controls") else{return}
        let folder=URL(fileURLWithPath:CommandLine.arguments[index+1])
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let view=presenter.verificationWindows.last!.contentView!
        view.layoutSubtreeIfNeeded()
        if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {
            view.cacheDisplay(in:view.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])?.write(to:folder.appendingPathComponent(name+".png"))
        }
    }
    try presenter.present(request,testFrame:frame)
    let controls=presenter.verificationWindows.last!
    var buttons=children(controls.contentView!,NSButton.self)
    check(buttons.count==3,"rest reminders keep their three existing actions")
    check(buttons.allSatisfy{$0.frame.height>=52 && ($0.font?.pointSize ?? 0)>=20},"buttons have large type and 52pt targets")
    check(buttons.allSatisfy{$0.attributedTitle.size().width<$0.frame.width-8},"all action titles fit without clipping")
    check(buttons.allSatisfy{controls.contentView!.bounds.contains($0.frame)},"wide actions fit inside the footer")
    let visual=presenter.verificationWindows.first!.contentView!.subviews.compactMap{$0 as? ScreenReminderVideoView}.first!
    check(visual.frame.minY>=controls.frame.maxY-frame.minY,"larger controls do not cover the video")
    check(buttons.allSatisfy{$0.acceptsFirstMouse(for:nil)},"actions accept the first mouse click")
    check(buttons[0].attributedTitle.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor == .black,
          "the primary action has dark text on a white surface")
    check(buttons[1].attributedTitle.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor == .white,
          "secondary actions have white text on a dark surface")
    check(presenter.remainingSeconds==21 && countdown().stringValue=="21 秒后自动关闭", "countdown uses the actual video-aware expiry")
    check((countdown().font?.pointSize ?? 0)>=20,"countdown stays readable")
    try render("rest-wide")
    now=101;presenter.refreshCountdown()
    check(presenter.remainingSeconds==20,"countdown advances from the monotonic deadline")
    now=120.1;presenter.refreshCountdown()
    check(presenter.remainingSeconds==1,"fractional remaining time rounds upward")
    now=121.2;presenter.refreshCountdown()
    check(presenter.remainingSeconds==0 && countdown().stringValue=="即将自动关闭","countdown never shows negative seconds")
    locked=true;presenter.suspendForLock()
    check(presenter.remainingSeconds==0 && presenter.verificationWindows.isEmpty,"locking clears visible countdown state")
    now=200;locked=false;presenter.resumePending()
    check(presenter.remainingSeconds==21,"replayed reminder restarts its own actual expiry")
    var next=request;next.style.durationSeconds=5;next.material.durationSeconds=0.1;next.isRest=false
    now=205;presenter.refreshCountdown();try presenter.present(next,testFrame:frame)
    check(presenter.remainingSeconds==16,"queueing a reminder does not reset the active countdown")
    presenter.dismiss()
    check(presenter.remainingSeconds==5,"the next reminder owns a fresh countdown")
    buttons=children(presenter.verificationWindows.last!.contentView!,NSButton.self)
    check(buttons.count==1 && buttons[0].frame.height>=52,"ordinary reminders keep one large close action")
    try render("message-close")
    presenter.dismissAll();now=1000;presenter.refreshCountdown()
    check(presenter.remainingSeconds==0 && presenter.verificationWindows.isEmpty,"dismissed timers cannot update a later surface")
    try presenter.present(request,testFrame:NSRect(x:0,y:0,width:480,height:700))
    let narrow=presenter.verificationWindows.last!,narrowView=presenter.verificationWindows.last!.contentView!
    buttons=children(narrowView,NSButton.self)
    check(narrow.frame.width<=448 && buttons.count==3,"narrow screens retain all rest actions")
    check(buttons.allSatisfy{narrowView.bounds.contains($0.frame) && $0.frame.height>=52},"narrow actions keep full-size targets")
    check(Set(buttons.map{$0.frame.minY}).count==3,"narrow screens stack actions vertically")
    check(buttons.allSatisfy{$0.attributedTitle.size().width<$0.frame.width-8},"stacked labels remain complete")
    check(presenter.verificationWindows.allSatisfy{!$0.isVisible && !$0.isOpaque && !$0.canBecomeKey},"synthetic layout checks remain hidden and nonactivating")
    try render("rest-narrow")
    presenter.dismissAll()

    let motion=Overlay(showsWindow:false,frame:frame)
    motion.multilineMotion=true;motion.enqueue("合成单次点击",messageID:"synthetic-first-press")
    var closed=0;motion.onFinished={_ in closed+=1};motion.tick()
    let flying=motion.flying.first!,target=flying.motionPanel!
    let point=flying.dismissButton.convert(NSPoint(x:15,y:15),to:nil)
    let click=NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:now,
                                windowNumber:target.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
    try presenter.present(request,testFrame:frame)
    check(presenter.handleLocalDismissalEvent(click) === click && presenter.verificationWindows.count==2,
          "the three-second reminder gate leaves ordinary pointer events untouched")
    now+=4
    let own=NSEvent.mouseEvent(with:.leftMouseDown,location:NSPoint(x:30,y:30),modifierFlags:[],timestamp:now,
                              windowNumber:presenter.verificationWindows.last!.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:1)!
    check(presenter.handleLocalDismissalEvent(own) === own && presenter.verificationWindows.count==2,
          "explicit reminder actions keep their own first click")
    let forwarded=presenter.handleLocalDismissalEvent(click)
    check(forwarded === click && presenter.verificationWindows.isEmpty && presenter.remainingSeconds==0,
          "dismissing a reminder forwards the original click to the intended control")
    if let forwarded { target.sendEvent(forwarded) }
    check(closed==1 && motion.flying.isEmpty,"one press closes a reminder and the target danmu without a second click")
    try presenter.present(request,testFrame:frame);now+=4
    let key=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:now,windowNumber:0,
                            context:nil,characters:"a",charactersIgnoringModifiers:"a",isARepeat:false,keyCode:0)!
    check(presenter.handleLocalDismissalEvent(key)==nil && presenter.verificationWindows.isEmpty,
          "keyboard dismissal still consumes the dismissal key")
}
