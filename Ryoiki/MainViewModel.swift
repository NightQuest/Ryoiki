import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Combine

@MainActor
final class MainViewModel: ObservableObject {
    @Published var recents = RecentFilesStore()
    @Published var hasFileOpened = false
    @Published var openedFile: URL?

    // Expose a stable date formatter for the view
    let lastOpenedFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    func onAppear() {
        recents.load()
    }

    func handleOpen(url: URL) {
        openedFile = url
        withAnimation(.easeInOut(duration: 0.2)) {
            hasFileOpened = true
        }
    }

    func handleClose() {
        withAnimation(.easeInOut(duration: 0.2)) {
            hasFileOpened = false
        }
        openedFile = nil
    }

    func openRecent(_ item: RecentFilesStore.Item) {
        if let url = item.url {
            var isReachable = false
            do { isReachable = try url.checkResourceIsReachable() } catch { isReachable = false }
            if isReachable { handleOpen(url: url); return }
        }

        let folderPath = item.location
        let filename = item.fileName
        let candidate = URL(fileURLWithPath: folderPath).appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: candidate.path) {
            recents.updateURL(for: item.id, to: candidate)
            if let refreshed = recents.items.first(where: { $0.id == item.id })?.url {
                handleOpen(url: refreshed)
            } else {
                handleOpen(url: candidate)
            }
            return
        }

        failedItem = item
        showRemoveFailedAlert = true
    }

    func needsReauth(_ item: RecentFilesStore.Item) -> Bool {
        guard let url = item.url else { return true }
        let ok = url.startAccessingSecurityScopedResource()
        if ok { url.stopAccessingSecurityScopedResource() }
        return !ok
    }

    // MARK: - Failed item and alerts
    @Published var failedItem: RecentFilesStore.Item?
    @Published var showRemoveFailedAlert: Bool = false
}
