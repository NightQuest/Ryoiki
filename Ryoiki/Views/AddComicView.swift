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

        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fill in the details below. You can edit these later.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .padding(.horizontal)

                Form {
                    ComicMetadataSection(vm: vm)
                    CSSSelectorSection(vm: vm)
                }
                .formStyle(.grouped)
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
}
