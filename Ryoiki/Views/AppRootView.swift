import SwiftUI

/// The app's main view that lists comics and provides tools to add and manage them.
struct AppRootView: View {
    @State private var selectedComic: Comic?
    @State private var displayInspector: Bool = false
    @State private var isInspectorAnimating: Bool = false
    @State private var isEditingComic: Bool = false

    var body: some View {
        ZStack {
            LibraryView(isEditingComic: $isEditingComic,
                        externalSelectedComic: $selectedComic,
                        displayInspector: $displayInspector,
                        isInspectorAnimating: $isInspectorAnimating)
        }
        .inspector(isPresented: Binding<Bool>(
            get: { displayInspector && !isEditingComic },
            set: { newValue in displayInspector = newValue }
        )) {
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
            if !newValue && !isEditingComic { selectedComic = nil }
        }
        .onChange(of: selectedComic) { _, newValue in
            if !isEditingComic {
                displayInspector = newValue != nil
            }
        }
        .onChange(of: isEditingComic) { _, editing in
            if !editing {
                displayInspector = selectedComic != nil
            }
        }
    }
}
