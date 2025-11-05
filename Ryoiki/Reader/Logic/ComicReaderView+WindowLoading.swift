//
//  ComicReaderView+WindowLoading.swift
//  Ryoiki
//
//  Created by Stardust on 2025-11-05.
//

import SwiftUI

extension ComicReaderView {
    // MARK: - Window Loading

    func ensureLoadedWindow(around index: Int, radius: Int) async {
        guard !flatURLs.isEmpty else { return }
        if Task.isCancelled { return }

        // Snapshot state on main actor to avoid data races.
        let (urls, currentLoaded): ([URL], Set<Int>) = await MainActor.run {
            (self.flatURLs, self.loadedIndices)
        }

        let radius = max(0, radius)
        let lower = max(0, index - radius)
        let upper = min(urls.count - 1, index + radius)
        let target = Set(lower...upper)

        // Eagerly ensure current index is available for immediate display
        if !currentLoaded.contains(index) {
            _ = await MainActor.run { loadedIndices.insert(index) }
        }
        if Task.isCancelled { return }

        // Load missing indices in the target window
        let toLoad = target.subtracting(currentLoaded)
        let loadedPairs: [(Int, URL)] = toLoad.compactMap { i in
            (i >= 0 && i < urls.count) ? (i, urls[i]) : nil
        }
        await MainActor.run {
            for (i, _) in loadedPairs { loadedIndices.insert(i) }
        }
        if Task.isCancelled { return }

        // Compute dynamic decode size based on viewport and display scale
        let basePixels: CGFloat = (viewportMax > 0) ? (viewportMax * displayScale) : CGFloat(readerDownsampleMaxPixel)
        let dyn = min(Int(readerDownsampleMaxPixel), Int(basePixels))
        let maxPixel = max(256, dyn)

        let batchSize = 6
        let count = loadedPairs.count
        var start = 0
        while start < count {
            if Task.isCancelled { return }
            let end = min(start + batchSize, count)
            let chunk = loadedPairs[start..<end]
            await withTaskGroup(of: Void.self) { group in
                for (_, url) in chunk {
                    group.addTask {
                        await CGImageLoader.warm(url: url, maxPixel: maxPixel)
                    }
                }
                await group.waitForAll()
            }
            start = end
        }
        if Task.isCancelled { return }

        // Evict outside of window using a fresh snapshot
        await MainActor.run {
            let current = self.loadedIndices
            let outside = current.subtracting(target)
            if !outside.isEmpty {
                self.loadedIndices.subtract(outside)
            }
        }
    }
}
