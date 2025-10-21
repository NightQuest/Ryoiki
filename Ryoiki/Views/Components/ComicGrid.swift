import SwiftUI

struct ComicGrid: View {
    let comics: [Comic]
    @Binding var selectedComic: Comic?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Layout.gridColumns, spacing: Layout.gridSpacing) {
                ForEach(comics, id: \.self) { comic in
                    Button {
                        selectedComic = comic
                    } label: {
                        ComicTile(comic: comic, isSelected: selectedComic == comic)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Layout.gridPadding)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                selectedComic = nil
            }
        )
    }
}
