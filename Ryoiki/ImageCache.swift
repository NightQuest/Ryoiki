import Foundation
import CoreGraphics

final class ImageCache {
    static let shared = ImageCache()

    private let cgImageCache = NSCache<NSString, CGImage>()

    private init() {
        cgImageCache.countLimit = 100
        cgImageCache.totalCostLimit = 64 * 1024 * 1024 // ~64 MB
    }

    func cgImage(forKey key: String) -> CGImage? {
        cgImageCache.object(forKey: key as NSString)
    }

    func setCGImage(_ image: CGImage, forKey key: String, cost: Int = 0) {
        if cost > 0 {
            cgImageCache.setObject(image, forKey: key as NSString, cost: cost)
        } else {
            cgImageCache.setObject(image, forKey: key as NSString)
        }
    }
}
