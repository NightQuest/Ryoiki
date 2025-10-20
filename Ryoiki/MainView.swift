import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var context

    @State var isAddingComic: Bool = false

    var body: some View {
        VStack {
            ContentUnavailableView("No web comics found",
                                   systemImage: "square.grid.2x2",
                                   description: Text("Add a web comic"))
        }
        .toolbar { mainToolbar }
        .sheet(isPresented: $isAddingComic) {
            AddComicView()
                .padding()
        }
    }

    // MARK: - Toolbars
    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                isAddingComic.toggle()
            } label: {
                Label("Add Web Comic", systemImage: "plus.app")
            }
        }

        ToolbarItemGroup {
            Button {
            } label: {
                Label("Fetch", systemImage: "tray.and.arrow.down")
            }
            .disabled(true)

            Button {
            } label: {
                Label("Update", systemImage: "square.and.arrow.down")
            }
            .disabled(true)
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(configurations: config)

    return MainView()
        .modelContainer(container)
}
