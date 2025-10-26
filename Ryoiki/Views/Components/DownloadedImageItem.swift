import Foundation

struct DownloadedImageItem: Identifiable, Hashable {
    let id: UUID
    let pageID: UUID
    let imageID: UUID
    let fileURL: URL
}
