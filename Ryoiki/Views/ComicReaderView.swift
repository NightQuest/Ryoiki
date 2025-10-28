import SwiftUI
import ImageIO

struct ComicReaderView: View {
    let comic: Comic

    // State
    @State private var selection: Int = 0
    @State private var imageURLs: [URL] = []
    @State private var isReady: Bool = false
    @State private var isScrubbing: Bool = false

    // Progressive hydration
    @State private var allPathSnapshots: [[String]] = []
    @State private var batchIndex: Int = 0
    private let initialBatchCount: Int = 50
    private let batchAppendCount: Int = 150

    // Settings
    @AppStorage(.settingsReaderDownsampleMaxPixel) private var readerDownsampleMaxPixel: Double = 2048
    @AppStorage(.settingsReaderPreloadRadius) private var readerPreloadRadius: Int = 5

    // Layout namespace
    @Namespace private var readerNS

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            if !isReady {
                ProgressView()
                    .controlSize(.large)
                    .padding()
            } else if imageURLs.isEmpty {
                ContentUnavailableView(
                    "No pages to read",
                    systemImage: "book.closed",
                    description: Text("This comic has no downloaded images.")
                )
                .padding()
            } else {
                VStack(spacing: 0) {
                    ReaderPager(
                        urls: imageURLs,
                        selection: $selection,
                        readerNS: readerNS,
                        downsampleMaxPixel: { _ in
                            max(256, Int(readerDownsampleMaxPixel))
                        }
                    )

                    ReaderScrubber(
                        selection: $selection,
                        count: imageURLs.count,
                        isScrubbing: $isScrubbing
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule(style: .circular))
                    .shadow(radius: 2, y: 1)
                    .padding(.bottom, 12)
                    .padding(.top, 8)
                }
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 0) }
                .overlay(alignment: .top) {
                    if selection < imageURLs.count {
                        let title = pageTitle(at: selection)
                        if !title.isEmpty {
                            Text(title)
                                .font(.headline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(.top, 8)
                        }
                    }
                }
                .overlay {
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { previousPage() }
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { nextPage() }
                        }
                        .allowsHitTesting(true)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .automatic)
        .task {
            // 1) Snapshot minimal, Sendable data on the main actor
            let snapshots: [[String]] = comic.pages.map { page in
                page.images.compactMap { image in
                    if let url = image.fileURL { return url.absoluteString }
                    if !image.downloadPath.isEmpty { return image.downloadPath }
                    return nil
                }
            }
            self.allPathSnapshots = snapshots
            self.batchIndex = 0

            // 2) Convert only the first batch off-main
            let firstBatch: [URL] = await convertPathsToURLs(
                Array(snapshots.prefix(initialBatchCount))
            )
            await MainActor.run {
                self.imageURLs = firstBatch
                self.selection = min(self.selection, max(0, firstBatch.count - 1))
                self.isReady = true
            }

            // Prefetch immediately around current selection using full user radius but bounded by hydrated set
            await prefetchNeighborsSmooth(around: self.selection, radius: readerPreloadRadius)

            // 3) Append remaining in background batches
            var nextStart = initialBatchCount
            while nextStart < snapshots.count {
                let nextEnd = min(nextStart + batchAppendCount, snapshots.count)
                let batchSlice = Array(snapshots[nextStart..<nextEnd])
                let urls = await convertPathsToURLs(batchSlice)

                // Append on main actor
                await MainActor.run {
                    self.imageURLs.append(contentsOf: urls)
                    self.batchIndex = nextEnd
                }

                // If any of these new indices fall into the current prefetch window, warm them now
                await prefetchNeighborsSmooth(around: self.selection, radius: readerPreloadRadius)

                nextStart = nextEnd
            }
        }
        .onChange(of: selection) { _, newValue in
            Task { await prefetchNeighborsSmooth(around: newValue, radius: readerPreloadRadius) }
        }
        .onKeyPress(.leftArrow) {
            previousPage()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            nextPage()
            return .handled
        }
    }

    private func convertPathsToURLs(_ pathSnapshots: [[String]]) async -> [URL] {
        await Task.detached(priority: .userInitiated) {
            pathSnapshots.flatMap { strings in
                strings.compactMap { s -> URL? in
                    if s.hasPrefix("file://") {
                        if let u = URL(string: s), u.isFileURL { return u }
                        let path = s.replacingOccurrences(of: "file://", with: "")
                        return URL(fileURLWithPath: path)
                    } else if s.hasPrefix("/") {
                        return URL(fileURLWithPath: s)
                    } else if let u = URL(string: s), u.isFileURL {
                        return u
                    } else {
                        return nil
                    }
                }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            }
        }.value
    }

    // MARK: - Prefetch

    private func prefetchNeighborsSmooth(around index: Int, radius: Int) async {
        guard !imageURLs.isEmpty else { return }
        let radius = max(0, radius)
        let lower = max(0, index - radius)
        let upper = min(imageURLs.count - 1, index + radius)
        // Interleave next and previous: +1, -1, +2, -2, ...
        var order: [Int] = []
        if radius > 0 {
            for d in 1...radius {
                let next = index + d
                let prev = index - d
                if next <= upper { order.append(next) }
                if prev >= lower { order.append(prev) }
            }
        }
        let neighbors: [URL] = order.map { imageURLs[$0] }
        let maxPixel = max(256, Int(readerDownsampleMaxPixel))

        for url in neighbors {
            await CGImageLoader.warm(url: url, maxPixel: maxPixel)
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func nextPage() {
        guard !imageURLs.isEmpty else { return }
        selection = min(selection + 1, imageURLs.count - 1)
    }

    private func previousPage() {
        guard !imageURLs.isEmpty else { return }
        selection = max(selection - 1, 0)
    }

    private func pageTitle(at index: Int) -> String {
        // Best effort: derive title from Comic model by matching URL
        guard index >= 0, index < imageURLs.count else { return "" }
        let url = imageURLs[index]
        // Find the first page that contains this URL and return its title
        for page in comic.pages where page.images.contains(where: { $0.fileURL == url }) {
            return page.title
        }
        return ""
    }
}

// MARK: - Reader Pager

private struct ReaderPager: View {
    let urls: [URL]
    @Binding var selection: Int
    var readerNS: Namespace.ID
    var downsampleMaxPixel: (CGFloat) -> Int

    var body: some View {
        GeometryReader { proxy in
            let viewportMax = max(proxy.size.width, proxy.size.height)

            TabView(selection: $selection) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    ZoomablePage(url: url, targetMaxPixel: downsampleMaxPixel(viewportMax))
                        .tag(index)
                        .padding(.horizontal)
                        .padding(.vertical, 16)
                }
            }
            .animation(.snappy(duration: 0.18), value: selection)
        }
    }
}

