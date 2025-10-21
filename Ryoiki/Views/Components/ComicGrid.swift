import SwiftUI

struct ComicGrid: View {
    let comics: [Comic]
    @Binding var selectedComic: Comic?
    @Binding var isInspectorAnimating: Bool
    let itemsPerRowPreference: Int

    @State private var frozenWidth: CGFloat?

    var body: some View {
        ScrollView {
            GeometryReader { proxy in
                let liveWidth = proxy.size.width
                let effectiveWidth = (isInspectorAnimating ? (frozenWidth ?? liveWidth) : (frozenWidth ?? liveWidth))
                let columns = computedColumns(for: effectiveWidth, itemsPerRowPreference: itemsPerRowPreference)

                LazyVGrid(columns: columns, spacing: Layout.gridSpacing) {
                    ForEach(comics, id: \.id) { comic in
                        Button {
                            selectedComic = comic
                        } label: {
                            ComicTile(comic: comic, isSelected: selectedComic == comic)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Layout.gridPadding)
                .transaction { $0.animation = nil }
                .onAppear {
                    if frozenWidth == nil {
                        frozenWidth = liveWidth
                    }
                }
                .onChange(of: isInspectorAnimating) { _, animating in
                    if !animating {
                        // When animation ends, sync to the current width to avoid a final snap
                        frozenWidth = liveWidth
                    }
                }
                .onChange(of: proxy.size.width) { _, newWidth in
                    if !isInspectorAnimating {
                        frozenWidth = newWidth
                    }
                }
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                selectedComic = nil
            }
        )
    }

    private func computedColumns(for width: CGFloat, itemsPerRowPreference: Int, minTileWidth: CGFloat = 160) -> [GridItem] {
        let spacing = Layout.gridSpacing
        if itemsPerRowPreference > 0 {
            let count = itemsPerRowPreference
            return Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count)
        } else {
            let count = max(1, Int((width + spacing) / (minTileWidth + spacing)))
            return Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count)
        }
    }
}
