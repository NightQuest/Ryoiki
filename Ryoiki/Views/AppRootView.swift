import SwiftUI

/// The app's main view that lists comics and provides tools to add and manage them.
struct AppRootView: View {
    @State private var selectedComic: Comic?
    @State private var displayInspector: Bool = false
    @State private var isEditingComic: Bool = false
    @State private var isDisplayingComicPages: Bool = false
    @State private var isDisplayingComicReader: Bool = false

    var body: some View {
        ZStack {
            LibraryView(isEditingComic: $isEditingComic,
                        isDisplayingComicPages: $isDisplayingComicPages,
                        isDisplayingReader: $isDisplayingComicReader,
                        externalSelectedComic: $selectedComic,
                        displayInspector: $displayInspector)
        }
        .onChange(of: isEditingComic) { _, editing in
            if !editing {
                displayInspector = selectedComic != nil
            }
        }
        .onChange(of: isDisplayingComicPages) { _, viewing in
            if !viewing {
                displayInspector = selectedComic != nil
            }
        }
        .onChange(of: isDisplayingComicReader) { _, viewing in
            if !viewing {
                displayInspector = selectedComic != nil
            }
        }
        .onChange(of: displayInspector) { _, newValue in
            if !newValue && !isEditingComic && !isDisplayingComicPages && !isDisplayingComicReader {
                selectedComic = nil
            }
        }
        .onChange(of: selectedComic) { _, newValue in
            if !isEditingComic && !isDisplayingComicPages && !isDisplayingComicReader {
                displayInspector = newValue != nil
            }
        }
        .inspector(isPresented: Binding<Bool>(
            get: { displayInspector && !isEditingComic && !isDisplayingComicPages && !isDisplayingComicReader },
            set: { newValue in
                displayInspector = newValue &&
                !isEditingComic &&
                !isDisplayingComicPages &&
                !isDisplayingComicReader
            }
        )) {
            if let comic = selectedComic, !isEditingComic && !isDisplayingComicPages && !isDisplayingComicReader {
                ComicDetailView(comic: comic, onClose: { selectedComic = nil })
            }
        }
    }
}
