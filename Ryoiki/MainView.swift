import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var context
    
    var body: some View {
        VStack {
            ContentUnavailableView("Select a comic",
                                   systemImage: "square.grid.2x2",
                                   description: Text("Choose a tile to see details"))
        }
        .toolbar { mainToolbar }
    }
    
    // MARK: - Toolbars
    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
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
