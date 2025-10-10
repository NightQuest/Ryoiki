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
    @State private var hasSecurityScope: Bool = false
    @State private var showReauthAlert: Bool = false
    @State private var reauthTargetURL: URL?
    private enum ImporterMode { case open, reauth }
    @State private var importerMode: ImporterMode = .open
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
        Group {
            if hasFileOpened, openedFile != nil {
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
                        // Offer to re-authorize access to this file
                        reauthTargetURL = url
                        importerMode = .reauth
                        showReauthAlert = true
                        hasFileOpened = false
                        openedFile = nil
                    }
                    .onOpenSucceeded { url in
                        if let item = recents.add(url: url) {
                            if let resolved = recents.items.first(where: { $0.id == item.id })?.url {
                                recents.updateURL(for: item.id, to: resolved)
                            }
                        }
                    }
                    .transition(.opacity)
            } else {
                ZStack(alignment: .topLeading) {
                    // Background gradient
                    LinearGradient(colors: [
                        Color.accentColor.opacity(0.25),
                        Color.purple.opacity(0.20),
                        Color.indigo.opacity(0.20)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                    // Content card
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        HStack(alignment: .center) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                                        )
                                    Image(systemName: "book.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Ryoiki")
                                        .font(.system(size: 34, weight: .bold))
                                        .foregroundStyle(
                                            LinearGradient(colors: [.white, .white.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                                        )
                                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                                    Text("Open a Comic Book Archive or pick from your recent files")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    showFileImporter = true
                                }
                            } label: {
                                Label("Open CBZ", systemImage: "folder.badge.plus")
                                    .font(.headline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .glassCapsule()
                            }
                            .buttonStyle(.plain)
                        }

                        // Recents Header
                        HStack {
                            Text("Recent Files")
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.95))
                            Spacer()
                            if !recents.items.isEmpty {
                                Button("Clear") { recents.clear() }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }

                        Group {
                            if recents.items.isEmpty {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .imageScale(.large)
                                        .foregroundStyle(.white.opacity(0.7))
                                    Text("No recent files")
                                        .foregroundStyle(.white.opacity(0.7))
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            } else {
                                // Card-styled list
                                VStack(spacing: 10) {
                                    ForEach(Array(recents.items.prefix(5).enumerated()), id: \.1.id) { index, item in
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                openRecent(item)
                                            }
                                        } label: {
                                            RecentFileRow(
                                                item: item,
                                                lastOpenedFormatter: lastOpenedFormatter,
                                                needsReauth: needsReauth(item),
                                                onDelete: { recents.remove(id: item.id) },
                                                onReauthorize: {
                                                    reauthTargetURL = item.url ?? URL(fileURLWithPath: item.location)
                                                        .appendingPathComponent(item.fileName)
                                                    importerMode = .reauth
                                                    showReauthAlert = false
                                                    showFileImporter = true
                                                }
                                            )
                                            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 6)
                                            .overlay(alignment: .topLeading) {
                                                if index == 0 {
                                                    LinearGradient(colors: [Color.accentColor.opacity(0.35), .clear],
                                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                                        .allowsHitTesting(false)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .transition(.opacity)
                                    }
                                }
                                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: recents.items)
                            }
                        }
                    }
                    .padding(24)
                    .glassContainer()
                    .padding()
                }
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

                        switch importerMode {
                        case .open:
                            print("Primary importer success; proceeding to open")
                            handleOpen(url: fileURL)
                        case .reauth:
                            print("Reauth importer success; refreshing bookmark and reopening")
                            // Update recents with the newly authorized URL and reopen using resolved bookmark URL
                            if let item = recents.add(url: fileURL) {
                                // Try to use the resolved bookmark URL
                                if let resolved = recents.items.first(where: { $0.id == item.id })?.url {
                                    handleOpen(url: resolved)
                                } else {
                                    handleOpen(url: fileURL)
                                }
                            } else {
                                handleOpen(url: fileURL)
                            }
                            importerMode = .open
                            reauthTargetURL = nil
                        }
                    case .failure:
                        print("FAILZ")
                    }
                }
                .onAppear { recents.load() }
                .onChange(of: openedFile) { _, newValue in
                    if newValue == nil {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            hasFileOpened = false
                        }
                    }
                }
                .alert("Re-authorize File Access?", isPresented: $showReauthAlert, presenting: reauthTargetURL) { _ in
                    Button("Re-authorize") {
                        // Present importer to re-pick the file and refresh bookmark
                        showFileImporter = true
                    }
                    Button("Cancel", role: .cancel) {
                        importerMode = .open
                        reauthTargetURL = nil
                    }
                } message: { url in
                    Text("We no longer have permission to read this file. Pick it again to refresh permissions.\n\n\(url.lastPathComponent)")
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hasFileOpened)
    }

    private func openRecent(_ item: RecentFilesStore.Item) {
        // Helper to attempt opening a URL and refresh bookmark if needed
        func openAndRefresh(using url: URL, for item: RecentFilesStore.Item) {
            // If this came from a reconstructed path, refresh the store's bookmark
            recents.updateURL(for: item.id, to: url)
            handleOpen(url: url)
        }

        // First, try the resolved bookmark URL if present and reachable
        if let url = item.url {
            var isReachable = false
            do {
                isReachable = try url.checkResourceIsReachable()
            } catch {
                isReachable = false
            }

            if isReachable {
                handleOpen(url: url)
                return
            }
            // If not reachable, continue to fallback path reconstruction below
        }

        // Fallback: reconstruct a file URL from stored display fields
        let folderPath = item.location
        let filename = item.fileName
        let candidate = URL(fileURLWithPath: folderPath).appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: candidate.path) {
            // Refresh the store with a new bookmark for this path
            recents.updateURL(for: item.id, to: candidate)
            // Re-fetch the updated item and use its bookmark-resolved URL, if available
            if let refreshed = recents.items.first(where: { $0.id == item.id })?.url {
                handleOpen(url: refreshed)
            } else {
                // Fallback to the plain candidate if resolution failed for some reason
                handleOpen(url: candidate)
            }
            return
        }

        // If we cannot resolve or reconstruct, prompt to remove
        failedItem = item
        showRemoveFailedAlert = true
    }

    private func handleOpen(url fileURL: URL) {
        print("Opening file at: \(fileURL.path)")
        openedFile = fileURL
        withAnimation(.easeInOut(duration: 0.2)) {
            hasFileOpened = true
        }
    }

    private func needsReauth(_ item: RecentFilesStore.Item) -> Bool {
        guard let url = item.url else { return true }
        // Try to briefly start/stop scope to verify permission
        let ok = url.startAccessingSecurityScopedResource()
        if ok { url.stopAccessingSecurityScopedResource() }
        return !ok
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 14) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                )
        )
    }

    func glassContainer(cornerRadius: CGFloat = 24) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 16)
        )
    }

    func glassCapsule() -> some View {
        self.background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
    }
}

private struct RecentFileRow: View {
    let item: RecentFilesStore.Item
    let lastOpenedFormatter: DateFormatter
    let needsReauth: Bool
    let onDelete: () -> Void
    let onReauthorize: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        )
                    Image(systemName: "doc.zipper")
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title ?? item.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                            .foregroundStyle(.white.opacity(0.6))
                        Text(item.fileName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundStyle(.white.opacity(0.6))
                        Text(item.location)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(lastOpenedFormatter.string(from: item.lastOpened))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from Recents")
                }
            }
        }
        .padding(12)
        .glassCard()
        .contentShape(Rectangle())
    }
}
