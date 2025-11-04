import SwiftUI
import Foundation
import Observation

internal struct VisiblePagePreferenceKey: PreferenceKey {
    typealias Value = [Int]
    static var defaultValue: [Int] = []

    static func reduce(value: inout [Int], nextValue: () -> [Int]) {
        value.append(contentsOf: nextValue())
    }
}

internal struct VerticalViewportMaxPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct VerticalReaderMode: View {
    var pages: [ComicPage]
    var pageImageURLs: [[URL]]
    @Binding var loadedIndices: Set<Int>
    @Binding var viewportMax: CGFloat
    var displayScale: CGFloat
    var downsampleMaxPixel: (CGFloat) -> Int
    @Binding var pillarboxEnabled: Bool
    @Binding var pillarboxPercent: Double
    @Binding var externalVisiblePageIndex: Int
    var onVisiblePageChanged: (Int) -> Void

    var progress: ReadingProgress?

    init(
        pages: [ComicPage],
        pageImageURLs: [[URL]],
        loadedIndices: Binding<Set<Int>>,
        viewportMax: Binding<CGFloat>,
        displayScale: CGFloat,
        downsampleMaxPixel: @escaping (CGFloat) -> Int,
        pillarboxEnabled: Binding<Bool>,
        pillarboxPercent: Binding<Double>,
        externalVisiblePageIndex: Binding<Int>,
        onVisiblePageChanged: @escaping (Int) -> Void,
        progress: ReadingProgress? = nil
    ) {
        self.pages = pages
        self.pageImageURLs = pageImageURLs
        self._loadedIndices = loadedIndices
        self._viewportMax = viewportMax
        self.displayScale = displayScale
        self.downsampleMaxPixel = downsampleMaxPixel
        self._pillarboxEnabled = pillarboxEnabled
        self._pillarboxPercent = pillarboxPercent
        self._externalVisiblePageIndex = externalVisiblePageIndex
        self.onVisiblePageChanged = onVisiblePageChanged
        self.progress = progress
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
            pillarboxPercent: $pillarboxPercent,
            externalVisiblePageIndex: $externalVisiblePageIndex,
            onVisiblePageChanged: onVisiblePageChanged,
            progress: progress
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
    @Binding var pillarboxPercent: Double
    @Binding var externalVisiblePageIndex: Int
    var onVisiblePageChanged: (Int) -> Void

    var progress: ReadingProgress?

    @State private var visiblePageIndices: [Int] = []
    @State private var throttledTask: Task<Void, Never>?

    @State private var containerWidth: CGFloat = 0
    @State private var containerHeight: CGFloat = 0

    private var perSidePadding: CGFloat {
        let clampedPercent = min(max(pillarboxPercent, 0), 50)
        return pillarboxEnabled ? (containerWidth * (clampedPercent / 100) / 2) : 0
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 24) {
                ForEach(pages.indices, id: \.self) { index in
                    let title = pages[index].title
                    let headerText = title.isEmpty ? "Page \(index + 1)" : "Page \(index + 1): \(title)"
                    Text(headerText)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                    PageColumn(
                        page: pages[index],
                        imageUrls: pageImageURLs[index],
                        pageIndex: index,
                        loadedIndices: $loadedIndices,
                        displayScale: displayScale,
                        downsampleMaxPixel: downsampleMaxPixel,
                        pillarboxEnabled: $pillarboxEnabled,
                        pillarboxPercent: $pillarboxPercent,
                        viewportMax: viewportMax
                    )
                    .background(GeometryReader { proxy in
                        Color.clear.preference(
                            key: VisiblePagePreferenceKey.self,
                            value: [isVisible(proxy: proxy) ? index : -1].compactMap { $0 >= 0 ? $0 : nil }
                        )
                    })
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, perSidePadding)
            .background(GeometryReader { proxy in
                Color.clear
                    .preference(key: VerticalViewportMaxPreferenceKey.self,
                                value: max(proxy.size.width, proxy.size.height))
                    .onAppear {
                        containerWidth = proxy.size.width
                        containerHeight = proxy.size.height
                    }
                    .onChange(of: proxy.size.width) { _, newValue in
                        containerWidth = newValue
                    }
                    .onChange(of: proxy.size.height) { _, newValue in
                        containerHeight = newValue
                    }
            })
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(VisiblePagePreferenceKey.self) { newValue in
            visiblePageIndices = newValue
            progress?.updatePage(newValue.first ?? 0)
            throttleVisiblePageChange()
        }
        .onPreferenceChange(VerticalViewportMaxPreferenceKey.self) { newValue in
            viewportMax = newValue
        }
        .onChange(of: externalVisiblePageIndex) { _, newValue in
            guard !visiblePageIndices.contains(newValue) else { return }
            progress?.updatePage(newValue)
            // External visible page index changed, perform any action if needed
        }
    }

    private func isVisible(proxy: GeometryProxy) -> Bool {
        let frame = proxy.frame(in: .named("scroll"))
        return frame.minY < viewportMax && frame.maxY > 0
    }

    private func throttleVisiblePageChange() {
        throttledTask?.cancel()
        throttledTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let firstVisible = visiblePageIndices.first {
                if externalVisiblePageIndex != firstVisible {
                    externalVisiblePageIndex = firstVisible
                    onVisiblePageChanged(firstVisible)
                }
            }
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
    @Binding var pillarboxPercent: Double
    var viewportMax: CGFloat

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
