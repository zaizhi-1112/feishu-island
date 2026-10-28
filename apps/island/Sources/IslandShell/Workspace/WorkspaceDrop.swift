import NookApp
import SwiftUI
import UniformTypeIdentifiers

struct VirxactMark: Shape {
    static let svgPath = "M592.42 587.09C590.52 589.6 588.42 591.96 586.14 594.24C583.87 596.51 581.51 598.62 578.99 600.52C559.45 615.82 534.17 620.3 511.27 614C504.73 612.22 498.4 609.53 492.43 605.98C490.56 604.87 488.74 603.67 486.95 602.39C481.54 598.51 480.82 590.72 485.53 586.01L518.51 553.03C522.1 549.44 522.1 543.63 518.51 540.04L511.58 533.1L465.56 579.12L431.03 613.65L430.01 614.67L407.01 637.67C403.42 641.26 403.42 647.08 407.01 650.67L413.94 657.61L436.16 635.38C440.07 631.47 446.37 631.1 450.57 634.7C452.95 636.74 455.4 638.68 457.89 640.51C463.2 644.43 468.75 647.86 474.47 650.8C518.77 673.66 573.88 668.24 613.03 634.55C615.41 632.52 617.75 630.35 620 628.1C622.26 625.85 624.4 623.53 626.46 621.12C660.17 581.96 665.58 526.84 642.73 482.54L609.55 515.72C607.39 517.88 606.41 520.98 607.04 523.97C611.58 545.6 606.72 568.84 592.42 587.09Z M649.51 422.03L656.44 428.97C660.03 432.56 660.03 438.38 656.44 441.97L633.46 464.95L632.44 465.97L597.91 500.5L551.87 546.54L544.94 539.6C541.35 536.01 541.35 530.19 544.94 526.61L577.94 493.61C582.65 488.89 581.93 481.11 576.52 477.23C574.73 475.94 572.9 474.75 571.04 473.64C565.06 470.09 558.74 467.4 552.2 465.62C529.3 459.32 504.02 463.8 484.45 479.12C481.94 481.02 479.58 483.13 477.3 485.4C475.03 487.68 472.93 490.04 471.02 492.55C456.75 510.78 451.89 534.02 456.43 555.65C457.06 558.64 456.08 561.74 453.92 563.9L420.74 597.08C397.89 552.77 403.3 497.66 436.99 458.52C439.02 456.13 441.19 453.79 443.44 451.54C445.7 449.29 448.01 447.14 450.42 445.09C489.59 411.38 544.7 405.96 589 428.82C594.72 431.76 600.27 435.18 605.57 439.11C608.07 440.94 610.51 442.88 612.9 444.92C617.1 448.52 623.4 448.14 627.31 444.24Z"
    func path(in rect: CGRect) -> Path {
        // The official mark contains only absolute M/L/C/Z commands.
        let pattern = "[MLCZ]|[-+]?(?:[0-9]*\\.)?[0-9]+"
        let ns = Self.svgPath as NSString
        let tokens = (try! NSRegularExpression(pattern:pattern)).matches(in:Self.svgPath,range:NSRange(location:0,length:ns.length)).map{ns.substring(with:$0.range)}
        var i = 0, path = Path()
        func point() -> CGPoint { let p = CGPoint(x:Double(tokens[i])!,y:Double(tokens[i+1])!); i += 2; return p }
        while i < tokens.count {
            let command = tokens[i]; i += 1
            switch command {
            case "M": path.move(to:point())
            case "L": path.addLine(to:point())
            case "C": let a = point(), b = point(), c = point(); path.addCurve(to:c,control1:a,control2:b)
            case "Z": path.closeSubpath()
            default: break
            }
        }
        let scale = min(rect.width/254.82,rect.height/249.70)
        return path.applying(CGAffineTransform(translationX:-404.31,y:-414.96)).applying(CGAffineTransform(scaleX:scale,y:scale)).applying(CGAffineTransform(translationX:rect.midX-254.82*scale/2,y:rect.midY-249.70*scale/2))
    }
}
struct WorkspaceDropMark: View {
    @ObservedObject var store: WorkspaceStore
    @State private var target = false
    var body: some View {
        ZStack {
            VirxactMark().fill(.white).frame(width:20,height:20)
            if store.ingestActive {
                Circle().trim(from:0.08,to:0.82).stroke(.white,lineWidth:1.5)
                    .frame(width:26,height:26)
            }
        }.frame(width:30,height:26).contentShape(Rectangle())
            .scaleEffect(target ? 1.12 : 1)
            .onDrop(of:[UTType.fileURL.identifier,UTType.image.identifier,UTType.utf8PlainText.identifier,UTType.url.identifier],isTargeted:$target) { providers in WorkspaceDrop.accept(providers,store:store) }
            .help("拖入文件、文字或链接，先存为待办")
    }
}

