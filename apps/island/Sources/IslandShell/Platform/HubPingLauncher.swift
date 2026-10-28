import AppKit
import Carbon
import SwiftUI
import NookApp

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
    private var registeredHotkey: NookHotkey?
    func start() {
        let preview = IslandRuntime.isSkinPreview && (Bundle.main.bundleIdentifier == "local.youzi.island.skin-preview"
            || ProcessInfo.processInfo.arguments.contains("--shortcut-preview"))
        guard preview || (Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview" && !IslandRuntime.isSkinPreview) else { return }
        if handler == nil {
        var type=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        let installed=InstallEventHandler(GetApplicationEventTarget(),{ _,event,_ in
            guard let event else {return OSStatus(eventNotHandledErr)}
            var id=EventHotKeyID()
            guard GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id)==noErr,
                  id.signature == OSType(0x49535047) else {return OSStatus(eventNotHandledErr)}
            Task { @MainActor in HubPingLauncher.shared.toggle() }
            return noErr
        },1,&type,nil,&handler)
        guard installed == noErr else { UnifiedPlatformStore.shared.reportShortcutError(); return }
        }
        let store = UnifiedPlatformStore.shared
        store.registerHotkey = { [weak self] value in self?.register(value) ?? false }
        if hotkey == nil, !register(store.hotkey) { store.reportShortcutError() }
    }
    private func register(_ value: NookHotkey) -> Bool {
        if registeredHotkey == value, hotkey != nil { return true }
        var candidate: EventHotKeyRef?
        guard RegisterEventHotKey(value.keyCode, value.carbonModifiers, EventHotKeyID(signature: OSType(0x49535047), id: 1), GetApplicationEventTarget(), 0, &candidate) == noErr else { return false }
        if let hotkey { UnregisterEventHotKey(hotkey) }
        hotkey = candidate; registeredHotkey = value
        return true
    }
    func suspendForRecording() { if let hotkey { UnregisterEventHotKey(hotkey) }; hotkey = nil; registeredHotkey = nil; close() }
    func resumeAfterRecording() {
        guard handler != nil else { return }
        if !register(UnifiedPlatformStore.shared.hotkey) { UnifiedPlatformStore.shared.reportShortcutError() }
    }
    func toggle() { if panel?.isVisible == true {close();return}; show() }
    func show() {
        guard !ScreenReminderSession.isLocked else {return}
        close()
        let launcher=UnifiedPlatformStore.shared,workspace=WorkspaceStore.shared
        let diameter: CGFloat = 400
        let view=HubPingWheel(destinations:launcher.destinations(cards:workspace.hub.cards,selectedIDs:workspace.disk.selectedCards,applications:workspace.hub.applications ?? []),diameter:diameter,activate: { [weak self] destination in
            let opened=launcher.activate(destination);if opened {self?.close()};return opened
        }, cancel: { [weak self] in self?.close() }).preferredColorScheme(.dark)
        let p=panel ?? HubPingPanel(contentRect:.init(x:0,y:0,width:diameter,height:diameter),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.isReleasedWhenClosed=false;p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false
        p.hidesOnDeactivate = false
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 9)
        p.title = "中台快捷轮盘"
        p.setAccessibilityIdentifier("island.hubWheel")
        p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];p.contentView=NSHostingView(rootView:view)
        let pointer=NSEvent.mouseLocation
        let bounds=(NSScreen.screens.first{$0.frame.contains(pointer)} ?? NSScreen.main)?.visibleFrame ?? .init(x:0,y:0,width:1024,height:768)
        p.setFrame(.init(x:min(max(pointer.x-diameter/2,bounds.minX+8),bounds.maxX-diameter-8),y:min(max(pointer.y-diameter/2,bounds.minY+8),bounds.maxY-diameter-8),width:diameter,height:diameter),display:false)
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
