import SwiftUI

public struct ReaderView<ImageContent: View>: View {
    @Binding var currentIndex: Int
    let totalPages: Int
    let maxIndex: Int
    @ViewBuilder let imageContent: () -> ImageContent
    let pageHasMeaningfulValues: (Int) -> Bool
    @State private var sliderValue: Double = 0
    @State private var isEditing: Bool = false

    private var snapTargets: [Int] {
        let candidates = (0..<totalPages).filter { pageHasMeaningfulValues($0) }
        return candidates.isEmpty ? Array(0..<totalPages) : candidates
    }

    private func nearestSnap(to value: Double) -> Int {
        let intValue = Int(value.rounded())
        return snapTargets.min(by: { abs($0 - intValue) < abs($1 - intValue) }) ?? intValue
    }

    public init(currentIndex: Binding<Int>,
                totalPages: Int,
                maxIndex: Int,
                @ViewBuilder imageContent: @escaping () -> ImageContent,
                pageHasMeaningfulValues: @escaping (Int) -> Bool) {
        self._currentIndex = currentIndex
        self.totalPages = totalPages
        self.maxIndex = maxIndex
        self.imageContent = imageContent
        self.pageHasMeaningfulValues = pageHasMeaningfulValues
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

            HStack(spacing: 12) {
                Spacer()
                Button {
                    currentIndex = max(0, currentIndex - 1)
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
                    currentIndex = min(maxIndex, currentIndex + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Next Page")
                .accessibilityLabel("Next Page")
                .disabled(currentIndex >= maxIndex)
                Spacer()
            }
            .onChange(of: currentIndex) { _, newIndex in
                let target = Double(max(0, min(maxIndex, newIndex)))
                if sliderValue != target {
                    sliderValue = target
                }
            }
            .onAppear {
                sliderValue = Double(max(0, min(maxIndex, currentIndex)))
            }

            if totalPages > 1 {
                Slider(
                    value: $sliderValue,
                    in: 0...Double(maxIndex),
                    step: 1,
                    onEditingChanged: { editing in
                        isEditing = editing
                        if !editing {
                            // Snap to nearest meaningful page and force the thumb to that value
                            let snapped = nearestSnap(to: sliderValue)
                            let clamped = max(0, min(maxIndex, snapped))
                            currentIndex = clamped
                            sliderValue = Double(clamped)
                        }
                    }
                )
                .sensoryFeedback(.impact, trigger: currentIndex)
                .background {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            ForEach(0..<totalPages, id: \.self) { i in
                                if pageHasMeaningfulValues(i) {
                                    let width = geo.size.width
                                    let horizontalPadding: CGFloat = 12
                                    let usableWidth = max(0, width - horizontalPadding * 2)
                                    let x = max(0, min(usableWidth, usableWidth * (CGFloat(i) / CGFloat(max(1, maxIndex))))) + horizontalPadding

                                    Color.accentColor
                                        .frame(width: 2)
                                        .frame(height: max(0, geo.size.height - 10))
                                        .position(x: x, y: geo.size.height / 2)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .accessibilityLabel("Page")
                .onChange(of: sliderValue) { _, newValue in
                    if isEditing {
                        // While dragging, keep currentIndex following the thumb (integer clamped)
                        let clamped = max(0, min(maxIndex, Int(newValue.rounded())))
                        if clamped != currentIndex {
                            currentIndex = clamped
                        }
                    } else {
                        // If the value changed without an editing session (e.g., track click), snap immediately
                        let snapped = nearestSnap(to: newValue)
                        let clamped = max(0, min(maxIndex, snapped))
                        if clamped != currentIndex {
                            currentIndex = clamped
                        }
                        if Double(clamped) != sliderValue {
                            sliderValue = Double(clamped)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var idx = 0
        var body: some View {
            ReaderView(currentIndex: $idx, totalPages: 10, maxIndex: 9) {
                Image(systemName: "book")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            } pageHasMeaningfulValues: { i in
                return i % 3 == 0
            }
            .padding()
            .frame(height: 400)
        }
    }
    return Demo()
}
