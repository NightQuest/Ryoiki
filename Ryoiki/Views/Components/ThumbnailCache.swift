import SwiftUI
import ImageIO

// A lightweight cross‑platform thumbnail cache for local image URLs.
// Uses CGImageSource thumbnail generation for speed and NSCache for reuse.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSURL, CGImage>()

    private init() {
        // Reasonable upper bound; adjust if your dataset is very large
        cache.countLimit = 600
        cache.totalCostLimit = 64 * 1024 * 1024 // ~64 MB of decoded thumbnails
    }

    func image(for url: URL, maxPixel: CGFloat) async -> Image? {
        let key = url as NSURL
        if let cg = cache.object(forKey: key) {
            return Image(decorative: cg, scale: 1, orientation: .up)
        }
        // Decode off-main, then cache on main
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: Int(max(1, maxPixel)),
                    kCGImageSourceCreateThumbnailWithTransform: true
                ]
                if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) {
                    let cg = thumb
                    DispatchQueue.main.async { [weak self] in
                        self?.cache.setObject(cg, forKey: key, cost: cg.bytesPerRow * cg.height)
                        continuation.resume(returning: Image(decorative: cg, scale: 1, orientation: .up))
                    }
                } else {
                    DispatchQueue.main.async {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}
