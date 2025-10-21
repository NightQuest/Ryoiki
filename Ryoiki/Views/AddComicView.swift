import SwiftUI
import Observation

private struct ValidationText: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
            .padding(.top, 2)
    }
}

struct ComicMetadataSection: View {
    @Bindable var vm: AddComicViewModel

    public var body: some View {
        Section {
            TextField("Name *", text: $vm.comicName)
            if vm.isComicNameEmpty {
                ValidationText(message: "Name is required.")
            }

            TextField("Author(s)", text: $vm.comicAuthor)
                .help("Separate multiple authors with a comma")

            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $vm.comicDescription)
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
                TextField("Main URL", text: $vm.comicURL)
                if vm.isMainURLPresentAndInvalid {
                    ValidationText(message: "Enter a valid URL (http/https).")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("First Page URL *", text: $vm.comicCurrentURL)
                if vm.isFirstPageURLEmpty {
                    ValidationText(message: "First Page URL is required.")
                } else if vm.isFirstPageURLInvalid {
                    ValidationText(message: "Enter a valid URL (http/https).")
                }
            }
        } header: {
            Text("URLs")
        } footer: {
            Text("The main URL is usually the comic’s homepage. The first page URL points to the very first strip.")
        }
    }
}

struct CSSSelectorSection: View {
    @Bindable var vm: AddComicViewModel

    var body: some View {
        Section {
            TextField("Image selector *", text: $vm.comicSelectorImage)
            if vm.isImageSelectorEmpty {
                ValidationText(message: "Image selector is required.")
            } else if !vm.isImageSelectorSyntaxValid {
                ValidationText(message: "This CSS selector appears invalid.")
            }
            TextField("Title selector", text: $vm.comicSelectorTitle)
            if vm.isTitleSelectorNonEmptyAndInvalid {
                ValidationText(message: "This CSS selector appears invalid.")
            }
            TextField("Next page selector *", text: $vm.comicSelectorNextPage)
            if vm.isNextSelectorEmpty {
                ValidationText(message: "Next page selector is required.")
            } else if !vm.isNextSelectorSyntaxValid {
                ValidationText(message: "This CSS selector appears invalid.")
            }
        } header: {
            Text("CSS Selectors")
        } footer: {
            Text("Use CSS selectors that are stable across pages. For example, prefer a class or id that’s consistently present.")
        }
    }
}

struct AddComicView: View {
    // MARK: External API
    /// Called when the user confirms the form.
    var onSubmit: ((ComicInput) -> Void)?

    // MARK: Internal State
    @State private var vm = AddComicViewModel()
    @Environment(\.dismiss) var dismiss

    // MARK: Body
    var body: some View {
        @Bindable var vm = vm

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
        }
        .navigationTitle("Add Web Comic")
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

    @State private var showDiscardAlert: Bool = false

    // MARK: Toolbar Buttons

    @ViewBuilder
    private var cancelButton: some View {
        Button("Cancel") {
            if vm.hasUnsavedChanges {
                showDiscardAlert = true
            } else {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var addButton: some View {
        Button("Add") {
            if let input = vm.buildInput() {
                onSubmit?(input)
                dismiss()
            }
        }
        .disabled(!vm.isValid)
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
                        TextField("Name", text: $vm.comicName)
                            .textFieldStyle(.roundedBorder)
                        if vm.isComicNameEmpty {
                            ValidationText(message: "Name is required.")
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Author(s)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Author(s)", text: $vm.comicAuthor)
                            .textFieldStyle(.roundedBorder)
                            .help("Separate multiple authors with a comma")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $vm.comicDescription)
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
                        Text("Main URL")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Main URL", text: $vm.comicURL)
                            .textFieldStyle(.roundedBorder)
                        if vm.isMainURLPresentAndInvalid {
                            ValidationText(message: "Enter a valid URL (http/https).")
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("First Page URL *")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("First Page URL", text: $vm.comicCurrentURL)
                            .textFieldStyle(.roundedBorder)
                        if vm.isFirstPageURLEmpty {
                            ValidationText(message: "First Page URL is required.")
                        } else if vm.isFirstPageURLInvalid {
                            ValidationText(message: "Enter a valid URL (http/https).")
                        }
                    }
                }
                Text("The main URL is usually the comic’s homepage. The first page URL points to the very first strip.")
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
                        TextField("Image selector", text: $vm.comicSelectorImage)
                            .textFieldStyle(.roundedBorder)
                        if vm.isImageSelectorEmpty {
                            ValidationText(message: "Image selector is required.")
                        } else if !vm.isImageSelectorSyntaxValid {
                            ValidationText(message: "This CSS selector appears invalid.")
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Title selector")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Title selector", text: $vm.comicSelectorTitle)
                            .textFieldStyle(.roundedBorder)
                        if vm.isTitleSelectorNonEmptyAndInvalid {
                            ValidationText(message: "This CSS selector appears invalid.")
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Next page selector *")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Next page selector", text: $vm.comicSelectorNextPage)
                            .textFieldStyle(.roundedBorder)
                        if vm.isNextSelectorEmpty {
                            ValidationText(message: "Next page selector is required.")
                        } else if !vm.isNextSelectorSyntaxValid {
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
}
