import SwiftUI
import Foundation

// MARK: - FileView
/// Primary view for inspecting a selected comic file: shows the cover, statistics, and editable metadata.
struct FileView: View {
    @Binding var comicInfoData: ComicInfoModel?
    @Binding var fileURL: URL?
    @StateObject var viewModel = FileViewModel()
    @StateObject var comicInfoEdited: ComicInfoModel = .init()
    @State private var communityRatingValue: Int = 0
    @State private var md5CopyTrigger: Int = 0

    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    @State private var currentIndex: Int = 0

    /// Extracts a cover image (direct image or archive entry) for the currently selected file.
    private var coverImage: Image? {
        guard let fileURL else { return nil }

        // Always treat as archive
        return ComicArchive(fileURL: fileURL).coverImage()
    }

    var body: some View {
        VStack {
            HStack(alignment: .top, spacing: 16) {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    VStack(alignment: .leading, spacing: 12) {
                        GroupBox("Cover Image") {
                            CoverImageView(image: coverImage)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.leading)

                        Spacer()

                        GroupBox("Statistics") {
                            LabeledContent("Page Count") {
                                HStack(spacing: 8) {
                                    Text("\(viewModel.pageCount)")
                                        .monospacedDigit()
                                        .padding(.leading)
                                }
                            }
                            DigestRow(
                                title: "MD5",
                                value: viewModel.md5Hex,
                                copyHelp: "Copy MD5",
                                copyTrigger: $md5CopyTrigger,
                                copyAction: viewModel.copyToPasteboard
                            )
                            DigestRow(
                                title: "SHA-1",
                                value: viewModel.sha1Hex,
                                copyHelp: "Copy SHA-1",
                                copyTrigger: $md5CopyTrigger,
                                copyAction: viewModel.copyToPasteboard
                            )
                            DigestRow(
                                title: "CRC32",
                                value: viewModel.crc32Hex,
                                copyHelp: "Copy CRC32",
                                copyTrigger: $md5CopyTrigger,
                                copyAction: viewModel.copyToPasteboard
                            )
                        }
                        .padding(.all)
                    }
                    .frame(width: 260, alignment: .top)
                } detail: {
                    TabView {
                        BookInformationForm(comicInfo: comicInfoEdited, communityRatingValue: $communityRatingValue)
                            .tabItem { Label("Info", systemImage: "info.circle") }

                        PagesTabView(fileURL: fileURL, pages: $comicInfoEdited.Pages, currentIndex: $currentIndex)
                            .tabItem { Label("Pages", systemImage: "photo.on.rectangle") }
                    }
                }

            }
        }
        .onAppear {
            // Initialize editable model and derived values when the view appears.
            if let model = comicInfoData {
                comicInfoEdited.overwrite(from: model)
            } else {
                comicInfoEdited.overwrite(from: ComicInfoModel())
            }
            communityRatingValue = comicInfoEdited.CommunityRating?.rawValue ?? 0
            viewModel.pageCount = viewModel.computePageCount(for: fileURL)
            if let fileURL {
                Task {
                    await viewModel.refreshHashes(for: fileURL)
                }
            }
        }
        .onChange(of: fileURL) { oldValue, newValue in
            viewModel.pageCount = viewModel.computePageCount(for: newValue)
            if let newValue {
                Task {
                    await viewModel.refreshHashes(for: newValue)
                }
            } else {
                // Clear hash values when no file is selected
                viewModel.md5Hex = ""
                viewModel.sha1Hex = ""
                viewModel.crc32Hex = ""
            }
        }
        .onChange(of: comicInfoData.map { ObjectIdentifier($0) }) { _, _ in
            if let model = comicInfoData {
                comicInfoEdited.overwrite(from: model)
            } else {
                comicInfoEdited.overwrite(from: ComicInfoModel())
            }
            communityRatingValue = comicInfoEdited.CommunityRating?.rawValue ?? 0
        }
    }
}

// MARK: - PagesTabView
/// Displays the image for each page and lets the user navigate with a slider.
private struct PagesTabView: View {
    let fileURL: URL?
    @Binding var pages: [ComicPageInfo]?
    @Binding var currentIndex: Int // zero-based

    private enum Constants {
        static let imageWidth = "Image Width"
        static let imageHeight = "Image Height"
        static let imageSize = "Image Size"
        static let isCover = "Is Cover"
    }

    private var pageInput: Binding<Int> {
        Binding(
            get: { Int(currentIndex + 1) },
            set: { currentIndex = $0 - 1 }
        )
    }

    private var pageProvider: PageDetailProvider? {
        guard let fileURL else { return nil }
        return PageDetailProvider(fileURL: fileURL, pages: pages)
    }

    private func totalPages() -> Int {
        (pages?.count).map { $0 } ?? 0
    }

    @ViewBuilder
    private func currentImageView() -> some View {
        if let pageProvider {
            if let image = pageProvider.image(atZeroBased: clampedIndex) {
                image.resizable().scaledToFit()
            } else {
                ContentUnavailableView("No Image", systemImage: "photo")
            }
        } else {
            ContentUnavailableView("No File", systemImage: "photo")
        }
    }

    private var clampedIndex: Int { min(max(0, currentIndex), maxIndex) }

    private var maxIndex: Int { max(0, totalPages() - 1) }

