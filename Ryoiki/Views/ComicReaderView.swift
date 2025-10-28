import SwiftUI
import ImageIO

private enum PageDirection: Int { case forward, backward }

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
    @State private var flatTitles: [String] = []
    @State private var loadedIndices: Set<Int> = []
    @State private var preheatTask: Task<Void, Never>?
    @State private var viewportMax: CGFloat = 0

    // Settings
    @AppStorage(.settingsReaderDownsampleMaxPixel) private var readerDownsampleMaxPixel: Double = 2048
    @AppStorage(.settingsReaderPreloadRadius) private var readerPreloadRadius: Int = 5

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    private var navigationTitleText: String {
        let t = pageTitle(at: selection)
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

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            if !isReady {
                ProgressView()
                    .controlSize(.large)
                    .padding()
            } else if flatURLs.isEmpty {
                ContentUnavailableView(
                    "No pages to read",
                    systemImage: "book.closed",
                    description: Text("This comic has no downloaded images.")
                )
                .padding()
            } else {
                VStack(spacing: 0) {
                    ReaderPager(
                        count: flatURLs.count,
                        selection: $selection,
                        navDirection: $pageDirection,
                        downsampleMaxPixel: { viewportMax in
                            let scaled = max(viewportMax, 1) * displayScale
                            let dyn = min(Int(readerDownsampleMaxPixel), Int(scaled))
                            return max(256, dyn)
                        },
                        urlForIndex: { idx in (loadedIndices.contains(idx) && idx >= 0 && idx < flatURLs.count) ? flatURLs[idx] : nil },
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
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 0) }
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
            }
        }
        .toolbar(.hidden, for: .automatic)
        .navigationTitle(navigationTitleText)
        .task {
            let pages = comic.pages.sorted { $0.index < $1.index }
            let snapshots: [URL] = pages.flatMap { page in
                page.images.sorted { $0.index < $1.index }.compactMap { $0.fileURL }
            }
            let titles: [String] = pages.flatMap { page in
                page.images.sorted { $0.index < $1.index }.compactMap { _ in page.title }
            }
            let restored: Int = await MainActor.run { loadPersistedSelection(totalCount: snapshots.count) }

            await MainActor.run {
                self.flatURLs = snapshots
                self.flatTitles = titles
            }

            // Preload around the restored index before showing UI to avoid placeholder flash
            await ensureLoadedWindow(around: restored, radius: effectivePreloadRadius)

            // Now show the UI
            await MainActor.run { self.isReady = true }

            // Give layout a moment to appear before applying scroll position
            await Task.yield()

            // Apply the selection so the pager scrolls to the correct page
            await MainActor.run {
                withAnimation(.none) {
                    self.pageDirection = .forward
                    self.previousSelection = restored
                    self.selection = restored
                }
            }
        }
        .onChange(of: selection) { _, newValue in
            preheatTask?.cancel()
            preheatTask = Task {
                await ensureLoadedWindow(around: newValue, radius: effectivePreloadRadius)
                await MainActor.run { savePersistedSelection(newValue) }
            }
        }
        .onKeyPress(.leftArrow) {
            previousPage()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            nextPage()
            return .handled
        }
        .onDisappear {
            preheatTask?.cancel()
            Task { @MainActor in savePersistedSelection(selection) }
        }
    }

    // MARK: - Persistence (current page)

    private var persistedSelectionKey: String {
        "reader.selection.\(comic.name)|\(comic.url)"
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
        guard index >= 0, index < flatTitles.count else { return "" }
        return flatTitles[index]
    }
}

// MARK: - Reader Pager

private struct ReaderPager: View {
    let count: Int
    @Binding var selection: Int
    @Binding var navDirection: PageDirection
    var downsampleMaxPixel: (CGFloat) -> Int
    var urlForIndex: (Int) -> URL?
    var onPrevious: () -> Void
    var onNext: () -> Void

    @State private var isZoomed: Bool = false

    private var slideTransition: AnyTransition {
        switch navDirection {
        case .forward:
            return .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        case .backward:
            return .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let viewportMax = max(proxy.size.width, proxy.size.height)
            ZStack {
                if let url = urlForIndex(selection) {
                    ZoomablePage(
                        url: url,
                        targetMaxPixel: downsampleMaxPixel(viewportMax),
                        isZoomed: $isZoomed
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .id("\(selection)-\(navDirection)")
                    .transition(slideTransition)
                } else {
                    ReaderPlaceholder(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .id("\(selection)-\(navDirection)")
                        .transition(slideTransition)
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

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { i in
            Array(self[i..<Swift.min(i + size, count)])
        }
    }
}
