import SwiftUI
import Foundation
import ZIPFoundation

// MARK: - FileView
/// Primary view for inspecting a selected comic file: shows the cover, statistics, and editable metadata.
struct FileView: View {
    @Binding var comicInfoData: ComicInfoModel?
    @Binding var fileURL: URL?
    @StateObject var viewModel = FileViewModel()
    @StateObject var comicInfoEdited: ComicInfoModel = .init()
    @State private var communityRatingValue: Int = 0
    @State private var statisticsCopyTrigger: Int = 0

    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    @State private var currentIndex: Int = 0
    @State private var scopedURL: URL?

    // Callback to notify the parent when opening/processing fails
    var onOpenFailed: ((URL) -> Void)?
    var onOpenSucceeded: ((URL) -> Void)?

    /// Extracts a cover image (direct image or archive entry) for the currently selected file.
    private var coverImage: Image? {
        guard let fileURL else { return nil }

        // Always treat as archive
        return ComicArchive(fileURL: fileURL).coverImage()
    }

    private func beginSecurityScope(for url: URL) -> Bool {
        if let scopedURL, scopedURL == url { return true }
        if let scopedURL { scopedURL.stopAccessingSecurityScopedResource() }
        let ok = url.startAccessingSecurityScopedResource()
        if ok { scopedURL = url }
        return ok
    }

    private func endSecurityScope() {
        if let scopedURL {
            scopedURL.stopAccessingSecurityScopedResource()
            self.scopedURL = nil
        }
    }

    private func prepareEditableModel(from url: URL?) {
        if comicInfoData == nil {
            if let url, let info = ComicArchive(fileURL: url).getComicInfoData(), info.parse() {
                comicInfoEdited.overwrite(from: info.parsed)
                communityRatingValue = comicInfoEdited.CommunityRating?.rawValue ?? 0
            }
        } else if let model = comicInfoData {
            comicInfoEdited.overwrite(from: model)
            communityRatingValue = comicInfoEdited.CommunityRating?.rawValue ?? 0
        }
    }

    private func ensurePagesCoverAllImages(from url: URL) {
        let archive = ComicArchive(fileURL: url)
        let total = archive.pageCount()
        guard total > 0 else { return }

        var finalPages = Array(repeating: ComicPageInfo(), count: total)
        if let existing = comicInfoEdited.Pages, !existing.isEmpty {
            let hasExplicitIndices = existing.contains { Int($0.Image) != nil }
            if hasExplicitIndices {
                for p in existing {
                    if let idx = Int(p.Image), idx >= 0, idx < total { finalPages[idx] = p }
                }
            } else {
                for (i, p) in existing.enumerated() where i < total { finalPages[i] = p }
            }
        } else {
            for i in 0..<total { finalPages[i].Image = String(i) }
        }
        comicInfoEdited.Pages = finalPages
        comicInfoEdited.PageCount = total
    }

    private func initialize(from url: URL?) {
        // Reset basics
        viewModel.pageCount = viewModel.computePageCount(for: url)
        viewModel.fileSize = viewModel.computeFileSize(for: url)

        guard let url else {
            // Clear when no file is selected and end scope
            viewModel.md5Hex = ""
            viewModel.sha1Hex = ""
            viewModel.crc32Hex = ""
            endSecurityScope()
            return
        }

        guard beginSecurityScope(for: url) else {
            onOpenFailed?(url)
            return
        }

        // Sanity check: ensure the archive can be opened
        do {
            _ = try Archive(url: url, accessMode: .read)
            onOpenSucceeded?(url)
        } catch {
            onOpenFailed?(url)
            return
        }

        // Parse ComicInfo.xml or use provided model
        prepareEditableModel(from: url)

        // Ensure Pages covers all images in the archive
        ensurePagesCoverAllImages(from: url)

        // Defer hash computation slightly to avoid hitching
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            await viewModel.refreshHashes(for: url)
        }
    }

    var body: some View {
        ZStack {
            // Background gradient (match MainView)
            LinearGradient(colors: [
                Color.accentColor.opacity(0.25),
                Color.purple.opacity(0.20),
                Color.indigo.opacity(0.20)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()

            // Content container
            VStack {
                HStack {
                    Button {
                        // Clear selection to return to MainView
                        fileURL = nil
                    } label: {
                        Label("Back to Library", systemImage: "chevron.left")
                            .font(.headline)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

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
                                StatisticsRow(
                                    title: "Page Count",
                                    value: String(viewModel.pageCount),
                                    copyHelp: "Copy Page Count",
                                    copyTrigger: $statisticsCopyTrigger,
                                    copyAction: viewModel.copyToPasteboard
                                )
                                StatisticsRow(
                                    title: "File Size",
                                    value: viewModel.fileSize,
                                    copyHelp: "Copy File Size",
                                    copyTrigger: $statisticsCopyTrigger,
                                    copyAction: viewModel.copyToPasteboard
                                )
                                StatisticsRow(
                                    title: "MD5",
                                    value: viewModel.md5Hex,
                                    copyHelp: "Copy MD5",
                                    copyTrigger: $statisticsCopyTrigger,
                                    copyAction: viewModel.copyToPasteboard
                                )
                                StatisticsRow(
                                    title: "SHA-1",
                                    value: viewModel.sha1Hex,
                                    copyHelp: "Copy SHA-1",
                                    copyTrigger: $statisticsCopyTrigger,
                                    copyAction: viewModel.copyToPasteboard
                                )
                                StatisticsRow(
                                    title: "CRC32",
                                    value: viewModel.crc32Hex,
                                    copyHelp: "Copy CRC32",
                                    copyTrigger: $statisticsCopyTrigger,
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
                        .padding()
                    }

                }
            }
            .padding()
        }
        .onAppear {
            // Initialize editable model and derived values when the view appears.
            if let model = comicInfoData {
                comicInfoEdited.overwrite(from: model)
            } else {
                comicInfoEdited.overwrite(from: ComicInfoModel())
            }
            viewModel.pageCount = viewModel.computePageCount(for: fileURL)
            viewModel.fileSize = viewModel.computeFileSize(for: fileURL)

            initialize(from: fileURL)
        }
        .onChange(of: fileURL) { _, newValue in
            initialize(from: newValue)
        }
        .onChange(of: comicInfoData.map { ObjectIdentifier($0) }) { _, _ in
            if let model = comicInfoData {
                comicInfoEdited.overwrite(from: model)
            } else {
                comicInfoEdited.overwrite(from: ComicInfoModel())
            }
            communityRatingValue = comicInfoEdited.CommunityRating?.rawValue ?? 0
        }
        .onDisappear {
            endSecurityScope()
        }
    }
}

extension FileView {
    func onOpenFailed(_ action: @escaping (URL) -> Void) -> FileView {
        var copy = self
        copy.onOpenFailed = action
        return copy
    }
}

extension FileView {
    func onOpenSucceeded(_ action: @escaping (URL) -> Void) -> FileView {
        var copy = self
        copy.onOpenSucceeded = action
        return copy
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
        pageDetailItems().filter { [Constants.imageWidth, Constants.imageHeight, Constants.imageSize, Constants.isCover].contains($0.0) }
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
