import Foundation
import ImageIO
import SwiftUI

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

    /// Returns a tuple of (width, height, size) for the given zero-based index, preferring metadata but falling back to source.
    func imageMetrics(atZeroBased index: Int) -> (width: Int, height: Int, size: Int64)? {
        guard totalPages() > 0 else { return nil }

        var width: Int = 0
        var height: Int = 0
        var size: Int64 = 0

        if let pgs = pages, !pgs.isEmpty, index < pgs.count {
            let p = pgs[index]
            width = p.ImageWidth
            height = p.ImageHeight
            size = p.ImageSize
        }

        if width > 0, height > 0, size > 0 {
            return (width, height, size)
        }

        // Fallback to reading from the archive
        let archive = ComicArchive(fileURL: fileURL)
        let paths = archive.imageEntryPaths()
        let clampedIndex = min(max(0, index), max(0, paths.count - 1))

        // Determine 1-based page number from metadata when possible
        var pageNumber = clampedIndex + 1
        if let pgs = pages, !pgs.isEmpty, clampedIndex < pgs.count {
            let p = pgs[clampedIndex]
            if let imgIdx = Int(p.Image) { pageNumber = imgIdx + 1 }
        }

        if pageNumber > 0, pageNumber <= paths.count {
            let path = paths[pageNumber - 1]
            if let data = archive.data(atEntryPath: path) {
                if size <= 0 { size = Int64(data.count) }
                if width <= 0 || height <= 0 {
                    if let src = CGImageSourceCreateWithData(data as CFData, nil),
                       let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                        if width <= 0 { width = cg.width }
                        if height <= 0 { height = cg.height }
                    }
                }
            }
        }

        if width > 0 || height > 0 || size > 0 {
            return (width, height, size)
        }
        return nil
    }
}
