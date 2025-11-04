import SwiftUI

public enum ReadingMode: String, CaseIterable, Codable, Sendable {
    case pager
    case vertical

    var label: String {
        switch self {
        case .pager: return "Pager"
        case .vertical: return "Vertical"
        }
    }
}

private struct ViewportMaxPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ComicReaderView: View {
    let comic: Comic

    // State
    @State private var selection: Int = 0
    @State private var previousSelection: Int = 0
    @State private var pageDirection: PageDirection = .forward
    @State private var isReady: Bool = false
    @State private var flatURLs: [URL] = []
    @State private var loadedIndices: Set<Int> = []
    @State private var preheatTask: Task<Void, Never>?
    @State private var viewportMax: CGFloat = 0
    @State private var progress = ReadingProgress()

    // New state for reading mode and page-based data
    @AppStorage(.settingsReaderMode) private var readerModeRaw: String = ReadingMode.pager.rawValue

    // Per-comic override storage (only when different from global default)
    @State private var perComicOverrideRaw: String?
    private var perComicModeKey: String { "reader.mode." + comic.id.uuidString }
    private var effectiveModeRaw: String { perComicOverrideRaw ?? readerModeRaw }

    private var readerMode: ReadingMode {
        ReadingMode(rawValue: effectiveModeRaw) ?? .pager
    }

    private func setReaderMode(_ mode: ReadingMode) { readerModeRaw = mode.rawValue }

    @MainActor
    private func loadPerComicModeOverride() {
        perComicOverrideRaw = UserDefaults.standard.string(forKey: perComicModeKey)
        // Normalize: if override equals current default, drop it
        if perComicOverrideRaw == readerModeRaw { perComicOverrideRaw = nil; UserDefaults.standard.removeObject(forKey: perComicModeKey) }
    }

    @MainActor
    private func savePerComicModeOverride(_ raw: String?) {
        // Store only if different from default; otherwise remove override
        if let raw, raw != readerModeRaw {
            UserDefaults.standard.set(raw, forKey: perComicModeKey)
            perComicOverrideRaw = raw
        } else {
            UserDefaults.standard.removeObject(forKey: perComicModeKey)
            perComicOverrideRaw = nil
        }
    }

    private func cycleReaderMode() {
        let all = ReadingMode.allCases
        let current = readerMode
        guard let idx = all.firstIndex(of: current) else { savePerComicModeOverride(nil); return }
        let next = all[(idx + 1) % all.count]
        // Persist override only if different from default
        if next.rawValue == readerModeRaw {
            savePerComicModeOverride(nil)
        } else {
            savePerComicModeOverride(next.rawValue)
        }
    }

    @State private var pages: [ComicPage] = []
    @State private var pageImageURLs: [[URL]] = [] // per-page images
    @State private var pageTitles: [String] = []
    @State private var pageToFirstFlatIndex: [Int] = [] // map page index to first flat image index

    @State private var verticalVisiblePageIndex: Int = 0

    // Settings
    @AppStorage(.settingsReaderDownsampleMaxPixel) private var readerDownsampleMaxPixel: Double = 10240
    @AppStorage(.settingsReaderPreloadRadius) private var readerPreloadRadius: Int = 5
    @AppStorage(.settingsVerticalPillarboxEnabled) private var verticalPillarboxEnabled: Bool = false
    @AppStorage(.settingsVerticalPillarboxWidth) private var verticalPillarboxPercent: Double = 0 // 0...50 (% of total width)

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    private var currentPageIndex: Int {
        switch readerMode {
        case .pager:
            guard !pageToFirstFlatIndex.isEmpty else { return 0 }
            let idx = pageToFirstFlatIndex.lastIndex(where: { selection >= $0 }) ?? 0
            return min(idx, max(0, pageTitles.count - 1))
        case .vertical:
            return verticalVisiblePageIndex
        }
    }

    private var navigationTitleText: String {
        let t = pageTitle(at: currentPageIndex)
        return t.isEmpty ? comic.name : "\(comic.name): \(t)"
    }

    // MARK: - Helpers

    private func clampedIndex(_ i: Int) -> Int {
        guard !flatURLs.isEmpty else { return 0 }
        return min(max(0, i), flatURLs.count - 1)
    }

    private var effectivePreloadRadius: Int {
        max(0, min(readerPreloadRadius, 12))
    }

