import Foundation
import ZIPFoundation
import ImageIO
import SwiftUI

// MARK: - Archive+ImageLoading
/// Convenience image decoding and caching for ZIPFoundation's Archive.
extension Archive {
    /// Decodes and returns a SwiftUI Image for the given entry path, using an in-memory cache.
    /// - Parameters:
    ///   - entryPath: The path of the entry inside the archive.
    ///   - cacheKeyPrefix: An optional prefix for the cache key (e.g., the archive URL string).
    /// - Returns: A SwiftUI Image if decoding succeeds; otherwise, nil.
    func image(atEntryPath entryPath: String, cacheKeyPrefix: String? = nil) -> Image? {
        guard let entry = self.first(where: { $0.path == entryPath && $0.type == .file }) else {
            return nil
        }

        var entryData = Data()
        do {
            _ = try self.extract(entry) { data in
                entryData.append(data)
            }
        } catch {
            return nil
        }
        guard !entryData.isEmpty else { return nil }

        let cacheKey = (cacheKeyPrefix ?? "archive") + "::" + entryPath
        if let cached = ImageCache.shared.cgImage(forKey: cacheKey) {
            return Image(decorative: cached, scale: 1, orientation: .up)
        }

        if let src = CGImageSourceCreateWithData(entryData as CFData, nil),
           let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            let cost = cg.width * cg.height * 4
            ImageCache.shared.setCGImage(cg, forKey: cacheKey, cost: cost)
            return Image(decorative: cg, scale: 1, orientation: .up)
        }
        return nil
    }
}
