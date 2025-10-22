import SwiftUI

struct ThumbnailImage: View {
    let url: URL?
    let maxPixel: CGFloat

    @State private var image: Image?

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                // Pure SwiftUI placeholder to avoid platform view flattening issues
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
                    .padding(24)
                    .task(id: url) { await load() }
            }
        }
    }

    @MainActor
    private func load() async {
        guard let url else { return }
        image = await ThumbnailCache.shared.image(for: url, maxPixel: maxPixel)
    }
}
