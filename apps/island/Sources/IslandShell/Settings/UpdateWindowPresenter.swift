import AppKit

/// Elevates only the windows belonging to an explicit Sparkle update check.
/// Ordinary settings and automatically scheduled checks keep their own focus rules.
@MainActor final class UpdateWindowPresenter {
    @MainActor private final class SavedWindow {
        weak var window: NSWindow?
        let level: NSWindow.Level
        let behavior: NSWindow.CollectionBehavior
        let hidesOnDeactivate: Bool
        init(_ window: NSWindow) {
            self.window = window; level = window.level
            behavior = window.collectionBehavior; hidesOnDeactivate = window.hidesOnDeactivate
        }
        func restore() {
            window?.level = level; window?.collectionBehavior = behavior
            window?.hidesOnDeactivate = hidesOnDeactivate
        }
    }
    private(set) var active = false
    private var saved: [ObjectIdentifier: SavedWindow] = [:]
    private var observers: [NSObjectProtocol] = []
    private var expectingModal = false
    private var presenting = false
    private var targetScreen: NSScreen?

    static func isSparkleWindow(_ window: NSWindow) -> Bool {
        let bundleID = "org.sparkle-project.Sparkle"
        if Bundle(for: type(of: window)).bundleIdentifier == bundleID { return true }
        if let controller = window.windowController,
           Bundle(for: type(of: controller)).bundleIdentifier == bundleID { return true }
        return false
    }

    func beginManualSession() {
        active = true
        targetScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSApp.keyWindow?.screen ?? NSScreen.main
        if observers.isEmpty {
            let center = NotificationCenter.default
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didUpdateNotification, NSWindow.didDeminiaturizeNotification] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated {
                        if let window = note.object as? NSWindow { self?.consider(window) }
                    }
                })
            }
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    if let window = note.object as? NSWindow {
                        self?.saved.removeValue(forKey: ObjectIdentifier(window))?.restore()
                    }
                }
            })
        }
        NSApp.activate(ignoringOtherApps: true)
        presentExistingWindows()
    }

    func expectModalAlert() { if active { expectingModal = true } }
    func didCloseModalAlert() { expectingModal = false }

    func presentExistingWindows() {
        guard active else { return }
        for window in NSApp.windows { consider(window, refocus: true) }
    }

    private func consider(_ window: NSWindow, refocus: Bool = false) {
        guard active, !presenting, window.isVisible || window.isMiniaturized,
              Self.isSparkleWindow(window) || expectingModal && NSApp.modalWindow === window else { return }
        let id = ObjectIdentifier(window)
        if saved[id] != nil && !refocus { return }
        presenting = true; defer { presenting = false }
        if saved[id] == nil { saved[id] = SavedWindow(window) }
        // The island is at level 33, above statusBar. Sparkle's normal/modal
        // windows otherwise sit behind it even when the application is active.
        let islandLevel = NSApp.windows.filter { $0.identifier?.rawValue == "opennook.panel" }
            .map { $0.level.rawValue }.max() ?? NSWindow.Level.statusBar.rawValue
        window.level = NSWindow.Level(rawValue: max(window.level.rawValue, islandLevel + 1))
        var behavior = window.collectionBehavior
        behavior.remove(.canJoinAllSpaces); behavior.remove(.stationary)
        behavior.formUnion([.moveToActiveSpace, .fullScreenAuxiliary, .canJoinAllApplications])
        window.collectionBehavior = behavior
        window.hidesOnDeactivate = false
        if window.isMiniaturized { window.deminiaturize(nil) }
        if let screen = targetScreen, !screen.frame.intersects(window.frame) {
            let frame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: frame.minX + max(0, (frame.width - window.frame.width) / 2),
                                          y: frame.minY + max(0, (frame.height - window.frame.height) / 2)))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func endSession() {
        active = false; expectingModal = false
        for entry in saved.values { entry.restore() }
        saved.removeAll()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll(); targetScreen = nil
    }
}
