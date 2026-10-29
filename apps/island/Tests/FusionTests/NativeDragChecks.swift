@testable import IslandLegacyFixtures
import AppKit
@testable import NookSurface

@MainActor
private final class SyntheticDrag: NSObject, NSDraggingInfo {
    let draggingPasteboard = NSPasteboard.withUniqueName()
    let item: NSDraggingItem
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    nonisolated var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    init(url: URL) {
        item = NSDraggingItem(pasteboardWriter:url as NSURL)
        super.init()
        draggingPasteboard.writeObjects([url as NSURL])
        item.setDraggingFrame(NSRect(x:0,y:0,width:16,height:16),contents:NSImage(size:NSSize(width:16,height:16)))
    }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey:Any], using block: (NSDraggingItem,Int,UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop = ObjCBool(false); block(item,0,&stop)
    }
}
@MainActor
private final class SyntheticDestination: NookDragDestination {
    var entered = 0; var exited = 0; var dropped = 0
    func nookPanelAcceptsDrag(at point:NSPoint) -> Bool { true }
    func nookPanelDraggingEntered(_ payload:NookDropPayload) -> NSDragOperation { entered += 1; return .copy }
    func nookPanelDraggingExited() { exited += 1 }
    func nookPanelPerformDrop(_ payload:NookDropPayload) -> Bool { dropped += 1; return true }
}
@MainActor
func verifyNativeDragPreview() {
    let drag = SyntheticDrag(url:URL(fileURLWithPath:"/tmp/synthetic-portal-file.txt"))
    let destination = SyntheticDestination()
    let view = NookDragInterceptingView(frame:NSRect(x:0,y:0,width:376,height:200))
    view.dragDestination = destination
    XCTAssertTrue(drag.item.imageComponentsProvider != nil)
    XCTAssertEqual(view.draggingEntered(drag),.copy)
    XCTAssertNil(drag.item.imageComponentsProvider)
    XCTAssertEqual(destination.entered,1)
    XCTAssertEqual(view.draggingUpdated(drag),.copy)
    XCTAssertTrue(view.prepareForDragOperation(drag)); XCTAssertTrue(view.performDragOperation(drag))
    XCTAssertEqual(destination.dropped,1)
    view.draggingExited(drag); XCTAssertEqual(destination.exited,1)
    XCTAssertNil(view.hitTest(.zero))
    drag.draggingPasteboard.releaseGlobally()
}
