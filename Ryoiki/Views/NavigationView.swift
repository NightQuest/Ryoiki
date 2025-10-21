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
struct NavigationView: View {
    @State var selectedNavigation: NavigationItems = .library

    var body: some View {
        NavigationSplitView {
            List(NavigationItems.allCases, selection: $selectedNavigation) { item in
                NavigationLink(value: item) {
                    Label(item.localizedName, systemImage: item.systemImage)
                }
            }
        } detail: {
            switch selectedNavigation {
            case .library:
                LibraryView()
            }
        }
    }
}
