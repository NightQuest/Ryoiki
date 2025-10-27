//
//  ComicManager+Deletion.swift
//  Ryoiki
//

import Foundation

// MARK: - Deletion
extension ComicManager {
    /// Deletes the folder on disk that contains downloaded images for the given comic.
    /// The folder is assumed to be located at `baseFolder/sanitizeFilename(comic.name)`.
    /// If the folder exists, it and all of its contents will be removed.
    func deleteDownloadFolder(for comic: Comic, in baseFolder: URL) {
        let fm = FileManager.default
        let folder = baseFolder.appendingPathComponent(sanitizeFilename(comic.name))
        if fm.fileExists(atPath: folder.path) { try? fm.removeItem(at: folder) }
    }
}
