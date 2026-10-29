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
    private var localMovement: Any?
    private var globalMovement: Any?
    private var gesture: HubPingGesture?
    private var openDirection: ((Int) -> Bool)?
    private var presentationID = UUID()
    private var shortcutDown = false
    private var releaseWatcher: Timer?
    private var keyFallback: Any?
    private var lastPressTime = -Double.greatestFiniteMagnitude
    private var expiry:Task<Void,Never>?
    private var registeredHotkey: NookHotkey?
    func start() {
        let preview = IslandRuntime.isSkinPreview && (Bundle.main.bundleIdentifier == "local.youzi.island.skin-preview"
            || ProcessInfo.processInfo.arguments.contains("--shortcut-preview"))
        guard preview || (Bundle.main.bundleIdentifier == "local.zaizhi.feishu-island.preview" && !IslandRuntime.isSkinPreview) else { return }
        if handler == nil {
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let installed=InstallEventHandler(GetApplicationEventTarget(),{ _,event,_ in
            guard let event else {return OSStatus(eventNotHandledErr)}
            var id=EventHotKeyID()
            guard GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id)==noErr,
                  id.signature == OSType(0x49535047) else {return OSStatus(eventNotHandledErr)}
            let kind = GetEventKind(event)
            DispatchQueue.main.async {
                if kind == UInt32(kEventHotKeyPressed) { HubPingLauncher.shared.shortcutPressed() }
                else if kind == UInt32(kEventHotKeyReleased) { HubPingLauncher.shared.shortcutReleased() }
            }
            return noErr
        },2,&types,nil,&handler)
        guard installed == noErr else { UnifiedPlatformStore.shared.reportShortcutError(); return }
        }
        let store = UnifiedPlatformStore.shared
        store.registerHotkey = { [weak self] value in self?.register(value) ?? false }
        if hotkey == nil, !register(store.hotkey) { store.reportShortcutError() }
        if keyFallback == nil {
            // App-directed key events may bypass Carbon while a settings or
            // nonactivating window owns focus. Preserve the same press/release path.
            keyFallback = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self, let value = self.registeredHotkey, UInt32(event.keyCode) == value.keyCode else { return event }
                if event.type == .keyUp, self.shortcutDown { self.shortcutReleased(); return nil }
                guard event.type == .keyDown, HubShortcutInput.matches(event, value) else { return event }
                if !event.isARepeat { self.shortcutPressed() }
                return nil
            }
        }
    }
    private func register(_ value: NookHotkey) -> Bool {
        if registeredHotkey == value, hotkey != nil { return true }
        var candidate: EventHotKeyRef?
        guard RegisterEventHotKey(value.keyCode, value.carbonModifiers, EventHotKeyID(signature: OSType(0x49535047), id: 1), GetApplicationEventTarget(), 0, &candidate) == noErr else { return false }
        if let hotkey { UnregisterEventHotKey(hotkey) }
        hotkey = candidate; registeredHotkey = value
        return true
    }
    func suspendForRecording() { if let hotkey { UnregisterEventHotKey(hotkey) }; hotkey = nil; registeredHotkey = nil; shortcutDown = false; close() }
    func resumeAfterRecording() {
        guard handler != nil else { return }
        if !register(UnifiedPlatformStore.shared.hotkey) { UnifiedPlatformStore.shared.reportShortcutError() }
    }
    private func shortcutPressed() {
        let now = ProcessInfo.processInfo.systemUptime
        guard !shortcutDown, now - lastPressTime > 0.10 else { return }
        lastPressTime = now
        if panel?.isVisible == true { close(); return }
        show(shortcutHeld: true)
        shortcutDown = true
        // Carbon can miss key-up when a nonactivating panel becomes key or a
        // modifier is released first. Observe physical release while held only.
        let code = CGKeyCode(registeredHotkey?.keyCode ?? UnifiedPlatformStore.shared.hotkey.keyCode)
        releaseWatcher = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !CGEventSource.keyState(.combinedSessionState, key: code) { self.shortcutReleased() }
            }
        }
        RunLoop.main.add(releaseWatcher!, forMode: .common)
    }
    private func shortcutReleased() {
        guard shortcutDown else { return }
        shortcutDown = false; releaseWatcher?.invalidate(); releaseWatcher = nil
        guard let panel, panel.isVisible, let gesture else { return }
        apply(gesture.releaseShortcut(at: pointInWheel(NSEvent.mouseLocation), mouseButtonDown: NSEvent.pressedMouseButtons != 0))
    }
    func show(shortcutHeld: Bool = false) {
        guard !ScreenReminderSession.isLocked else {return}
        close()
        let launcher=UnifiedPlatformStore.shared,workspace=WorkspaceStore.shared
        let diameter: CGFloat = 400
        let p=panel ?? HubPingPanel(contentRect:.init(x:0,y:0,width:diameter,height:diameter),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.isReleasedWhenClosed=false;p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false
        p.hidesOnDeactivate = false
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 9)
        p.title = "中台快捷轮盘"
        p.setAccessibilityIdentifier("island.hubWheel")
        p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        p.acceptsMouseMovedEvents = true
        let pointer=NSEvent.mouseLocation
        let bounds=(NSScreen.screens.first{$0.frame.contains(pointer)} ?? NSScreen.main)?.visibleFrame ?? .init(x:0,y:0,width:1024,height:768)
        p.setFrame(.init(x:min(max(pointer.x-diameter/2,bounds.minX+8),bounds.maxX-diameter-8),y:min(max(pointer.y-diameter/2,bounds.minY+8),bounds.maxY-diameter-8),width:diameter,height:diameter),display:false)
        panel = p
        let interaction = HubPingGesture(diameter: diameter, origin: pointInWheel(pointer), shortcutHeld: shortcutHeld)
        gesture = interaction
        let destinations = launcher.destinations(cards:workspace.hub.cards,selectedIDs:workspace.disk.selectedCards,applications:workspace.hub.applications ?? [])
        let session = presentationID
        openDirection = { id in
            guard let destination = destinations.first(where: { $0.id == id }) else { return false }
            return launcher.activate(destination)
        }
        p.contentView = NSHostingView(rootView: HubPingWheel(destinations: destinations, gesture: interaction, activate: { [weak self] destination in
            guard let self, self.presentationID == session, self.panel?.isVisible == true else { return false }
            interaction.cancel()
            let opened = launcher.activate(destination)
            if opened { self.close() } else { interaction.reset(at: self.pointInWheel(NSEvent.mouseLocation)) }
            return opened
        }, cancel: { [weak self] in
            guard self?.presentationID == session else { return }
            self?.close()
        }).preferredColorScheme(.dark))
        p.makeKeyAndOrderFront(nil)
        outside=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { if self?.presentationID == session { self?.close() } }
        }
        keys=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            if event.keyCode == 53 {
                DispatchQueue.main.async { if self?.presentationID == session { self?.close() } }
                return nil
            };return event
        }
        let movement: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let track: (NSEvent) -> Void = { [weak self] _ in
            let point = NSEvent.mouseLocation, buttons = NSEvent.pressedMouseButtons
            DispatchQueue.main.async {
                guard let self, self.presentationID == session, self.panel?.isVisible == true else { return }
                self.apply(self.gesture?.move(to: self.pointInWheel(point), mouseButtonDown: buttons != 0))
            }
        }
        localMovement = NSEvent.addLocalMonitorForEvents(matching: movement) { event in track(event); return event }
        globalMovement = NSEvent.addGlobalMonitorForEvents(matching: movement, handler: track)
        expiry=Task { @MainActor [weak self] in do {try await Task.sleep(for:.seconds(20))} catch {return};self?.close() }
    }
    private func pointInWheel(_ point: CGPoint) -> CGPoint {
        guard let panel else { return .zero }
        return CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
    }
    private func apply(_ action: HubPingGesture.Action?) {
        guard let action, panel?.isVisible == true else { return }
        guard !ScreenReminderSession.isLocked else { close(); return }
        switch action {
        case .cancel: close()
        case .open(let direction):
            if openDirection?(direction) == true { close() }
            else { gesture?.reset(at: pointInWheel(NSEvent.mouseLocation)) }
        }
    }
    func close() {
        shortcutDown = false; releaseWatcher?.invalidate(); releaseWatcher = nil
        presentationID = UUID()
        gesture?.cancel(); gesture = nil; openDirection = nil
        expiry?.cancel();expiry=nil;panel?.orderOut(nil)
        if let outside {NSEvent.removeMonitor(outside);self.outside=nil}
        if let keys {NSEvent.removeMonitor(keys);self.keys=nil}
        if let localMovement { NSEvent.removeMonitor(localMovement); self.localMovement = nil }
        if let globalMovement { NSEvent.removeMonitor(globalMovement); self.globalMovement = nil }
    }
}

@MainActor enum HubShortcutInput {
    static func matches(_ event: NSEvent, _ value: NookHotkey) -> Bool {
        guard UInt32(event.keyCode) == value.keyCode else { return false }
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers == value.carbonModifiers
    }
}
