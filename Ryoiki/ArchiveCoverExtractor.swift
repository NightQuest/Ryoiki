import Foundation
import ZIPFoundation
internal import UniformTypeIdentifiers
import ImageIO
import SwiftUI
import CoreGraphics

// MARK: - ArchiveCoverExtractor
/// Finds and decodes cover images and direct images, with in-memory caching and security-scoped access.
enum ArchiveCoverExtractor {
    static func coverImage(from fileURL: URL) -> Image? {
        let needsSecurity = fileURL.startAccessingSecurityScopedResource()
        defer { if needsSecurity { fileURL.stopAccessingSecurityScopedResource() } }

        do {
            let archive = try Archive(url: fileURL, accessMode: .read)
            let cacheKeyPrefix = fileURL.absoluteString + "::"

            // Regex for a leading number (e.g., 0, 0-foo, 0_bar) and an image extension.
            let pattern = /^(?<num>\d+)(?:(?<sep>[-_])(?<suffix>.+))?\.(?<ext>[a-z0-9]{1,10})$/
            let commonImageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "tif", "tiff", "heic", "heif", "webp", "jp2", "j2k"]

            var selectedEntry: ZIPFoundation.Entry?
            var firstImageEntry: ZIPFoundation.Entry?

            for entry in archive where entry.type == .file {
                let originalPath = entry.path
                let fileLower = originalPath.split(separator: "/").last.map { $0.lowercased() } ?? originalPath.lowercased()

                // Track first image as a fallback (by extension or UTType)
                if firstImageEntry == nil, let dot = fileLower.lastIndex(of: ".") {
                    let ext = String(fileLower[fileLower.index(after: dot)...])
                    let isImageByUTType = UTType(filenameExtension: ext)?.conforms(to: .image) == true
                    if isImageByUTType || commonImageExts.contains(ext) {
                        firstImageEntry = entry
                    }
                }

                // Check for zero-named rule on last component
                guard let m = fileLower.wholeMatch(of: pattern) else { continue }

                let ext = String(m.output.ext)
                let isImage = UTType(filenameExtension: ext)?.conforms(to: .image) == true || commonImageExts.contains(ext)
                guard isImage else { continue }

                guard let num = Int(String(m.output.num)), num == 0 else { continue }

                if m.output.sep != nil {
                    guard let suffix = m.output.suffix.map({ String($0) }), !suffix.isEmpty else { continue }
                }

                selectedEntry = entry
                break
            }

            // Prefer the zero-named match; fall back to the first image found
            guard let chosen = selectedEntry ?? firstImageEntry else { return nil }

            var entryData = Data()
            _ = try archive.extract(chosen) { data in
                entryData.append(data)
            }
            guard !entryData.isEmpty else { return nil }

            // Cache fast-path
            let cacheKey = cacheKeyPrefix + chosen.path
            if let cached = ImageCache.shared.cgImage(forKey: cacheKey) {
                return Image(decorative: cached, scale: 1, orientation: .up)
            }

            // Decode image data and put it in cache with a rough cost estimate.
            if let cgImageSource = CGImageSourceCreateWithData(entryData as CFData, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(cgImageSource, 0, nil) {
                // Rough cost estimate: bytes per pixel (assume 4) * width * height
                let width = cgImage.width
                let height = cgImage.height
                let cost = width * height * 4
                ImageCache.shared.setCGImage(cgImage, forKey: cacheKey, cost: cost)
                return Image(decorative: cgImage, scale: 1, orientation: .up)
            }

            return nil
        } catch {
            return nil
        }
    }

    static func image(from fileURL: URL) -> Image? {
        let needsSecurity = fileURL.startAccessingSecurityScopedResource()
        defer { if needsSecurity { fileURL.stopAccessingSecurityScopedResource() } }

        // Cache fast-path
        let cacheKey = fileURL.absoluteString
        if let cached = ImageCache.shared.cgImage(forKey: cacheKey) {
            return Image(decorative: cached, scale: 1, orientation: .up)
        }

        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return nil
        }

        // Decode image data and put it in cache with a rough cost estimate.
        if let src = CGImageSourceCreateWithData(data as CFData, nil),
           let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            let cost = cg.width * cg.height * 4
            ImageCache.shared.setCGImage(cg, forKey: cacheKey, cost: cost)
            return Image(decorative: cg, scale: 1, orientation: .up)
        }
        return nil
    }
}
