import AppKit
@testable import IslandShell

@MainActor func checkHubPingGestures() {
    let center = CGPoint(x: 200, y: 200)
    func point(_ direction: Int, _ radius: CGFloat) -> CGPoint {
        let angle = CGFloat(direction * 45 - 90) * .pi / 180
        return CGPoint(x: 200 + cos(angle) * radius, y: 200 + sin(angle) * radius)
    }
    for direction in 0..<8 {
        let tapped = HubPingGesture(shortcutHeld: true)
        check(tapped.releaseShortcut(at: center) == nil && !tapped.finished, "tap leaves wheel open for click or swipe")
        check(tapped.move(to: point(direction, 145)) == nil && tapped.selection == direction, "hover highlights direction \(direction) without launching")
        check(tapped.move(to: point(direction, 215)) == .open(direction), "unpressed mouse swipes through direction \(direction)")
        check(tapped.move(to: point(direction, 230)) == nil, "swipe launches at most once")

        let held = HubPingGesture(shortcutHeld: true)
        check(held.move(to: point(direction, 145)) == nil && held.selection == direction, "held shortcut tracks direction \(direction)")
        check(held.releaseShortcut(at: point(direction, 145)) == .open(direction), "shortcut release opens direction \(direction)")
        check(held.releaseShortcut(at: point(direction, 145)) == nil, "duplicate release never opens twice")
    }
    let fast = HubPingGesture()
    check(fast.move(to: point(2, 260)) == .open(2), "fast outward swipe may skip intermediate pointer samples")
    let heldOutside = HubPingGesture(shortcutHeld: true)
    check(heldOutside.move(to: point(7, 270)) == nil && heldOutside.selection == 7, "holding shortcut keeps outside direction highlighted")
    check(heldOutside.releaseShortcut(at: point(7, 270)) == .open(7), "held shortcut supports flick beyond wheel")
    let returned = HubPingGesture(shortcutHeld: true)
    _ = returned.move(to: point(4, 145))
    check(returned.move(to: center) == nil && returned.selection == nil, "returning to center clears selection")
    check(returned.releaseShortcut(at: center) == .cancel, "return to center and release cancels")
    let jitter = HubPingGesture(shortcutHeld: true)
    _ = jitter.move(to: CGPoint(x: 202, y: 201))
    check(jitter.releaseShortcut(at: CGPoint(x: 203, y: 204)) == nil && !jitter.finished, "small pointer jitter is still a shortcut tap")
    let clamped = HubPingGesture(origin: point(2, 185), shortcutHeld: true)
    check(clamped.releaseShortcut(at: point(2, 185)) == nil, "screen-edge placement never activates at initial pointer")
    check(clamped.move(to: point(2, 230)) == nil, "screen-edge movement cannot accidentally count as an armed swipe")
    _ = clamped.move(to: center)
    check(clamped.move(to: point(6, 220)) == .open(6), "screen-edge wheel can arm after entering center")
    let outsideOrigin = HubPingGesture(origin: point(0, 300), shortcutHeld: true)
    _ = outsideOrigin.move(to: point(1, 300))
    check(outsideOrigin.releaseShortcut(at: point(1, 300)) == nil, "moving outside a clamped wheel does not select an unrelated entry")
    let mouseDrag = HubPingGesture(shortcutHeld: true)
    check(mouseDrag.move(to: point(0, 250), mouseButtonDown: true) == nil, "mouse drag cannot trigger swipe")
    check(mouseDrag.releaseShortcut(at: point(0, 250), mouseButtonDown: true) == nil, "mouse drag cannot also trigger shortcut release")
    check(mouseDrag.pick(point(0, 145)) == 0 && mouseDrag.pick(point(0, 250)) == nil, "mouse click and drag retain bounded wheel geometry")
    check(mouseDrag.move(to: point(0, 260)) == nil, "mouse release outside does not trigger a second swipe")
    let cancelled = HubPingGesture(shortcutHeld: true)
    _ = cancelled.move(to: point(3, 145))
    cancelled.cancel()
    check(cancelled.releaseShortcut(at: point(3, 145)) == nil && cancelled.move(to: point(3, 250)) == nil, "Escape or closed presentation rejects late events")
    let failedOpen = HubPingGesture()
    check(failedOpen.move(to: point(1, 215)) == .open(1), "attempted open has one action")
    failedOpen.reset(at: point(1, 215))
    check(failedOpen.move(to: point(1, 240)) == nil, "failed or unavailable entry does not keep retrying outside rim")
    _ = failedOpen.move(to: center)
    check(failedOpen.move(to: point(4, 215)) == .open(4), "another entry remains usable after unavailable destination")
    let invalid = HubPingGesture(shortcutHeld: true)
    check(invalid.move(to: CGPoint(x: CGFloat.nan, y: 0)) == nil && invalid.releaseShortcut(at: CGPoint(x: 0, y: CGFloat.infinity)) == nil, "invalid pointer coordinates never activate")
}
