import SwiftUI
import SwiftSoup

struct ComicInput {
    let name: String
    let author: String
    let description: String
    let url: String
    let firstPageURL: String
    let selectorImage: String
    let selectorTitle: String
    let selectorNext: String
}

struct AddComicView: View {
    @Environment(\.dismiss) private var dismiss
    var onSubmit: ((ComicInput) -> Void)?

    @State var comicName: String = ""
    @State var comicAuthor: String = ""
    @State var comicDescription: String = ""
    @State var comicURL: String = ""
    @State var comicCurrentURL: String = ""
    @State var comicSelectorImage: String = ""
    @State var comicSelectorTitle: String = ""
    @State var comicSelectorNextPage: String = ""
    @State private var showDiscardAlert: Bool = false

    @State private var isImageSelectorSyntaxValid: Bool = true
    @State private var isTitleSelectorSyntaxValid: Bool = true
    @State private var isNextSelectorSyntaxValid: Bool = true

    @State private var imageSelectorValidationWorkItem: DispatchWorkItem?
    @State private var titleSelectorValidationWorkItem: DispatchWorkItem?
    @State private var nextSelectorValidationWorkItem: DispatchWorkItem?

    var isValid: Bool {
        !comicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isValidURL(comicCurrentURL) &&
        !comicSelectorImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !comicSelectorNextPage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isImageSelectorSyntaxValid &&
        isNextSelectorSyntaxValid
    }

