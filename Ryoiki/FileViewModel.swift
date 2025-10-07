import Foundation
import Combine
import SwiftUI

@MainActor
final class FileViewModel: ObservableObject {    
    @Published var md5Hex: String = ""
    @Published var sha1Hex: String = ""
    @Published var crc32Hex: String = ""
    @Published var pageCount: Int = 0

    func computePageCount(for url: URL?) -> Int {
        guard let url else { return 0 }
        return FileUtilities.pageCount(for: url)
    }

    func copyToPasteboard(_ text: String) {
        FileUtilities.copyToPasteboard(text)
    }

    func refreshHashes(for url: URL?) {
        md5Hex = ""
        sha1Hex = ""
        crc32Hex = ""
        guard let url else {
            md5Hex = "—"; sha1Hex = "—"; crc32Hex = "—"; return
        }
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            let result = try? FileUtilities.computeFileDigests(url: url)
            await MainActor.run {
                if let result {
                    self.md5Hex = result.md5
                    self.sha1Hex = result.sha1
                    self.crc32Hex = result.crc32
                } else {
                    self.md5Hex = "—"
                    self.sha1Hex = "—"
                    self.crc32Hex = "—"
                }
            }
        }
    }
}
