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

    private func readArchiveMetrics(_ archive: ComicArchive, paths: [String], pageNumber: Int, metrics: inout ImageMetrics) {
        guard pageNumber > 0, pageNumber <= paths.count else { return }
        let path = paths[pageNumber - 1]
        var m = metrics
        if let data = archive.data(atEntryPath: path) {
            if m.size <= 0 { m.size = Int64(data.count) }
            if m.width <= 0 || m.height <= 0 {
                if let src = CGImageSourceCreateWithData(data as CFData, nil),
                   let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                    if m.width <= 0 { m.width = cg.width }
                    if m.height <= 0 { m.height = cg.height }
                }
            }
        }
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