    private var currentPageInfo: ComicPageInfo? {
        guard let p = pages, !p.isEmpty else { return nil }
        let idx = min(clampedIndex, p.count - 1)
        return p[idx]
    }

    private func pageDetailItems() -> [(String, String)] {
        var items: [(String, String)] = []

        if let p = currentPageInfo {
            items.append(("Image Index", valueOrDash(p.Image)))
            items.append(("Page Type", p.PageType.rawValue))
            items.append(("Bookmark", valueOrDash(p.Bookmark)))
            items.append(("Double Page", p.DoublePage ? "Yes" : "No"))

            if let metrics = pageProvider?.imageMetrics(atZeroBased: clampedIndex) {
                items.append((Constants.imageWidth, metrics.width > 0 ? "\(metrics.width) px" : "—"))
                items.append((Constants.imageHeight, metrics.height > 0 ? "\(metrics.height) px" : "—"))
                items.append((Constants.imageSize, metrics.size > 0 ? formatBytes(metrics.size) : "—"))
            } else {
                items.append((Constants.imageWidth, "—"))
                items.append((Constants.imageHeight, "—"))
                items.append((Constants.imageSize, "—"))
            }

            items.append(("Key", valueOrDash(p.Key)))
        } else {
            items.append(("Image Index", "\(clampedIndex + 1)"))
            if let metrics = pageProvider?.imageMetrics(atZeroBased: clampedIndex) {
                items.append((Constants.imageWidth, metrics.width > 0 ? "\(metrics.width) px" : "—"))
                items.append((Constants.imageHeight, metrics.height > 0 ? "\(metrics.height) px" : "—"))
                items.append((Constants.imageSize, metrics.size > 0 ? formatBytes(metrics.size) : "—"))
            }
        }

        if let pageProvider {
            let isCover = pageProvider.isCover(atZeroBased: clampedIndex)
            items.append((Constants.isCover, isCover ? "Yes" : "No"))
        }

        return items
    }

    private func readOnlyPageDetailItems() -> [(String, String)] {
        // Keep only the computed, read-only items for display
        return pageDetailItems().filter { [Constants.imageWidth, Constants.imageHeight, Constants.imageSize, Constants.isCover].contains($0.0) }
    }

    private func pageFieldBinding<T>(_ keyPath: WritableKeyPath<ComicPageInfo, T>, default defaultValue: T) -> Binding<T> {
        Binding(
            get: {
                if let p = pages, !p.isEmpty, clampedIndex < p.count {
                    return p[clampedIndex][keyPath: keyPath]
                }
                return defaultValue
            },
            set: { newValue in
                var p = pages ?? []
                if clampedIndex >= p.count {
                    let needed = clampedIndex + 1 - p.count
                    p.append(contentsOf: Array(repeating: ComicPageInfo(), count: needed))
                }
                p[clampedIndex][keyPath: keyPath] = newValue
                pages = p
            }
        )
    }

    private func pageHasMeaningfulValues(at index: Int) -> Bool {
        guard let p = pages, index >= 0, index < p.count else { return false }
        let page = p[index]
        // Consider a page as having non-default values if any of these differ from defaults
        return page.PageType != .Story || !page.Bookmark.isEmpty || page.DoublePage || !page.Key.isEmpty
    }

    private var headerText: String {
        let currentPage = clampedIndex + 1
        let totalPageCount = max(totalPages(), 1)
        return "Page \(currentPage) of \(totalPageCount)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                Text(headerText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Image + Details
            HStack(alignment: .top, spacing: 12) {
                ReaderView(currentIndex: $currentIndex, totalPages: totalPages(), maxIndex: maxIndex) {
                    currentImageView()
                } pageHasMeaningfulValues: { i in
                    pageHasMeaningfulValues(at: i)
                }

                VStack(spacing: 16) {
                    GroupBox("Page Editor") {
                        DetailFormView(
                            pageType: pageFieldBinding(\ComicPageInfo.PageType, default: .Story),
                            bookmark: pageFieldBinding(\ComicPageInfo.Bookmark, default: ""),
                            doublePage: pageFieldBinding(\ComicPageInfo.DoublePage, default: false),
                            key: pageFieldBinding(\ComicPageInfo.Key, default: "")
                        )
                        .padding(.top, 4)
                    }

                    GroupBox("Page Metrics") {
                        VStack(spacing: 8) {
                            ForEach(readOnlyPageDetailItems(), id: \.0) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(item.0)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .help(item.0)
                                    Text(item.1)
                                        .monospacedDigit()
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .padding(.vertical, 4)
                                Divider()
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: 300)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        .onAppear {
            currentIndex = 0
        }
        .onChange(of: pages) { _, _ in
            currentIndex = 0
        }
        .onChange(of: fileURL) { _, _ in
            currentIndex = 0
        }
        .onChange(of: currentIndex) { _, _ in
            // Redundant clamp/snap to keep index tight even if updated elsewhere
            let snapped = min(max(0, Int(Double(currentIndex).rounded())), maxIndex)
            if snapped != currentIndex {
                let transaction = Transaction(animation: nil)
                withTransaction(transaction) {
                    currentIndex = snapped
                }
            }
        }
    }

    private func valueOrDash(_ s: String) -> String { s.isEmpty ? "—" : s }

    private func formatBytes(_ bytes: Int64) -> String {
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        return fmt.string(fromByteCount: bytes)
    }
}
