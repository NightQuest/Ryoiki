import SwiftUI
import ImageIO

// A lightweight cross‑platform thumbnail cache for local image URLs.
// Uses CGImageSource thumbnail generation for speed and NSCache for reuse.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSURL, CGImage>()
    private var inflight: [NSURL: [CheckedContinuation<Image?, Never>]] = [:]

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

        // Coalesce concurrent requests for the same URL
        if inflight[key] != nil {
            return await withCheckedContinuation { continuation in
                inflight[key, default: []].append(continuation)
            }
        }

        return await withCheckedContinuation { leader in
            // Register leader; any subsequent callers will join above
            inflight[key] = []
            DispatchQueue.global(qos: .userInitiated).async {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: Int(max(1, maxPixel)),
                    kCGImageSourceCreateThumbnailWithTransform: true
                ]
                var resultImage: Image?
                if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) {
                    let cg = thumb
                    resultImage = Image(decorative: cg, scale: 1, orientation: .up)
                    DispatchQueue.main.async { [weak self] in
                        self?.cache.setObject(cg, forKey: key, cost: cg.bytesPerRow * cg.height)
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    // Resume leader
                    leader.resume(returning: resultImage)
                    // Fan out to any waiters
                    if let waiters = self?.inflight[key] {
                        waiters.forEach { $0.resume(returning: resultImage) }
                    }
                    // Clear inflight entry
                    self?.inflight[key] = nil
                }
            }
        }
    }
}
