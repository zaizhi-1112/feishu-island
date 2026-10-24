// SPDX-License-Identifier: Apache-2.0
import AppKit
import SwiftUI

/// A single trackpad gesture owns its axis and can navigate at most once.
struct NookModuleSwipeTracker {
    private enum Axis { case undecided, horizontal, vertical }
    private var axis = Axis.undecided
    private var x: CGFloat = 0
    private var y: CGFloat = 0
    private var switched = false
    private var tracking = false
    private(set) var consumesEvent = false

    mutating func reset() { self = Self() }

    mutating func update(dx: CGFloat, dy: CGFloat, phase: NSEvent.Phase,
                         momentum: NSEvent.Phase = [], precise: Bool = true,
                         inverted: Bool = true) -> Int? {
        consumesEvent = false
        guard precise else { return nil }
        if !momentum.isEmpty {
            consumesEvent = axis == .horizontal
            return nil
        }
        if phase.contains(.began) { reset(); tracking = true }
        guard tracking else { return nil }
        if phase.contains(.cancelled) { reset(); return nil }
        defer { if phase.contains(.ended) { tracking = false } }
        x += dx; y += abs(dy)
        if axis == .undecided, max(abs(x), y) >= 10 {
            if abs(x) > y * 1.6 { axis = .horizontal }
            else if y > abs(x) * 1.2 { axis = .vertical }
        }
        consumesEvent = axis == .horizontal
        guard axis == .horizontal, !switched, abs(x) >= 48 else { return nil }
        switched = true
        // Match physical finger direction even with natural scrolling disabled.
        let fingerX = inverted ? x : -x
        return fingerX < 0 ? 1 : -1
    }

    static func destination(modules: [String], activeID: String, step: Int) -> String? {
        guard abs(step) == 1, let index = modules.firstIndex(of: activeID),
              modules.indices.contains(index + step) else { return nil }
        return modules[index + step]
    }
}

/// Lives outside the module identity so replacing a page cannot reset the gesture
/// and let its remaining deltas or momentum advance a second page.
struct NookModuleSwipeRegion: NSViewRepresentable {
    var canNavigate: @MainActor () -> Bool
    var switchPage: @MainActor (Int) -> Void

    func makeNSView(context: Context) -> SwipeView { SwipeView() }
    func updateNSView(_ view: SwipeView, context: Context) {
        view.canNavigate = canNavigate
        view.switchPage = switchPage
    }
    static func dismantleNSView(_ view: SwipeView, coordinator: ()) { view.stop() }

    @MainActor
    final class SwipeView: NSView {
        var canNavigate: @MainActor () -> Bool = { false }
        var enabled: Bool { canNavigate() }
        var switchPage: (@MainActor (Int) -> Void)?
        private var monitor: Any?
        private var tracker = NookModuleSwipeTracker()
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self else { return false }
                    return self.handle(event) == nil
                }
                return consumed ? nil : event
            }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil; tracker.reset()
        }
        func handle(_ event: NSEvent) -> NSEvent? {
            guard enabled, !isHiddenOrHasHiddenAncestor, event.window === window,
                  bounds.contains(convert(event.locationInWindow, from: nil)) else {
                tracker.reset(); return event
            }
            let step = tracker.update(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY,
                                      phase: event.phase, momentum: event.momentumPhase,
                                      precise: event.hasPreciseScrollingDeltas,
                                      inverted: event.isDirectionInvertedFromDevice)
            if let step { switchPage?(step) }
            return tracker.consumesEvent ? nil : event
        }
    }
}
