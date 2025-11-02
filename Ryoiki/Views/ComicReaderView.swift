import SwiftUI
import ImageIO

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

private enum PageDirection: Int { case forward, backward }

private struct ViewportMaxPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct VisiblePagePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:] // [pageIndex: distanceToCenter]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        // Merge latest measurements; prefer the most recent values
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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
    @State private var flatTitles: [String] = []
    @State private var loadedIndices: Set<Int> = []
    @State private var preheatTask: Task<Void, Never>?
    @State private var viewportMax: CGFloat = 0

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
    @AppStorage(.settingsReaderDownsampleMaxPixel) private var readerDownsampleMaxPixel: Double = 2048
    @AppStorage(.settingsReaderPreloadRadius) private var readerPreloadRadius: Int = 5
    @AppStorage(.settingsVerticalPillarboxEnabled) private var verticalPillarboxEnabled: Bool = false
    @AppStorage(.settingsVerticalPillarboxWidth) private var verticalPillarboxPercent: Double = 0 // 0...50 (% of total width)

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    private var currentPageIndex: Int {
        switch readerMode {
        case .pager:
            // Map current image selection to owning page index using pageToFirstFlatIndex
            // Find greatest page whose firstFlatIndex <= selection
            guard !pageToFirstFlatIndex.isEmpty else { return 0 }
            var idx = 0
            for (p, start) in pageToFirstFlatIndex.enumerated() {
                if selection >= start { idx = p } else { break }
            }
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
        let dyn = min(Int(readerDownsampleMaxPixel), Int(scaled))
        return max(256, dyn)
    }

    // Helper to provide a URL for a flat image index if it's loaded and in range
    private func urlForFlatIndex(_ idx: Int) -> URL? {
        (loadedIndices.contains(idx) && idx >= 0 && idx < flatURLs.count) ? flatURLs[idx] : nil
    }

    // Map a flat image selection index to its owning page index
    private func pageIndexForImageSelection(_ imageIndex: Int) -> Int {
        guard !pageToFirstFlatIndex.isEmpty else { return 0 }
        var idx = 0
        for (p, start) in pageToFirstFlatIndex.enumerated() {
            if imageIndex >= start { idx = p } else { break }
        }
        return min(idx, max(0, pageTitles.count - 1))
    }

    // Get the first flat image index for a given page index
    private func firstImageIndex(forPage page: Int) -> Int {
        guard page >= 0, page < pageToFirstFlatIndex.count else { return 0 }
        return pageToFirstFlatIndex[page]
    }

    private var pagerView: some View {
        VStack(spacing: 0) {
            ReaderPager(
                count: flatURLs.count,
                selection: $selection,
                previousSelection: previousSelection,
                navDirection: $pageDirection,
                downsampleMaxPixel: { viewport in computeDownsampleMaxPixel(for: viewport) },
                urlForIndex: { idx in urlForFlatIndex(idx) },
                onPrevious: { previousPage() },
                onNext: { nextPage() }
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
        return VerticalReader(
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
            }
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
            let restoredPage: Int = await MainActor.run { loadPersistedPageSelection(totalPages: titles.count) }

            await MainActor.run {
                self.pages = sortedPages
                self.pageImageURLs = perPageURLs
                self.pageTitles = titles
                self.pageToFirstFlatIndex = firstIndex
                self.flatURLs = flat
                self.flatTitles = flat.map { _ in "" } // keep length aligned; titles now per-page
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
                }
            }
        }
        .onChange(of: selection) { _, newValue in
            preheatTask?.cancel()
            preheatTask = Task {
                await ensureLoadedWindow(around: newValue, radius: effectivePreloadRadius)
                await MainActor.run {
                    savePersistedSelection(newValue)
                    if readerMode == .pager {
                        savePersistedPage(currentPageIndex)
                    }
                    // Keep vertical state in sync with pager selection
                    verticalVisiblePageIndex = currentPageIndex
                }
            }
        }
        .onChange(of: verticalVisiblePageIndex) { _, newValue in
            Task { @MainActor in
                savePersistedPage(newValue)
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
                savePersistedPage(sourcePage)
                if newMode == .pager {
                    // Jump pager selection to the first image of the source page
                    let imgIndex = firstImageIndex(forPage: sourcePage)
                    withAnimation(.none) {
                        previousSelection = selection
                        selection = min(max(0, imgIndex), max(flatURLs.count - 1, 0))
                        pageDirection = .forward
                    }
                    await ensureLoadedWindow(around: selection, radius: effectivePreloadRadius)
                    savePersistedSelection(selection)
                    // Keep vertical page in sync as well
                    verticalVisiblePageIndex = min(max(0, sourcePage), max(pageTitles.count - 1, 0))
                } else {
                    // Vertical mode: show the same page and warm around it
                    verticalVisiblePageIndex = min(max(0, sourcePage), max(pageTitles.count - 1, 0))
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
                savePersistedSelection(selection)
                savePersistedPage(currentPageIndex)
            }
        }
    }

    // MARK: - Persistence (current page)

    private var persistedSelectionKey: String {
        "reader.selection.\(comic.name)|\(comic.url)"
    }

    private var persistedPageKey: String {
        "reader.page.\(comic.name)|\(comic.url)"
    }

    @MainActor
    private func loadPersistedSelection(totalCount: Int) -> Int {
        let raw = UserDefaults.standard.object(forKey: persistedSelectionKey) as? Int
        guard let raw, totalCount > 0 else { return 0 }
        return min(max(0, raw), totalCount - 1)
    }

    @MainActor
    private func savePersistedSelection(_ index: Int) {
        UserDefaults.standard.set(index, forKey: persistedSelectionKey)
    }

    @MainActor
    private func loadPersistedPageSelection(totalPages: Int) -> Int {
        if let raw = UserDefaults.standard.object(forKey: persistedPageKey) as? Int, totalPages > 0 {
            return min(max(0, raw), totalPages - 1)
        }
        // Back-compat: if old image index exists, map to page
        if let old = UserDefaults.standard.object(forKey: persistedSelectionKey) as? Int, totalPages > 0, !pageToFirstFlatIndex.isEmpty {
            var pageIdx = 0
            for (p, start) in pageToFirstFlatIndex.enumerated() {
                if old >= start { pageIdx = p } else { break }
            }
            return min(max(0, pageIdx), totalPages - 1)
        }
        return 0
    }

    @MainActor
    private func savePersistedPage(_ pageIndex: Int) {
        UserDefaults.standard.set(pageIndex, forKey: persistedPageKey)
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

        // Compute dynamic decode size and cap concurrency via chunking
        let basePixels: CGFloat = (viewportMax > 0) ? (viewportMax * displayScale) : CGFloat(readerDownsampleMaxPixel)
        let dyn = min(Int(readerDownsampleMaxPixel), Int(basePixels))
        let maxPixel = max(256, dyn)
        let batchSize = 6
        for chunk in loadedPairs.chunked(into: batchSize) {
            if Task.isCancelled { return }
            await withTaskGroup(of: Void.self) { group in
                for (_, url) in chunk {
                    group.addTask {
                        await CGImageLoader.warm(url: url, maxPixel: maxPixel)
                    }
                }
                await group.waitForAll()
            }
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

// MARK: - Reader Pager

private struct ReaderPager: View {
    let count: Int
    @Binding var selection: Int
    var previousSelection: Int
    @Binding var navDirection: PageDirection
    var downsampleMaxPixel: (CGFloat) -> Int
    var urlForIndex: (Int) -> URL?
    var onPrevious: () -> Void
    var onNext: () -> Void

    @State private var isZoomed: Bool = false
    @State private var slideProgress: CGFloat = 1
    @State private var activeDirection: PageDirection = .forward

    @State private var displayedIndex: Int = 0
    @State private var phase: Int = 0 // 0: steady, 1: sliding out, 2: sliding in
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            let viewportMax = max(proxy.size.width, proxy.size.height)

            ZStack {
                let width = proxy.size.width
                // Compute animation parameters for single view
                let isSlidingOut = phase == 1
                let isSlidingIn = phase == 2
                let dirSign: CGFloat = (activeDirection == .forward ? 1 : -1)
                let offsetX: CGFloat = {
                    if isSlidingOut {
                        // Push a bit farther than one width for stronger parallax
                        return -dirSign * width * (1.10 * slideProgress)
                    } else if isSlidingIn {
                        // Start farther out and settle to center
                        return dirSign * width * (1.60 * (1 - slideProgress))
                    } else {
                        return 0
                    }
                }()
                let opacityVal: Double = {
                    if isSlidingOut {
                        return max(0, 1 - 0.55 * Double(slideProgress)) // 1 -> 0.45
                    } else if isSlidingIn {
                        return min(1, 0.55 + 0.45 * Double(slideProgress)) // 0.55 -> 1
                    } else {
                        return 1
                    }
                }()
                let scaleVal: CGFloat = {
                    if isSlidingOut {
                        return 1 - 0.50 * slideProgress // 1 -> 0.5
                    } else if isSlidingIn {
                        return 0.94 + 0.06 * slideProgress // 0.94 -> 1.0
                    } else {
                        return 1
                    }
                }()
                let blurVal: CGFloat = {
                    if isSlidingOut {
                        return 0 + 2 * slideProgress // up to 2pt blur
                    } else if isSlidingIn {
                        return max(0, 2 * (1 - slideProgress)) // 2 -> 0
                    } else {
                        return 0
                    }
                }()
                let shadowRadius: CGFloat = {
                    if isSlidingIn {
                        return 8 * slideProgress // subtle lift while arriving
                    } else {
                        return 0
                    }
                }()
                let shadowOpacity: Double = {
                    if isSlidingIn {
                        return 0.25 * Double(slideProgress)
                    } else {
                        return 0
                    }
                }()
                let rotationDeg: Double = {
                    // Subtle Y-axis tilt that follows direction
                    if isSlidingOut {
                        return Double(-dirSign * 8 * slideProgress)
                    } else if isSlidingIn {
                        return Double(dirSign * 8 * (1 - slideProgress))
                    } else {
                        return 0
                    }
                }()

                if let url = urlForIndex(displayedIndex) {
                    ZoomablePage(
                        url: url,
                        targetMaxPixel: downsampleMaxPixel(viewportMax),
                        isZoomed: $isZoomed
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .offset(x: offsetX)
                    .opacity(opacityVal)
                    .scaleEffect(scaleVal)
                    .blur(radius: blurVal)
                    .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: 4)
                    .rotation3DEffect(.degrees(rotationDeg), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
                    .id(url)
                } else {
                    ReaderPlaceholder(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .offset(x: offsetX)
                        .opacity(opacityVal)
                        .scaleEffect(scaleVal)
                        .blur(radius: blurVal)
                        .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: 4)
                        .rotation3DEffect(.degrees(rotationDeg), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
                        .id("placeholder-\(displayedIndex)")
                }
            }
            .onAppear {
                activeDirection = navDirection
                displayedIndex = selection
                slideProgress = 1
                phase = 0
            }
            .onChange(of: selection) { _, newValue in
                guard newValue != displayedIndex else { return }

                // Cancel any in-flight animation task and immediately settle the previous animation state.
                animationTask?.cancel()
                animationTask = nil
                withAnimation(.none) {
                    // Force settle whatever phase was in progress so we have a clean slate.
                    phase = 0
                    slideProgress = 1
                }

                // Start a fresh, cancelable animation sequence for the new selection.
                animationTask = Task { @MainActor in
                    if Task.isCancelled { return }

                    activeDirection = navDirection

                    // Slide out current content
                    phase = 1
                    slideProgress = 0
                    withAnimation(.easeIn(duration: 0.18)) {
                        slideProgress = 1
                    }

                    // Wait for the slide-out to mostly complete, but bail if cancelled.
                    do { try await Task.sleep(nanoseconds: 180_000_000) } catch { return }
                    if Task.isCancelled { return }

                    // Swap content and slide in from the correct edge
                    displayedIndex = newValue
                    isZoomed = false

                    phase = 2
                    slideProgress = 0
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.85)) {
                        slideProgress = 1
                    }

                    // Wait for the slide-in to settle, but bail if cancelled.
                    do { try await Task.sleep(nanoseconds: 360_000_000) } catch { return }
                    if Task.isCancelled { return }

                    // Final settle
                    phase = 0
                    slideProgress = 1
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(
                GeometryReader { gp in
                    Color.clear
                        .preference(key: ViewportMaxPreferenceKey.self,
                                    value: max(gp.size.width, gp.size.height))
                }
            )
            .accessibilityLabel(Text("Comic Reader"))
            .accessibilityValue(Text("Page \(selection + 1) of \(count)"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onNext()
                case .decrement: onPrevious()
                default: break
                }
            }
            .accessibilityScrollAction { edge in
                switch edge {
                case .trailing: onNext()
                case .leading: onPrevious()
                default: break
                }
            }
            .overlay {
                // Simple left/right tap regions (30% each). Disabled while zoomed.
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: proxy.size.width * 0.3)
                        .contentShape(Rectangle())
                        .onTapGesture { if !isZoomed { onPrevious() } }
                    Color.clear
                        .frame(width: proxy.size.width * 0.4)
                        .allowsHitTesting(false)
                    Color.clear
                        .frame(width: proxy.size.width * 0.3)
                        .contentShape(Rectangle())
                        .onTapGesture { if !isZoomed { onNext() } }
                }
                .accessibilityHidden(true)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onEnded { value in
                        guard !isZoomed else { return }
                        let threshold = proxy.size.width * 0.15
                        if value.translation.width <= -threshold {
                            onNext()
                        } else if value.translation.width >= threshold {
                            onPrevious()
                        }
                    }
            )
        }
    }
}

// MARK: - Placeholder

@ViewBuilder
private func ReaderPlaceholder(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
    ZStack {
        Color.clear
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .imageScale(.large)
                .foregroundStyle(.secondary)
            Text("Loading…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
}

// MARK: - Zoomable Page

private struct ZoomablePage: View {
    let url: URL
    let targetMaxPixel: Int
    @Binding var isZoomed: Bool
    @Environment(\.displayScale) private var displayScale

    private struct ZoomState {
        var scale: CGFloat = 1
        var lastScale: CGFloat = 1
        var offset: CGSize = .zero
        var lastOffset: CGSize = .zero
        mutating func reset() { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero }
    }

    @State private var zoom = ZoomState()
    @State private var isPinching: Bool = false
    @State private var requestedFullRes: Bool = false
    @State private var useFullRes: Bool = false
    @State private var imageAspect: CGFloat?

    private func fittedContentSize(viewportW: CGFloat, viewportH: CGFloat, aspect: CGFloat) -> (contentW: CGFloat, contentH: CGFloat) {
        let viewportAspect = viewportW / viewportH
        if aspect > viewportAspect {
            let contentW = viewportW
            let contentH = viewportW / aspect
            return (contentW, contentH)
        } else {
            let contentH = viewportH
            let contentW = viewportH * aspect
            return (contentW, contentH)
        }
    }

    // Hysteresis thresholds for switching between downsampled and full-resolution
    private let fullResOnScale: CGFloat = 1.10
    private let fullResOffScale: CGFloat = 1.02

    var body: some View {
        GeometryReader { proxy in
            let maxWidth = proxy.size.width
            let maxHeight = proxy.size.height
            let isGIF = url.pathExtension.lowercased() == "gif"

            Group {
                if isGIF {
                    GIFAnimatedImageView(url: url, contentMode: .fit, onFirstFrame: {
                        if let first = GIFFrameCache.shared.frames(for: url)?.first {
                            imageAspect = CGFloat(first.image.width) / max(CGFloat(first.image.height), 1)
                        }
                    })
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                    .scaleEffect(zoom.scale)
                    .offset(zoom.offset)
                    .id(url)
                    .onAppear {
                        imageAspect = nil
                        zoom.reset()
                        requestedFullRes = false
                        useFullRes = false
                    }
                } else {
                    CGImageLoader(
                        url: url,
                        maxPixelProvider: { useFullRes ? CGFloat.greatestFiniteMagnitude : CGFloat(targetMaxPixel) },
                        content: { cgImage in
                            if let cgImage: CGImage {
                                // Compute whether displaying at 1x would upscale the source relative to the fitted content size.
                                let imageW = CGFloat(cgImage.width)
                                let imageH = CGFloat(cgImage.height)
                                let aspect = imageW / max(imageH, 1)
                                let fitted = fittedContentSize(viewportW: maxWidth, viewportH: maxHeight, aspect: aspect)
                                let targetPixelsW = fitted.contentW * displayScale
                                let targetPixelsH = fitted.contentH * displayScale
                                let isUpscalingAt1x = (targetPixelsW > imageW) || (targetPixelsH > imageH)

                                let baseImage = Image(decorative: cgImage, scale: 1, orientation: .up)
                                baseImage
                                    .resizable()
                                    .interpolation(isUpscalingAt1x ? .none : .high)
                                    .scaledToFit()
                                    .contentTransition(.opacity)
                                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                                    .scaleEffect(zoom.scale)
                                    .offset(zoom.offset)
                                    .onAppear {
                                        imageAspect = aspect
                                    }
                            } else {
                                ReaderPlaceholder(maxWidth: maxWidth, maxHeight: maxHeight)
                            }
                        }
                    )
                    .id(url)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onChange(of: zoom.scale) { _, newValue in isZoomed = newValue > 1 }
            .highPriorityGesture(
                MagnifyGesture()
                    .onChanged { value in
                        isPinching = true
                        zoom.scale = min(max(1, zoom.lastScale * value.magnification), 8)

                        // Hysteresis: enable full-res when crossing up threshold; disable when below off threshold
                        if !useFullRes && zoom.scale >= fullResOnScale {
                            useFullRes = true
                            if !requestedFullRes {
                                requestedFullRes = true
                                Task { await CGImageLoader.warm(url: url, maxPixel: Int.max) }
                            }
                        } else if useFullRes && zoom.scale <= fullResOffScale {
                            useFullRes = false
                        }
                    }
                    .onEnded { _ in
                        isPinching = false
                        if zoom.scale <= 1.01 {
                            zoom.reset()
                            requestedFullRes = false
                            useFullRes = false
                        } else {
                            zoom.lastScale = zoom.scale
                        }
                    }
            )
            .gesture(
                TapGesture(count: 2).onEnded {
                    withAnimation(.snappy) {
                        if zoom.scale > 1 {
                            zoom.reset()
                            useFullRes = false
                        } else {
                            let target: CGFloat = 2
                            zoom.scale = min(max(1, target), 8)
                            zoom.lastScale = zoom.scale
                            useFullRes = true
                            if !requestedFullRes {
                                requestedFullRes = true
                                Task { await CGImageLoader.warm(url: url, maxPixel: Int.max) }
                            }
                        }
                    }
                }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard zoom.scale > 1 || isPinching, let aspect = imageAspect else { return }

                        // Compute fitted content size (before scale) for scaledToFit
                        let (contentW, contentH) = fittedContentSize(viewportW: maxWidth, viewportH: maxHeight, aspect: aspect)
                        let scaledW = contentW * zoom.scale
                        let scaledH = contentH * zoom.scale

                        // Max allowed offset to keep content covering viewport
                        let maxOffsetX = max(0, (scaledW - maxWidth) / 2)
                        let maxOffsetY = max(0, (scaledH - maxHeight) / 2)

                        let tentative = CGSize(width: zoom.lastOffset.width + value.translation.width,
                                               height: zoom.lastOffset.height + value.translation.height)
                        let clamped = CGSize(
                            width: min(max(tentative.width, -maxOffsetX), maxOffsetX),
                            height: min(max(tentative.height, -maxOffsetY), maxOffsetY)
                        )
                        zoom.offset = clamped
                    }
                    .onEnded { _ in
                        guard let aspect = imageAspect else {
                            zoom.offset = .zero
                            zoom.lastOffset = .zero
                            return
                        }
                        if zoom.scale <= 1 && !isPinching {
                            zoom.reset()
                            return
                        }
                        let maxWidth = proxy.size.width
                        let maxHeight = proxy.size.height
                        let (contentW, contentH) = fittedContentSize(viewportW: maxWidth, viewportH: maxHeight, aspect: aspect)
                        let scaledW = contentW * zoom.scale
                        let scaledH = contentH * zoom.scale
                        let maxOffsetX = max(0, (scaledW - maxWidth) / 2)
                        let maxOffsetY = max(0, (scaledH - maxHeight) / 2)
                        let clamped = CGSize(
                            width: min(max(zoom.offset.width, -maxOffsetX), maxOffsetX),
                            height: min(max(zoom.offset.height, -maxOffsetY), maxOffsetY)
                        )
                        zoom.offset = clamped
                        zoom.lastOffset = clamped
                    }
            )
        }
    }
}

// MARK: - VerticalReader and PageColumn

private struct VerticalReader: View {
    let pages: [ComicPage]
    let pageImageURLs: [[URL]]
    @Binding var loadedIndices: Set<Int>
    @Binding var viewportMax: CGFloat
    let displayScale: CGFloat
    let downsampleMaxPixel: (CGFloat) -> Int
    @Binding var pillarboxEnabled: Bool
    @Binding var pillarboxPercent: Double // 0...50 (% of total width)
    @Binding var externalVisiblePageIndex: Int
    var onVisiblePageChanged: (Int) -> Void

    @State private var containerWidth: CGFloat = 0
    @State private var containerHeight: CGFloat = 0
    @State private var lastUserReportedIndex: Int?

    // Added state for throttling visible page updates
    @State private var visibleUpdateTask: Task<Void, Never>?

    private var perSidePadding: CGFloat {
        let clampedPercent = min(max(pillarboxPercent, 0), 50)
        return pillarboxEnabled ? (containerWidth * (clampedPercent / 100) / 2) : 0
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .center, spacing: 24) {
                    ForEach(pages.indices, id: \.self) { pageIndex in
                        let title = pages[pageIndex].title
                        let headerText = title.isEmpty ? "Page \(pageIndex + 1)" : "Page \(pageIndex + 1): \(title)"
                        Text(headerText)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)

                        PageColumn(pageIndex: pageIndex,
                                   urls: pageImageURLs[pageIndex],
                                   displayScale: displayScale,
                                   viewportMax: $viewportMax,
                                   downsampleMaxPixel: downsampleMaxPixel)
                            .id(pageIndex)
                            .background(GeometryReader { gp in
                                let midY = gp.frame(in: .named("verticalScroll")).midY
                                Color.clear
                                    .preference(key: VisiblePagePreferenceKey.self, value: [pageIndex: midY])
                            })
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, perSidePadding)
            }
            .onPreferenceChange(VisiblePagePreferenceKey.self) { midYs in
                guard !midYs.isEmpty else { return }
                let centerY = containerHeight / 2
                // Find nearest page by minimizing distance to centerY
                if let nearest = midYs.min(by: { abs($0.value - centerY) < abs($1.value - centerY) })?.key {
                    // Throttle: schedule on next runloop and coalesce rapid updates
                    visibleUpdateTask?.cancel()
                    visibleUpdateTask = Task { @MainActor in
                        await Task.yield()
                        if nearest != externalVisiblePageIndex {
                            lastUserReportedIndex = nearest
                            onVisiblePageChanged(nearest)
                        }
                    }
                }
            }
            .onAppear {
                // When vertical mode appears, jump to the externally requested page.
                lastUserReportedIndex = nil
                let target = min(max(0, externalVisiblePageIndex), max(pages.count - 1, 0))
                if pages.indices.contains(target) {
                    scrollProxy.scrollTo(target, anchor: .top)
                }
            }
            .onChange(of: externalVisiblePageIndex) { _, newValue in
                let target = min(max(0, newValue), max(pages.count - 1, 0))
                // If this change was just reported by the user via visibility tracking, don't fight it.
                if let userIdx = lastUserReportedIndex, userIdx == target {
                    // Clear the marker and skip programmatic scroll
                    lastUserReportedIndex = nil
                    return
                }
                if pages.indices.contains(target) {
                    withAnimation(.none) {
                        scrollProxy.scrollTo(target, anchor: .top)
                    }
                }
            }
        }
        .coordinateSpace(name: "verticalScroll")
        .background(
            GeometryReader { gp in
                Color.clear
                    .onAppear {
                        viewportMax = max(gp.size.width, gp.size.height)
                        containerWidth = gp.size.width
                        containerHeight = gp.size.height
                    }
                    .onChange(of: gp.size.width) { _, _ in
                        viewportMax = max(gp.size.width, gp.size.height)
                        containerWidth = gp.size.width
                    }
                    .onChange(of: gp.size.height) { _, _ in
                        viewportMax = max(gp.size.width, gp.size.height)
                        containerHeight = gp.size.height
                    }
            }
        )
        .background(Color.black.ignoresSafeArea())
    }
}

private struct PageColumn: View {
    let pageIndex: Int
    let urls: [URL]
    let displayScale: CGFloat
    @Binding var viewportMax: CGFloat
    let downsampleMaxPixel: (CGFloat) -> Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(urls.indices, id: \.self) { i in
                let url = urls[i]
                CGImageLoader(url: url, maxPixelProvider: { CGFloat(downsampleMaxPixel(viewportMax)) }, content: { cg in
                    if let cg {
                        let imageW = CGFloat(cg.width)
                        let imageH = CGFloat(cg.height)
                        let aspect = imageW / max(imageH, 1)
                        // Use Pager-like interpolation logic based on fitted width
                        let targetPixelsW = viewportMax * displayScale
                        let targetPixelsH = (viewportMax / max(aspect, 0.0001)) * displayScale
                        let isUpscalingAt1x = (targetPixelsW > imageW) || (targetPixelsH > imageH)

                        Image(decorative: cg, scale: 1, orientation: .up)
                            .resizable()
                            .interpolation(isUpscalingAt1x ? .none : .high)
                            .scaledToFit()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        // Provide a reasonable placeholder height so it isn't tiny
                        ReaderPlaceholder(maxWidth: viewportMax, maxHeight: viewportMax)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }
                })
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Array chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { i in
            Array(self[i..<Swift.min(i + size, count)])
        }
    }
}
