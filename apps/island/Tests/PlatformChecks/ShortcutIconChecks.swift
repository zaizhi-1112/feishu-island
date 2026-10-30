import AppKit
@testable import IslandShell

@MainActor func checkShortcutIcons() -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 400, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for x in 0..<800 { for y in 0..<400 { bitmap.setColor(x < 400 ? NSColor(deviceRed: 0, green: 0.4, blue: 1, alpha: 1) : NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0), atX: x, y: y) } }
    let source = bitmap.representation(using: .png, properties: [:])!
    let icon = try! HubShortcutIcon.normalize(source)
    let result = NSBitmapImageRep(data: icon)!
    check(result.pixelsWide == 256 && result.pixelsHigh == 128, "icon scales preserving aspect ratio")
    check(result.colorAt(x: 220, y: 60)!.alphaComponent == 0, "transparent pixels retained")
    check((try? HubShortcutIcon.normalize(Data("not an image".utf8))) == nil, "invalid image rejected")
    check((try? HubShortcutIcon.normalize(Data(count: HubShortcutIcon.inputLimit + 1))) == nil, "oversized input rejected")
    check(!HubShortcutIcon.valid(source), "unnormalized large icon rejected at persistence boundary")
    let old = Data(#"{"source":"custom","cardID":"","title":"旧入口","address":"https://example.com"}"#.utf8)
    check((try! JSONDecoder().decode(HubPingShortcut.self, from: old)).iconPNG == nil, "old preferences migrate without resetting")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("shortcut-icons-" + UUID().uuidString)
    let store = UnifiedPlatformStore(root: root)
    check(store.setSlot(0, .init(iconPNG: icon)), "default destination accepts custom image")
    check(store.swapSlots(0, 1), "image entry swapped")
    let restored = UnifiedPlatformStore(root: root)
    check(restored.preferences.slots[1].iconPNG == icon, "image follows automatic entry after swap and restart")
    check(restored.destinations(cards: [], selectedIDs: [])[1].iconPNG == icon, "wheel receives saved image")
    check(!store.setSlot(0, .init(iconPNG: Data([1,2,3]))), "corrupt image cannot overwrite slot")
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.setData(source, forType: .png)
    check((try? ShortcutImageDropView.read(pasteboard).get()) == icon, "clipboard image normalized")
    let file = root.appendingPathComponent("original.png")
    try! source.write(to: file)
    pasteboard.clearContents(); pasteboard.writeObjects([file as NSURL])
    check((try? ShortcutImageDropView.read(pasteboard).get()) == icon, "Finder copied or dragged file normalized")
    check(try! Data(contentsOf: file) == source, "original image unchanged")
    pasteboard.clearContents(); pasteboard.setString("https://example.com/image.png", forType: .string)
    check((try? ShortcutImageDropView.read(pasteboard).get()) == nil, "text paste never fetches remote content")
    pasteboard.releaseGlobally()
    return icon
}
