import SwiftUI
import Foundation
import Observation

internal struct ImageVisiblePreferenceKey: PreferenceKey {
    typealias Value = [Int]
    static var defaultValue: [Int] = []
    static func reduce(value: inout [Int], nextValue: () -> [Int]) {
        value.append(contentsOf: nextValue())
    }
}

struct ReaderVerticalMode: View {
    var pages: [ComicPage]
    var pageImageURLs: [[URL]]
    @Binding var loadedIndices: Set<Int>
    @Binding var viewportMax: CGFloat
    var displayScale: CGFloat
    var downsampleMaxPixel: (CGFloat) -> Int
    @Binding var pillarboxEnabled: Bool
    @Binding var pillarboxWidth: Double
    @Binding var externalVisiblePageIndex: Int
    var onVisiblePageChanged: (Int) -> Void

    var progress: ReadingProgress?
    var pageToFirstFlatIndex: [Int]
    var externalVisibleImageIndex: Int?

    init(
        pages: [ComicPage],
        pageImageURLs: [[URL]],
        loadedIndices: Binding<Set<Int>>,
        viewportMax: Binding<CGFloat>,
        displayScale: CGFloat,
        downsampleMaxPixel: @escaping (CGFloat) -> Int,
        pillarboxEnabled: Binding<Bool>,
        pillarboxWidth: Binding<Double>,
        externalVisiblePageIndex: Binding<Int>,
        onVisiblePageChanged: @escaping (Int) -> Void,
        progress: ReadingProgress? = nil,
        pageToFirstFlatIndex: [Int],
        externalVisibleImageIndex: Int? = nil
    ) {
        self.pages = pages
        self.pageImageURLs = pageImageURLs
        self._loadedIndices = loadedIndices
        self._viewportMax = viewportMax
        self.displayScale = displayScale
        self.downsampleMaxPixel = downsampleMaxPixel
        self._pillarboxEnabled = pillarboxEnabled
        self._pillarboxWidth = pillarboxWidth
        self._externalVisiblePageIndex = externalVisiblePageIndex
        self.onVisiblePageChanged = onVisiblePageChanged
        self.progress = progress
        self.pageToFirstFlatIndex = pageToFirstFlatIndex
        self.externalVisibleImageIndex = externalVisibleImageIndex
    }

    var body: some View {
        InnerVerticalReader(
            pages: pages,
            pageImageURLs: pageImageURLs,
            loadedIndices: $loadedIndices,
            viewportMax: $viewportMax,
            displayScale: displayScale,
            downsampleMaxPixel: downsampleMaxPixel,
            pillarboxEnabled: $pillarboxEnabled,
            pillarboxWidth: $pillarboxWidth,
            externalVisiblePageIndex: $externalVisiblePageIndex,
            onVisiblePageChanged: onVisiblePageChanged,
            progress: progress,
            pageToFirstFlatIndex: pageToFirstFlatIndex,
            externalVisibleImageIndex: externalVisibleImageIndex
        )
    }
}

struct InnerVerticalReader: View {
    var pages: [ComicPage]
    var pageImageURLs: [[URL]]
    @Binding var loadedIndices: Set<Int>
    @Binding var viewportMax: CGFloat
    var displayScale: CGFloat
    var downsampleMaxPixel: (CGFloat) -> Int
    @Binding var pillarboxEnabled: Bool
    @Binding var pillarboxWidth: Double
    @Binding var externalVisiblePageIndex: Int
    var onVisiblePageChanged: (Int) -> Void

    var progress: ReadingProgress?
    var pageToFirstFlatIndex: [Int]
    var externalVisibleImageIndex: Int?

    let imageAnchorBase: Int = 1_000_000

    @State private var scrollPosition: Int?
    @State private var scrollDebounceTask: Task<Void, Never>?
    @State private var suppressNextPageAnchorImageUpdate: Bool = false

    @State private var containerWidth: CGFloat = 0
    @State private var containerHeight: CGFloat = 0

    private var perSidePadding: CGFloat {
        pillarboxEnabled ? CGFloat(pillarboxWidth) : 0
    }