// MARK: - Placeholder

@ViewBuilder
private func ReaderPlaceholder(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.quaternary)
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

// MARK: - Blurred Preview

private struct BlurredPreview: View {
    let url: URL

    var body: some View {
        GeometryReader { proxy in
            CGImageLoader(
                url: url,
                maxPixelProvider: { max(proxy.size.width, proxy.size.height) },
                content: { cgImage in
                    if let cgImage {
                        Image(decorative: cgImage, scale: 1, orientation: .up)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .blur(radius: 20)
                            .opacity(0.25)
                    } else {
                        Color.black
                    }
                }
            )
        }
    }
}

// Inserted BackgroundLayers view

private struct BackgroundLayers: View {
    let selection: Int
    let imageURLs: [URL]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Base black
                Color.black
                    .ignoresSafeArea()

                // Left side layers (prev pages)
                VStack { Spacer() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 0) {
                            // Closest previous
                            if let left1 = url(at: selection - 1) {
                                BlurredPreview(url: left1)
                                    .blur(radius: 20)
                                    .opacity(0.25)
                                    .frame(width: proxy.size.width / 2, height: proxy.size.height)
                            } else {
                                Color.black.frame(width: proxy.size.width / 2, height: proxy.size.height)
                            }
                            // Second previous
                            if let left2 = url(at: selection - 2) {
                                BlurredPreview(url: left2)
                                    .blur(radius: 28)
                                    .opacity(0.15)
                                    .frame(width: proxy.size.width / 2, height: proxy.size.height)
                            }
                        }
                    }

                // Right side layers (next pages)
                VStack { Spacer() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .trailing) {
                        HStack(spacing: 0) {
                            // Closest next
                            if let right1 = url(at: selection + 1) {
                                BlurredPreview(url: right1)
                                    .blur(radius: 20)
                                    .opacity(0.25)
                                    .frame(width: proxy.size.width / 2, height: proxy.size.height)
                            } else {
                                Color.black.frame(width: proxy.size.width / 2, height: proxy.size.height)
                            }
                            // Second next
                            if let right2 = url(at: selection + 2) {
                                BlurredPreview(url: right2)
                                    .blur(radius: 28)
                                    .opacity(0.15)
                                    .frame(width: proxy.size.width / 2, height: proxy.size.height)
                            }
                        }
                    }

                // Vignette overlays
                VignetteOverlay()
            }
            .ignoresSafeArea()
        }
    }

    private func url(at index: Int) -> URL? {
        guard imageURLs.indices.contains(index) else { return nil }
        return imageURLs[index]
    }
}

