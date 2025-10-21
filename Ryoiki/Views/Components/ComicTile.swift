import SwiftUI

/// A single comic tile showing a thumbnail placeholder and the comic's name.
struct ComicTile: View {
    let comic: Comic
    let isSelected: Bool

    var coverImage: some View {
        let firstPage = comic.pages.first
        return AsyncImage(url: URL(string: firstPage?.downloadPath ?? "")) { result in
            result.image?
                .resizable()
                .scaledToFit()
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: Layout.cornerRadius)
                        .fill(.quaternary)
                    ZStack {
                        Image(systemName: "photo")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        coverImage
                    }
                }
                .aspectRatio(contentMode: .fit)

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

            // Custom badge
            if !comic.pages.isEmpty {
                Text("\(comic.pages.count)")
                    .font(.caption2).bold()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.red, in: Capsule())
                    .foregroundStyle(.white)
                    .padding(6) // inset from the top-right corner
            }
        }
    }
}
