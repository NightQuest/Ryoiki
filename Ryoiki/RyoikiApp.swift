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
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .modelContainer(sharedModelContainer)
        .windowToolbarStyle(.expanded)
        .windowToolbarLabelStyle(fixed: .titleAndIcon)
    }
}
