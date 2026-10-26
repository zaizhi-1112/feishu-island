import AppKit
import Combine
import SwiftUI
@testable import NookSurface

/// Exercises the real queued transition before any window is created. All changes
/// before each await share the main actor, so the exit/cancel deterministically wins
/// the race against the queued peek body. No account, product store or visible UI.
@MainActor
func runPeekTransitionChecks(check: (Bool, String) -> Void) async {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else {
        check(false, "peek transition fixture requires a display")
        return
    }
    func fixture() -> Nook<EmptyView, EmptyView, EmptyView> {
        let nook = Nook(expanded: { EmptyView() },
                        compactLeading: { EmptyView() },
                        compactTrailing: { EmptyView() })
        nook.peekContent = AnyView(Text("Synthetic peek"))
        nook.edgeDocked = true
        // _compact creates its panel with orderFront:false, publishes state, then
        // shows it. Fail at publication even if this regression returns, so the
        // fixture can never put a synthetic island on the user's desktop.
        nook.$state.dropFirst().sink { _ in
            preconditionFailure("Cancelled peek attempted a visible lifecycle transition")
        }.store(in: &nook.cancellables)
        return nook
    }
    func verifyUntouched(_ nook: Nook<EmptyView, EmptyView, EmptyView>, _ label: String) {
        check(!nook.isPeeking && !nook.peekStartedByHover, label + " cannot revive peek")
        check(nook.state == .hidden, label + " preserves lifecycle")
        check(!nook.hasLiveWindow, label + " never creates a window")
    }

    let exited = fixture()
    exited.setHoveringWithoutTransition(true)
    let pendingExit = exited.runPeek(on: screen, byHover: true)
    check(pendingExit != nil, "rapid exit queues an actual peek transition")
    // Mirrors the pointer flag written by updateHoverState(false), before the
    // queued task has established peekStartedByHover for runEndPeek to consume.
    exited.setHoveringWithoutTransition(false)
    await pendingExit?.value
    verifyUntouched(exited, "rapid pointer exit")

    let cancelled = fixture()
    // A host's peek ignores pointer position, but still obeys task cancellation.
    let pendingCancel = cancelled.runPeek(on: screen, byHover: false)
    check(pendingCancel != nil, "cancellation queues an actual host peek transition")
    pendingCancel?.cancel()
    await pendingCancel?.value
    verifyUntouched(cancelled, "cancelled host task")

    let superseded = fixture()
    superseded.setHoveringWithoutTransition(true)
    let pendingOld = superseded.runPeek(on: screen, byHover: true)
    check(pendingOld != nil, "supersession queues an actual peek transition")
    let replacement = superseded.runTransition(toward: .hidden) { _ in }
    await pendingOld?.value
    await replacement.value
    verifyUntouched(superseded, "newer transition")
    superseded.setHoveringWithoutTransition(false)
}
