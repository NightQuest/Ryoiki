//
//  ContentView.swift
//  MetaComic
//
//  Created by Stardust on 2025-10-03.
//

import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @StateObject private var vm = MainViewModel()
    @State var comicInfoData: ComicInfoModel?
    @State private var showFileImporter: Bool = false

    var body: some View {
        if vm.hasFileOpened, vm.openedFile != nil {
            FileView(comicInfoData: $comicInfoData, fileURL: $vm.openedFile)
                .onOpenFailed { _ in
                    vm.hasFileOpened = false
                    vm.openedFile = nil
                }
                .onOpenSucceeded { url in
                    if let item = vm.recents.add(url: url) {
                        if let resolved = vm.recents.items.first(where: { $0.id == item.id })?.url {
                            vm.recents.updateURL(for: item.id, to: resolved)
                        }
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: vm.hasFileOpened)
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
                        if !vm.recents.items.isEmpty {
                            Button("Clear") { vm.recents.clear() }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }

                    Group {
                        if vm.recents.items.isEmpty {
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
                                ForEach(Array(vm.recents.items.prefix(5).enumerated()), id: \.1.id) { index, item in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            vm.openRecent(item)
                                        }
                                    } label: {
                                        RecentFileRow(
                                            item: item,
                                            lastOpenedFormatter: vm.lastOpenedFormatter,
                                            needsReauth: vm.needsReauth(item),
                                            onDelete: { vm.recents.remove(id: item.id) },
                                            onReauthorize: {
                                                if let url = item.url {
                                                    vm.handleOpen(url: url)
                                                } else {
                                                    let candidate = URL(fileURLWithPath: item.location).appendingPathComponent(item.fileName)
                                                    vm.handleOpen(url: candidate)
                                                }
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
                            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: vm.recents.items)
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
                    vm.handleOpen(url: fileURL)
                case .failure:
                    break
                }
            }
            .onChange(of: vm.openedFile) { _, newValue in
                if newValue == nil {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.hasFileOpened = false
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: vm.hasFileOpened)
        }
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

    @State private var cover: Image?

    private func loadCoverIfNeeded() {
        let baseURL: URL? = item.url ?? URL(fileURLWithPath: item.location).appendingPathComponent(item.fileName)
        guard let u = baseURL else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let archive = ComicArchive(fileURL: u)
            let img = archive.coverImage()
            DispatchQueue.main.async { self.cover = img }
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 128, height: 128)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        )
                    if let cover {
                        cover
                            .resizable()
                            .scaledToFit()
                            .frame(width: 128, height: 128)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Image(systemName: "doc.zipper")
                            .foregroundStyle(Color.accentColor)
                    }
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
        .onAppear { loadCoverIfNeeded() }
    }
}
