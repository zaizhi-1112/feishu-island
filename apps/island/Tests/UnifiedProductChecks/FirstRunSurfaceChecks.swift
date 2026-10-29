import AppKit
import NookApp
import NookSurface
import SwiftUI
@testable import IslandShell

@MainActor func runFirstRunSurfaceChecks(check: (Bool,String)->Void) async throws {
    let surface = Nook { Text("Synthetic guide gate") } compactLeading: { Text("A") } compactTrailing: { Text("B") }
    surface.presentationAllowed = { false }
    await surface.compact(on: NSScreen.main)
    await surface.expand(on: NSScreen.main)
    await surface.peek(on: NSScreen.main)
    check(surface.window == nil && surface.state == .hidden, "guide gate blocks boot, notification and peek before any window is created")
    guard let flag=CommandLine.arguments.firstIndex(of:"--render"),flag+1<CommandLine.arguments.count else{return}
    let output=URL(fileURLWithPath:CommandLine.arguments[flag+1]).appendingPathComponent("hub-content")
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    let fixtures: [(String,[String:Any])] = [
        ("我运营的达人",["items":[["name":"合成达人甲","contract":"全约","level":"S","platforms":[["name":"公众号","followers":183287],["name":"小红书","followers":396]],"tags":"人工智能"],["name":"合成达人乙","platforms":[["name":"微博","followers":42000]],"tags":"科技"]]]),
        ("社群分析与数据资料",["entries":[["name":"运营看板","href":"https://example.com/private","key":"internal","kind":"dashboard","ownerAvatar":"https://example.com/avatar"],["name":"社群资料","href":"https://example.com/doc","live":["editedAt":"2026-10-29"]]]]),
        ("项目进展",["rows":[["title":"很长的项目标题用于检查窄窗口换行与内容完整性","owner":"合成成员","current":4,"target":8,"description":"核对本周反馈，逐项确认结果。"]]])
    ]
    for width in [320.0,620.0] {
        for dark in [false,true] {
            let content=VStack(alignment:.leading,spacing:18) {
                ForEach(Array(fixtures.enumerated()),id:\.offset) { _, fixture in
                    VStack(alignment:.leading,spacing:12) {
                        Text(fixture.0).font(.system(size:17,weight:.semibold))
                        HubCardContent(card:.init(id:fixture.0,title:fixture.0,kind:"cards",text:"",sections:HubStructured.sections(fixture.1)))
                    }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(dark ? Color(white:0.14):.white,in:RoundedRectangle(cornerRadius:10))
                }
            }.padding(16).frame(width:width).foregroundStyle(dark ? Color.white:Color.black).background(dark ? Color(white:0.08):Color(white:0.95)).preferredColorScheme(dark ? .dark:.light)
            let view=NSHostingView(rootView:content)
            let size=view.fittingSize
            let window=NSWindow(contentRect:CGRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;window.contentView=view;view.layoutSubtreeIfNeeded()
            let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("cards-\(Int(width))-\(dark ? "dark":"light").png"))
            check(view.bounds.width == width && !window.isVisible,"structured hub cards render at \(width) without opening a window")
            window.close()
        }
    }
}