    private var pageSliderBinding: Binding<Double> {
        Binding(
            get: { Double(selection) },
            set: { raw in
                let newIndex = clampedIndex(Int(raw.rounded()))
                let delta = newIndex - selection
                withAnimation(.none) {
                    pageDirection = (abs(delta) > 1) ? .forward : (delta > 0 ? .forward : (delta < 0 ? .backward : .forward))
                    previousSelection = selection
                    selection = newIndex
                }
            }
        )
    }

    // Helper to compute dynamic downsample max pixel for a given viewport
    private func computeDownsampleMaxPixel(for viewport: CGFloat) -> Int {
        let scaled = max(viewport, 1) * displayScale
        return max(256, min(Int(readerDownsampleMaxPixel), Int(scaled)))
    }

    // Helper to provide a URL for a flat image index if it's loaded and in range
    private func urlForFlatIndex(_ idx: Int) -> URL? {
        (loadedIndices.contains(idx) && idx >= 0 && idx < flatURLs.count) ? flatURLs[idx] : nil
    }

    // Map a flat image selection index to its owning page index
    private func pageIndexForImageSelection(_ imageIndex: Int) -> Int {
        guard !pageToFirstFlatIndex.isEmpty else { return 0 }
        let idx = pageToFirstFlatIndex.lastIndex(where: { imageIndex >= $0 }) ?? 0
        return min(idx, max(0, pageTitles.count - 1))
    }

    // Get the first flat image index for a given page index
    private func firstImageIndex(forPage page: Int) -> Int {
        guard page >= 0, page < pageToFirstFlatIndex.count else { return 0 }
        return pageToFirstFlatIndex[page]
    }

    private var progressStore: ReadingProgressStore { ReadingProgressStore(comicName: comic.name, comicURL: comic.url) }

