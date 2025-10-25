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
        WindowGroup {
            AppRootView()
        }
        .modelContainer(modelContainer)
        .windowToolbarStyle(.expanded)
        .windowToolbarLabelStyle(fixed: .titleAndIcon)

#if os(macOS)
        Settings {
            SettingsView()
        }
        .windowToolbarStyle(.expanded)
        .windowToolbarLabelStyle(fixed: .titleAndIcon)
#endif
    }
}
