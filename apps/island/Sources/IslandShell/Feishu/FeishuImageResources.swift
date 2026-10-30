import AppKit
import CryptoKit
import ImageIO
import SwiftUI

func validFeishuImageKey(_ value: String) -> Bool {
    value.hasPrefix("img_") && (5...512).contains(value.count)
        && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
}

func accountMessageImageKeys(_ message: [String: Any]) -> [String] {
    guard ["image", "post", "interactive"].contains(message["msg_type"] as? String ?? ""),
          let raw = (message["body"] as? [String: Any])?["content"] as? String,
          let bytes = raw.data(using: .utf8), let content = try? JSONSerialization.jsonObject(with: bytes) else { return [] }
    var keys: [String] = [], seen = Set<String>()
    func visit(_ value: Any, depth: Int = 0) {
        guard depth < 16, keys.count < 64 else { return }
        if let array = value as? [Any] { for item in array { visit(item, depth: depth + 1) }; return }
        guard let object = value as? [String: Any] else { return }
        for field in ["image_key", "img_key"] {
            if let key = object[field] as? String, validFeishuImageKey(key), seen.insert(key).inserted { keys.append(key) }
        }
        if let localized = object["zh_cn"] ?? object["en_us"] { visit(localized, depth: depth + 1); return }
        for field in ["content", "elements", "body", "columns", "items", "rows", "img", "header"] {
            if let child = object[field] { visit(child, depth: depth + 1) }
        }
    }
    visit(content)
    return keys
}

enum FeishuImageResources {
    static let maximumBytes = 20_000_000
    // Serialize cache fills: island and danmu may request the same image together.
    // This queue is independent from the message receiver's polling slots.
    static let slots = DispatchSemaphore(value: 1)
    static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func scope(_ connection: FeishuConnection) -> String? {
        if let account = connection.localAccount { return digest(account.appID + ":" + account.openID) }
        guard connection.profile == CompanyConnection.profile,
              let user = UserDefaults.standard.string(forKey: "island.company.user"),
              let open = UserDefaults.standard.string(forKey: "island.company.receive.openID") else { return nil }
        return digest(user + ":" + open)
    }
    static func validMessageID(_ id: String) -> Bool {
        id.hasPrefix("om_") && id.count < 256 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
    static func thumbnail(_ data: Data, maxPixel: Int) throws -> NSImage {
        guard data.count <= maximumBytes, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0, width.doubleValue * height.doubleValue <= 64_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel] as CFDictionary) else {
            throw WorkError.message("图片格式暂不支持，或图片过大。请在飞书中查看。")
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
    static func credential(_ connection: FeishuConnection) throws -> CompanyConnection.Credential? {
        guard connection.valid else { throw WorkError.message("请先连接自己的飞书账号。") }
        if connection.profile == CompanyConnection.profile { return try CompanyConnection.shared.credential(.receive) }
        _ = try LocalCLIJob.verified(connection, purpose: .receive)
        return nil
    }
    static func resolve(_ message: FeishuMessage, connection: FeishuConnection) throws -> [String] {
        guard validMessageID(message.id) else { return message.imageKeys }
        if !message.imageKeys.isEmpty { return message.imageKeys }
        let credential = try credential(connection)
        let result = try LocalCLIJob.json(connection, ["api", "GET", "/open-apis/im/v1/messages/" + message.id, "--as", "user", "--format", "json"], companyCredential: credential)
        guard result["identity"] as? String == "user", let body = result["data"] as? [String: Any],
              let raw = (body["items"] as? [[String: Any]])?.first(where: { $0["message_id"] as? String == message.id }) else {
            throw WorkError.message("图片信息暂时无法读取，请重试。")
        }
        return accountMessageImageKeys(raw)
    }
    static func load(messageID: String, key: String, connection: FeishuConnection, accountScope: String) throws -> Data {
        guard validMessageID(messageID), validFeishuImageKey(key), scope(connection) == accountScope else {
            throw WorkError.message("图片与当前飞书账号不匹配。")
        }
        slots.wait(); defer { slots.signal() }
        let fm = FileManager.default
        let root = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FeishuIsland/MessageImages/" + accountScope, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let file = root.appendingPathComponent(digest(messageID + ":" + key) + ".img")
        if let attrs = try? fm.attributesOfItem(atPath: file.path), attrs[.type] as? FileAttributeType == .typeRegular,
           let size = attrs[.size] as? NSNumber, size.intValue > 0, size.intValue <= maximumBytes,
           let modified = attrs[.modificationDate] as? Date, Date().timeIntervalSince(modified) < 7 * 86400 {
            return try Data(contentsOf: file, options: .mappedIfSafe)
        }
        if fm.fileExists(atPath: file.path) { try fm.trashItem(at: file, resultingItemURL: nil) }
        let credential = try credential(connection)
        let result = try LocalCLIJob.json(connection, ["im", "+messages-resources-download", "--message-id", messageID,
            "--file-key", key, "--type", "image", "--output", file.path, "--as", "user", "--format", "json"], companyCredential: credential)
        guard result["identity"] as? String == "user", scope(connection) == accountScope,
              let attrs = try? fm.attributesOfItem(atPath: file.path), attrs[.type] as? FileAttributeType == .typeRegular,
              let size = attrs[.size] as? NSNumber, size.intValue > 0, size.intValue <= maximumBytes else {
            throw WorkError.message("图片暂时无法加载，请重试或在飞书中查看。")
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        // Cache eviction is reversible and only touches this app's hashed image files.
        let files = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])) ?? []
        var total = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        for candidate in files.sorted(by: { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }) where candidate != file && candidate.pathExtension == "img" {
            let values = try? candidate.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
            if values?.isRegularFile == true, total > 100_000_000 || (values?.contentModificationDate ?? .distantPast) < Date().addingTimeInterval(-7 * 86400) {
                if (try? fm.trashItem(at: candidate, resultingItemURL: nil)) != nil { total -= values?.fileSize ?? 0 }
            }
        }
        return try Data(contentsOf: file, options: .mappedIfSafe)
    }
}