    private var pagerView: some View {
        VStack(spacing: 0) {
            PagerReaderMode(
                count: flatURLs.count,
                selection: $selection,
                previousSelection: previousSelection,
                navDirection: $pageDirection,
                downsampleMaxPixel: { viewport in computeDownsampleMaxPixel(for: viewport) },
                urlForIndex: { idx in urlForFlatIndex(idx) },
                onPrevious: { previousPage() },
                onNext: { nextPage() },
                progress: progress
            )
            .onPreferenceChange(ViewportMaxPreferenceKey.self) { viewportMax = $0 }

            VStack(spacing: 6) {
                HStack {
                    Text("Page")
                    Spacer()
                    Text("\(selection + 1) / \(flatURLs.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: pageSliderBinding,
                    in: 0...Double(max(flatURLs.count - 1, 0)),
                    step: 1
                )
            }
            .font(.subheadline)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var verticalReaderView: some View {
        // Bindings and closures as locals to help the type-checker
        let downsample: (CGFloat) -> Int = { viewport in computeDownsampleMaxPixel(for: viewport) }
        return VerticalReaderMode(
            pages: pages,
            pageImageURLs: pageImageURLs,
            loadedIndices: $loadedIndices,
            viewportMax: $viewportMax,
            displayScale: displayScale,
            downsampleMaxPixel: downsample,
            pillarboxEnabled: $verticalPillarboxEnabled,
            pillarboxPercent: $verticalPillarboxPercent,
            externalVisiblePageIndex: $verticalVisiblePageIndex,
            onVisiblePageChanged: { idx in
                verticalVisiblePageIndex = idx
            },
            progress: progress
        )
    }

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            if !isReady {
                ProgressView()
                    .controlSize(.large)
                    .padding()
            } else if readerMode == .pager && flatURLs.isEmpty {
                ContentUnavailableView(
                    "No pages to read",
                    systemImage: "book.closed",
                    description: Text("This comic has no downloaded images.")
                )
                .padding()
            } else if readerMode == .vertical && pages.isEmpty {
                ContentUnavailableView(
                    "No pages to read",
                    systemImage: "book.closed",
                    description: Text("This comic has no downloaded images.")
                )
                .padding()
            } else {
                Group {
                    if readerMode == .pager {
                        pagerView
                    } else {
                        verticalReaderView
                    }
                }
                .overlay(alignment: .topLeading) {
                    Button { dismiss() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.backward")
                            Text("Back to Library")
                                .fontWeight(.semibold)
                        }
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .padding(.leading, 8)
                }
                .overlay(alignment: .topTrailing) {
                    VStack {
                        Button(action: { cycleReaderMode() }, label: {
                            HStack(spacing: 8) {
                                Image(systemName: readerMode == .pager ? "rectangle.on.rectangle" : "rectangle.split.2x1")
                                Text(readerMode.label)
                                    .fontWeight(.semibold)
                            }
                            .font(.headline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                        })
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                        .accessibilityLabel("Toggle reading mode")
                        .accessibilityHint("Switches between Pager and Vertical modes")

                        HStack(spacing: 8) {
                            Toggle("Pillarbox", isOn: $verticalPillarboxEnabled)
                                .labelsHidden()
                            Slider(value: $verticalPillarboxPercent, in: 0...50, step: 1)
                                .frame(width: 140)
                            Text("\(Int(verticalPillarboxPercent))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                    }
                }
            }
        }
        .navigationTitle(navigationTitleText)
        .toolbar(.hidden, for: .automatic)
        .task {
            await MainActor.run { loadPerComicModeOverride() }
            // Build page-based arrays + flat arrays for pager
            let sortedPages = comic.pages.sorted { $0.index < $1.index }
            var perPageURLs: [[URL]] = []
            var titles: [String] = []
            var flat: [URL] = []
            var firstIndex: [Int] = []
            var running = 0
            for page in sortedPages {
                let urls = page.images.sorted { $0.index < $1.index }.compactMap { $0.fileURL }
                perPageURLs.append(urls)
                titles.append(page.title)
                firstIndex.append(running)
                running += urls.count
                flat.append(contentsOf: urls)
            }
            let restored = progressStore.load(totalPages: titles.count, totalImages: flat.count, pageToFirstFlatIndex: firstIndex)
            let restoredPage = restored.page

            await MainActor.run {
                self.pages = sortedPages
                self.pageImageURLs = perPageURLs
                self.pageTitles = titles
                self.pageToFirstFlatIndex = firstIndex
                self.flatURLs = flat
            }
            await MainActor.run {
                progress.configureTotals(pages: titles.count, images: flat.count)
            }

            let restoredImageIndex = min(max(0, (restoredPage < firstIndex.count ? firstIndex[restoredPage] : 0)), max(flat.count - 1, 0))
            await ensureLoadedWindow(around: restoredImageIndex, radius: effectivePreloadRadius)

            await MainActor.run { self.isReady = true }

            await Task.yield()

            await MainActor.run {
                withAnimation(.none) {
                    self.pageDirection = .forward
                    self.previousSelection = restoredImageIndex
                    self.selection = restoredImageIndex
                    self.verticalVisiblePageIndex = min(max(0, restoredPage), max(titles.count - 1, 0))
                    progress.updatePage(restoredPage)
                    progress.updateImageIndex(restoredImageIndex)
                }
            }
        }
        .onChange(of: selection) { _, newValue in
            preheatTask?.cancel()
            preheatTask = Task {
                await ensureLoadedWindow(around: newValue, radius: effectivePreloadRadius)
                await MainActor.run {
                    if readerMode == .pager {
                    }
                    // Keep vertical state in sync with pager selection
                    verticalVisiblePageIndex = currentPageIndex
                    progress.updateImageIndex(newValue)
                    progressStore.save(progress: progress)
                }
            }
        }
        .onChange(of: verticalVisiblePageIndex) { _, newValue in
            Task { @MainActor in
                // Removed savePersistedPage(newValue)
                // Warm images around the first image index of the visible page
                if newValue >= 0, newValue < pageToFirstFlatIndex.count {
                    let centerIndex = pageToFirstFlatIndex[newValue]
                    await ensureLoadedWindow(around: centerIndex, radius: effectivePreloadRadius)
                }
                // Keep pager selection in sync with vertical page (no UI impact while in vertical)
                if newValue >= 0, newValue < pageToFirstFlatIndex.count {
                    let imgIndex = pageToFirstFlatIndex[newValue]
                    previousSelection = selection
                    selection = min(max(0, imgIndex), max(flatURLs.count - 1, 0))
                }
                progress.updatePage(newValue)
                progressStore.save(progress: progress)
            }
        }
        .onChange(of: effectiveModeRaw) { oldRaw, newRaw in
            // Compute source page from the PREVIOUS mode, then map into the new mode.
            let oldMode = ReadingMode(rawValue: oldRaw) ?? .pager
            let newMode = ReadingMode(rawValue: newRaw) ?? .pager

            let sourcePage: Int = {
                switch oldMode {
                case .pager:
                    return pageIndexForImageSelection(selection)
                case .vertical:
                    return min(max(0, verticalVisiblePageIndex), max(pageTitles.count - 1, 0))
                }
            }()

            Task { @MainActor in
                if newMode == .pager {
                    // Jump pager selection to the first image of the source page
                    let imgIndex = firstImageIndex(forPage: sourcePage)
                    withAnimation(.none) {
                        previousSelection = selection
                        selection = min(max(0, imgIndex), max(flatURLs.count - 1, 0))
                        pageDirection = .forward
                    }
                    await ensureLoadedWindow(around: selection, radius: effectivePreloadRadius)
                    progress.updateImageIndex(selection)
                    progress.updatePage(sourcePage)
                    progressStore.save(progress: progress)
                    // Keep vertical page in sync as well
                    verticalVisiblePageIndex = min(max(0, sourcePage), max(pageTitles.count - 1, 0))
                } else {
                    // Vertical mode: show the same page and warm around it
                    verticalVisiblePageIndex = min(max(0, sourcePage), max(pageTitles.count - 1, 0))
                    progress.updatePage(sourcePage)
                    progressStore.save(progress: progress)
                    if sourcePage >= 0, sourcePage < pageToFirstFlatIndex.count {
                        let centerIndex = pageToFirstFlatIndex[sourcePage]
                        await ensureLoadedWindow(around: centerIndex, radius: effectivePreloadRadius)
                    }
                }
            }
        }
        .onKeyPress(.leftArrow) {
            if readerMode == .pager {
                previousPage()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            if readerMode == .pager {
                nextPage()
                return .handled
            }
            return .ignored
        }
        .onDisappear {
            preheatTask?.cancel()
            Task { @MainActor in
                progressStore.save(progress: progress)
            }
        }
    }

    // MARK: - Window Loading

    private func ensureLoadedWindow(around index: Int, radius: Int) async {
        guard !flatURLs.isEmpty else { return }
        if Task.isCancelled { return }

        // Snapshot state on main actor to avoid data races.
        let (urls, currentLoaded): ([URL], Set<Int>) = await MainActor.run {
            (self.flatURLs, self.loadedIndices)
        }

        let radius = max(0, radius)
        let lower = max(0, index - radius)
        let upper = min(urls.count - 1, index + radius)
        let target = Set(lower...upper)

        // Eagerly ensure current index is available for immediate display
        if !currentLoaded.contains(index) {
            _ = await MainActor.run { loadedIndices.insert(index) }
        }
        if Task.isCancelled { return }

        // Load missing indices in the target window
        let toLoad = target.subtracting(currentLoaded)
        let loadedPairs: [(Int, URL)] = toLoad.compactMap { i in
            (i >= 0 && i < urls.count) ? (i, urls[i]) : nil
        }
        await MainActor.run {
            for (i, _) in loadedPairs { loadedIndices.insert(i) }
        }
        if Task.isCancelled { return }

        // Compute dynamic decode size based on viewport and display scale
        let basePixels: CGFloat = (viewportMax > 0) ? (viewportMax * displayScale) : CGFloat(readerDownsampleMaxPixel)
        let dyn = min(Int(readerDownsampleMaxPixel), Int(basePixels))
        let maxPixel = max(256, dyn)

        let batchSize = 6
        let count = loadedPairs.count
        var start = 0
        while start < count {
            if Task.isCancelled { return }
            let end = min(start + batchSize, count)
            let chunk = loadedPairs[start..<end]
            await withTaskGroup(of: Void.self) { group in
                for (_, url) in chunk {
                    group.addTask {
                        await CGImageLoader.warm(url: url, maxPixel: maxPixel)
                    }
                }
                await group.waitForAll()
            }
            start = end
        }
        if Task.isCancelled { return }

        // Evict outside of window using a fresh snapshot
        await MainActor.run {
            let current = self.loadedIndices
            let outside = current.subtracting(target)
            if !outside.isEmpty {
                self.loadedIndices.subtract(outside)
            }
        }
    }

    private func nextPage() {
        guard !flatURLs.isEmpty else { return }
        withAnimation(.snappy) {
            pageDirection = .forward
            previousSelection = selection
            selection = min(selection + 1, flatURLs.count - 1)
        }
    }

    private func previousPage() {
        guard !flatURLs.isEmpty else { return }
        withAnimation(.snappy) {
            pageDirection = .backward
            previousSelection = selection
            selection = max(selection - 1, 0)
        }
    }

    private func pageTitle(at index: Int) -> String {
        guard index >= 0, index < pageTitles.count else { return "" }
        return pageTitles[index]
    }
}
