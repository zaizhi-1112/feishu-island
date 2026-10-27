#!/usr/bin/env swift
import AppKit

// Native vector artwork: no fonts, external images, or generated-image services.
// Usage: swift scripts/generate-app-icon.swift [project-root]
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func gradient(_ colors: [NSColor]) -> NSGradient { NSGradient(colors: colors)! }
func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawIcon() {
    // A soft continuous-corner tile, sized to sit alongside macOS app icons.
    let tile = NSBezierPath()
    tile.move(to: NSPoint(x: 512, y: 928))
    tile.curve(to: NSPoint(x: 928, y: 512), controlPoint1: NSPoint(x: 876, y: 928), controlPoint2: NSPoint(x: 928, y: 876))
    tile.curve(to: NSPoint(x: 512, y: 96), controlPoint1: NSPoint(x: 928, y: 148), controlPoint2: NSPoint(x: 876, y: 96))
    tile.curve(to: NSPoint(x: 96, y: 512), controlPoint1: NSPoint(x: 148, y: 96), controlPoint2: NSPoint(x: 96, y: 148))
    tile.curve(to: NSPoint(x: 512, y: 928), controlPoint1: NSPoint(x: 96, y: 876), controlPoint2: NSPoint(x: 148, y: 928))
    tile.close()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0.12, 0.16, 0.23, 0.19)
    shadow.shadowBlurRadius = 23
    shadow.shadowOffset = NSSize(width: 0, height: -13)
    shadow.set()
    color(0.9, 0.91, 0.93).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    gradient([color(0.84, 0.87, 0.90), color(0.96, 0.97, 0.98), .white]).draw(in: tile, angle: 85)
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    gradient([color(1, 1, 1, 0.80), color(1, 1, 1, 0)]).draw(fromCenter: NSPoint(x: 320, y: 795), radius: 0, toCenter: NSPoint(x: 320, y: 795), radius: 670, options: [])
    NSGraphicsContext.restoreGraphicsState()
    color(1, 1, 1, 0.8).setStroke()
    tile.lineWidth = 3
    tile.stroke()

    let island = rounded(NSRect(x: 204, y: 384, width: 616, height: 256), 128)
    NSGraphicsContext.saveGraphicsState()
    let lift = NSShadow()
    lift.shadowColor = color(0.13, 0.19, 0.25, 0.22)
    lift.shadowBlurRadius = 21
    lift.shadowOffset = NSSize(width: 0, height: -17)
    lift.set()
    color(0.02, 0.025, 0.035).setFill()
    island.fill()
    NSGraphicsContext.restoreGraphicsState()
    gradient([color(0.015, 0.019, 0.028), color(0.07, 0.08, 0.10)]).draw(in: island, angle: 90)
    color(0.18, 0.20, 0.23).setStroke()
    island.lineWidth = 2
    island.stroke()

    NSGraphicsContext.saveGraphicsState()
    island.addClip()
    gradient([color(0.12, 0.60, 0.72, 0.21), color(0.1, 0.4, 0.6, 0)]).draw(fromCenter: NSPoint(x: 445, y: 483), radius: 0, toCenter: NSPoint(x: 445, y: 483), radius: 195, options: [])
    // A single continuous wave carries the sense of motion at small sizes.
    let wave = NSBezierPath()
    wave.move(to: NSPoint(x: 268, y: 494))
    wave.curve(to: NSPoint(x: 431, y: 527), controlPoint1: NSPoint(x: 329, y: 445), controlPoint2: NSPoint(x: 367, y: 573))
    wave.curve(to: NSPoint(x: 625, y: 531), controlPoint1: NSPoint(x: 507, y: 473), controlPoint2: NSPoint(x: 547, y: 485))
    wave.curve(to: NSPoint(x: 434, y: 496), controlPoint1: NSPoint(x: 559, y: 447), controlPoint2: NSPoint(x: 497, y: 449))
    wave.curve(to: NSPoint(x: 268, y: 494), controlPoint1: NSPoint(x: 362, y: 553), controlPoint2: NSPoint(x: 329, y: 431))
    wave.close()
    gradient([color(0.25, 0.45, 0.96), color(0.23, 0.85, 0.96), color(0.56, 0.96, 0.83)]).draw(in: wave, angle: 0)
    let dot = NSBezierPath(ovalIn: NSRect(x: 705, y: 484, width: 56, height: 56))
    let glow = NSShadow()
    glow.shadowColor = color(0.38, 0.96, 0.79, 0.30)
    glow.shadowBlurRadius = 19
    glow.shadowOffset = .zero
    glow.set()
    gradient([color(0.28, 0.76, 0.66), color(0.68, 1, 0.85)]).draw(in: dot, angle: 90)
    NSGraphicsContext.restoreGraphicsState()
}

func png(size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawIcon()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try png(size: points * scale).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
try png(size: 1024).write(to: resources.appendingPathComponent("AppIcon.png"))
let tool = Process()
tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
tool.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try tool.run()
tool.waitUntilExit()
guard tool.terminationStatus == 0 else { exit(tool.terminationStatus) }
print("Created Resources/AppIcon.icns and PNG artwork.")
