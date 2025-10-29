import SwiftUI
import ImageIO

actor ThumbnailInflightRegistry {
    private var inflight = Set<NSURL>()
    private var waiters: [NSURL: [CheckedContinuation<Image?, Never>]] = [:]

    func tryStart(_ key: NSURL) -> Bool {
        if inflight.contains(key) { return false }
        inflight.insert(key)
        waiters[key] = []
        return true
    }

    func addWaiter(_ continuation: CheckedContinuation<Image?, Never>, for key: NSURL) {
        waiters[key, default: []].append(continuation)
    }

    func finish(_ key: NSURL, with image: Image?) {
        let continuations = waiters[key] ?? []
        inflight.remove(key)
        waiters[key] = nil
        for c in continuations { c.resume(returning: image) }
    }
}

// A lightweight cross‑platform thumbnail cache for local image URLs.
// Uses CGImageSource thumbnail generation for speed and NSCache for reuse.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private static let inflightRegistry = ThumbnailInflightRegistry()

    private let cache = NSCache<NSURL, CGImage>()

    private init() {
        // Reasonable upper bound; adjust if your dataset is very large
        cache.countLimit = 600
        cache.totalCostLimit = 64 * 1024 * 1024 // ~64 MB of decoded thumbnails
    }

    func image(for url: URL, maxPixel: CGFloat) async -> Image? {
        // Only attempt to decode local files; avoids ImageIO warnings on unsupported URLs
        guard url.isFileURL, maxPixel > 0 else { return nil }

        let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        if resourceValues?.isRegularFile == false { return nil }
        if (resourceValues?.fileSize ?? 0) <= 0 { return nil }

        let key = url as NSURL
        if let cg = cache.object(forKey: key) {
            return Image(decorative: cg, scale: 1, orientation: .up)
        }

        let isLeader = await ThumbnailCache.inflightRegistry.tryStart(key)
        if !isLeader {
            return await withCheckedContinuation { continuation in
                Task { await ThumbnailCache.inflightRegistry.addWaiter(continuation, for: key) }
            }
        }

        let resultImage: Image? = await Task.detached(priority: .userInitiated) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(max(1, maxPixel)),
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
                return nil
            }
            DispatchQueue.main.async {
                self.cache.setObject(thumb, forKey: key, cost: thumb.bytesPerRow * thumb.height)
            }
            return Image(decorative: thumb, scale: 1, orientation: .up)
        }.value

        await ThumbnailCache.inflightRegistry.finish(key, with: resultImage)
        return resultImage
    }
}
