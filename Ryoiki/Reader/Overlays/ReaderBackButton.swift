//
//  ReaderBackButton.swift
//  Ryoiki
//
//  Created by Stardust on 2025-11-05.
//

import SwiftUI

struct ReaderBackButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.backward")
                Text("Back to Library")
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
