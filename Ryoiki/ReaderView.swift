import SwiftUI

public struct ReaderView<ImageContent: View>: View {
    @Binding var currentIndex: Int
    let totalPages: Int
    let maxIndex: Int
    @ViewBuilder let imageContent: () -> ImageContent
    let pageHasMeaningfulValues: (Int) -> Bool

    public enum PageAttributeKind { case doublePage, bookmark, key, none }
    let attributeKindForPage: ((Int) -> PageAttributeKind)?

    @State private var sliderValue: Double = 0
    @State private var isEditing: Bool = false
    @State private var isProgrammaticChange: Bool = false

    private var pages: [Int] { Array(0..<totalPages) }

    private var snapTargets: [Int] {
        let candidates = pages.filter { pageHasMeaningfulValues($0) }
        return candidates.isEmpty ? pages : candidates
    }

    private func nearestSnap(to value: Double) -> Int {
        guard !snapTargets.isEmpty else { return Int(value.rounded()) }

        // Use distance first; on ties, use the fractional position to pick the side that feels closer.
        let frac = value - floor(value) // [0, 1)

        return snapTargets.min { a, b in
            let da = abs(Double(a) - value)
            let db = abs(Double(b) - value)
            if da != db { return da < db }
            // Tie-breaker: favor the higher tick if the thumb is past the midpoint, else the lower.
            if frac > 0.5 { return a > b }
            if frac < 0.5 { return a < b }
            // Exactly midpoint: prefer lower for stability.
            return a < b
        } ?? Int(value.rounded())
    }

    public init(currentIndex: Binding<Int>,
                totalPages: Int,
                maxIndex: Int,
                @ViewBuilder imageContent: @escaping () -> ImageContent,
                pageHasMeaningfulValues: @escaping (Int) -> Bool,
                attributeKindForPage: ((Int) -> PageAttributeKind)? = nil) {
        self._currentIndex = currentIndex
        self.totalPages = totalPages
        self.maxIndex = maxIndex
        self.imageContent = imageContent
        self.pageHasMeaningfulValues = pageHasMeaningfulValues
        self.attributeKindForPage = attributeKindForPage
    }

    private var pageInput: Binding<Int> {
        Binding(
            get: { Int(currentIndex + 1) },
            set: { currentIndex = $0 - 1 }
        )
    }

    public var body: some View {
        VStack {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.06))
                imageContent()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(8)
            }
            .frame(maxHeight: .infinity)

            let maxPageIndex = max(0, totalPages - 1)

            HStack(spacing: 12) {
                Spacer()
                Button {
                    isProgrammaticChange = true
                    currentIndex = max(0, currentIndex - 1)
                    DispatchQueue.main.async { isProgrammaticChange = false }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Previous Page")
                .accessibilityLabel("Previous Page")
                .disabled(currentIndex <= 0)

                TextField("", value: pageInput, format: .number)
                    .labelsHidden()
                    .frame(width: 60)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Page Number")

                Button {
                    isProgrammaticChange = true
                    currentIndex = min(maxPageIndex, currentIndex + 1)
                    DispatchQueue.main.async { isProgrammaticChange = false }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Next Page")
                .accessibilityLabel("Next Page")
                .disabled(currentIndex >= maxPageIndex)
                Spacer()
            }
            .onChange(of: currentIndex) { _, newIndex in
                let target = Double(max(0, min(maxPageIndex, newIndex)))
                if sliderValue != target {
                    sliderValue = target
                }
            }
            .onAppear {
                sliderValue = Double(max(0, min(maxPageIndex, currentIndex)))
            }

            if totalPages > 1 {
                SnappingSlider(
                    value: $sliderValue,
                    range: 0...Double(maxPageIndex),
                    snapTargets: snapTargets.map(Double.init),
                    snapOnTrackTap: true,
                    snapOnDragEnd: false,
                    trackHeight: 4,
                    thumbSize: 28
                )
                .background {
                    if attributeKindForPage != nil {
                        GeometryReader { geo in
                            let width = geo.size.width
                            let height = geo.size.height
                            let usableWidth = max(1, width - 28)
                            let midY = height / 2
                            let maxPageIndex = max(0, totalPages - 1)
                            Canvas { context, _ in
                                guard totalPages > 1, maxPageIndex > 0 else { return }

                                for item in 0..<totalPages {
                                    guard let kind = attributeKindForPage?(item) else { continue }

                                    let color: Color
                                    let tickHeight: CGFloat
                                    switch kind {
                                    case .doublePage:
                                        color = .orange
                                        tickHeight = height * 0.9
                                    case .bookmark:
                                        color = .blue
                                        tickHeight = height * 0.7
                                    case .key:
                                        color = .pink
                                        tickHeight = height * 0.55
                                    case .none:
                                        continue
                                    }

                                    let fraction: CGFloat = CGFloat(item) / CGFloat(maxPageIndex)
                                    let x: CGFloat = fraction * usableWidth + 14

                                    let rect = CGRect(x: x - 1, y: midY - tickHeight / 2, width: 2, height: tickHeight)
                                    context.fill(Path(rect), with: .color(color))
                                }
                            }
                            .accessibilityHidden(true)
                        }
                    }
                }
                .sensoryFeedback(.impact, trigger: currentIndex)
                .accessibilityLabel("Page")
                .onChange(of: sliderValue) { _, newValue in
                    if isEditing {
                        // While dragging, allow stopping at any integer page (no snapping)
                        let clamped = max(0, min(maxPageIndex, Int(newValue.rounded())))
                        if clamped != currentIndex {
                            currentIndex = clamped
                        }
                    } else if isProgrammaticChange {
                        // Programmatic updates should not snap
                        let clamped = max(0, min(maxPageIndex, Int(newValue.rounded())))
                        if clamped != currentIndex {
                            currentIndex = clamped
                        }
                    } else {
                        // Non-editing changes from direct slider interactions (track tap) should snap
                        let snapped = nearestSnap(to: newValue)
                        let clamped = max(0, min(maxPageIndex, snapped))
                        if clamped != currentIndex {
                            currentIndex = clamped
                        }
                        DispatchQueue.main.async {
                            withAnimation(.snappy(duration: 0.15)) {
                                sliderValue = Double(clamped)
                            }
                        }
                    }
                }
                .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
                    if !isEditing { isEditing = true }
                }.onEnded { _ in
                    isEditing = false
                })
            }
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var idx = 0
        var body: some View {
            ReaderView(currentIndex: $idx, totalPages: 195, maxIndex: 194) {
                Image(systemName: "book")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            } pageHasMeaningfulValues: { i in
                i % 3 == 0
            }
            .padding()
            .frame(height: 400)
        }
    }
    return Demo()
}
