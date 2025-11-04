import Foundation

public struct ReadingProgressStore {
    public let selectionKey: String
    public let pageKey: String

    public init(comicName: String, comicURL: String) {
        // Keep key scheme compatible with existing storage
        self.selectionKey = "reader.selection.\(comicName)|\(comicURL)"
        self.pageKey = "reader.page.\(comicName)|\(comicURL)"
    }

    public func load(totalPages: Int, totalImages: Int, pageToFirstFlatIndex: [Int]) -> (page: Int, imageIndex: Int) {
        let defaults = UserDefaults.standard
        var page = 0
        if let raw = defaults.object(forKey: pageKey) as? Int, totalPages > 0 {
            page = min(max(0, raw), totalPages - 1)
        } else if let oldImage = defaults.object(forKey: selectionKey) as? Int, totalPages > 0, !pageToFirstFlatIndex.isEmpty {
            // Back-compat: map old image selection to a page index
            let pageIdx = pageToFirstFlatIndex.lastIndex(where: { oldImage >= $0 }) ?? 0
            page = min(max(0, pageIdx), totalPages - 1)
        }
        let firstImageIndex = (page < pageToFirstFlatIndex.count ? pageToFirstFlatIndex[page] : 0)
        let imageIndex = min(max(0, firstImageIndex), max(totalImages - 1, 0))
        return (page, imageIndex)
    }

    public func save(progress: ReadingProgress) {
        let defaults = UserDefaults.standard
        defaults.set(progress.currentImageIndex, forKey: selectionKey)
        defaults.set(progress.currentPage, forKey: pageKey)
    }
}