@MainActor final class FeishuImageModel: ObservableObject {
    private final class Cached: NSObject {
        let image: NSImage, bytes: Data
        init(_ image: NSImage, _ bytes: Data) { self.image = image; self.bytes = bytes }
    }
    private static let cache: NSCache<NSString, Cached> = {
        let value = NSCache<NSString, Cached>(); value.totalCostLimit = 64_000_000; return value
    }()
    @Published var image: NSImage?
    @Published var error: String?
    private var bytes: Data?
    private var attempt = UUID()
    func load(messageID: String, key: String, connection: FeishuConnection) async {
        let attempt = UUID(); self.attempt = attempt; error = nil
        guard let scope = FeishuImageResources.scope(connection) else { error = "请先连接飞书"; return }
        let cacheKey = (scope + ":" + messageID + ":" + key) as NSString
        if let hit = Self.cache.object(forKey: cacheKey) { image = hit.image; bytes = hit.bytes; return }
        do {
            let bytes = try await Task.detached(priority: .utility) { try FeishuImageResources.load(messageID: messageID, key: key, connection: connection, accountScope: scope) }.value
            guard self.attempt == attempt, !Task.isCancelled, FeishuImageResources.scope(connection) == scope else { return }
            let image = try FeishuImageResources.thumbnail(bytes, maxPixel: 640)
            self.image = image; self.bytes = bytes
            Self.cache.setObject(Cached(image, bytes), forKey: cacheKey, cost: bytes.count + 640 * 640 * 4)
        } catch { guard self.attempt == attempt else { return }; self.error = "图片加载失败，点按重试" }
    }
    func expand() { if let bytes { FeishuImagePreview.shared.open(bytes) } }
}

