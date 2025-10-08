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
    @Published var pageCount: Int = 0 {
        willSet {
            objectWillChange.send()
        }
    }

    func computePageCount(for url: URL?) -> Int {
        guard let url else { return 0 }
        return FileUtilities.pageCount(for: url)
    }

    func copyToPasteboard(_ text: String) {
        FileUtilities.copyToPasteboard(text)
    }

    func refreshHashes(for url: URL?) async {
        md5Hex = ""
        sha1Hex = ""
        crc32Hex = ""
        guard let url else {
            md5Hex = "—"; sha1Hex = "—"; crc32Hex = "—"; return
        }

        // NOTE: Per Option C, all read utilities (e.g., FileUtilities.computeFileDigests) must manage their own security-scoped access.

        let task = Task {
            return try? FileUtilities.computeFileDigests(url: url)
        }

        let result = await task.value

        self.md5Hex = result?.md5 ?? "—"
        self.sha1Hex = result?.sha1 ?? "-"
        self.crc32Hex = result?.crc32 ?? "-"
    }
}

