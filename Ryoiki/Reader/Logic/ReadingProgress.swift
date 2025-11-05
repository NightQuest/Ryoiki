import Foundation
import Observation

@Observable
public final class ReadingProgress: @unchecked Sendable {
    public var currentPage: Int
    public var currentImageIndex: Int
    public var totalPages: Int
    public var totalImages: Int

    public init(currentPage: Int = 0, currentImageIndex: Int = 0, totalPages: Int = 0, totalImages: Int = 0) {
        self.currentPage = currentPage
        self.currentImageIndex = currentImageIndex
        self.totalPages = totalPages
        self.totalImages = totalImages
    }

    public func updatePage(_ page: Int) {
        currentPage = max(0, page)
    }

    public func updateImageIndex(_ index: Int) {
        currentImageIndex = max(0, index)
    }

    public func configureTotals(pages: Int, images: Int) {
        totalPages = max(0, pages)
        totalImages = max(0, images)
    }
}
