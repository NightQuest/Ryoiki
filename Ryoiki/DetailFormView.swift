import SwiftUI

/// Small form for editing per-page metadata fields.
struct DetailFormView: View {
    @Binding var pageType: ComicPageType
    @Binding var bookmark: String
    @Binding var doublePage: Bool
    @Binding var key: String

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Page Type")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help("Page Type")
                        Picker("", selection: $pageType) {
                            ForEach(ComicPageType.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    Divider()

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Bookmark")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help("Bookmark")
                        TextField("", text: $bookmark)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    Divider()

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Double Page")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help("Double Page")
                        Toggle("", isOn: $doublePage)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    Divider()

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Key")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help("Key")
                        TextField("", text: $key)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
                .padding(.top, 4)
            }
        }
    }
}
