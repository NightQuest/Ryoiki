import SwiftUI

// MARK: - CoverImageView
/// Displays the cover image or a placeholder when unavailable.
struct CoverImageView: View {
    let image: Image?
    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 120, height: 180)
            }
        }
    }
}