@MainActor
enum WorkspaceDrop {
    static func acceptPayload(_ payload: NookDropPayload, store: WorkspaceStore) -> Bool {
        switch payload {
        case .files(let urls): return acceptFiles(urls,store:store)
        case .text(let text): return accept([NSItemProvider(object:text as NSString)],store:store)
        case .link(let url): return accept([NSItemProvider(object:url as NSURL)],store:store)
        }
    }

    static func acceptFiles(_ urls: [URL], store: WorkspaceStore) -> Bool {
        guard !urls.isEmpty, urls.count <= 20, urls.allSatisfy(\.isFileURL) else {
            store.error = "请选择1到20个本机材料文件。"; return false
        }
        return accept(urls.map { NSItemProvider(item:$0 as NSURL,typeIdentifier:UTType.fileURL.identifier) },store:store)
    }
    static func accept(_ providers: [NSItemProvider], store: WorkspaceStore) -> Bool {
        guard !providers.isEmpty, providers.count <= 20 else { store.error = "一次最多放入20份材料。"; return false }
        guard store.beginMaterialDrop() else { return false }
        Task {
            defer { store.endMaterialDrop() }
            do {
                var text: [String] = [], files: [URL] = [], inlineImages: [PendingWorkImage] = []
                for provider in providers {
                    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                        let data = try await load(provider,type:UTType.fileURL.identifier)
                        guard let url = URL(dataRepresentation:data,relativeTo:nil), url.isFileURL else { throw WorkError.message("文件地址无效。") }; files.append(url)
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                        let data = try await load(provider,type:UTType.image.identifier)
                        inlineImages.append(try PendingWorkImage.decode(data,name:"拖入图片"))
                    } else {
                        let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url.identifier : UTType.utf8PlainText.identifier
                        let data = try await load(provider,type:type)
                        guard let s = String(data:data,encoding:.utf8) else { throw WorkError.message("无法读取拖入的文字。") }; text.append(s)
                    }
                }
                // Parsing is off the UI thread; files are never uploaded or executed by dropping alone.
                let captured = text.joined(separator:"\n"), urls = files
                let material = try await Task.detached { () -> (String,[PendingWorkImage]) in
                    var pieces = captured.isEmpty ? [] : [captured], images: [PendingWorkImage] = []
                    for url in urls {
                        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        if WorkspaceStore.isImage(url) { images.append(try PendingWorkImage.read(url)) }
                        else { pieces.append("文件：\(url.lastPathComponent)\n" + (try WorkMaterial.read(url))) }
                    }
                    return (pieces.joined(separator:"\n\n"),images)
                }.value
                _ = try store.add(text:material.0,images:material.1+inlineImages)
            } catch { store.error = error.localizedDescription }
        }
        return true
    }
    private static func load(_ provider: NSItemProvider, type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { c in provider.loadDataRepresentation(forTypeIdentifier:type) { data,error in if let data, data.count <= 10_000_000 { c.resume(returning:data) } else { c.resume(throwing:error ?? WorkError.message("拖入内容过大或无法读取。")) } } }
    }
}
