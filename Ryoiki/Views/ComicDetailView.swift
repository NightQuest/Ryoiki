import SwiftUI
import SwiftData

struct ComicDetailView: View {
    let comic: Comic
    var onClose: (() -> Void)?

    @State private var frozenPageCount: Int?
    @State private var frozenImageCount: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(comic.name)
                    .font(.largeTitle)
                    .bold()

                if !comic.author.isEmpty {
                    LabeledContent("Author", value: comic.author)
                }

                if !(comic.pages.isEmpty) {
                    let count = frozenPageCount ?? comic.dedupedPageCount
                    LabeledContent("Pages", value: String(count))
                }

                if !(comic.pages.isEmpty) {
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
                if frozenPageCount == nil { frozenPageCount = comic.dedupedPageCount }
                if frozenImageCount == nil { frozenImageCount = comic.imageCount }
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
