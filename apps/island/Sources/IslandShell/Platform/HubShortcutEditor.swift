import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor struct HubShortcutEditor: View {
    @ObservedObject var store: UnifiedPlatformStore
    let index: Int
    let destination: HubPingDestination
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HubPingShortcut
    @State private var custom: Bool
    @State private var error = ""
    init(store: UnifiedPlatformStore, index: Int, destination: HubPingDestination) {
        self.store = store; self.index = index; self.destination = destination
        let entry = store.preferences.slots[index]
        _draft = State(initialValue: entry)
        _custom = State(initialValue: entry.source == .custom)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("编辑入口 · " + HubShortcutSettings.directions[index]).font(.title2.bold())
            Toggle("使用自定义网址", isOn: $custom)
            if custom {
                TextField("入口名称", text: $draft.title)
                TextField("https://…", text: $draft.address)
            } else { Text(destination.title).font(.headline) }
            HStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(.primary.opacity(0.05))
                    if let image = HubShortcutIcon.image(draft.iconPNG) {
                        Image(nsImage: image).resizable().scaledToFit().padding(14)
                    } else {
                        Image(systemName: "photo.badge.plus").font(.system(size: 32)).foregroundStyle(.secondary)
                    }
                    ShortcutImageDropTarget { result in accept(result) }
                }.frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: 12) {
                    Text("拖入图片，或点击左侧后按 ⌘V").font(.callout)
                    HStack {
                        Button("导入图片…", action: choose)
                        Button("粘贴图片") { accept(ShortcutImageDropView.read(NSPasteboard.general)) }
                    }
                    Button("恢复默认图标") { draft.iconPNG = nil; error = "" }.disabled(draft.iconPNG == nil)
                }
            }
            if !error.isEmpty { Text(error).foregroundStyle(.orange).font(.callout) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    var value = draft
                    if custom {
                        value.source = .custom; value.cardID = ""
                        value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        value.address = value.address.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if value.source == .custom { value = .init(iconPNG: value.iconPNG) }
                    if store.setSlot(index, value) { dismiss() } else { error = store.error }
                }.keyboardShortcut(.defaultAction)
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 500)
    }
    private func accept(_ result: Result<Data, Error>) {
        switch result {
        case .success(let data): draft.iconPNG = data; error = ""
        case .failure(let failure): error = failure.localizedDescription
        }
    }
    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            accept(Result { try HubShortcutIcon.read(url) })
        }
    }
}

@MainActor private struct ShortcutImageDropTarget: NSViewRepresentable {
    let receive: (Result<Data, Error>) -> Void
    func makeNSView(context: Context) -> ShortcutImageDropView { ShortcutImageDropView(receive: receive) }
    func updateNSView(_ nsView: ShortcutImageDropView, context: Context) { nsView.receive = receive }
}

@MainActor final class ShortcutImageDropView: NSView {
    var receive: (Result<Data, Error>) -> Void
    init(receive: @escaping (Result<Data, Error>) -> Void) {
        self.receive = receive
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL, .png, .tiff])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("入口图标，拖入图片或点击后粘贴")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    @objc func paste(_ sender: Any?) { receive(Self.read(.general)) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "v" { paste(nil); return true }
        return super.performKeyEquivalent(with: event)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let result = Self.read(sender.draggingPasteboard)
        receive(result)
        if case .success = result { return true }; return false
    }
    static func read(_ pasteboard: NSPasteboard) -> Result<Data, Error> {
        Result {
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
                guard urls.count == 1 else { throw WorkError.message("请一次选择一张图片。") }
                return try HubShortcutIcon.read(urls[0])
            }
            for type in [NSPasteboard.PasteboardType.png, .tiff] {
                if let data = pasteboard.data(forType: type) { return try HubShortcutIcon.normalize(data) }
            }
            throw WorkError.message("没有找到图片。请先复制图片或图片文件。")
        }
    }
}
