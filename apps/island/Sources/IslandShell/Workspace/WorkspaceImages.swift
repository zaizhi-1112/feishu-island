import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

struct WorkImage: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var width: Int
    var height: Int
    var filename: String { id.uuidString + ".png" }
}
struct PendingWorkImage: Identifiable {
    var image: WorkImage
    var data: Data
    var id: UUID { image.id }
    static func decode(_ data: Data, name: String) throws -> PendingWorkImage {
        guard data.count <= 10_000_000,
              let source = CGImageSourceCreateWithData(data as CFData,nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width)*Double(height) <= 32_000_000,
              let cg = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:2400,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else {
            throw WorkError.message("图片须小于10MB、3200万像素，支持PNG、JPEG、HEIC等系统图片格式。")
        }
        let png = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(png,UTType.png.identifier as CFString,1,nil) else { throw WorkError.message("图片转换失败。") }
        CGImageDestinationAddImage(dest,cg,nil)
        guard CGImageDestinationFinalize(dest), png.length <= 10_000_000 else { throw WorkError.message("图片转换后过大。") }
        return PendingWorkImage(image:WorkImage(id:UUID(),name:String(name.prefix(100)),width:cg.width,height:cg.height),data:png as Data)
    }
    static func read(_ url: URL) throws -> PendingWorkImage {
        let v = try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard url.isFileURL, v.isRegularFile == true, v.isSymbolicLink != true, (v.fileSize ?? 0)<=10_000_000 else { throw WorkError.message("请选择10MB以内的普通图片文件。") }
        return try decode(Data(contentsOf:url),name:url.lastPathComponent)
    }
}

/// Cmd-V reads the clipboard only on an explicit paste action. Ordinary text keeps native editing.
struct WorkInputEditor: NSViewRepresentable {
    @Binding var text: String
    var pasteImage: (Data) -> Void
    final class Editor: NSTextView {
        var receiveImage: ((Data)->Void)?
        var clipboardImage: () -> Data? = { NSPasteboard.general.data(forType:.png) ?? NSPasteboard.general.data(forType:.tiff) }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.modifierFlags.intersection([.command,.control,.option]) == .command, event.charactersIgnoringModifiers?.lowercased() == "v" { paste(nil); return true }
            return super.performKeyEquivalent(with:event)
        }
        override func paste(_ sender: Any?) {
            if let data = clipboardImage() { receiveImage?(data); return }
            super.paste(sender)
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var owner: WorkInputEditor
        init(_ owner: WorkInputEditor) { self.owner = owner }
        func textDidChange(_ notification: Notification) { if let text = notification.object as? NSTextView { owner.text = text.string } }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let editor = Editor(frame:NSRect(x:0,y:0,width:350,height:72)); editor.isRichText = false; editor.drawsBackground = false
        editor.minSize = NSSize(width:0,height:72); editor.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.containerSize = NSSize(width:350,height:CGFloat.greatestFiniteMagnitude)
        editor.textColor = .white; editor.insertionPointColor = .white; editor.font = .systemFont(ofSize:13)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.textContainer?.widthTracksTextView = true; editor.autoresizingMask = [.width]
        editor.delegate = context.coordinator; editor.receiveImage = pasteImage; editor.setAccessibilityLabel("材料文字或链接，可粘贴截图")
        scroll.documentView = editor; return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.owner = self
        guard let editor = scroll.documentView as? Editor else { return }
        if editor.string != text { editor.string = text }
        editor.receiveImage = pasteImage
    }
}
