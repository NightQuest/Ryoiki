//
//  ImagesGrid.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-24.
//

import SwiftUI

struct ImagesGrid: View {
    let downloadedPages: [ComicPage]
    @Binding var selectionManager: SelectionManager
    let onLayoutUpdate: (_ frames: [UUID: CGRect], _ origin: CGPoint, _ orderedIDs: [UUID]) -> Void

    var body: some View {
        EntityGrid(
            items: downloadedPages,
            selectionManager: $selectionManager,
            onLayoutUpdate: onLayoutUpdate,
            minWidth: 140,
            maxWidth: 260
        ) { page, isSelected in
            PageTile(page: page, isSelected: isSelected)
        } contextMenu: { page, isSelected in
            if let fileURL = page.downloadedFileURL,
               FileManager.default.fileExists(atPath: fileURL.path) {
                Button {
                    page.comic.setCoverImage(from: fileURL)
                } label: {
                    Label("Set as Cover", systemImage: "rectangle.portrait")
                }
                .disabled(!(selectionManager.selection.isEmpty ||
                          (isSelected && selectionManager.selection.count == 1)))
            } else {
                Text("Select a single image to set as cover").foregroundStyle(.secondary)
            }
            Button(isSelected ? "Deselect" : "Select") {
                selectionManager.toggleSelection(page.id)
            }
        }
    }
}
