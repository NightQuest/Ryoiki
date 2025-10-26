//
//  PageTile.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-24.
//
import SwiftUI

struct ImageTile: View {
    let fileURL: URL
    let isSelected: Bool
    var title: String?
    var subtitle: String?

    init(fileURL: URL, isSelected: Bool, title: String?, subtitle: String?) {
        self.fileURL = fileURL
        self.isSelected = isSelected
        self.title = title
        self.subtitle = subtitle
    }

    init(fileURL: URL, isSelected: Bool, title: String?) {
        self.fileURL = fileURL
        self.isSelected = isSelected
        self.title = title
        self.subtitle = nil
    }

    init(fileURL: URL, isSelected: Bool, pageURL: String?) {
        self.fileURL = fileURL
        self.isSelected = isSelected
        self.title = nil
        if let pageURL, let host = URL(string: pageURL)?.host, !host.isEmpty {
            self.subtitle = host
        } else {
            self.subtitle = nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                    .fill(.quinary.opacity(0.4))
                ThumbnailImage(url: fileURL, maxPixel: 512)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
                    .overlay {
                        // Fallback placeholder overlay if the thumbnail fails to render
                        Rectangle()
                            .fill(Color.clear)
                            .overlay {
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                    .opacity(0.2)
                            }
                            .allowsHitTesting(false)
                    }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title {
                        Text(title)
                            .font(.subheadline)
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.1))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}
