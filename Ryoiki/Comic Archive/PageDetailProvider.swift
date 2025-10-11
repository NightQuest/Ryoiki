import Foundation
import ImageIO
import SwiftUI

struct ImageMetrics: Equatable {
    var width: Int
    var height: Int
    var size: Int64
}

/// Provides computed details about a page image, centralizing logic to read from ComicArchive and XML metadata.
struct PageDetailProvider {
    // Lightweight, process-wide cache for per-page metrics keyed by entry path.
    private struct MetricsCacheKey: Hashable {
        let archiveURL: String
        let entryPath: String
    }

    private static var metricsCache: [MetricsCacheKey: ImageMetrics] = [:]
    private static let metricsCacheLock = NSLock()

    private static func cachedMetrics(for url: URL, entryPath: String) -> ImageMetrics? {
        let key = MetricsCacheKey(archiveURL: url.absoluteString, entryPath: entryPath)
        metricsCacheLock.lock(); defer { metricsCacheLock.unlock() }
        return metricsCache[key]
    }

    private static func storeMetrics(_ metrics: ImageMetrics, for url: URL, entryPath: String) {
        let key = MetricsCacheKey(archiveURL: url.absoluteString, entryPath: entryPath)
        metricsCacheLock.lock(); defer { metricsCacheLock.unlock() }
        metricsCache[key] = metrics
    }

    let fileURL: URL
    let pages: [ComicPageInfo]?

    /// Returns the total page count, favoring explicit Pages metadata when available.
    func totalPages() -> Int {
        let archiveCount = ComicArchive(fileURL: fileURL).pageCount()
        let metadataCount = (pages?.count).map { $0 } ?? 0
        return max(archiveCount, metadataCount)
    }

    /// Returns whether the given zero-based index is the cover image.
    func isCover(atZeroBased index: Int) -> Bool {
        ComicArchive(fileURL: fileURL).isCoverImage(pageNumber: index + 1)
    }

    /// Returns the SwiftUI Image for the given zero-based index using metadata when available.
    func image(atZeroBased index: Int) -> Image? {
        let archive = ComicArchive(fileURL: fileURL)
        let pageCount = totalPages()
        let clampedIndex = min(max(0, index), max(0, pageCount - 1))

        if let p = pages, !p.isEmpty {
            let page = p[clampedIndex]
            if let imgIdx = Int(page.Image), let image = archive.getImage(pageNumber: imgIdx + 1) {
                return image
            } else if let image = archive.getImage(pageNumber: clampedIndex + 1) {
                return image
            } else {
                return nil
            }
        } else if let image = archive.getImage(pageNumber: clampedIndex + 1) {
            return image
        } else {
            return nil
        }
    }

    private func initialMetrics(from pages: [ComicPageInfo]?, at index: Int) -> ImageMetrics {
        var w = 0, h = 0
        var s: Int64 = 0
        if let pgs = pages, !pgs.isEmpty, index < pgs.count {
            let p = pgs[index]
            w = p.ImageWidth
            h = p.ImageHeight
            s = p.ImageSize
        }
        return ImageMetrics(width: w, height: h, size: s)
    }

    // Merge metrics B into A for any fields in A that are missing (<= 0)
    private func mergingFilledFields(base: ImageMetrics, fill: ImageMetrics) -> ImageMetrics {
        var result = base
        if result.size <= 0 { result.size = fill.size }
        if result.width <= 0 { result.width = fill.width }
        if result.height <= 0 { result.height = fill.height }
        return result
    }

    // Update cache with a merged view so that cached values only ever improve
    private func mergedCacheWrite(existing: ImageMetrics?, learned: ImageMetrics, url: URL, entryPath: String) {
        var merged = existing ?? ImageMetrics(width: 0, height: 0, size: 0)
        if learned.size > 0 { merged.size = max(merged.size, learned.size) }
        if learned.width > 0 { merged.width = max(merged.width, learned.width) }
        if learned.height > 0 { merged.height = max(merged.height, learned.height) }
        if merged.width > 0 || merged.height > 0 || merged.size > 0 {
            Self.storeMetrics(merged, for: url, entryPath: entryPath)
        }
    }

    // Extract pixel dimensions from image data without forcing a full decode when possible
    private func extractDimensions(from data: Data) -> (width: Int, height: Int)? {
        let options: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, options) as? [CFString: Any] {
            let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
            if w > 0 || h > 0 { return (w, h) }
        }
        if let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            return (cg.width, cg.height)
        }
        return nil
    }

    private func readArchiveMetrics(_ archive: ComicArchive, paths: [String], pageNumber: Int, metrics: inout ImageMetrics) {
        guard pageNumber > 0, pageNumber <= paths.count else { return }
        let path = paths[pageNumber - 1]

        // Cache fast path
        if let cached = Self.cachedMetrics(for: fileURL, entryPath: path) {
            let updated = mergingFilledFields(base: metrics, fill: cached)
            if updated.width > 0 || updated.height > 0 || updated.size > 0 {
                metrics = updated
                return
            }
        }

        guard let data = archive.data(atEntryPath: path) else { return }

        var m = metrics
        if m.size <= 0 { m.size = Int64(data.count) }

        if m.width <= 0 || m.height <= 0, let dims = extractDimensions(from: data) {
            if m.width <= 0 { m.width = dims.width }
            if m.height <= 0 { m.height = dims.height }
        }

        // Cache write-through
        let existing = Self.cachedMetrics(for: fileURL, entryPath: path)
        mergedCacheWrite(existing: existing, learned: m, url: fileURL, entryPath: path)
        metrics = m
    }

    /// Returns a tuple of (width, height, size) for the given zero-based index, preferring metadata but falling back to source.
    func imageMetrics(atZeroBased index: Int) -> ImageMetrics? {
        guard totalPages() > 0 else { return nil }

        let initial = initialMetrics(from: pages, at: index)
        var width = initial.width
        var height = initial.height
        var size = initial.size

        if width > 0, height > 0, size > 0 {
            return ImageMetrics(width: width, height: height, size: size)
        }

        let archive = ComicArchive(fileURL: fileURL)
        let paths = archive.imageEntryPaths()
        let clampedIndex = min(max(0, index), max(0, paths.count - 1))

        var pageNumber = clampedIndex + 1
        if let pgs = pages, !pgs.isEmpty, clampedIndex < pgs.count,
           let imgIdx = Int(pgs[clampedIndex].Image) {
            pageNumber = imgIdx + 1
        }

        var m = ImageMetrics(width: width, height: height, size: size)
        readArchiveMetrics(archive, paths: paths, pageNumber: pageNumber, metrics: &m)
        width = m.width; height = m.height; size = m.size

        if width > 0 || height > 0 || size > 0 {
            return ImageMetrics(width: width, height: height, size: size)
        }
        return nil
    }
}
