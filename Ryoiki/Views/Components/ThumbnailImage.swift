import SwiftUI

struct ThumbnailImage: View {
    let url: URL?
    let maxPixel: CGFloat
    let onFirstImage: (() -> Void)?

    @State private var image: Image?
    @State private var didNotify = false

    init(url: URL?, maxPixel: CGFloat, onFirstImage: (() -> Void)? = nil) {
        self.url = url
        self.maxPixel = maxPixel
        self.onFirstImage = onFirstImage
    }

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .scaledToFit()
                    .task {
                        if !didNotify {
                            didNotify = true
                            onFirstImage?()
                        }
                    }
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
        if image != nil && !didNotify {
            didNotify = true
            onFirstImage?()
        }
    }
}
