import SwiftUI

struct ComicReaderView: View {
    let comic: Comic

    // State
    @State var selection: Int = 0
    @State var previousSelection: Int = 0
    @State var pageDirection: PageDirection = .forward
    @State var isReady: Bool = false
    @State var flatURLs: [URL] = []
    @State var loadedIndices: Set<Int> = []
    @State var viewportMax: CGFloat = 0
    @State var progress = ReadingProgress()

    // New state for reading mode and page-based data (moved logic to extension)
    @AppStorage(.settingsReaderMode) var readerModeRaw: String = ReadingMode.pager.rawValue

    // Per-comic override storage (only when different from global default) (logic in extension)
    @State var perComicOverrideRaw: String?

    @State var pages: [ComicPage] = []
    @State var pageImageURLs: [[URL]] = [] // per-page images
    @State var pageTitles: [String] = []
    @State var pageToFirstFlatIndex: [Int] = [] // map page index to first flat image index

    @State var verticalVisiblePageIndex: Int = 0

    // Settings
    @AppStorage(.settingsReaderDownsampleMaxPixel) var readerDownsampleMaxPixel: Double = 10240
    @AppStorage(.settingsReaderPreloadRadius) var readerPreloadRadius: Int = 5
    @AppStorage(.settingsVerticalPillarboxEnabled) var verticalPillarboxEnabled: Bool = false
    @AppStorage(.settingsVerticalPillarboxWidth) var verticalPillarboxWidth: Double = 0 // points per side

    @Environment(\.dismiss) var dismiss
    @Environment(\.displayScale) var displayScale

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
                        ReaderPagerMode(
                            count: flatURLs.count,
                            selection: $selection,
                            previousSelection: previousSelection,
                            navDirection: $pageDirection,
                            downsampleMaxPixel: { viewport in computeDownsampleMaxPixel(for: viewport) },
                            urlForIndex: { idx in urlForFlatIndex(idx) },
                            pageIndexForImage: { idx in pageIndexForImageSelection(idx) },
                            onPrevious: { previousPage() },
                            onNext: { nextPage() },
                            slider: pageSliderBinding,
                            progress: progress
                        )
                    } else {
                        ReaderVerticalMode(
                            pages: pages,
                            pageImageURLs: pageImageURLs,
                            loadedIndices: $loadedIndices,
                            viewportMax: $viewportMax,
                            displayScale: displayScale,
                            downsampleMaxPixel: { viewport in computeDownsampleMaxPixel(for: viewport) },
                            pillarboxEnabled: $verticalPillarboxEnabled,
                            pillarboxWidth: $verticalPillarboxWidth,
                            externalVisiblePageIndex: $verticalVisiblePageIndex,
                            onVisiblePageChanged: { idx in verticalVisiblePageIndex = idx },
                            progress: progress,
                            pageToFirstFlatIndex: pageToFirstFlatIndex,
                            externalVisibleImageIndex: progress.currentImageIndex
                        )
                    }
                }
                .overlay(alignment: .topLeading) {
                    ReaderBackButton { dismiss() }
                        .padding(.top, 8)
                        .padding(.leading, 8)
                }
                .overlay(alignment: .topTrailing) {
                    VStack {
                        ReaderModeToggle(readerMode: readerMode) { cycleReaderMode() }
                            .padding(.top, 8)
                            .padding(.trailing, 8)
                            .accessibilityLabel("Toggle reading mode")
                            .accessibilityHint("Switches between Pager and Vertical modes")

                        ReaderPillarboxControls(
                            enabled: $verticalPillarboxEnabled,
                            width: $verticalPillarboxWidth
                        )
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                    }
                }
            }
        }
        .navigationTitle(navigationTitleText)
        .toolbar(.hidden, for: .automatic)
        .task {
            await initialLoadTask()
        }
        .task(id: selection) {
            await selectionChangedTask(newValue: selection)
        }
        .task(id: verticalVisiblePageIndex) {
            await verticalVisiblePageChangedTask(newValue: verticalVisiblePageIndex)
        }
        .onChange(of: effectiveModeRaw) { oldRaw, newRaw in
            modeChanged(oldRaw: oldRaw, newRaw: newRaw)
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
            saveOnDisappear()
        }
    }
}
