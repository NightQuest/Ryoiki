import SwiftUI
import SwiftData

struct ComicDetailView: View {
    let comic: Comic
    var onClose: (() -> Void)?

    @State private var frozenPageCount: Int?
    @State private var frozenImageCount: Int?

    private func refreshFrozenCounts() {
        frozenPageCount = comic.pageCount
        frozenImageCount = comic.imageCount
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(comic.name)
                    .font(.largeTitle)
                    .bold()

                if !comic.author.isEmpty {
                    LabeledContent("Author", value: comic.author)
                }

                if comic.pageCount > 0 {
                    let count = frozenPageCount ?? comic.pageCount
                    LabeledContent("Pages", value: String(count))
                }

                if comic.imageCount > 0 {
                    let count = frozenImageCount ?? comic.imageCount
                    LabeledContent("Images", value: String(count))
                }

                if !comic.descriptionText.isEmpty {
                    Text(comic.descriptionText)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .padding(.vertical, 8)

                HStack(spacing: 12) {
                    if !comic.url.isEmpty, let url = URL(string: comic.url) {
                        Link(destination: url) {
                            Label("Homepage", systemImage: "safari")
                        }
                    }

                    if let firstURL = URL(string: comic.firstPageURL) {
                        Link(destination: firstURL) {
                            Label("First Page", systemImage: "arrow.right.circle")
                        }
                    }
                }
            }
            .padding()
            .onDisappear {
                frozenPageCount = nil
                frozenImageCount = nil
            }
            .task {
                if frozenPageCount == nil { frozenPageCount = comic.pageCount }
                if frozenImageCount == nil { frozenImageCount = comic.imageCount }
            }
            .onChange(of: comic.name) { _, _ in
                refreshFrozenCounts()
            }
            .onChange(of: comic.firstPageURL) { _, _ in
                refreshFrozenCounts()
            }
        }
        .navigationTitle(comic.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let onClose {
                    Button("Close", systemImage: "xmark.circle.fill") {
                        onClose()
                    }
                }
            }
        }
    }
}
