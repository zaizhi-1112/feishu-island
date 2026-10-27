import AppKit
import Carbon
import SwiftUI

private final class HubPingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// One small, transient panel at the pointer. No full-screen overlay or Agent actions.
@MainActor final class HubPingLauncher {
    static let shared=HubPingLauncher()
    private var hotkey:EventHotKeyRef?
    private var handler:EventHandlerRef?
    private var panel:NSPanel?
    private var outside:Any?
    private var keys:Any?
    private var expiry:Task<Void,Never>?
    func start() {
        guard hotkey == nil,Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview",!IslandRuntime.isSkinPreview else {return}
        var type=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        let installed=InstallEventHandler(GetApplicationEventTarget(),{ _,event,_ in
            guard let event else {return OSStatus(eventNotHandledErr)}
            var id=EventHotKeyID()
            guard GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id)==noErr,
                  id.signature == OSType(0x49535047) else {return OSStatus(eventNotHandledErr)}
            Task { @MainActor in HubPingLauncher.shared.toggle() }
            return noErr
        },1,&type,nil,&handler)
        guard installed == noErr else {return}
        let result=RegisterEventHotKey(UInt32(kVK_Space),UInt32(controlKey|optionKey),EventHotKeyID(signature:OSType(0x49535047),id:1),GetApplicationEventTarget(),0,&hotkey)
        if result != noErr { UnifiedPlatformStore.shared.reportShortcutError() }
    }
    func toggle() { if panel?.isVisible == true {close();return}; show() }
    func show() {
        guard !ScreenReminderSession.isLocked else {return}
        let launcher=UnifiedPlatformStore.shared,workspace=WorkspaceStore.shared
        let view=HubPingWheel(destinations:launcher.destinations(cards:workspace.hub.cards,selectedIDs:workspace.disk.selectedCards),diameter:340) { [weak self] destination in
            let opened=launcher.activate(destination);if opened {self?.close()};return opened
        }.padding(12).background(Color.black.opacity(0.94),in:RoundedRectangle(cornerRadius:24)).preferredColorScheme(.dark)
        let p=panel ?? HubPingPanel(contentRect:.init(x:0,y:0,width:364,height:400),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.isReleasedWhenClosed=false;p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=true;p.level = .floating
        p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];p.contentView=NSHostingView(rootView:view)
        let pointer=NSEvent.mouseLocation
        let bounds=(NSScreen.screens.first{$0.frame.contains(pointer)} ?? NSScreen.main)?.visibleFrame ?? .init(x:0,y:0,width:1024,height:768)
        p.setFrameOrigin(.init(x:min(max(pointer.x-182,bounds.minX+8),bounds.maxX-372),y:min(max(pointer.y-200,bounds.minY+8),bounds.maxY-408)))
        panel=p;p.makeKeyAndOrderFront(nil)
        outside=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) { [weak self] _ in Task { @MainActor in self?.close() } }
        keys=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            if event.keyCode == 53 {Task { @MainActor in self?.close() };return nil};return event
        }
        expiry=Task { @MainActor [weak self] in do {try await Task.sleep(for:.seconds(20))} catch {return};self?.close() }
    }
    func close() {
        expiry?.cancel();expiry=nil;panel?.orderOut(nil)
        if let outside {NSEvent.removeMonitor(outside);self.outside=nil}
        if let keys {NSEvent.removeMonitor(keys);self.keys=nil}
    }
}
