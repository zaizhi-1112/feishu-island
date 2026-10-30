import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Persist a small, metadata-free PNG with the entry, never a reference to the original file.
enum HubShortcutIcon {
    static let inputLimit = 10 * 1024 * 1024
    static let outputLimit = 2 * 1024 * 1024
    private static let cache = NSCache<NSData, NSImage>()

    static func normalize(_ data: Data) throws -> Data {
        guard data.count <= inputLimit,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16000, height <= 16000,
              Double(width) * Double(height) <= 32_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            throw WorkError.message("请选择不超过 10 MB、3200 万像素的图片。")
        }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil) else {
            throw WorkError.message("图片无法转换，请换一张图片。")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), result.length <= outputLimit else {
            throw WorkError.message("图片无法保存，请换一张图片。")
        }
        return result as Data
    }

    static func valid(_ data: Data) -> Bool {
        guard data.count <= outputLimit, let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return false }
        return w > 0 && h > 0 && w <= 256 && h <= 256
    }

    static func image(_ data: Data?) -> NSImage? {
        guard let data else { return nil }
        let key = data as NSData
        if let image = cache.object(forKey: key) { return image }
        guard valid(data), let image = NSImage(data: data) else { return nil }
        cache.countLimit = 24
        cache.setObject(image, forKey: key)
        return image
    }

    static func read(_ url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let properties = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard url.isFileURL, properties.isRegularFile == true, let size = properties.fileSize, size <= inputLimit else {
            throw WorkError.message("请选择不超过 10 MB 的图片文件。")
        }
        return try normalize(Data(contentsOf: url, options: .mappedIfSafe))
    }
}
