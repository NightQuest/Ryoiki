//
//  ComicReaderView+Computed.swift
//  Ryoiki
//
//  Created by Stardust on 2025-11-05.
//

import SwiftUI

extension ComicReaderView {
    // MARK: - Helpers

    func clampedIndex(_ i: Int) -> Int {
        guard !flatURLs.isEmpty else { return 0 }
        return min(max(0, i), flatURLs.count - 1)
    }

    var effectivePreloadRadius: Int {
        max(0, min(readerPreloadRadius, 12))
    }

    var pageSliderBinding: Binding<Double> {
        Binding(
            get: { Double(selection) },
            set: { raw in
                let newIndex = clampedIndex(Int(raw.rounded()))
                let delta = newIndex - selection
                withAnimation(.none) {
                    pageDirection = (abs(delta) > 1) ? .forward : (delta > 0 ? .forward : (delta < 0 ? .backward : .forward))
                    previousSelection = selection
                    selection = newIndex
                }
            }
        )
    }

    func computeDownsampleMaxPixel(for viewport: CGFloat) -> Int {
        let scaled = max(viewport, 1) * displayScale
        return max(256, min(Int(readerDownsampleMaxPixel), Int(scaled)))
    }

    func urlForFlatIndex(_ idx: Int) -> URL? {
        (loadedIndices.contains(idx) && idx >= 0 && idx < flatURLs.count) ? flatURLs[idx] : nil
    }

    func pageIndexForImageSelection(_ imageIndex: Int) -> Int {
        guard !pageToFirstFlatIndex.isEmpty else { return 0 }
        let idx = pageToFirstFlatIndex.lastIndex(where: { imageIndex >= $0 }) ?? 0
        return min(idx, max(0, pageTitles.count - 1))
    }

    func firstImageIndex(forPage page: Int) -> Int {
        guard page >= 0, page < pageToFirstFlatIndex.count else { return 0 }
        return pageToFirstFlatIndex[page]
    }

    var progressStore: ReadingProgressStore { ReadingProgressStore(comicName: comic.name, comicURL: comic.url) }

    func nextPage() {
        guard !flatURLs.isEmpty else { return }
        withAnimation(.snappy) {
            pageDirection = .forward
            previousSelection = selection
            selection = min(selection + 1, flatURLs.count - 1)
        }
    }

    func previousPage() {
        guard !flatURLs.isEmpty else { return }
        withAnimation(.snappy) {
            pageDirection = .backward
            previousSelection = selection
            selection = max(selection - 1, 0)
        }
    }

    func pageTitle(at index: Int) -> String {
        guard index >= 0, index < pageTitles.count else { return "" }
        return pageTitles[index]
    }
}
