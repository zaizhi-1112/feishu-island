import AppKit
import SwiftUI
import Combine
@testable import NookSurface

/// Replays cursor positions observed on the built-in display. Testing only a
/// point below the camera misses an actual upward move through the notch.
@MainActor @discardableResult func runHoverContinuityChecks() async -> Int {
    var count = 0
    func check(_ value: Bool, _ label: String) {
        guard value else { fputs("FAIL: \(label)\n", stderr); exit(1) }
        count += 1
    }
    let screen = NSScreen.main!
    let nook = Nook {
        Text("合成悬停检查").frame(width: 400, height: 300)
    } compactLeading: { Text("W") } compactTrailing: { Text("WorkBuddy") }
    nook.edgeDocked = true
    nook.presentation = .floating
    nook.hoverIntent = .init(action: .expand, delay: .zero)
    var cursor = NSPoint.zero
    nook.pointerLocation = { cursor }
    var states: [NookState] = []
    let observer = nook.$state.sink { states.append($0) }
    defer { observer.cancel() }
    for physical in [CGFloat(0), CGFloat(32)] {
        nook.setHoveringWithoutTransition(false)
        await nook.compact(on: screen)
        nook.configureWindow { $0.orderOut(nil) }
        nook.updateScreenGeometry(notch: CGSize(width: 180, height: 32), physicalHeight: physical, menuHeight: 32)
        try? await Task.sleep(for: .milliseconds(500))
        let window = nook.window!
        cursor = NSPoint(x: window.frame.midX, y: window.frame.maxY - physical - 2)
        states.removeAll()
        nook.updateChromeHoverState(true)
        try? await Task.sleep(for: .milliseconds(30))
        check(nook.state == .expanded, "full hover starts immediately on display \(physical)")
        // Enter below the lip, then move up over the camera or to the screen edge.
        // SwiftUI reports false as its animated visible shape moves away.
        let depths: [CGFloat] = physical > 0 ? [34, 30, 19, 1, 0] : [2, 0.5]
        for depth in depths {
            for offset: CGFloat in [-55, 0, 55] {
                cursor = NSPoint(x: window.frame.midX + offset, y: window.frame.maxY - depth)
                nook.updateChromeHoverState(false)
                try? await Task.sleep(for: .milliseconds(80))
                check(nook.state == .expanded && nook.isHovering,
                      "upward cursor remains expanded at depth \(depth), offset \(offset), notch \(physical)")
                nook.updateChromeHoverState(true)
            }
        }
        check(states.allSatisfy { $0 == .expanded }, "upward hover never inserts a collapse or hide on display \(physical)")
        check(!window.isKeyWindow && !window.isVisible, "hover-only regression does not activate or display a window")
        cursor = NSPoint(x: window.frame.midX + 300, y: window.frame.maxY - max(physical / 2, 1))
        let began = Date()
        while nook.state != .compact && Date().timeIntervalSince(began) < 0.3 {
            try? await Task.sleep(for: .milliseconds(5))
        }
        check(nook.state == .compact, "moving sideways into the menu bar still retracts on display \(physical)")
        for attempt in 0..<3 {
            cursor = NSPoint(x: window.frame.midX, y: window.frame.maxY - physical - 2)
            nook.updateChromeHoverState(true)
            try? await Task.sleep(for: .milliseconds(10))
            cursor.x += 400
            nook.updateChromeHoverState(false)
            try? await Task.sleep(for: .milliseconds(10))
            cursor = NSPoint(x: window.frame.midX, y: window.frame.maxY - max(1, physical / 2))
            nook.updateChromeHoverState(true)
            try? await Task.sleep(for: .milliseconds(100))
            check(nook.state == .expanded && nook.isHovering, "rapid re-entry cancels the older exit \(attempt) on display \(physical)")
        }

    }
    cursor = NSPoint(x: screen.frame.maxX + 100, y: screen.frame.minY - 100)
    nook.updateChromeHoverState(false)
    await nook.hide()
    print("PASS: \(count) upward-hover continuity checks; synthetic cursor, hidden native window")
    return count
}
