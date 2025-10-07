//
//  ContentView.swift
//  MetaComic
//
//  Created by Stardust on 2025-10-03.
//

import SwiftUI
import ZIPFoundation
internal import UniformTypeIdentifiers

struct MainView: View {
    @State private var showFileImporter = false
    @State private var hasFileOpened = false
    @State private var openedFile: URL?
    @State var comicInfoData: ComicInfoModel?

    var body: some View {
        if hasFileOpened {
            FileView(comicInfoData: $comicInfoData, fileURL: $openedFile)
        } else {
            VStack {
                HStack {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Open CBZ", systemImage: "zipper.page")
                    }
                    .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.zip]) { result in
                        switch result {
                        case .success(let fileURL):
                            do {
                                // Request a security scope
                                let hasAccess = fileURL.startAccessingSecurityScopedResource()
                                if !hasAccess { return }

                                // Make sure we exit our security scope
                                defer { fileURL.stopAccessingSecurityScopedResource() }

                                // Attempt to open our archive
                                let archive = try Archive(url: fileURL, accessMode: .read)

                                // Open ComicInfo.xml if it exists
                                if let file = archive["ComicInfo.xml"] {
                                    var comicInfo: Data = .init()

                                    // Extract file to memory
                                    _ = try archive.extract(file) { data in
                                        comicInfo.append(data)
                                    }

                                    // Parse XML
                                    let comicInfoXML: ComicInfoXML = .init(data: comicInfo)
                                    if !comicInfoXML.parse() {
                                        throw ComicInfoXMLError.parsingFailed
                                    }

                                    // Set variables to move to the next View
                                    comicInfoData = comicInfoXML.parsed

                                    // Ensure Pages covers all images in the archive
                                    let archiveHelper = ComicArchive(fileURL: fileURL)
                                    let total = archiveHelper.pageCount()
                                    if total > 0 {
                                        var finalPages = Array(repeating: ComicPageInfo(), count: total)
                                        // Default Image indices are zero-based to match PageDetailProvider expectations
                                        for i in 0..<total { finalPages[i].Image = String(i) }

                                        if let existing = comicInfoData?.Pages, !existing.isEmpty {
                                            let hasExplicitIndices = existing.contains { Int($0.Image) != nil }
                                            if hasExplicitIndices {
                                                for p in existing {
                                                    if let idx = Int(p.Image), idx >= 0, idx < total {
                                                        finalPages[idx] = p
                                                    }
                                                }
                                            } else {
                                                for (i, p) in existing.enumerated() where i < total {
                                                    finalPages[i] = p
                                                }
                                            }
                                        }

                                        comicInfoData?.Pages = finalPages
                                        comicInfoData?.PageCount = total
                                    }

                                    hasFileOpened = true
                                    openedFile = fileURL
                                } else {
                                    // Set variables to move to the next View
                                    comicInfoData = .init()

                                    // Initialize default Pages to match archive image count
                                    let archiveHelper = ComicArchive(fileURL: fileURL)
                                    let total = archiveHelper.pageCount()
                                    if total > 0 {
                                        var finalPages = Array(repeating: ComicPageInfo(), count: total)
                                        for i in 0..<total { finalPages[i].Image = String(i) }
                                        comicInfoData?.Pages = finalPages
                                        comicInfoData?.PageCount = total
                                    }

                                    hasFileOpened = true
                                    openedFile = fileURL
                                }
                            } catch {
                                print("An error occurred: \(error.localizedDescription)")
                            }

                        case .failure:
                            print("FAILZ")
                        }
                    }
                }
            }
        }
    }
}
