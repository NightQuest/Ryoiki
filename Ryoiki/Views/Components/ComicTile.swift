import SwiftUI

/// A single comic tile showing a thumbnail placeholder and the comic's name.
struct ComicTile: View {
    let comic: Comic
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: Layout.cornerRadius)
                    .fill(.quaternary)
                Image(systemName: "photo")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
            }
            .aspectRatio(3/2, contentMode: .fit)

            Text(comic.name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Layout.cornerRadius)
                .fill(.quaternary)
        )
        .selectionBorder(isSelected)
    }
}
