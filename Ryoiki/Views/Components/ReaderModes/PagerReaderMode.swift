import SwiftUI
import ImageIO

public enum PageDirection: Int {
    case forward, backward
}

public protocol PagerReaderModeDelegate: AnyObject {
    func pagerReaderModeWillNavigate(_ direction: PageDirection)
}

public struct PagerReaderMode: View {
    public var count: Int
    @Binding public var selection: Int
    public var previousSelection: Int
    @Binding public var navDirection: PageDirection
    public var downsampleMaxPixel: (CGFloat) -> Int
    public var urlForIndex: (Int) -> URL?
    public var onPrevious: () -> Void
    public var onNext: () -> Void
    public var delegate: PagerReaderModeDelegate?

    public init(
        count: Int,
        selection: Binding<Int>,
        previousSelection: Int,
        navDirection: Binding<PageDirection>,
        downsampleMaxPixel: @escaping (CGFloat) -> Int,
        urlForIndex: @escaping (Int) -> URL?,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        delegate: PagerReaderModeDelegate? = nil
    ) {
        self.count = count
        self._selection = selection
        self.previousSelection = previousSelection
        self._navDirection = navDirection
        self.downsampleMaxPixel = downsampleMaxPixel
        self.urlForIndex = urlForIndex
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.delegate = delegate
    }

    public var body: some View {
        InnerReaderPager(
            count: count,
            selection: $selection,
            previousSelection: previousSelection,
            navDirection: $navDirection,
            downsampleMaxPixel: downsampleMaxPixel,
            urlForIndex: urlForIndex,
            onPrevious: onPrevious,
            onNext: onNext,
            delegate: delegate
        )
    }
}

struct InnerReaderPager: View {
    var count: Int
    @Binding var selection: Int
    var previousSelection: Int
    @Binding var navDirection: PageDirection
    var downsampleMaxPixel: (CGFloat) -> Int
    var urlForIndex: (Int) -> URL?
    var onPrevious: () -> Void
    var onNext: () -> Void
    var delegate: PagerReaderModeDelegate?

    @State private var zoomScale: CGFloat = 1
    @State private var isZoomed: Bool = false

    @State private var slideProgress: CGFloat = 1
    @State private var activeDirection: PageDirection = .forward

