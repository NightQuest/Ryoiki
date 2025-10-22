import SwiftUI

/// The app's main view that lists comics and provides tools to add and manage them.
struct AppRootView: View {
    @State private var selectedComic: Comic?
    @State private var displayInspector: Bool = false
    @State private var isInspectorAnimating: Bool = false

    var body: some View {
        ZStack {
            LibraryView(externalSelectedComic: $selectedComic, displayInspector: $displayInspector, isInspectorAnimating: $isInspectorAnimating)
        }
        .inspector(isPresented: $displayInspector) {
            if let comic = selectedComic {
                ComicDetailView(comic: comic, onClose: { selectedComic = nil })
            }
        }
        .onChange(of: displayInspector) { _, newValue in
            // Mark animation phase; delay reset to allow system animation to complete
            isInspectorAnimating = true
            // Estimate animation duration; adjust if needed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isInspectorAnimating = false
            }
            if !newValue { selectedComic = nil }
        }
        .onChange(of: selectedComic) { _, newValue in
            displayInspector = newValue != nil
        }
    }
}
