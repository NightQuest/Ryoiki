import SwiftUI
import Observation
import SwiftData
import SwiftSoup

private struct ValidationText: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
            .padding(.top, 2)
    }
}

struct ComicEditorView: View {
    // MARK: External API
    /// Called when the user confirms the form.
    var onSubmit: ((ComicInput) -> Void)?
    let comicToEdit: Comic?

    // MARK: Internal State
    @Environment(\.dismiss) var dismiss

    @State private var showDiscardAlert: Bool = false

    // Form Fields
    @State private var comicName: String
    @State private var comicAuthor: String
    @State private var comicDescription: String
    @State private var comicURL: String
    @State private var comicCurrentURL: String

    // Initial snapshot for change detection
    private let initialName: String
    private let initialAuthor: String
    private let initialDescription: String
    private let initialURL: String
    private let initialFirstPageURL: String
    private let initialSelectorImage: String
    private let initialSelectorTitle: String
    private let initialSelectorNext: String

    // Validation state
    @State private var isImageSelectorSyntaxValid: Bool = true
    @State private var isTitleSelectorSyntaxValid: Bool = true
    @State private var isNextSelectorSyntaxValid: Bool = true

    // Debounced validation tasks
    @State private var imageValidationTask: Task<Void, Never>?
    @State private var titleValidationTask: Task<Void, Never>?
    @State private var nextValidationTask: Task<Void, Never>?

    @State private var comicSelectorImage: String
    @State private var comicSelectorTitle: String
    @State private var comicSelectorNextPage: String

    init(comicToEdit: Comic? = nil, onSubmit: ((ComicInput) -> Void)? = nil) {
        self.comicToEdit = comicToEdit
        self.onSubmit = onSubmit
        if let comic = comicToEdit {
            _comicName = State(initialValue: comic.name)
            _comicAuthor = State(initialValue: comic.author)
            _comicDescription = State(initialValue: comic.descriptionText)
            _comicURL = State(initialValue: comic.url)
            _comicCurrentURL = State(initialValue: comic.firstPageURL)
            _comicSelectorImage = State(initialValue: comic.selectorImage)
            _comicSelectorTitle = State(initialValue: comic.selectorTitle)
            _comicSelectorNextPage = State(initialValue: comic.selectorNext)

            self.initialName = comic.name
            self.initialAuthor = comic.author
            self.initialDescription = comic.descriptionText
            self.initialURL = comic.url
            self.initialFirstPageURL = comic.firstPageURL
            self.initialSelectorImage = comic.selectorImage
            self.initialSelectorTitle = comic.selectorTitle
            self.initialSelectorNext = comic.selectorNext
        } else {
            _comicName = State(initialValue: "")
            _comicAuthor = State(initialValue: "")
            _comicDescription = State(initialValue: "")
            _comicURL = State(initialValue: "")
            _comicCurrentURL = State(initialValue: "")
            _comicSelectorImage = State(initialValue: "")
            _comicSelectorTitle = State(initialValue: "")
            _comicSelectorNextPage = State(initialValue: "")

            self.initialName = ""
            self.initialAuthor = ""
            self.initialDescription = ""
            self.initialURL = ""
            self.initialFirstPageURL = ""
            self.initialSelectorImage = ""
            self.initialSelectorTitle = ""
            self.initialSelectorNext = ""
        }
    }

