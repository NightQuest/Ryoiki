//
//  ComicReaderView+State.swift
//  Ryoiki
//
//  Created by Stardust on 2025-11-05.
//

import SwiftUI

extension ComicReaderView {
    // MARK: - Mode Keys & Effective Mode
    var perComicModeKey: String { "reader.mode." + comic.id.uuidString }
    var effectiveModeRaw: String { perComicOverrideRaw ?? readerModeRaw }

    var readerMode: ReadingMode {
        ReadingMode(rawValue: effectiveModeRaw) ?? .pager
    }

    // MARK: - Derived UI State
    var currentPageIndex: Int {
        switch readerMode {
        case .pager:
            guard !pageToFirstFlatIndex.isEmpty else { return 0 }
            let idx = pageToFirstFlatIndex.lastIndex(where: { selection >= $0 }) ?? 0
            return min(idx, max(0, pageTitles.count - 1))
        case .vertical:
            return verticalVisiblePageIndex
        }
    }

    var navigationTitleText: String {
        let t = pageTitle(at: currentPageIndex)
        return t.isEmpty ? comic.name : "\(comic.name): \(t)"
    }
}
