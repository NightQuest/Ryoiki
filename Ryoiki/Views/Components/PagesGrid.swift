//
//  PagesGrid.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-24.
//

import SwiftUI

struct PagesGrid: View {
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
            Button(isSelected ? "Deselect" : "Select") {
                selectionManager.toggleSelection(page.id)
            }
        }
    }
}