    @State private var displayedIndex: Int = 0
    @State private var phase: Int = 0 // 0: steady, 1: sliding out, 2: sliding in
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                let width = geometry.size.width
                let isSlidingOut = phase == 1
                let isSlidingIn = phase == 2
                let dirSign: CGFloat = (activeDirection == .forward ? 1 : -1)
                let offsetX: CGFloat = {
                    if isSlidingOut {
                        return -dirSign * width * (1.10 * slideProgress)
                    } else if isSlidingIn {
                        return dirSign * width * (1.60 * (1 - slideProgress))
                    } else {
                        return 0
                    }
                }()
                let opacityVal: Double = {
                    if isSlidingOut {
                        return max(0, 1 - 0.55 * Double(slideProgress))
                    } else if isSlidingIn {
                        return min(1, 0.55 + 0.45 * Double(slideProgress))
                    } else {
                        return 1
                    }
                }()
                let scaleVal: CGFloat = {
                    if isSlidingOut {
                        return 1 - 0.50 * slideProgress
                    } else if isSlidingIn {
                        return 0.94 + 0.06 * slideProgress
                    } else {
                        return 1
                    }
                }()
                let blurVal: CGFloat = {
                    if isSlidingOut {
                        return 0 + 2 * slideProgress
                    } else if isSlidingIn {
                        return max(0, 2 * (1 - slideProgress))
                    } else {
                        return 0
                    }
                }()
                let shadowRadius: CGFloat = {
                    if isSlidingIn {
                        return 8 * slideProgress
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
                        downsampleMaxPixel: downsampleMaxPixel,
                        zoomScale: $zoomScale,
                        isZoomed: $isZoomed,
                        geometrySize: geometry.size
                    )
                    .accessibilityElement()
                    .accessibilityAddTraits(.isImage)
                    .gesture(
                        DragGesture(minimumDistance: isZoomed ? 20 : 10)
                            .onEnded { value in
                                guard !isZoomed else { return }
                                if value.translation.width < -50 {
                                    if selection < count - 1 {
                                        delegate?.pagerReaderModeWillNavigate(.forward)
                                        onNext()
                                    }
                                } else if value.translation.width > 50 {
                                    if selection > 0 {
                                        delegate?.pagerReaderModeWillNavigate(.backward)
                                        onPrevious()
                                    }
                                }
                            }
                    )
                    .offset(x: offsetX)
                    .opacity(opacityVal)
                    .scaleEffect(scaleVal)
                    .blur(radius: blurVal)
                    .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: 4)
                    .rotation3DEffect(.degrees(rotationDeg), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
                    .id(url)
                } else {
                    ReaderPlaceholder()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .offset(x: offsetX)
                        .opacity(opacityVal)
                        .scaleEffect(scaleVal)
                        .blur(radius: blurVal)
                        .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: 4)
                        .rotation3DEffect(.degrees(rotationDeg), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
                        .id("placeholder-\(displayedIndex)")
                }
            }
            .overlay {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: geometry.size.width * 0.3)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !isZoomed {
                                delegate?.pagerReaderModeWillNavigate(.backward)
                                onPrevious()
                            }
                        }
                    Color.clear
                        .frame(width: geometry.size.width * 0.4)
                        .allowsHitTesting(false)
                    Color.clear
                        .frame(width: geometry.size.width * 0.3)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !isZoomed {
                                delegate?.pagerReaderModeWillNavigate(.forward)
                                onNext()
                            }
                        }
                }
                .accessibilityHidden(true)
            }
            .onAppear {
                activeDirection = navDirection
                displayedIndex = selection
                slideProgress = 1
                phase = 0
            }
            .onChange(of: selection) { _, newValue in
                guard newValue != displayedIndex else { return }

                animationTask?.cancel()
                animationTask = nil
                withAnimation(.none) {
                    phase = 0
                    slideProgress = 1
                }

                animationTask = Task { @MainActor in
                    if Task.isCancelled { return }

                    activeDirection = navDirection

                    phase = 1
                    slideProgress = 0
                    withAnimation(.easeIn(duration: 0.18)) {
                        slideProgress = 1
                    }

                    do { try await Task.sleep(nanoseconds: 180_000_000) } catch { return }
                    if Task.isCancelled { return }

                    displayedIndex = newValue
                    isZoomed = false

                    phase = 2
                    slideProgress = 0
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.85)) {
                        slideProgress = 1
                    }

                    do { try await Task.sleep(nanoseconds: 360_000_000) } catch { return }
                    if Task.isCancelled { return }

                    phase = 0
                    slideProgress = 1
                }
            }
        }
    }
}

private struct ZoomablePage: View {
    var url: URL
    var downsampleMaxPixel: (CGFloat) -> Int

    @Binding var zoomScale: CGFloat
    @Binding var isZoomed: Bool

    var geometrySize: CGSize

    @State private var lastScaleValue: CGFloat = 1

    var body: some View {
        let maxSide = max(geometrySize.width, geometrySize.height)
        let isGIF = url.pathExtension.lowercased() == "gif"
        Group {
            if isGIF {
                GIFAnimatedImageView(url: url, contentMode: .fit)
                    .frame(maxWidth: geometrySize.width, maxHeight: geometrySize.height)
            } else {
                CGImageLoader(
                    url: url,
                    maxPixelProvider: { CGFloat(downsampleMaxPixel(maxSide)) },
                    content: { cg in
                        if let cg {
                            Image(decorative: cg, scale: 1, orientation: .up)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(maxWidth: geometrySize.width, maxHeight: geometrySize.height)
                        } else {
                            ReaderPlaceholder()
                                .frame(width: geometrySize.width, height: geometrySize.height)
                        }
                    }
                )
            }
        }
        .scaleEffect(zoomScale)
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let delta = value / lastScaleValue
                    lastScaleValue = value
                    let newScale = zoomScale * delta
                    zoomScale = min(max(newScale, 1), 8)
                    isZoomed = zoomScale > 1
                }
                .onEnded { _ in
                    if zoomScale < 1 {
                        zoomScale = 1
                        isZoomed = false
                    }
                    lastScaleValue = 1
                }
        )
        .animation(.easeInOut(duration: 0.2), value: zoomScale)
    }
}

private func ReaderPlaceholder() -> some View {
    ZStack {
        Color.gray.opacity(0.15)
        Image(systemName: "photo")
            .font(.system(size: 40))
            .foregroundStyle(.secondary)
    }
}
