//
//  Comic.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-25.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

extension Comic {
    @MainActor
    func setCoverImage(from fileURL: URL, maxPixel: CGFloat = 512, compressionQuality: CGFloat = 0.8) {

        Task { @MainActor in
            // Synchronous worker that performs ImageIO work
            func makeThumbnailDataSync() -> Data? {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel)
                ]

                guard let src = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                      let cgThumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
                    return nil
                }

                let data = NSMutableData()
                let jpegUTI = UTType.jpeg.identifier as CFString
                guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, jpegUTI, 1, nil) else {
                    return nil
                }
                let props: [CFString: Any] = [
                    kCGImageDestinationLossyCompressionQuality: min(max(compressionQuality, 0), 1)
                ]
                CGImageDestinationAddImage(dest, cgThumb, props as CFDictionary)
                guard CGImageDestinationFinalize(dest) else { return nil }
                return data as Data
            }

            // Offload to background queue to avoid blocking the main actor
            let resultData: Data? = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = makeThumbnailDataSync() ?? (try? Data(contentsOf: fileURL))
                    continuation.resume(returning: data)
                }
            }

            if let resultData {
                self.coverImage = resultData
            }
        }
    }

    var dedupedPageCount: Int {
        let uniqueByURL = Set(self.pages.map { $0.pageURL })
        return uniqueByURL.count
    }
}
