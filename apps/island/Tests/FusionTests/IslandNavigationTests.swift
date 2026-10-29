@testable import IslandLegacyFixtures
import AppKit
@testable import IslandShell

extension FusionTests {
    func testIslandHorizontalSwipeIntentAndLifetime() {
        var swipe=IslandSwipeAccumulator()
        // Small movement is not a navigation command; a deliberate horizontal swipe is.
        XCTAssertFalse(swipe.receive(dx:-6,dy:1,phase:.began,timestamp:1).consumesEvent)
        XCTAssertNil(swipe.receive(dx:-10,dy:1,phase:.changed,timestamp:2).direction)
        XCTAssertEqual(swipe.receive(dx:-18,dy:1,phase:.changed,timestamp:3).direction,.next)
        // The same event and the remainder of the gesture cannot advance a replacement view.
        XCTAssertNil(swipe.receive(dx:-18,dy:1,phase:.changed,timestamp:3).direction)
        XCTAssertNil(swipe.receive(dx:-80,dy:0,phase:.changed,timestamp:4).direction)
        XCTAssertTrue(swipe.receive(dx:0,dy:0,phase:.ended,timestamp:5).consumesEvent)
        XCTAssertFalse(swipe.receive(dx:-80,dy:0,phase:[],momentum:.changed,timestamp:6).consumesEvent)
        XCTAssertEqual(swipe.receive(dx:40,dy:0,phase:.began,timestamp:7).direction,.previous)
        _=swipe.receive(dx:0,dy:0,phase:.cancelled,timestamp:8)
        // Vertical scrolling locks its axis and is never stolen by later horizontal drift.
        XCTAssertFalse(swipe.receive(dx:1,dy:18,phase:.began,timestamp:9).consumesEvent)
        XCTAssertFalse(swipe.receive(dx:90,dy:0,phase:.changed,timestamp:10).consumesEvent)
        _=swipe.receive(dx:0,dy:0,phase:.ended,timestamp:11)
        // Wheel-only scrolling and a gesture which started outside the island remain native.
        XCTAssertFalse(swipe.receive(dx:100,dy:0,phase:.began,precise:false,timestamp:12).consumesEvent)
        XCTAssertFalse(swipe.receive(dx:100,dy:0,phase:.changed,timestamp:13).consumesEvent)
        XCTAssertFalse(swipe.receive(dx:100,dy:0,phase:[],timestamp:14).consumesEvent)
        // A diagonal movement must establish horizontal dominance before navigation.
        XCTAssertFalse(swipe.receive(dx:20,dy:18,phase:.began,timestamp:15).consumesEvent)
        XCTAssertFalse(swipe.receive(dx:15,dy:10,phase:.changed,timestamp:16).consumesEvent)
        XCTAssertEqual(swipe.receive(dx:30,dy:0,phase:.changed,timestamp:17).direction,.previous)
        _=swipe.receive(dx:0,dy:0,phase:.ended,timestamp:18)
        XCTAssertFalse(swipe.receive(dx:.nan,dy:0,phase:.began,timestamp:19).consumesEvent)
    }
}
