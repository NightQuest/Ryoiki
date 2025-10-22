import SwiftUI
import SwiftData
import CoreGraphics
import ImageIO

struct ComicPagesView: View {
    let comic: Comic

    @State private var selection = Set<UUID>()

    private var downloadedPages: [ComicPage] {
        comic.pages
            .sorted { $0.index < $1.index }
            .filter { page in
                guard let url = page.downloadedFileURL else { return false }
                return FileManager.default.fileExists(atPath: url.path)
            }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if downloadedPages.isEmpty {
                    ContentUnavailableView("No downloaded pages",
                                           systemImage: "photo",
                                           description: Text("Use Update to download images first."))
                    .padding()
                } else {
                    ScrollView {
                        LazyVGrid(columns: adaptiveColumns, spacing: Layout.gridSpacing) {
                            ForEach(downloadedPages, id: \.id) { page in
                                PageTile(page: page, isSelected: selection.contains(page.id))
                                    .contentShape(Rectangle())
                                    .contextMenu {
                                        Button(selection.contains(page.id) ? "Deselect" : "Select") {
                                            toggleSelection(page.id)
                                        }
                                    }
                            }
                        }
                        .padding(Layout.gridPadding)
                    }
                    .toolbar { selectionToolbar }
                }
            }
        }
        .navigationTitle("Pages: \(comic.name)")
    }

    // MARK: - Selection

    private func toggleSelection(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var selectionToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("Select All") { selection = Set(downloadedPages.map { $0.id }) }
                .disabled(downloadedPages.isEmpty || selection.count == downloadedPages.count)
            Button("Clear Selection") { selection.removeAll() }
                .disabled(selection.isEmpty)
            Text("\(selection.count) selected")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Layout

    private var adaptiveColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 140, maximum: 260), spacing: Layout.gridSpacing, alignment: .top)]
    }
}

private struct PageTile: View {
    let page: ComicPage
    let isSelected: Bool
    @State private var cachedImage: Image?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                    .fill(.quinary.opacity(0.4))
                if let image = cachedImage {
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
                } else if page.downloadedFileURL != nil {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.secondary)
                        .task { await loadTileImage() }
                } else {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .padding(24)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(page.title.isEmpty ? "#\(page.index)" : page.title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text(URL(string: page.pageURL)?.host ?? "")
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
    }

    private func loadTileImage() async {
        guard let url = page.downloadedFileURL else { return }
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let maxPixel: CGFloat = 512 // tile thumbnail size
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel),
                    kCGImageSourceCreateThumbnailWithTransform: true
                ]
                let loaded: Image? = {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                          let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                        return nil
                    }
                    return Image(decorative: cgThumb, scale: 1, orientation: .up)
                }()
                DispatchQueue.main.async {
                    self.cachedImage = loaded
                    continuation.resume()
                }
            }
        }
    }
}
