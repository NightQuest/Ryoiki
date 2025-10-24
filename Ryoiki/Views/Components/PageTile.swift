//
//  PageTile.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-24.
//
import SwiftUI

struct PageTile: View {
    let page: ComicPage
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                    .fill(.quinary.opacity(0.4))
                if let url = page.downloadedFileURL {
                    ThumbnailImage(url: url, maxPixel: 512)
                        .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .padding(24)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(page.title.isEmpty ? "#\(page.index)" : page.title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text(URL(string: page.pageURL)?.host ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
