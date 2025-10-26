//
//  ImagesGrid.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-24.
//

import SwiftUI

struct ImagesGrid: View {
    let downloadedImages: [DownloadedImageItem]
    let comic: Comic
    @Binding var selectionManager: SelectionManager
    let onLayoutUpdate: (_ frames: [UUID: CGRect], _ origin: CGPoint, _ orderedIDs: [UUID]) -> Void

    var body: some View {
        EntityGrid(
            items: downloadedImages,
            selectionManager: $selectionManager,
            onLayoutUpdate: onLayoutUpdate,
            minWidth: 140,
            maxWidth: 260
        ) { item, isSelected in
            ImageTile(
                fileURL: item.fileURL,
                isSelected: isSelected,
                title: item.fileURL.deletingPathExtension().lastPathComponent,
                subtitle: URL(string: comic.url)?.host
            )
        } contextMenu: { item, isSelected in
            if FileManager.default.fileExists(atPath: item.fileURL.path) {
                Button {
                    // Set cover from selected image
                    comic.setCoverImage(from: item.fileURL)
                } label: {
                    Label("Set as Cover", systemImage: "rectangle.portrait")
                }
                .disabled(!(selectionManager.selection.isEmpty || (isSelected && selectionManager.selection.count == 1)))
            } else {
                Text("Select a single image to set as cover").foregroundStyle(.secondary)
            }
            Button(isSelected ? "Deselect" : "Select") {
                selectionManager.toggleSelection(item.id)
            }
        }
    }
}
