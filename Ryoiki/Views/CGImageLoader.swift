import SwiftUI
import ImageIO

/// A lightweight downsampling image loader with a shared decoded-image cache.
/// - Decodes using ImageIO thumbnails to a caller-provided max pixel size.
/// - Caches decoded CGImages in-memory via NSCache.
/// - Provides a `warm(url:maxPixel:)` API for pre-decoding images off the main thread.
struct CGImageLoader: View {
    let url: URL
    let maxPixelProvider: () -> CGFloat
    let content: (CGImage?) -> AnyView

    @State private var cgImage: CGImage?
    @State private var hasAttempted = false

    // Shared cache
    private static var cache = NSCache<NSURL, CGImage>()

    init(url: URL, maxPixelProvider: @escaping () -> CGFloat, @ViewBuilder content: @escaping (CGImage?) -> some View) {
        self.url = url
        self.maxPixelProvider = maxPixelProvider
        self.content = { AnyView(content($0)) }
    }

    var body: some View {
        content(cgImage)
            .task(id: url, loadIfNeeded)
    }

    @Sendable
    private func loadIfNeeded() async {
        let key = url as NSURL
        if let cached = Self.cache.object(forKey: key) {
            cgImage = cached
            return
        }
        guard !hasAttempted else { return }
        hasAttempted = true

        let requestedMax = Int(max(1, maxPixelProvider()))
        let decoded: CGImage? = await Task.detached(priority: .userInitiated) {
            await CGImageLoader.decodeThumbnail(from: url, maxPixel: requestedMax)
        }.value

        if let decoded {
            Self.cache.setObject(decoded, forKey: key, cost: decoded.bytesPerRow * decoded.height)
        }
        await MainActor.run { cgImage = decoded }
    }

    /// Warm the shared cache by decoding the image to the provided max pixel size.
    static func warm(url: URL, maxPixel: Int) async {
        let key = url as NSURL
        if cache.object(forKey: key) != nil { return }
        _ = await Task.detached(priority: .utility) {
            if let cgImage = await decodeThumbnail(from: url, maxPixel: maxPixel) {
                await MainActor.run {
                    cache.setObject(cgImage, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
                }
            }
        }.value
    }

    /// Decode and downsample to a thumbnail with the given max pixel size.
    private static func decodeThumbnail(from url: URL, maxPixel: Int) -> CGImage? {
        guard url.isFileURL else { return nil }
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        if resourceValues?.isRegularFile == false { return nil }
        if (resourceValues?.fileSize ?? 0) <= 0 { return nil }

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) {
            return thumb
        }
        if let full = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            return full
        }
        return nil
    }
}