    // MARK: Body
    var body: some View {

        GeometryReader { proxy in
            let isTwoColumn = proxy.size.width >= 900

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fill in the details below. You can edit these later.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .padding(.top)
                    }

                    if isTwoColumn {
                        HStack(alignment: .top, spacing: 24) {
                            leftForm
                                .frame(minWidth: 360, maxWidth: .infinity, alignment: .topLeading)
                            rightForm
                                .frame(minWidth: 360, maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        VStack(spacing: 24) {
                            leftForm
                            rightForm
                                .padding(.bottom)
                        }
                    }
                }
                .padding(.horizontal)
                .frame(maxWidth: 1200, alignment: .center)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                initializeValidationStates()
            }
        }
        .navigationTitle(comicToEdit == nil ? "Add Web Comic" : "Edit Web Comic")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                cancelButton
            }
            ToolbarItem(placement: .confirmationAction) {
                addButton
            }
        }
        .alert("Discard changes?",
               isPresented: $showDiscardAlert,
               actions: { discardAlertActions },
               message: { discardAlertMessage }
        )
    }

    // MARK: Toolbar Buttons

    @ViewBuilder
    private var cancelButton: some View {
        Button("Cancel") {
            if hasUnsavedChanges {
                showDiscardAlert = true
            } else {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var addButton: some View {
        Button(comicToEdit == nil ? "Add" : "Save") {
            if let input = buildInput() {
                onSubmit?(input)
                dismiss()
            }
        }
        .disabled(!isValid)
    }

    // MARK: Alert

    @ViewBuilder
    private var discardAlertActions: some View {
        Button("Discard", role: .destructive) { dismiss() }
        Button("Keep Editing", role: .cancel) { }
    }

    @ViewBuilder
    private var discardAlertMessage: some View {
        Text("You have unsaved changes. If you discard, your edits will be lost.")
    }

    // MARK: New Layout Subviews

    @ViewBuilder
    private var leftForm: some View {
        VStack(spacing: 16) {
            cardSection(title: "Details") {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name *")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Name", text: $comicName)
                            .textFieldStyle(.roundedBorder)
                        if isComicNameEmpty {
                            ValidationText(message: "Name is required.")
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Author(s)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Author(s)", text: $comicAuthor)
                            .textFieldStyle(.roundedBorder)
                            .help("Separate multiple authors with a comma")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $comicDescription)
                            .frame(minHeight: 140)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.background)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(.quaternary, lineWidth: 1)
                            )
                    }
                }
                Text("Provide a short description to help identify the comic later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            cardSection(title: "URLs") {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Homepage")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Homepage", text: $comicURL)
                            .textFieldStyle(.roundedBorder)
                        if isMainURLPresentAndInvalid {
                            ValidationText(message: "Enter a valid URL (http/https).")
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("First Page URL *")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("First Page URL", text: $comicCurrentURL)
                            .textFieldStyle(.roundedBorder)
                        if isFirstPageURLEmpty {
                            ValidationText(message: "First Page URL is required.")
                        } else if isFirstPageURLInvalid {
                            ValidationText(message: "Enter a valid URL (http/https).")
                        }
                    }
                }
                Text("The Homepage is usually the comic’s main website URL. The first page URL points to the very first strip.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var rightForm: some View {
        VStack(spacing: 16) {
            cardSection(title: "CSS Selectors") {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Image selector *")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Image selector", text: $comicSelectorImage)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: comicSelectorImage) { _, _ in scheduleImageValidation() }
                        if isImageSelectorEmpty {
                            ValidationText(message: "Image selector is required.")
                        } else if !isImageSelectorSyntaxValid {
                            ValidationText(message: "This CSS selector appears invalid.")
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Title selector")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Title selector", text: $comicSelectorTitle)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: comicSelectorTitle) { _, _ in scheduleTitleValidation() }
                        if isTitleSelectorNonEmptyAndInvalid {
                            ValidationText(message: "This CSS selector appears invalid.")
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Next page selector *")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Next page selector", text: $comicSelectorNextPage)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: comicSelectorNextPage) { _, _ in scheduleNextValidation() }
                        if isNextSelectorEmpty {
                            ValidationText(message: "Next page selector is required.")
                        } else if !isNextSelectorSyntaxValid {
                            ValidationText(message: "This CSS selector appears invalid.")
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("• Prefer stable selectors like IDs or persistent classes.")
                    Text("• Avoid selectors that rely on positions (e.g., nth-child) if the layout changes.")
                    Text("• Test selectors on multiple pages to ensure consistency.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func cardSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    // MARK: - Validation & Helpers

    private var isComicNameEmpty: Bool { comicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isMainURLPresentAndInvalid: Bool { !comicURL.isEmpty && !isValidURL(comicURL) }
    private var isFirstPageURLEmpty: Bool { comicCurrentURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isFirstPageURLInvalid: Bool { !isFirstPageURLEmpty && !isValidURL(comicCurrentURL) }
    private var isImageSelectorEmpty: Bool { comicSelectorImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isTitleSelectorNonEmptyAndInvalid: Bool {
        let trimmed = comicSelectorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !isTitleSelectorSyntaxValid
    }
    private var isNextSelectorEmpty: Bool { comicSelectorNextPage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var isValid: Bool {
        !comicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isValidURL(comicCurrentURL) &&
        !comicSelectorImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !comicSelectorNextPage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isImageSelectorSyntaxValid &&
        isNextSelectorSyntaxValid
    }

    private var hasUnsavedChanges: Bool {
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        return t(comicName) != t(initialName) ||
               t(comicAuthor) != t(initialAuthor) ||
               t(comicDescription) != t(initialDescription) ||
               t(comicURL) != t(initialURL) ||
               t(comicCurrentURL) != t(initialFirstPageURL) ||
               t(comicSelectorImage) != t(initialSelectorImage) ||
               t(comicSelectorTitle) != t(initialSelectorTitle) ||
               t(comicSelectorNextPage) != t(initialSelectorNext)
    }

    private func initializeValidationStates() {
        let img = comicSelectorImage.trimmingCharacters(in: .whitespacesAndNewlines)
        isImageSelectorSyntaxValid = !img.isEmpty && isValidCSSSelector(img)

        let ttl = comicSelectorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        isTitleSelectorSyntaxValid = ttl.isEmpty || isValidCSSSelector(ttl)

        let nxt = comicSelectorNextPage.trimmingCharacters(in: .whitespacesAndNewlines)
        isNextSelectorSyntaxValid = !nxt.isEmpty && isValidCSSSelector(nxt)
    }

    private func buildInput() -> ComicInput? {
        guard isValid else { return nil }

        let name = comicName.trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedAuthors: String = comicAuthor
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: ";", with: ",")
            .split(separator: ",")
            .map { part in
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                let collapsed = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                return collapsed
            }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        let description = comicDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        let url = normalizeURLString(comicURL)
        let firstPageURL = normalizeURLString(comicCurrentURL)

        let selectorImage = comicSelectorImage.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectorTitle = comicSelectorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectorNext = comicSelectorNextPage.trimmingCharacters(in: .whitespacesAndNewlines)

        return ComicInput(
            name: name,
            author: normalizedAuthors,
            description: description,
            url: url,
            firstPageURL: firstPageURL,
            selectorImage: selectorImage,
            selectorTitle: selectorTitle,
            selectorNext: selectorNext
        )
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

    private func normalizeURLString(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var comps = URLComponents(string: t) else { return t }
        if let scheme = comps.scheme { comps.scheme = scheme.lowercased() }
        if let host = comps.host { comps.host = host.lowercased() }
        return comps.string ?? t
    }

    private func scheduleImageValidation() {
        imageValidationTask?.cancel()
        imageValidationTask = Task { [comicSelectorImage] in
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            let trimmed = comicSelectorImage.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run { isImageSelectorSyntaxValid = !trimmed.isEmpty && isValidCSSSelector(trimmed) }
        }
    }

    private func scheduleTitleValidation() {
        titleValidationTask?.cancel()
        titleValidationTask = Task { [comicSelectorTitle] in
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            let trimmed = comicSelectorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run { isTitleSelectorSyntaxValid = trimmed.isEmpty || isValidCSSSelector(trimmed) }
        }
    }

    private func scheduleNextValidation() {
        nextValidationTask?.cancel()
        nextValidationTask = Task { [comicSelectorNextPage] in
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            let trimmed = comicSelectorNextPage.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run { isNextSelectorSyntaxValid = !trimmed.isEmpty && isValidCSSSelector(trimmed) }
        }
    }
}
