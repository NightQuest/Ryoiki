import SwiftUI

public struct SnappingSlider: View {
    @Binding public var value: Double
    public let range: ClosedRange<Double>
    public let snapTargets: [Double]

    public var snapOnTrackTap: Bool = true
    public var snapOnDragEnd: Bool = true
    public var trackHeight: CGFloat = 4
    public var thumbSize: CGFloat = 28

    public init(value: Binding<Double>,
                range: ClosedRange<Double>,
                snapTargets: [Double],
                snapOnTrackTap: Bool = true,
                snapOnDragEnd: Bool = true,
                trackHeight: CGFloat = 4,
                thumbSize: CGFloat = 28) {
        self._value = value
        self.range = range
        self.snapTargets = snapTargets
        self.snapOnTrackTap = snapOnTrackTap
        self.snapOnDragEnd = snapOnDragEnd
        self.trackHeight = trackHeight
        self.thumbSize = thumbSize
    }

    public var body: some View {
        GeometryReader { geo in
            let sortedTargets = snapTargets.sorted()
            // Helper closures to map value <-> x position
            let width = geo.size.width
            let xForValue: (Double) -> CGFloat = { val in
                let clamped = min(max(val, range.lowerBound), range.upperBound)
                let fraction = (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
                return CGFloat(fraction) * (width - thumbSize) + thumbSize / 2
            }
            let valueForX: (CGFloat) -> Double = { x in
                let limitedX = min(max(x, thumbSize / 2), width - thumbSize / 2)
                let fraction = Double((limitedX - thumbSize / 2) / (width - thumbSize))
                return fraction * (range.upperBound - range.lowerBound) + range.lowerBound
            }

            ZStack {
                // Track
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: trackHeight)
                    .frame(maxWidth: .infinity)

                // Tick marks
                ForEach(sortedTargets, id: \.self) { tick in
                    Rectangle()
                        .fill(Color.primary.opacity(0.5))
                        .frame(width: 2, height: trackHeight * 2)
                        .position(x: xForValue(tick), y: geo.size.height / 2)
                }

                // Thumb
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: thumbSize, height: thumbSize)
                    .position(x: xForValue(value), y: geo.size.height / 2)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                let newValue = valueForX(gesture.location.x)
                                let clamped = min(max(newValue, range.lowerBound), range.upperBound)
                                self.value = clamped
                            }
                            .onEnded { _ in
                                if snapOnDragEnd, let snap = nearestSnap(to: value) {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        self.value = snap
                                    }
                                }
                            }
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let tapValue = valueForX(location.x)
                if snapOnTrackTap, let snap = nearestSnap(to: tapValue) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.value = snap
                    }
                } else {
                    self.value = min(max(tapValue, range.lowerBound), range.upperBound)
                }
            }
        }
        .frame(height: max(trackHeight * 4, thumbSize))
    }

    private func nearestSnap(to val: Double) -> Double? {
        guard !snapTargets.isEmpty else { return nil }

        var nearest = snapTargets[0]
        var minDistance = abs(nearest - val)

        for i in 1..<snapTargets.count {
            let tick = snapTargets[i]
            let dist = abs(tick - val)
            if dist < minDistance {
                minDistance = dist
                nearest = tick
            } else if dist == minDistance {
                // Tie-breaker: prefer the lower tick
                nearest = min(nearest, tick)
            }
        }
        return nearest
    }
}

struct SnappingSlider_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var sliderValue: Double = 3
        let range: ClosedRange<Double> = 0...10
        let snaps: [Double] = [0, 2.5, 5, 7.5, 10]

        var body: some View {
            VStack(spacing: 40) {
                Text("Value: \(sliderValue, specifier: "%.2f")")
                    .font(.headline)
                SnappingSlider(value: $sliderValue, range: range, snapTargets: snaps)
                    .padding(.horizontal, 30)
            }
            .padding()
        }
    }

    static var previews: some View {
        PreviewWrapper()
            .previewLayout(.sizeThatFits)
    }
}
