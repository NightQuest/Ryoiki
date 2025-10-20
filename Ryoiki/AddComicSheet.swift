import SwiftUI
import SwiftData

struct AddComicView: View {
    @Environment(\.dismiss) private var dismiss

    @State var comicName: String = ""
    @State var comicAuthor: String = ""
    @State var comicDescription: String = ""
    @State var comicURL: String = ""
    @State var comicCurrentURL: String = ""
    @State var comicSelectorImage: String = ""
    @State var comicSelectorTitle: String = ""
    @State var comicSelectorNextPage: String = ""

    var body: some View {
        VStack {
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text("Add Web Comic")
                    .bold()
                Spacer()
                Button("Add") {}
            }
            .padding(.bottom)

            Form {
                Section("Details") {
                    TextField("Name", text: $comicName)
                        .help("The name of the Comic")
                    TextField("Author", text: $comicAuthor)
                        .help("A comma-seperated list of authors")
                    LabeledContent {
                        TextEditor(text: $comicDescription)
                    } label: {
                        Text("Description")
                    }
                    .help("A description or synopsis of the comic as a whole")
                }

                Section("URLs") {
                    TextField("Main", text: $comicURL)
                        .help("This is typically the home page of the comic")
                    TextField("First Page", text: $comicCurrentURL)
                        .help("The very first page of the comic")
                }

                Section("CSS Selectors") {
                    TextField("Image", text: $comicSelectorImage)
                        .help("For an image, it's recommended to use a css selector that can match multiple images")
                    TextField("Title", text: $comicSelectorTitle)
                        .help("The title can be anything, but a common one is #cc-newsheader")
                    TextField("Next Page", text: $comicSelectorNextPage)
                        .help("You'll want a css selector that matches the next page button")
                }
            }
        }
    }
}
