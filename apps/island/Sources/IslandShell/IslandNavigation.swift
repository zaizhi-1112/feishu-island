import AppKit
import NookApp
import SwiftUI

/// Shared routing keeps module changes on OpenNook's supported coordinator path.
@MainActor
final class IslandModuleNavigation: ObservableObject {
    static let shared = IslandModuleNavigation()
    private weak var coordinator: AppCoordinator?
    @Published private(set) var appState: AppState?

    func bind(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        if appState !== coordinator.appState { appState = coordinator.appState }
    }
    func openFeishu() { coordinator?.switchModule(to: IslandHost.feishuID) }
    func openWorkspace() { coordinator?.switchModule(to: IslandHost.workspaceID) }
    func toggleKeepOpen() { coordinator?.toggleKeepNookOpen() }
}

enum IslandSwipeDirection: Equatable { case previous, next }

/// A pure accumulator, shared across replacement views for the same window. A module
/// switch must not turn the remainder of the same trackpad gesture into another switch.
struct IslandSwipeAccumulator {
    struct Result {
        var direction: IslandSwipeDirection?
        var consumesEvent = false
    }
    private enum Axis { case undecided, vertical, horizontal }
    private var axis = Axis.undecided
    private var active = false
    private var fired = false
    private var x: CGFloat = 0
    private var horizontalTravel: CGFloat = 0
    private var verticalTravel: CGFloat = 0
    private var lastTimestamp: TimeInterval?

    mutating func receive(dx: CGFloat, dy: CGFloat, phase: NSEvent.Phase,
                          momentum: NSEvent.Phase = [], precise: Bool = true,
                          timestamp: TimeInterval) -> Result {
        guard precise, momentum.isEmpty, !phase.isEmpty, dx.isFinite, dy.isFinite else { return .init() }
        // Two represented views can briefly coexist during a cross-fade.
        if lastTimestamp == timestamp { return .init(consumesEvent: axis == .horizontal && fired) }
        lastTimestamp = timestamp
        if phase.contains(.began) {
            active = true; fired = false; axis = .undecided
            x = 0; horizontalTravel = 0; verticalTravel = 0
        }
        guard active else { return .init() } // Moving over the island mid-scroll isn't a new swipe.
        if phase.contains(.cancelled) || phase.contains(.ended) {
            let consumed = axis == .horizontal && fired
            active = false
            return .init(consumesEvent: consumed)
        }
        if fired { return .init(consumesEvent: true) }
        x += dx; horizontalTravel += abs(dx); verticalTravel += abs(dy)
        if axis == .undecided, verticalTravel >= 10, verticalTravel > horizontalTravel * 1.2 {
            axis = .vertical
        }
        guard axis != .vertical, abs(x) >= 32, horizontalTravel > verticalTravel * 1.6 else { return .init() }
        axis = .horizontal; fired = true
        // scrollingDeltaX follows content movement (including macOS natural scrolling).
        return .init(direction: x < 0 ? .next : .previous, consumesEvent: true)
    }
}

@MainActor
private final class IslandSwipeSessions {
    static let shared = IslandSwipeSessions()
    private var windows: [Int: IslandSwipeAccumulator] = [:]
    func receive(_ event: NSEvent, window: NSWindow) -> IslandSwipeAccumulator.Result {
        var session = windows[window.windowNumber] ?? .init()
        let result = session.receive(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY,
                                     phase: event.phase, momentum: event.momentumPhase,
                                     precise: event.hasPreciseScrollingDeltas, timestamp: event.timestamp)
        windows[window.windowNumber] = session
        return result
    }
}

/// Observes only scroll events over its own visible bounds. It is a background view:
/// clicks, text selection and vertical scrolling continue to the real SwiftUI controls.
@MainActor
private struct IslandSwipeSurface: NSViewRepresentable {
    let action: (IslandSwipeDirection) -> Void
    func makeNSView(context: Context) -> IslandSwipeNSView { IslandSwipeNSView(action: action) }
    func updateNSView(_ view: IslandSwipeNSView, context: Context) { view.action = action }
}

@MainActor
private final class IslandSwipeNSView: NSView {
    var action: (IslandSwipeDirection) -> Void
    private var monitor: Any?
    init(action: @escaping (IslandSwipeDirection) -> Void) {
        self.action = action
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let consumesEvent = MainActor.assumeIsolated {
                guard let self, let window = self.window, event.window === window,
                      !self.isHiddenOrHasHiddenAncestor,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return false }
                let result = IslandSwipeSessions.shared.receive(event, window: window)
                if let direction = result.direction { self.action(direction) }
                return result.consumesEvent
            }
            return consumesEvent ? nil : event
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}

extension View {
    @MainActor
    func islandHorizontalSwipe(_ action: @escaping (IslandSwipeDirection) -> Void) -> some View {
        background(IslandSwipeSurface(action: action))
    }
}
