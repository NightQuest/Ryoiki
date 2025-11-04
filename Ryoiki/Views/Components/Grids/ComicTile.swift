import SwiftUI
import ImageIO

/// A single comic tile showing a thumbnail placeholder and the comic's name.
struct ComicTile: View {
    let comic: Comic
    let isSelected: Bool
    let isFetching: Bool
    let isUpdating: Bool
    let overridePageCount: Int?
    @State private var frozenBadgeCount: Int?

    init(comic: Comic, isSelected: Bool, showBadge: Bool = true, isFetching: Bool = false, isUpdating: Bool = false, overridePageCount: Int? = nil) {
        self.comic = comic
        self.isSelected = isSelected
        self.isFetching = isFetching
        self.isUpdating = isUpdating
        self.overridePageCount = overridePageCount
    }

    private var subtitleText: String {
        if !comic.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return comic.author
        }
        if let host = URL(string: comic.url)?.host {
            return host
        }
        return ""
    }

    private var firstLocalURL: URL? {
        guard let first = comic.pages.min(by: { $0.index < $1.index }) else { return nil }
        let url = first.images.min(by: { $0.index < $1.index })?.fileURL
        if let url, FileManager.default.fileExists(atPath: url.path) { return url }
        return nil
    }

    private var displayedBadgeCount: Int? {
        if isFetching || isUpdating { return frozenBadgeCount }
        return overridePageCount
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                        .fill(.quinary.opacity(0.4))

                    // Thumbnail: prefer explicit coverImage; fallback to earliest downloaded image
                    if let data = comic.coverImage,
                       let src = CGImageSourceCreateWithData(data as CFData, nil),
                       let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                        Image(decorative: cgImage, scale: 1, orientation: .up)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
                    } else if let url = firstLocalURL {
                        ThumbnailImage(url: url, maxPixel: 512)
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
                    } else {
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFit()
                            .padding(24)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(idealWidth: 250, maxWidth: 250)
                .aspectRatio(0.75, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(comic.name)
                        .font(.subheadline)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                            .fill(Color.accentColor.opacity(0.1))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            )

            // Custom badge (undownloaded page count)
            if let count = displayedBadgeCount, count > 0 {
                Text("\(count)")
                    .font(.caption2).bold()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.red, in: Capsule())
                    .foregroundStyle(.white)
                    .padding(6)
            }
        }
        .onAppear {
            if !(isFetching || isUpdating) { frozenBadgeCount = overridePageCount }
        }
        .onChange(of: isFetching || isUpdating) { _, isBusy in
            if !isBusy { frozenBadgeCount = overridePageCount }
        }
        .onChange(of: overridePageCount) { _, newValue in
            if !(isFetching || isUpdating) { frozenBadgeCount = newValue }
        }
    }
}
