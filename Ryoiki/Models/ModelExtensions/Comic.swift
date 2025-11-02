//
//  Comic.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-25.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers
import SwiftData

extension Comic {
    @MainActor
    func setCoverImage(from fileURL: URL, context: ModelContext, maxPixel: CGFloat = 512, compressionQuality: CGFloat = 0.8) {
        Task {
            let data: Data? = await Task.detached(priority: .userInitiated) { () -> Data? in
                // Create thumbnail via ImageIO
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel)
                ]
                if let src = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                   let cgThumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) {
                    let out = NSMutableData()
                    let jpegUTI = UTType.jpeg.identifier as CFString
                    if let dest = CGImageDestinationCreateWithData(out as CFMutableData, jpegUTI, 1, nil) {
                        let props: [CFString: Any] = [ kCGImageDestinationLossyCompressionQuality: min(max(compressionQuality, 0), 1) ]
                        CGImageDestinationAddImage(dest, cgThumb, props as CFDictionary)
                        if CGImageDestinationFinalize(dest) {
                            return out as Data
                        }
                    }
                }
                // Fallback to raw file data if thumbnail creation fails
                return try? Data(contentsOf: fileURL)
            }.value
            if let data {
                self.coverImage = data
                if self.coverFilePath.isEmpty {
                    self.coverFilePath = fileURL.path
                }
                try? context.save()
            }
        }
    }

    var computedDedupedPageCount: Int {
        let uniqueByURL = Set(self.pages.map { $0.pageURL })
        return uniqueByURL.count
    }

    var computedImageCount: Int {
        pages.reduce(0) { $0 + $1.images.count }
    }

    var lastDateFetched: Date? {
        self.pages.compactMap { $0.dateFetched }.max()
    }

    var lastDateDownloaded: Date? {
        self.pages.compactMap { $0.images.compactMap { $0.dateDownloaded }.max() }.max()
    }

    func hasAnyDownloadedImage(fileManager: FileManager = .default) -> Bool {
        for page in pages {
            for image in page.images {
                if let url = image.fileURL, url.scheme != nil {
                    do {
                        return try url.checkResourceIsReachable()
                    } catch {
                        return false
                    }
                }
            }
        }
        return false
    }

    func undownloadedPageCount(fileManager: FileManager = .default) -> Int? {
        let total = pages.count
        if total == 0 { return nil }
        let remaining = pages.filter { page in
            if page.images.isEmpty { return true }
            for img in page.images {
                if let url = img.fileURL, url.scheme != nil {
                    do {
                        return try !url.checkResourceIsReachable()
                    } catch {
                        return true
                    }
                } else {
                    return true
                }
            }
            return false
        }.count
        return remaining == 0 ? nil : remaining
    }
}
