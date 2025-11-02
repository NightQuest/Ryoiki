import SwiftUI

/// The app's main view that lists comics and provides tools to add and manage them.
struct AppRootView: View {
    @State private var selectedComic: Comic?
    @State private var isEditingComic: Bool = false
    @State private var isDisplayingComicPages: Bool = false
    @State private var isDisplayingComicReader: Bool = false
    @State private var isDisplayingComicDetails: Bool = false

    var body: some View {
        LibraryView(
            isEditingComic: $isEditingComic,
            isDisplayingComicPages: $isDisplayingComicPages,
            isDisplayingReader: $isDisplayingComicReader,
            externalSelectedComic: $selectedComic,
            isDisplayingComicDetails: $isDisplayingComicDetails
        )
        .onChange(of: selectedComic) { _, newValue in
            // If selection is cleared, also close any detail view that depends on it
            if newValue == nil {
                isDisplayingComicDetails = false
            }
        }
    }
}
