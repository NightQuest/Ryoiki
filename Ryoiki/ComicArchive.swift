import Foundation
import SwiftUI
import ZIPFoundation

// MARK: - ComicArchive
/// Utilities for working with comic archive files (CBZ/ZIP), including cover detection and image extraction.
struct ComicArchive {
    let fileURL: URL

    /// Supported image extensions for archive entries.
    static let imageExtensions: Set<String> = [
        "jpg","jpeg","png","gif","bmp","tif","tiff","heic","heif","webp","jp2","j2k"
    ]

    /// Centralizes security-scoped access and Archive creation.
    private func withArchive<T>(_ body: (Archive) throws -> T?) -> T? {
        let needsSecurity = fileURL.startAccessingSecurityScopedResource()
        defer { if needsSecurity { fileURL.stopAccessingSecurityScopedResource() } }
        do {
            let archive = try Archive(url: fileURL, accessMode: .read)
            return try body(archive)
        } catch {
            return nil
        }
    }

    /// Natural (Finder-like) sort for entry paths.
    private static func sortNaturally(_ paths: [String]) -> [String] {
        return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Gathers image entry paths from an already-opened archive without sorting.
    private static func imageEntryPaths(in archive: Archive) -> [String] {
        var paths: [String] = []
        for entry in archive where entry.type == .file {
            let lower = entry.path.lowercased()
            if let dot = lower.lastIndex(of: ".") {
                let ext = String(lower[lower.index(after: dot)...])
                if Self.imageExtensions.contains(ext) {
                    paths.append(entry.path)
                }
            }
        }
        return paths
    }

    // Selects a preferred cover image entry path using zero-named heuristics, falling back to the first image.
    private static func chooseCoverPath(in archive: Archive) -> String? {
        var firstImage: String?
        var chosenPath: String?

        for entry in archive where entry.type == .file {
            let lastComponent = entry.path.split(separator: "/").last.map(String.init) ?? entry.path
            let lower = lastComponent.lowercased()
            guard let dot = lower.lastIndex(of: ".") else { continue }

            let ext = String(lower[lower.index(after: dot)...])
            guard Self.imageExtensions.contains(ext) else { continue }

            if firstImage == nil { firstImage = entry.path }

            // Base name without extension
            let base = String(lower[..<dot])
            if base == "0" {
                chosenPath = entry.path
                break
            }
            if (base.hasPrefix("0-") || base.hasPrefix("0_")) && base.count > 2 {
                chosenPath = entry.path
                break
            }
        }

        return chosenPath ?? firstImage
    }

    // Extracts a cover Image from the archive at fileURL, if possible
    func coverImage() -> Image? {
        return withArchive { archive in
            guard let chosenPath = Self.chooseCoverPath(in: archive) else { return nil }
            return archive.image(atEntryPath: chosenPath, cacheKeyPrefix: fileURL.absoluteString)
        }
    }

    // Returns an Image for a specific entry path if it exists and is decodable
    func image(atEntryPath path: String, cacheKeyPrefix: String? = nil) -> Image? {
        return withArchive { archive in
            return archive.image(atEntryPath: path, cacheKeyPrefix: cacheKeyPrefix ?? fileURL.absoluteString)
        }
    }

    // Lists all entry paths in the archive (files and directories)
    func allEntryPaths() -> [String] {
        return withArchive { archive in
            return Array(archive.map { $0.path })
        } ?? []
    }

    // Lists only file entry paths (excluding directories)
    func fileEntryPaths() -> [String] {
        return withArchive { archive in
            var paths: [String] = []
            for entry in archive where entry.type == .file {
                paths.append(entry.path)
            }
            return paths
        } ?? []
    }

    // Lists file entry paths that appear to be images by extension
    func imageEntryPaths() -> [String] {
        return withArchive { archive in
            let paths = Self.imageEntryPaths(in: archive)
            return Self.sortNaturally(paths)
        } ?? []
    }

    // Total number of image pages (1-based indexing for public APIs)
    func pageCount() -> Int {
        return imageEntryPaths().count
    }

    // Returns the 1-based index of the cover page if it can be identified
    func coverPageIndex() -> Int? {
        return withArchive { archive in
            let paths = Self.sortNaturally(Self.imageEntryPaths(in: archive))

            guard let coverPath = Self.chooseCoverPath(in: archive) else { return nil }
            guard let idx = paths.firstIndex(of: coverPath) else { return nil }
            return idx + 1 // 1-based
        }
    }

    // Returns the Image for a given 1-based page number
    func getImage(pageNumber: Int) -> Image? {
        guard pageNumber > 0 else { return nil }
        let paths = imageEntryPaths()
        guard pageNumber <= paths.count else { return nil }
        let path = paths[pageNumber - 1]
        return image(atEntryPath: path)
    }

    // Indicates whether a given 1-based page number is the selected cover page
    func isCoverImage(pageNumber: Int) -> Bool {
        return withArchive { archive in
            let paths = Self.sortNaturally(Self.imageEntryPaths(in: archive))
            guard pageNumber > 0, pageNumber <= paths.count else { return false }

            let coverPath = Self.chooseCoverPath(in: archive)
            guard let coverPath else { return false }
            return paths[pageNumber - 1] == coverPath
        } ?? false
    }

    // Returns the raw data for ComicInfo.xml if present in the archive
    func getComicInfoData() -> ComicInfoXML? {
        return withArchive { archive in
            // Find an entry named "ComicInfo.xml" (case-insensitive) only at the root (no subdirectories)
            guard let entry = archive.first(where: {
                // Must be at root (no subdirectories) and named exactly "ComicInfo.xml" (case-insensitive)
                let nsPath = $0.path as NSString
                guard nsPath.pathComponents.count == 1 else { return false }
                return nsPath.lastPathComponent.caseInsensitiveCompare("ComicInfo.xml") == .orderedSame
            }) else { return nil }

            var data = Data()
            guard (try? archive.extract(entry) { data.append($0) }) != nil else { return nil }
            return ComicInfoXML(data: data)
        }
    }

    // Checks whether an entry with the given path exists
    func containsEntry(path: String) -> Bool {
        return withArchive { archive in
            for entry in archive where entry.path == path { return true }
            return false
        } ?? false
    }

    // Reads raw Data for a specific entry path, if present
    func data(atEntryPath path: String) -> Data? {
        return withArchive { archive in
            guard let entry = archive.first(where: { $0.path == path }) else { return nil }
            var data = Data()
            do {
                _ = try archive.extract(entry) { buffer in
                    data.append(buffer)
                }
                return data
            } catch {
                return nil
            }
        }
    }
}

