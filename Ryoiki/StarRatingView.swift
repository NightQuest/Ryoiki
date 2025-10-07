import SwiftUI

// MARK: - StarRatingView
/// Simple interactive star rating control used for Community Rating.
struct StarRatingView: View {
    @Binding var value: Int
    var max: Int = 5

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...max, id: \.self) { index in
                Button {
                    value = index
                } label: {
                    Image(systemName: index <= value ? "star.fill" : "star")
                        .symbolRenderingMode(.monochrome)
                        .foregroundColor(index <= value ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
    }
}
