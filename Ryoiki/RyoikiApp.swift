//
//  RyoikiApp.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-16.
//

import SwiftUI
import SwiftData

@main
struct RyoikiApp: App {
    let modelContainer: ModelContainer

    init() {
        // Register default settings values on first launch
        UserDefaults.standard.register(defaults: [
            .settingsLibraryItemsPerRow: 6,
            .settingsReaderPreloadRadius: 10,
            .settingsReaderDownsampleMaxPixel: 2048,
            .settingsNetworkUserAgent: defaultUserAgent,
            .settingsNetworkPerHost: 6,
            .settingsDownloadMaxConcurrent: 10,
            .settingsReaderMode: "pager",
            .settingsVerticalPillarboxEnabled: false,
            .settingsVerticalPillarboxWidth: 0
        ])

        do {
            modelContainer = try ModelContainer(
                for: Comic.self, ComicPage.self,
                migrationPlan: ComicMigrationPlan.self
            )
        } catch {
            fatalError("Failed to initialize model container.")
        }
    }

    var body: some Scene {
#if !os(macOS)
        WindowGroup {
            AppRootView()
        }
        .modelContainer(modelContainer)
#else
        WindowGroup {
            AppRootView()
        }
        .modelContainer(modelContainer)
        .windowToolbarStyle(.expanded)
        .windowToolbarLabelStyle(fixed: .titleAndIcon)

        Settings {
            SettingsView()
        }
        .windowToolbarStyle(.expanded)
        .windowToolbarLabelStyle(fixed: .titleAndIcon)
#endif
    }
}
