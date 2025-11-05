//
//  ReaderModeToggle.swift
//  Ryoiki
//
//  Created by Stardust on 2025-11-05.
//

import SwiftUI

struct ReaderModeToggle: View {
    var readerMode: ReadingMode
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: readerMode == .pager ? "rectangle.on.rectangle" : "rectangle.split.2x1")
                Text(readerMode.label)
                    .fontWeight(.semibold)
            }
            .font(.headline)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}