    private func coalescedSetViewportMax(width: CGFloat, height: CGFloat) {
        let newMax = max(width, height)
        if newMax != viewportMax {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                viewportMax = newMax
            }
        }
    }

    private func clampedImageIndex(_ idx: Int) -> Int {
        let total = pageImageURLs.reduce(0) { $0 + $1.count }
        return min(max(0, idx), max(total - 1, 0))
    }

    private func clampedPageIndex(_ idx: Int) -> Int {
        min(max(0, idx), max(pages.count - 1, 0))
    }

    private func pageIndex(forFlatImage flatIndex: Int) -> Int {
        guard !pageToFirstFlatIndex.isEmpty else { return 0 }
        let clamped = max(0, flatIndex)
        var lo = 0
        var hi = pageToFirstFlatIndex.count - 1
        var ans = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if pageToFirstFlatIndex[mid] <= clamped {
                ans = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return clampedPageIndex(ans)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 24) {
                    ForEach(pages.indices, id: \.self) { index in
                        VerticalPageRow(
                            index: index,
                            page: pages[index],
                            imageUrls: pageImageURLs[index],
                            loadedIndices: $loadedIndices,
                            displayScale: displayScale,
                            downsampleMaxPixel: downsampleMaxPixel,
                            pillarboxEnabled: $pillarboxEnabled,
                            pillarboxWidth: $pillarboxWidth,
                            viewportMax: viewportMax,
                            baseFlatIndex: (index < pageToFirstFlatIndex.count ? pageToFirstFlatIndex[index] : 0),
                            imageAnchorBase: imageAnchorBase,
                            containerHeight: containerHeight,
                        )
                        .id(index)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, perSidePadding)
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            coalescedSetViewportMax(width: proxy.size.width, height: proxy.size.height)
                        }
                        .onChange(of: proxy.size.width) { _, newValue in
                            containerWidth = newValue
                            coalescedSetViewportMax(width: containerWidth, height: containerHeight)
                        }
                        .onChange(of: proxy.size.height) { _, newValue in
                            containerHeight = newValue
                            coalescedSetViewportMax(width: containerWidth, height: containerHeight)
                        }
                })
            }
            .coordinateSpace(name: "scroll")
            .scrollPosition(id: $scrollPosition)
            .onChange(of: scrollPosition) { _, newValue in
                scrollDebounceTask?.cancel()
                if let raw = newValue {
                    scrollDebounceTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        if Task.isCancelled { return }
                        if raw >= imageAnchorBase {
                            let imageIdx = clampedImageIndex(raw - imageAnchorBase)
                            let derivedPage = pageIndex(forFlatImage: imageIdx)
                            if externalVisiblePageIndex != derivedPage {
                                externalVisiblePageIndex = derivedPage
                                onVisiblePageChanged(derivedPage)
                                progress?.updatePage(derivedPage)
                            }
                            progress?.updateImageIndex(imageIdx)
                            // After handling an image anchor, ensure we do not suppress subsequent page updates
                            suppressNextPageAnchorImageUpdate = false
                        } else {
                            let derivedPage = clampedPageIndex(raw)
                            if externalVisiblePageIndex != derivedPage {
                                externalVisiblePageIndex = derivedPage
                                onVisiblePageChanged(derivedPage)
                                progress?.updatePage(derivedPage)
                            }
                            if suppressNextPageAnchorImageUpdate {
                                // Skip updating image index for this synthetic page anchor set after image scroll
                                suppressNextPageAnchorImageUpdate = false
                            } else {
                                if derivedPage >= 0 && derivedPage < pageToFirstFlatIndex.count {
                                    let firstImg = pageToFirstFlatIndex[derivedPage]
                                    let clampedFirst = clampedImageIndex(firstImg)
                                    progress?.updateImageIndex(clampedFirst)
                                }
                            }
                        }
                    }
                }
            }
            .onPreferenceChange(ImageVisiblePreferenceKey.self) { visibleImages in
                guard let first = visibleImages.min() else { return }
                let imgIdx = clampedImageIndex(first)
                progress?.updateImageIndex(imgIdx)
                let derivedPage = pageIndex(forFlatImage: imgIdx)
                if externalVisiblePageIndex != derivedPage {
                    externalVisiblePageIndex = derivedPage
                    onVisiblePageChanged(derivedPage)
                    progress?.updatePage(derivedPage)
                }
            }
            .onAppear {
                let pageIdx = clampedPageIndex(externalVisiblePageIndex)
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    if let img = progress?.currentImageIndex {
                        // Temporarily clear scrollPosition to avoid the system snapping back to the page anchor
                        scrollPosition = nil
                        let clampedImg = clampedImageIndex(img)
                        proxy.scrollTo(imageAnchorBase + clampedImg, anchor: .top)
                        // After a short delay, set scrollPosition to the page to keep external sync stable
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            suppressNextPageAnchorImageUpdate = true
                            var t2 = Transaction()
                            t2.disablesAnimations = true
                            withTransaction(t2) {
                                scrollPosition = pageIdx
                            }
                        }
                    } else {
                        scrollPosition = pageIdx
                        proxy.scrollTo(pageIdx, anchor: .top)
                    }
                }
            }
            .onChange(of: externalVisiblePageIndex) { _, newValue in
                let pageIdx = clampedPageIndex(newValue)
                if scrollPosition != pageIdx {
                    scrollPosition = pageIdx
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        proxy.scrollTo(pageIdx, anchor: .top)
                    }
                }
            }
        }
    }
}

