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
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(for: [Comic.self, ComicPage.self])
        .windowToolbarStyle(.expanded)
        .windowToolbarLabelStyle(fixed: .titleAndIcon)
    }
}
