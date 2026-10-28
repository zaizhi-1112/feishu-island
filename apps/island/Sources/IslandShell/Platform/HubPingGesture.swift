import AppKit

/// One wheel presentation. Pointer positions stay in memory and use view coordinates.
@MainActor final class HubPingGesture: ObservableObject {
    enum Action: Equatable { case open(Int), cancel }

    let diameter: CGFloat
    var deadZone: CGFloat { diameter * 75 / 320 }
    @Published private(set) var selection: Int?
    @Published private(set) var shortcutHeld: Bool
    private(set) var finished = false
    private var origin: CGPoint
    private var moved = false
    private var leftCenter = false
    private var swipeArmed: Bool
    private var enteredWheel: Bool

    init(diameter: CGFloat = 400, origin: CGPoint = CGPoint(x: 200, y: 200), shortcutHeld: Bool = false) {
        self.diameter = diameter
        self.origin = origin
        self.shortcutHeld = shortcutHeld
        let radius = hypot(origin.x - diameter / 2, origin.y - diameter / 2)
        swipeArmed = radius < diameter * 75 / 320
        enteredWheel = radius <= diameter / 2
    }

    func pick(_ point: CGPoint, outside: Bool = false) -> Int? {
        HubPingGeometry.slice(dx: Double(point.x - diameter / 2), dy: Double(point.y - diameter / 2),
                              deadZone: Double(deadZone), outerLimit: outside ? .infinity : Double(diameter / 2))
    }

    func move(to point: CGPoint, mouseButtonDown: Bool = false) -> Action? {
        guard !finished, point.x.isFinite, point.y.isFinite else { return nil }
        // Mouse dragging keeps its existing release-to-select path. It must never
        // also launch through a swipe or through a shortcut release.
        if mouseButtonDown {
            reset(at: point)
            swipeArmed = false
            return nil
        }
        if hypot(point.x - origin.x, point.y - origin.y) >= 12 { moved = true }
        let radius = hypot(point.x - diameter / 2, point.y - diameter / 2)
        if radius <= diameter / 2 { enteredWheel = true }
        if radius < deadZone { swipeArmed = true }
        let direction = pick(point, outside: true)
        if direction != nil && moved { leftCenter = true }
        let highlighted = shortcutHeld ? direction : pick(point)
        if selection != highlighted { selection = highlighted }
        // A tapped shortcut leaves the wheel open. Crossing its rim deliberately
        // activates a direction; simply hovering over an entry only highlights it.
        if !shortcutHeld, swipeArmed, moved, radius >= diameter / 2 + 6, let direction {
            return finish(.open(direction))
        }
        return nil
    }

    func releaseShortcut(at point: CGPoint, mouseButtonDown: Bool = false) -> Action? {
        guard !finished, shortcutHeld, point.x.isFinite, point.y.isFinite else { return nil }
        _ = move(to: point, mouseButtonDown: mouseButtonDown)
        shortcutHeld = false
        guard !mouseButtonDown, moved, enteredWheel else { return nil }
        if let direction = pick(point, outside: true) { return finish(.open(direction)) }
        if leftCenter { return finish(.cancel) }
        return nil
    }

    func cancel() { finished = true; selection = nil; shortcutHeld = false }

    /// Unavailable entries or an OS open failure leave click selection usable.
    func reset(at point: CGPoint) {
        origin = point; moved = false; leftCenter = false; finished = false
        shortcutHeld = false; selection = nil
        let radius = hypot(point.x - diameter / 2, point.y - diameter / 2)
        swipeArmed = radius < deadZone
        enteredWheel = radius <= diameter / 2
    }

    private func finish(_ action: Action) -> Action { finished = true; return action }
}