struct FeishuImageGallery: View {
    let message: FeishuMessage
    let connection: FeishuConnection
    var compact = false
    @State private var resolved: [String] = []
    @State private var failed = false
    var body: some View {
        Group {
            if resolved.isEmpty {
                HStack { Image(systemName: "photo"); Text(failed ? "图片信息暂不可用" : "正在读取图片…") }.font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                if compact {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 8) {
                            ForEach(resolved, id: \.self) { key in FeishuImageTile(messageID: message.id, key: key, connection: connection, height: 90).frame(width: 132) }
                        }
                    }.frame(height: 104)
                } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 92 : 120))], spacing: 8) {
                    ForEach(resolved, id: \.self) { key in FeishuImageTile(messageID: message.id, key: key, connection: connection, height: compact ? 90 : 132) }
                }
                }
            }
        }
        .task(id: connection) {
            resolved = message.imageKeys
            if resolved.isEmpty {
                do { resolved = try await Task.detached(priority: .utility) { try FeishuImageResources.resolve(message, connection: connection) }.value; failed = resolved.isEmpty }
                catch { failed = true }
            }
        }
    }
}

private struct FeishuImageTile: View {
    let messageID: String, key: String
    let connection: FeishuConnection
    let height: CGFloat
    @StateObject private var model = FeishuImageModel()
    @State private var retry = 0
    var body: some View {
        Button {
            if model.image != nil { model.expand() } else { retry += 1 }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Color.secondary.opacity(0.1))
                if let image = model.image { Image(nsImage: image).resizable().scaledToFit().padding(3) }
                else if let error = model.error { VStack { Image(systemName: "arrow.clockwise"); Text(error).font(.system(size: 10)) }.padding(8) }
                else { ProgressView().controlSize(.small) }
            }.frame(height: height)
        }.buttonStyle(.plain).accessibilityLabel(model.image == nil ? "加载飞书图片" : "展开飞书图片")
            .accessibilityIdentifier("feishu.image.thumbnail")
            .task(id: retry) { await model.load(messageID: messageID, key: key, connection: connection) }
    }
}

@MainActor final class FeishuImagePreview {
    static let shared = FeishuImagePreview()
    private var window: NSWindow?
    func open(_ bytes: Data) {
        guard let image = try? FeishuImageResources.thumbnail(bytes, maxPixel: 4096) else { return }
        if window == nil {
            let next = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 620), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            next.title = "飞书图片"; next.isReleasedWhenClosed = false; next.minSize = NSSize(width: 360, height: 280)
            next.identifier = .init("feishu.image.preview"); next.level = .init(rawValue: NSWindow.Level.statusBar.rawValue + 10)
            next.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .canJoinAllApplications]
            next.hidesOnDeactivate = false; next.center(); window = next
        }
        window?.contentView = NSHostingView(rootView: FeishuImagePreviewContent(image: image))
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func close() { window?.close(); window?.contentView = nil }
}

private struct FeishuImagePreviewContent: View {
    let image: NSImage
    @State private var zoom: CGFloat = 1
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button { zoom = max(0.5, zoom / 1.4) } label: { Image(systemName: "minus.magnifyingglass") }.accessibilityLabel("缩小图片")
                Button { zoom = min(8, zoom * 1.4) } label: { Image(systemName: "plus.magnifyingglass") }.accessibilityLabel("放大图片")
                Button("适合窗口") { zoom = 1 }
                Spacer()
            }.buttonStyle(.bordered).padding(10)
            GeometryReader { geometry in
                let fit = min(max(1, geometry.size.width - 32) / image.size.width, max(1, geometry.size.height - 32) / image.size.height)
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image).resizable()
                        .frame(width: image.size.width * fit * zoom, height: image.size.height * fit * zoom)
                        .padding(16).frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                }
            }
        }.background(Color.black.opacity(0.92)).preferredColorScheme(.dark)
    }
}
