//
//  ComicReaderView+Persistence.swift
//  Ryoiki
//
//  Created by Stardust on 2025-11-05.
//

import SwiftUI

extension ComicReaderView {
    private func setReaderMode(_ mode: ReadingMode) { readerModeRaw = mode.rawValue }

    @MainActor
    func loadPerComicModeOverride() {
        perComicOverrideRaw = UserDefaults.standard.string(forKey: perComicModeKey)
        // Normalize: if override equals current default, drop it
        if perComicOverrideRaw == readerModeRaw { perComicOverrideRaw = nil; UserDefaults.standard.removeObject(forKey: perComicModeKey) }
    }

    @MainActor
    func savePerComicModeOverride(_ raw: String?) {
        // Store only if different from default; otherwise remove override
        if let raw, raw != readerModeRaw {
            UserDefaults.standard.set(raw, forKey: perComicModeKey)
            perComicOverrideRaw = raw
        } else {
            UserDefaults.standard.removeObject(forKey: perComicModeKey)
            perComicOverrideRaw = nil
        }
    }

    func cycleReaderMode() {
        let all = ReadingMode.allCases
        let current = readerMode
        guard let idx = all.firstIndex(of: current) else { savePerComicModeOverride(nil); return }
        let next = all[(idx + 1) % all.count]
        // Persist override only if different from default
        if next.rawValue == readerModeRaw {
            savePerComicModeOverride(nil)
        } else {
            savePerComicModeOverride(next.rawValue)
        }
    }
}
