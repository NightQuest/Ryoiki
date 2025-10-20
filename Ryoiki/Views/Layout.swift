import SwiftUI

/// Shared layout constants for consistent spacing and sizing.
enum Layout {
    static let cornerRadius: CGFloat = 12
    static let gridSpacing: CGFloat = 16
    static let gridPadding: CGFloat = 16

    static var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: gridSpacing)]
    }
}
