import SwiftUI

enum NavigationItems: Int, Hashable, CaseIterable, Identifiable, Codable {
    case library

    var id: Int { rawValue }

    var localizedName: LocalizedStringKey {
        switch self {
        case .library:
            return "Library"
        }
    }

    var systemImage: String {
        switch self {
        case .library:
            "books.vertical"
        }
    }
}

/// The app's main view that lists comics and provides tools to add and manage them.
struct AppRootView: View {
    @State var selectedNavigation: NavigationItems = .library
    @State private var selectedComic: Comic?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var displayInspector: Bool = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(NavigationItems.allCases, selection: $selectedNavigation) { item in
                NavigationLink(value: item) {
                    Label(item.localizedName, systemImage: item.systemImage)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 340)
        } detail: {
            switch selectedNavigation {
            case .library:
                LibraryView(externalSelectedComic: $selectedComic, displayInspector: $displayInspector)
            }
        }
        .inspector(isPresented: $displayInspector) {
            if let comic = selectedComic {
                ComicDetailView(comic: comic, onClose: { selectedComic = nil })
            }
        }
        .onChange(of: displayInspector) { _, newValue in
            if !newValue { selectedComic = nil }
        }
        .onChange(of: selectedComic) { _, newValue in
            displayInspector = newValue != nil
        }
    }
}
