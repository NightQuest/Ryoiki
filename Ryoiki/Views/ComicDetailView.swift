import SwiftUI
import SwiftData
import ImageIO

private func imageFromData(_ data: Data) -> Image? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    return Image(decorative: cg, scale: 1, orientation: .up)
}

struct ComicDetailView: View {
    let comic: Comic

    // Optional callbacks supplied by parent to perform actions
    var onClose: (() -> Void)?
    var onRead: (() -> Void)?
    var onEdit: (() -> Void)?
    var onFetch: (() -> Void)?
    var onUpdate: (() -> Void)?
    var onOpenImages: (() -> Void)?
    var onCancelFetch: (() -> Void)?
    var onCancelUpdate: (() -> Void)?

    var isFetching: Bool = false
    var isUpdating: Bool = false

    @Environment(\.dismiss) private var dismiss

    @State private var isDescriptionExpanded: Bool = false
    @State private var isHoveringProgress: Bool = false

    private var coverImageView: some View {
        Group {
            if let data = comic.coverImage, let img = imageFromData(data) {
                img
                    .resizable()
                    .scaledToFill()
                    .frame(width: 240, height: 320)
                    .clipped()
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.quaternary)
                    Image(systemName: "photo")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 240, height: 320)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            }
        }
        .accessibilityLabel(Text("Cover Image"))
        .overlay(alignment: .bottom) {
            if isFetching || isUpdating {
                HStack(spacing: 8) {
                    Text(isUpdating ? "Updating…" : "Fetching…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    ZStack {
                        ProgressView()
                            .scaleEffect(0.8)
                            .opacity(isHoveringProgress ? 0 : 1)
                        if isHoveringProgress {
                            Button {
                                if isUpdating { onCancelUpdate?() } else { onCancelFetch?() }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Cancel")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.quaternary, lineWidth: 1))
                .padding(8)
                .transition(.opacity.combined(with: .scale))
                .animation(.default, value: isFetching || isUpdating)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) { isHoveringProgress = hovering }
                }
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(comic.name)
                .font(.system(size: 34, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if !comic.author.isEmpty {
                Text(comic.author)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if !comic.descriptionText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(comic.descriptionText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(isDescriptionExpanded ? nil : 3)
                        .animation(.default, value: isDescriptionExpanded)

                    Button(action: { isDescriptionExpanded.toggle() }, label: {
                        Text(isDescriptionExpanded ? "Less" : "More…")
                            .font(.subheadline)
                    })
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(isDescriptionExpanded ? "Show less description" : "Show more description"))
                }
                .padding(.top, 4)
            }

            HStack(spacing: 8) {
                if comic.pageCount > 0 { metricChip(systemImage: "doc.on.doc", "\(comic.pageCount) pages") }
                if comic.imageCount > 0 { metricChip(systemImage: "photo.on.rectangle", "\(comic.imageCount) images") }
                if comic.downloadedImageCount > 0 {
                    Button {
                        onOpenImages?()
                    } label: {
                        metricChip(systemImage: "arrow.down.circle", "\(comic.downloadedImageCount) downloaded")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)

            actionsRow
                .padding(.top, 12)
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 12) {
            if onRead != nil {
                Button {
                    onRead?()
                } label: {
                    Label("Read Comic", systemImage: "book")
                        .frame(minWidth: 0)
                }
                .buttonStyle(.borderedProminent)
            }

            if let url = URL(string: comic.url), !comic.url.isEmpty {
                Link(destination: url) {
                    Label("Home Page", systemImage: "safari")
                }
                .buttonStyle(.bordered)
            }

            if onEdit != nil {
                Button { onEdit?() } label: { Label("Edit", systemImage: "pencil") }
                    .buttonStyle(.bordered)
            }

            if onFetch != nil {
                Button { onFetch?() } label: { Label("Fetch", systemImage: "tray.and.arrow.down") }
                    .buttonStyle(.bordered)
                    .disabled(isFetching || isUpdating)
            }

            if onUpdate != nil {
                Button { onUpdate?() } label: { Label("Update", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.bordered)
                    .disabled(isFetching || isUpdating)
            }
        }
    }

    @ViewBuilder
    private func metricChip(systemImage: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
                .monospacedDigit()
        }
        .font(.footnote)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quinary.opacity(0.5), in: Capsule())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 24) {
                    coverImageView
                    titleBlock
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle(comic.name)
    }
}
