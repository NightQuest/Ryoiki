import SwiftUI

/// A single comic tile showing a thumbnail placeholder and the comic's name.
struct ComicTile: View {
    let comic: Comic
    let isSelected: Bool
    let isFetching: Bool
    let isUpdating: Bool
    let overridePageCount: Int?

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

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                        .fill(.quinary.opacity(0.4))

                    // Thumbnail: prefer explicit coverImage; fallback to earliest downloaded image
                    if let data = comic.coverImage, let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
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

            // Custom badge (page count)
            if !comic.pages.isEmpty {
                Text("\(overridePageCount ?? comic.dedupedPageCount)")
                    .font(.caption2).bold()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.red, in: Capsule())
                    .foregroundStyle(.white)
                    .padding(6)
            }

            if isFetching || isUpdating {
                VStack(spacing: 6) {
                    ProgressView()
                    Text(isUpdating ? "Updating…" : "Fetching…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.quaternary, lineWidth: 1))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .transition(.opacity.combined(with: .scale))
                .animation(.default, value: isFetching)
            }
        }
    }
}
