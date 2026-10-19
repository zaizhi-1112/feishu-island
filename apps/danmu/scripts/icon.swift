import Cocoa
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories:true)
func draw(_ pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
    let ctx = NSGraphicsContext.current!.cgContext; ctx.scaleBy(x:CGFloat(pixels)/1024,y:CGFloat(pixels)/1024)
    let base = NSBezierPath(roundedRect:NSRect(x:52,y:52,width:920,height:920),xRadius:218,yRadius:218)
    NSGradient(colors:[NSColor(calibratedRed:0.12,green:0.23,blue:0.30,alpha:1), NSColor(calibratedRed:0.035,green:0.075,blue:0.12,alpha:1)])!.draw(in:base,angle:-65)
    NSColor(calibratedWhite:1,alpha:0.1).setStroke(); base.lineWidth=3; base.stroke()
    let bubble = NSBezierPath(roundedRect:NSRect(x:215,y:300,width:650,height:420),xRadius:126,yRadius:126)
    NSGradient(colors:[NSColor(calibratedRed:0.59,green:1,blue:0.83,alpha:1),NSColor(calibratedRed:0.15,green:0.75,blue:0.72,alpha:1)])!.draw(in:bubble,angle:-45)
    let tail = NSBezierPath(); tail.move(to:NSPoint(x:335,y:345));tail.line(to:NSPoint(x:310,y:215));tail.line(to:NSPoint(x:495,y:345));tail.close()
    NSColor(calibratedRed:0.30,green:0.84,blue:0.75,alpha:1).setFill();tail.fill()
    NSColor(calibratedRed:0.035,green:0.13,blue:0.18,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:333,y:533,width:390,height:47),xRadius:24,yRadius:24).fill()
    NSBezierPath(roundedRect:NSRect(x:333,y:433,width:267,height:47),xRadius:24,yRadius:24).fill()
    NSColor(calibratedRed:0.54,green:0.94,blue:0.85,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:105,y:558,width:73,height:30),xRadius:15,yRadius:15).fill()
    NSBezierPath(roundedRect:NSRect(x:80,y:467,width:98,height:30),xRadius:15,yRadius:15).fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using:.png,properties:[:])!
}
for size in [16,32,128,256,512] {
    try draw(size).write(to:folder.appendingPathComponent("icon_\(size)x\(size).png"))
    try draw(size*2).write(to:folder.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