private struct VerticalPageRow: View {
    let index: Int
    let page: ComicPage
    let imageUrls: [URL]
    @Binding var loadedIndices: Set<Int>
    let displayScale: CGFloat
    let downsampleMaxPixel: (CGFloat) -> Int
    @Binding var pillarboxEnabled: Bool
    @Binding var pillarboxWidth: Double
    let viewportMax: CGFloat
    let baseFlatIndex: Int
    let imageAnchorBase: Int
    let containerHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            let title = page.title
            let headerText = title.isEmpty ? "Page \(index + 1)" : "Page \(index + 1): \(title)"
            Text(headerText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .padding(.bottom)
            PageColumn(
                page: page,
                imageUrls: imageUrls,
                pageIndex: index,
                loadedIndices: $loadedIndices,
                displayScale: displayScale,
                downsampleMaxPixel: downsampleMaxPixel,
                pillarboxEnabled: $pillarboxEnabled,
                pillarboxWidth: $pillarboxWidth,
                viewportMax: viewportMax,
                baseFlatIndex: baseFlatIndex,
                imageAnchorBase: imageAnchorBase,
                containerHeight: containerHeight
            )
        }
    }
}

private struct PageColumn: View {
    var page: ComicPage
    var imageUrls: [URL]
    var pageIndex: Int
    @Binding var loadedIndices: Set<Int>
    var displayScale: CGFloat
    var downsampleMaxPixel: (CGFloat) -> Int
    @Binding var pillarboxEnabled: Bool
    @Binding var pillarboxWidth: Double
    var viewportMax: CGFloat
    var baseFlatIndex: Int
    var imageAnchorBase: Int
    var containerHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(imageUrls.indices, id: \.self) { index in
                let imageUrl = imageUrls[index]
                CGImageLoader(url: imageUrl, maxPixelProvider: { CGFloat(downsampleMaxPixel(viewportMax)) }, content: { cg in
                    if let cg {
                        Image(decorative: cg, scale: 1, orientation: .up)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ReaderPlaceholder()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }
                })
                .id(imageAnchorBase + baseFlatIndex + index)
                .background(
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .named("scroll"))
                        let isVisible = frame.minY < containerHeight && frame.maxY > 0
                        Color.clear.preference(
                            key: ImageVisiblePreferenceKey.self,
                            value: isVisible ? [baseFlatIndex + index] : []
                        )
                    }
                )
            }
        }
        .onAppear {
            loadedIndices.insert(pageIndex)
        }
        .onDisappear {
            loadedIndices.remove(pageIndex)
        }
    }
}

private struct ReaderPlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 200)
            .overlay(
                Image(systemName: "photo.on.rectangle")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
            )
    }
}
