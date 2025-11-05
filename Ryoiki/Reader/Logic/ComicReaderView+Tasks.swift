//
//  ComicReaderView+Tasks.swift
//  Ryoiki
//
//  Created by Stardust on 2025-11-05.
//

import SwiftUI

extension ComicReaderView {
    // MARK: - Task Helpers

    func initialLoadTask() async {
        await MainActor.run { loadPerComicModeOverride() }
        // Build page-based arrays + flat arrays for pager
        let sortedPages = comic.pages.sorted { $0.index < $1.index }
        var perPageURLs: [[URL]] = []
        var titles: [String] = []
        var flat: [URL] = []
        var firstIndex: [Int] = []
        var running = 0
        for page in sortedPages {
            let urls = page.images.sorted { $0.index < $1.index }.compactMap { $0.fileURL }
            perPageURLs.append(urls)
            titles.append(page.title)
            firstIndex.append(running)
            running += urls.count
            flat.append(contentsOf: urls)
        }
        let restored = progressStore.load(totalPages: titles.count, totalImages: flat.count, pageToFirstFlatIndex: firstIndex)
        let restoredPage = restored.page

        await MainActor.run {
            self.pages = sortedPages
            self.pageImageURLs = perPageURLs
            self.pageTitles = titles
            self.pageToFirstFlatIndex = firstIndex
            self.flatURLs = flat
        }
        await MainActor.run {
            progress.configureTotals(pages: titles.count, images: flat.count)
        }

        let restoredImageIndex = min(max(0, (restoredPage < firstIndex.count ? firstIndex[restoredPage] : 0)), max(flat.count - 1, 0))
        await ensureLoadedWindow(around: restoredImageIndex, radius: effectivePreloadRadius)

        await MainActor.run { self.isReady = true }

        await Task.yield()

        await MainActor.run {
            withAnimation(.none) {
                self.pageDirection = .forward
                self.previousSelection = restoredImageIndex
                self.selection = restoredImageIndex
                self.verticalVisiblePageIndex = min(max(0, restoredPage), max(titles.count - 1, 0))
                progress.updatePage(restoredPage)
                progress.updateImageIndex(restoredImageIndex)
            }
        }
    }

    func selectionChangedTask(newValue: Int) async {
        await ensureLoadedWindow(around: newValue, radius: effectivePreloadRadius)
        await MainActor.run {
            verticalVisiblePageIndex = currentPageIndex
            progress.updateImageIndex(newValue)
            progressStore.save(progress: progress)
        }
    }

    func verticalVisiblePageChangedTask(newValue: Int) async {
        if newValue >= 0, newValue < pageToFirstFlatIndex.count {
            let centerIndex = pageToFirstFlatIndex[newValue]
            await ensureLoadedWindow(around: centerIndex, radius: effectivePreloadRadius)
        }
        await MainActor.run {
            if newValue >= 0, newValue < pageToFirstFlatIndex.count {
                let imgIndex = pageToFirstFlatIndex[newValue]
                previousSelection = selection
                selection = min(max(0, imgIndex), max(flatURLs.count - 1, 0))
            }
            progress.updatePage(newValue)
            progressStore.save(progress: progress)
        }
    }

    func modeChanged(oldRaw: String, newRaw: String) {
        // Compute source page from the PREVIOUS mode, then map into the new mode.
        let oldMode = ReadingMode(rawValue: oldRaw) ?? .pager
        let newMode = ReadingMode(rawValue: newRaw) ?? .pager

        let sourcePage: Int = {
            switch oldMode {
            case .pager:
                return pageIndexForImageSelection(selection)
            case .vertical:
                return min(max(0, verticalVisiblePageIndex), max(pageTitles.count - 1, 0))
            }
        }()

        Task { @MainActor in
            if newMode.rawValue == ReadingMode.pager.rawValue {
                // Jump pager selection to the first image of the source page
                let imgIndex = firstImageIndex(forPage: sourcePage)
                withAnimation(.none) {
                    previousSelection = selection
                    selection = min(max(0, imgIndex), max(flatURLs.count - 1, 0))
                    pageDirection = .forward
                }
                await ensureLoadedWindow(around: selection, radius: effectivePreloadRadius)
                progress.updateImageIndex(selection)
                progress.updatePage(sourcePage)
                progressStore.save(progress: progress)
                // Keep vertical page in sync as well
                verticalVisiblePageIndex = min(max(0, sourcePage), max(pageTitles.count - 1, 0))
            } else {
                // Vertical mode: show the same page and warm around it
                verticalVisiblePageIndex = min(max(0, sourcePage), max(pageTitles.count - 1, 0))
                progress.updatePage(sourcePage)
                progressStore.save(progress: progress)
                if sourcePage >= 0, sourcePage < pageToFirstFlatIndex.count {
                    let centerIndex = pageToFirstFlatIndex[sourcePage]
                    await ensureLoadedWindow(around: centerIndex, radius: effectivePreloadRadius)
                }
            }
        }
    }

    func saveOnDisappear() {
        Task { @MainActor in
            progressStore.save(progress: progress)
        }
    }
}
