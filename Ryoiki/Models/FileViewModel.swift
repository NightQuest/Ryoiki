import Foundation
import Combine
import SwiftUI

@MainActor
final class FileViewModel: ObservableObject {
    @Published var md5Hex: String = "" {
        willSet {
            objectWillChange.send()
        }
    }
    @Published var sha1Hex: String = "" {
        willSet {
            objectWillChange.send()
        }
    }
    @Published var crc32Hex: String = "" {
        willSet {
            objectWillChange.send()
        }
    }
    @Published var fileSize: String = "" {
        willSet { objectWillChange.send() }
    }
    @Published var pageCount: Int = 0 {
        willSet {
            objectWillChange.send()
        }
    }

    @Published var editableComicInfo: ComicInfoModel = .init()
    @Published var coverImage: Image?
    @Published private(set) var openedURL: URL?

    private var scopedURL: URL?

    func computePageCount(for url: URL?) -> Int {
        guard let url else { return 0 }
        return FileUtilities.pageCount(for: url)
    }

    func computeFileSize(for url: URL?) -> String {
        guard let url else { return "—" }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let bytes = values.fileSize {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useKB, .useMB, .useGB]
                formatter.countStyle = .file
                return formatter.string(fromByteCount: Int64(bytes))
            }
        } catch {
            // ignore and fall through
        }
        return "—"
    }

    func copyToPasteboard(_ text: String) {
        FileUtilities.copyToPasteboard(text)
    }

    func refreshHashes(for url: URL?) async {
        md5Hex = ""
        sha1Hex = ""
        crc32Hex = ""
        fileSize = ""
        guard let url else {
            md5Hex = "—"; sha1Hex = "—"; crc32Hex = "—"; fileSize = "—"; return
        }

        fileSize = computeFileSize(for: url)

        let task = Task {
            try? FileUtilities.computeFileDigests(url: url)
        }

        let result = await task.value

        self.md5Hex = result?.md5 ?? "—"
        self.sha1Hex = result?.sha1 ?? "—"
        self.crc32Hex = result?.crc32 ?? "—"
    }

    func open(url: URL?, providedComicInfo: ComicInfoModel?) {
        // Reset basics
        pageCount = computePageCount(for: url)
        fileSize = computeFileSize(for: url)

        guard let url else {
            md5Hex = ""; sha1Hex = ""; crc32Hex = ""; coverImage = nil
            endSecurityScope()
            openedURL = nil
            return
        }

        guard beginSecurityScope(for: url) else {
            openedURL = nil
            return
        }
        openedURL = url

        // Attempt to read cover and metadata
        let archive = ComicArchive(fileURL: url)
        coverImage = archive.coverImage()

        prepareEditableModel(from: url, provided: providedComicInfo)
        ensurePagesCoverAllImages(from: url)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            await refreshHashes(for: url)
        }
    }

    func close() {
        endSecurityScope()
        openedURL = nil
        coverImage = nil
    }

    private func beginSecurityScope(for url: URL) -> Bool {
        if let scopedURL, scopedURL == url { return true }
        if let scopedURL { scopedURL.stopAccessingSecurityScopedResource() }
        let ok = url.startAccessingSecurityScopedResource()
        if ok { scopedURL = url }
        return ok
    }

    private func endSecurityScope() {
        if let scopedURL {
            scopedURL.stopAccessingSecurityScopedResource()
            self.scopedURL = nil
        }
    }

    private func prepareEditableModel(from url: URL, provided: ComicInfoModel?) {
        if let provided {
            editableComicInfo.overwrite(from: provided)
        } else if let info = ComicArchive(fileURL: url).getComicInfoData(), info.parse() {
            editableComicInfo.overwrite(from: info.parsed)
        } else {
            editableComicInfo.overwrite(from: ComicInfoModel())
        }
    }

    private func ensurePagesCoverAllImages(from url: URL) {
        let archive = ComicArchive(fileURL: url)
        let total = archive.pageCount()
        guard total > 0 else { return }

        var finalPages = Array(repeating: ComicPageInfo(), count: total)
        if let existing = editableComicInfo.Pages, !existing.isEmpty {
            let hasExplicitIndices = existing.contains { Int($0.Image) != nil }
            if hasExplicitIndices {
                for p in existing {
                    if let idx = Int(p.Image), idx >= 0, idx < total { finalPages[idx] = p }
                }
            } else {
                for (i, p) in existing.enumerated() where i < total { finalPages[i] = p }
            }
        } else {
            for i in 0..<total { finalPages[i].Image = String(i) }
        }
        editableComicInfo.Pages = finalPages
        editableComicInfo.PageCount = total
    }
}
