//
//  ContentView.swift
//  MetaComic
//
//  Created by Stardust on 2025-10-03.
//

import SwiftUI
import ZIPFoundation
import UniformTypeIdentifiers

struct MainView: View {
    @StateObject private var recents = RecentFilesStore()
    @State private var showFileImporter = false
    @State private var hasFileOpened = false
    @State private var openedFile: URL?
    @State var comicInfoData: ComicInfoModel?

    @State private var failedItem: RecentFilesStore.Item?
    @State private var showRemoveFailedAlert: Bool = false

    private let lastOpenedFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    var body: some View {
        if hasFileOpened {
            AnyView(
                FileView(comicInfoData: $comicInfoData, fileURL: $openedFile)
                    .onOpenFailed { url in
                        print("FileView failed to open: \(url.path)")
                        if let item = recents.items.first(where: { $0.url == url }) {
                            failedItem = item
                        } else if let item = recents.items.first(where: { $0.fileName == url.lastPathComponent }) {
                            failedItem = item
                        } else {
                            failedItem = nil
                        }
                        showRemoveFailedAlert = true
                        hasFileOpened = false
                        openedFile = nil
                    }
                    .onOpenSucceeded { url in
                        _ = recents.add(url: url)
                    }
            )
        } else {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ryoiki")
                            .font(.largeTitle.bold())
                        Text("Open a Comic Book Archive or pick from your recent files")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Open CBZ", systemImage: "folder.badge.plus")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Recents Header
                HStack {
                    Text("Recent Files")
                        .font(.headline)
                    Spacer()
                    if !recents.items.isEmpty {
                        Button("Clear") { recents.clear() }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                }

                if recents.items.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .imageScale(.large)
                            .foregroundStyle(.secondary)
                        Text("No recent files")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    List(recents.items.prefix(5), id: \.id) { item in
                        Button {
                            openRecent(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "doc.zipper")
                                            .foregroundStyle(Color.accentColor)
                                        Text(item.title ?? item.name)
                                            .font(.headline)
                                    }
                                    Spacer()
                                    Text(lastOpenedFormatter.string(from: item.lastOpened))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                // Filename beneath the title
                                HStack(spacing: 6) {
                                    Image(systemName: "doc")
                                        .foregroundStyle(.secondary)
                                    Text(item.fileName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                // Location line (kept for context)
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                        .foregroundStyle(.secondary)
                                    Text(item.location)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 220)
                }
            }
            .padding()
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [
                    UTType(filenameExtension: "cbz") ?? .zip,
                    .zip
                ]
            ) { result in
                switch result {
                case .success(let fileURL):
                    print("Importer selected: \(fileURL.path)")
                    let didAccess = fileURL.startAccessingSecurityScopedResource()
                    print("Importer scope acquired: \(didAccess)")
                    defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }
                    print("Primary importer success; proceeding to open")
                    handleOpen(url: fileURL)
                case .failure:
                    print("FAILZ")
                }
            }
            .onAppear { recents.load() }
            .alert("Remove from Recents?", isPresented: $showRemoveFailedAlert, presenting: failedItem) { item in
                Button("Remove", role: .destructive) {
                    recents.remove(id: item.id)
                }
                Button("Cancel", role: .cancel) { }
            } message: { item in
                Text("The file could not be opened. Would you like to remove it from Recents?\n\n\(item.fileName)")
            }
        }
    }

    private func openRecent(_ item: RecentFilesStore.Item) {
        // First try the resolved bookmark URL
        if let url = item.url {
            handleOpen(url: url)
            return
        }

        // Fallback: reconstruct a file URL from stored display fields
        let folderPath = item.location
        let filename = item.fileName
        let candidate = URL(fileURLWithPath: folderPath).appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: candidate.path) {
            // Refresh the store with a new bookmark for this path
            recents.updateURL(for: item.id, to: candidate)
            handleOpen(url: candidate)
            return
        }

        // If we cannot resolve or reconstruct, prompt to remove
        failedItem = item
        showRemoveFailedAlert = true
    }

    private func handleOpen(url fileURL: URL) {
        print("Opening file at: \(fileURL.path)")
        openedFile = fileURL
        hasFileOpened = true
    }
}