private struct VignetteOverlay: View {
    var body: some View {
        ZStack {
            // Horizontal vignette
            LinearGradient(
                colors: [Color.black.opacity(0.35), .clear, .clear, Color.black.opacity(0.35)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()
            // Vertical vignette
            LinearGradient(
                colors: [Color.black.opacity(0.25), .clear, Color.black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Zoomable Page

private struct ZoomablePage: View {
    let url: URL
    let targetMaxPixel: Int

    @State private var isVisible = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let maxWidth = proxy.size.width
            let maxHeight = proxy.size.height

            Group {
                if isVisible {
                    CGImageLoader(
                        url: url,
                        maxPixelProvider: { CGFloat(targetMaxPixel) },
                        content: { cgImage in
                            if let cgImage {
                                Image(decorative: cgImage, scale: 1, orientation: .up)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                                    .scaleEffect(scale)
                                    .gesture(
                                        MagnifyGesture()
                                            .onChanged { value in
                                                scale = min(max(0.8, lastScale * value.magnification), 3)
                                            }
                                            .onEnded { _ in
                                                lastScale = scale
                                            }
                                    )
                            } else {
                                ReaderPlaceholder(maxWidth: maxWidth, maxHeight: maxHeight)
                            }
                        }
                    )
                } else {
                    ReaderPlaceholder(maxWidth: maxWidth, maxHeight: maxHeight)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
        }
    }
}

// MARK: - Reader Scrubber

private struct ReaderScrubber: View {
    @Binding var selection: Int
    let count: Int
    @Binding var isScrubbing: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Page")
                Spacer()
                Text("\(selection + 1) / \(count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(selection) },
                    set: { selection = max(0, min(count - 1, Int($0.rounded()))) }
                ),
                in: 0...Double(max(count - 1, 0)),
                step: 1
            )
            .onChange(of: selection) { oldValue, newValue in
                isScrubbing = true
                #if os(iOS)
                if newValue != oldValue {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                #endif
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if selection == newValue { isScrubbing = false }
                }
            }
        }
        .font(.subheadline)
        .padding(.horizontal)
        .frame(maxWidth: 520)
    }
}

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Loader (preserved)

private struct CGImageLoader: View {
    let url: URL
    let maxPixelProvider: () -> CGFloat
    let content: (CGImage?) -> AnyView

    @State private var cgImage: CGImage?
    @State private var hasAttempted = false

    // Shared cache
    private static var cache = NSCache<NSURL, CGImage>()

    init(url: URL, maxPixelProvider: @escaping () -> CGFloat, @ViewBuilder content: @escaping (CGImage?) -> some View) {
        self.url = url
        self.maxPixelProvider = maxPixelProvider
        self.content = { AnyView(content($0)) }
    }

    var body: some View {
        content(cgImage)
            .task(id: url, loadIfNeeded)
    }

    @Sendable
    private func loadIfNeeded() async {
        let key = url as NSURL
        if let cached = Self.cache.object(forKey: key) {
            cgImage = cached
            return
        }
        guard !hasAttempted else { return }
        hasAttempted = true

        let requestedMax = Int(max(1, maxPixelProvider()))
        let decoded: CGImage? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let cgImage = Self.decodeThumbnail(from: url, maxPixel: requestedMax)
                continuation.resume(returning: cgImage)
            }
        }

        if let decoded {
            Self.cache.setObject(decoded, forKey: key, cost: decoded.bytesPerRow * decoded.height)
        }
        await MainActor.run {
            cgImage = decoded
        }
    }

    // Public: warm the cache for prefetching
    static func warm(url: URL, maxPixel: Int) async {
        let key = url as NSURL
        if cache.object(forKey: key) != nil { return }
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let cgImage = decodeThumbnail(from: url, maxPixel: maxPixel)
                if let cgImage { cache.setObject(cgImage, forKey: key, cost: cgImage.bytesPerRow * cgImage.height) }
                continuation.resume()
            }
        }
    }

    // Decode and downsample to a thumbnail with given max pixel size
    private static func decodeThumbnail(from url: URL, maxPixel: Int) -> CGImage? {
        guard url.isFileURL else { return nil }
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            #if DEBUG
            print("Reader: file does not exist at path:", path)
            #endif
            return nil
        }
        let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        if resourceValues?.isRegularFile == false { return nil }
        if (resourceValues?.fileSize ?? 0) <= 0 { return nil }

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) {
            return thumb
        }
        if let full = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            return full
        }
        #if DEBUG
        print("Reader: failed to decode image at:", path)
        #endif
        return nil
    }
}
