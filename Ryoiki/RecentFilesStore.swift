import Foundation
import UniformTypeIdentifiers
import Combine

// MARK: - RecentFilesStore
final class RecentFilesStore: ObservableObject {
    // MARK: Model
    struct Item: Identifiable, Codable, Equatable {
        let id: UUID
        private let bookmarkData: Data?
        var lastOpened: Date
        let title: String?
        let displayFileName: String?
        let displayLocation: String?

        init(url: URL, lastOpened: Date = Date(), title: String? = nil, id: UUID = UUID()) {
            self.id = id
            self.lastOpened = lastOpened
            self.title = title
            // Create security-scoped bookmark data for the URL when possible.
            if let data = try? url.bookmarkData(options: [.securityScopeAllowOnlyReadAccess],
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil) {
                self.bookmarkData = data
            } else {
                self.bookmarkData = nil
            }
            // Store display fields so UI can show meaningful values even if URL can't be resolved later.
            self.displayFileName = url.lastPathComponent
            self.displayLocation = url.deletingLastPathComponent().path
        }

        // Resolves the URL from bookmark data if present; falls back to nil if resolution fails.
        var url: URL? {
            guard let bookmarkData else { return nil }
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmarkData,
                                       options: [.withSecurityScope],
                                       relativeTo: nil,
                                       bookmarkDataIsStale: &isStale) {
                if isStale {
                    // Attempt to refresh the bookmark if it's stale by creating a new one
                    if ((try? resolved.bookmarkData(options: [.securityScopeAllowOnlyReadAccess],
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil)) != nil) {
                        // Note: Since `Item` is a value type and Codable, we do not mutate here;
                        // the store will refresh bookmarks on `load()` when possible.
                        return resolved
                    }
                }
                return resolved
            }
            return nil
        }

        var name: String {
            if let u = url { return u.deletingPathExtension().lastPathComponent }
            if let n = displayFileName { return URL(fileURLWithPath: n).deletingPathExtension().lastPathComponent }
            return URL(fileURLWithPath: "/").deletingPathExtension().lastPathComponent
        }
        var fileName: String { url?.lastPathComponent ?? displayFileName ?? URL(fileURLWithPath: "/").lastPathComponent }
        var location: String { url?.deletingLastPathComponent().path ?? displayLocation ?? URL(fileURLWithPath: "/").deletingLastPathComponent().path }
    }

    @Published private(set) var items: [Item] = []

    private let recentFilesKey = "RecentFiles"

    // MARK: Persistence
    func load() {
        if let data = UserDefaults.standard.data(forKey: recentFilesKey) {
            do {
                // First try to decode the new format with bookmarkData
                let files = try JSONDecoder().decode([Item].self, from: data)
                items = Array(files.sorted { $0.lastOpened > $1.lastOpened }.prefix(5))
                // Normalize: ensure display fields are present by rebuilding from resolved URLs when possible
                let normalized = items.map { item in
                    if let u = item.url {
                        return Item(url: u, lastOpened: item.lastOpened, title: item.title, id: item.id)
                    } else if item.displayFileName == nil || item.displayLocation == nil {
                        return item // cannot improve without a URL
                    } else {
                        return item
                    }
                }
                items = Array(normalized.prefix(5))
                save()
                print("Recent Files: Loaded \(items.count) items")
            } catch {
                // Attempt migration from legacy format that stored a plain URL
                print("Recent Files: Attempting migration from legacy format due to error: \(error)")
                struct LegacyItem: Identifiable, Codable, Equatable {
                    let id: UUID
                    let url: URL?
                    var lastOpened: Date
                    let title: String?
                }
                if let legacy = try? JSONDecoder().decode([LegacyItem].self, from: data) {
                    let migrated: [Item] = legacy.compactMap { old in
                        if let u = old.url {
                            return Item(url: u, lastOpened: old.lastOpened, title: old.title, id: old.id)
                        } else {
                            return nil
                        }
                    }
                    items = Array(migrated.sorted { $0.lastOpened > $1.lastOpened }.prefix(5))
                    save()
                    print("Recent Files: Migrated \(items.count) legacy items to bookmark-based storage")
                } else {
                    print("Recent Files: Failed to decode legacy format. Clearing incompatible stored data.")
                    UserDefaults.standard.removeObject(forKey: recentFilesKey)
                    items = []
                }
            }
        } else {
            print("Recent Files: No stored data")
        }
    }

    private func save() {
        let trimmed = items.sorted { $0.lastOpened > $1.lastOpened }.prefix(5)
        do {
            let data = try JSONEncoder().encode(Array(trimmed))
            UserDefaults.standard.set(data, forKey: recentFilesKey)
            UserDefaults.standard.synchronize()
            print("Recent Files: Saved \(trimmed.count) items")
        } catch {
            print("Recent Files: Failed to encode with error: \(error)")
        }
    }

    // MARK: Public API
    @discardableResult
    func add(url: URL, title: String? = nil) -> Item? {
        let std = url.standardizedFileURL

        // Determine initial title: prefer provided title, else existing stored title.
        let initialTitle: String? = title ?? items.first { $0.url?.standardizedFileURL == std }?.title

        // Remove any existing entries that resolve to the same standardized URL
        items.removeAll { $0.url?.standardizedFileURL == std }

        // Create a new item with bookmark data
        let newItem = Item(url: std, lastOpened: Date(), title: initialTitle)
        items.insert(newItem, at: 0)
        items = Array(items.prefix(5))
        save()
        print("Recent Files: Added \(std.lastPathComponent)")

        // If we don't have a title yet, enrich it asynchronously from ComicInfo.xml.
        if initialTitle == nil || initialTitle?.isEmpty == true {
            Task { [weak self] in
                guard let self else { return }
                let archive = ComicArchive(fileURL: std)
                if let info = archive.getComicInfoData(), info.parse() {
                    let t = info.parsed.Title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty {
                        DispatchQueue.main.async { [weak self] in
                            guard let self else { return }
                            if let idx = self.items.firstIndex(where: { $0.url?.standardizedFileURL == std }) {
                                let updated = Item(url: std, lastOpened: Date(), title: t, id: self.items[idx].id)
                                self.items.remove(at: idx)
                                self.items.insert(updated, at: 0)
                                self.items = Array(self.items.prefix(5))
                                self.save()
                                print("Recent Files: Enriched title for \(std.lastPathComponent) -> \(t)")
                            }
                        }
                    }
                }
            }
        }

        return newItem
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func updateURL(for id: UUID, to newURL: URL) {
        let std = newURL.standardizedFileURL
        if let idx = items.firstIndex(where: { $0.id == id }) {
            let old = items[idx]
            let updated = Item(url: std, lastOpened: Date(), title: old.title, id: old.id)
            items.remove(at: idx)
            items.insert(updated, at: 0)
            items = Array(items.prefix(5))
            save()
            print("Recent Files: Updated URL for \(updated.fileName)")
        }
    }
}
