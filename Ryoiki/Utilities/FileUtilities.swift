import Foundation
import CryptoKit
import zlib
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// Digest container to avoid large tuple warnings
struct FileDigests: Codable, Equatable {
    let md5: String
    let sha1: String
    let crc32: String
}

// MARK: - FileUtilities
/// Cross-platform helpers for file inspection, hashing, and pasteboard.
enum FileUtilities {
    /// Supported image extensions for direct-file detection.
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "tif", "tiff", "heic", "heif", "webp", "jp2", "j2k"
    ]

    /// Returns true if the URL points directly to an image file (by extension).
    static func isDirectImageURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    /// Returns page count for the given URL: 1 for direct images, otherwise archive page count.
    static func pageCount(for url: URL) -> Int {
        isDirectImageURL(url) ? 1 : ComicArchive(fileURL: url).pageCount()
    }

    /// Copies text to the system pasteboard on AppKit/UIKit platforms.
    static func copyToPasteboard(_ text: String) {
        #if canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }

    /// Streams a file and computes MD5, SHA-1, and CRC32 digests efficiently.
    static func computeFileDigests(url: URL) throws -> FileDigests {
        let chunkSize = 1_048_576 // 1 MB
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var md5 = Insecure.MD5()
        var sha1 = Insecure.SHA1()
        var crc: uLong = crc32(0, nil, 0)

        while true {
            let data = try handle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty { break }
            md5.update(data: data)
            sha1.update(data: data)
            data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
                guard let base = buf.bindMemory(to: Bytef.self).baseAddress else { return }
                crc = crc32(crc, base, uInt(data.count))
            }
        }

        let md5Hex = md5.finalize().map { String(format: "%02x", $0) }.joined()
        let sha1Hex = sha1.finalize().map { String(format: "%02x", $0) }.joined()
        let crc32Hex = String(format: "%08x", UInt32(crc))
        return FileDigests(md5: md5Hex, sha1: sha1Hex, crc32: crc32Hex)
    }
}