    private var hasUnsavedChanges: Bool {
        !(comicName.isEmpty &&
          comicAuthor.isEmpty &&
          comicDescription.isEmpty &&
          comicURL.isEmpty &&
          comicCurrentURL.isEmpty &&
          comicSelectorImage.isEmpty &&
          comicSelectorTitle.isEmpty &&
          comicSelectorNextPage.isEmpty)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fill in the details below. You can edit these later.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .padding(.horizontal)
                Form {
                    Section {
                        TextField("Name *", text: $comicName)
                        if comicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Name is required.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.top, 2)
                        }

                        TextField("Author(s)", text: $comicAuthor)
                            .help("Separate multiple authors with a comma")

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $comicDescription)
                                .frame(minHeight: 140)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.quaternary.opacity(0.3))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(.quaternary, lineWidth: 1)
                                )
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    } header: {
                        Text("Details")
                    } footer: {
                        Text("Provide a short description to help identify the comic later.")
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Main URL", text: $comicURL)
                            if !comicURL.isEmpty && !isValidURL(comicURL) {
                                Text("Enter a valid URL (http/https).")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .padding(.top, 2)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            TextField("First Page URL *", text: $comicCurrentURL)
                            if comicCurrentURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("First Page URL is required.")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .padding(.top, 2)
                            } else if !isValidURL(comicCurrentURL) {
                                Text("Enter a valid URL (http/https).")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .padding(.top, 2)
                            }
                        }
                    } header: {
                        Text("URLs")
                    } footer: {
                        Text("The main URL is usually the comic’s homepage. The first page URL points to the very first strip.")
                    }

                    Section {
                        TextField("Image selector *", text: $comicSelectorImage)
                            .onChange(of: comicSelectorImage) { _, newValue in
                                imageSelectorValidationWorkItem?.cancel()
                                let work = DispatchWorkItem { [newValue] in
                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if trimmed.isEmpty {
                                        isImageSelectorSyntaxValid = false
                                    } else {
                                        isImageSelectorSyntaxValid = isValidCSSSelector(trimmed)
                                    }
                                }
                                imageSelectorValidationWorkItem = work
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
                            }
                        let imageTrimmed = comicSelectorImage.trimmingCharacters(in: .whitespacesAndNewlines)
                        if imageTrimmed.isEmpty {
                            Text("Image selector is required.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.top, 2)
                        } else if !isImageSelectorSyntaxValid {
                            Text("This CSS selector appears invalid.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.top, 2)
                        }
                        TextField("Title selector", text: $comicSelectorTitle)
                            .onChange(of: comicSelectorTitle) { _, newValue in
                                titleSelectorValidationWorkItem?.cancel()
                                let work = DispatchWorkItem { [newValue] in
                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if trimmed.isEmpty {
                                        isTitleSelectorSyntaxValid = true // optional field: empty is acceptable
                                    } else {
                                        isTitleSelectorSyntaxValid = isValidCSSSelector(trimmed)
                                    }
                                }
                                titleSelectorValidationWorkItem = work
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
                            }
                        let titleTrimmed = comicSelectorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !titleTrimmed.isEmpty && !isTitleSelectorSyntaxValid {
                            Text("This CSS selector appears invalid.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.top, 2)
                        }
                        TextField("Next page selector *", text: $comicSelectorNextPage)
                            .onChange(of: comicSelectorNextPage) { _, newValue in
                                nextSelectorValidationWorkItem?.cancel()
                                let work = DispatchWorkItem { [newValue] in
                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if trimmed.isEmpty {
                                        isNextSelectorSyntaxValid = false
                                    } else {
                                        isNextSelectorSyntaxValid = isValidCSSSelector(trimmed)
                                    }
                                }
                                nextSelectorValidationWorkItem = work
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
                            }
                        let nextTrimmed = comicSelectorNextPage.trimmingCharacters(in: .whitespacesAndNewlines)
                        if nextTrimmed.isEmpty {
                            Text("Next page selector is required.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.top, 2)
                        } else if !isNextSelectorSyntaxValid {
                            Text("This CSS selector appears invalid.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.top, 2)
                        }
                    } header: {
                        Text("CSS Selectors")
                    } footer: {
                        Text("Use CSS selectors that are stable across pages. For example, prefer a class or id that’s consistently present.")
                    }
                }
                .formStyle(.grouped)
            }
            .navigationTitle("Add Web Comic")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasUnsavedChanges {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd() }
                        .disabled(!isValid)
                }
            }
            .alert("Discard changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("You have unsaved changes. If you discard, your edits will be lost.")
            }
            .onAppear {
                // Initialize validation states based on current values
                let img = comicSelectorImage.trimmingCharacters(in: .whitespacesAndNewlines)
                isImageSelectorSyntaxValid = !img.isEmpty && isValidCSSSelector(img)

                let ttl = comicSelectorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                isTitleSelectorSyntaxValid = ttl.isEmpty || isValidCSSSelector(ttl)

                let nxt = comicSelectorNextPage.trimmingCharacters(in: .whitespacesAndNewlines)
                isNextSelectorSyntaxValid = !nxt.isEmpty && isValidCSSSelector(nxt)
            }
        }
    }

    private func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string), let scheme = url.scheme else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func isValidCSSSelector(_ selector: String) -> Bool {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            let html = "<html><body><div id='probe' class='x y'></div></body></html>"
            let doc = try SwiftSoup.parse(html)
            _ = try doc.select(trimmed)
            return true
        } catch {
            return false
        }
    }

    private func onAdd() {
        let name = comicName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Normalize authors:
        // - Convert common separators to a comma
        // - Split, trim, collapse internal spaces, drop empties
        // - Join with ", "
        let normalizedAuthors: String = comicAuthor
            .replacingOccurrences(of: "，", with: ",") // full-width comma
            .replacingOccurrences(of: ";", with: ",")  // semicolon to comma
            .split(separator: ",")
            .map { part in
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                let collapsed = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                return collapsed
            }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        let description = comicDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        // Normalize URLs: trim and lowercase scheme
        func normalizeURLString(_ s: String) -> String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard var comps = URLComponents(string: t) else { return t }
            if let scheme = comps.scheme {
                comps.scheme = scheme.lowercased()
            }
            return comps.string ?? t
        }

        let url = normalizeURLString(comicURL)
        let firstPageURL = normalizeURLString(comicCurrentURL)

        let selectorImage = comicSelectorImage.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectorTitle = comicSelectorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectorNext = comicSelectorNextPage.trimmingCharacters(in: .whitespacesAndNewlines)

        let input = ComicInput(
            name: name,
            author: normalizedAuthors,
            description: description,
            url: url,
            firstPageURL: firstPageURL,
            selectorImage: selectorImage,
            selectorTitle: selectorTitle,
            selectorNext: selectorNext
        )
        onSubmit?(input)
        dismiss()
    }
}
