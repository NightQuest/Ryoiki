import SwiftUI
import Observation
import SwiftSoup

// MARK: - Public Types

/// Simple DTO that is handed back to the caller when the user taps **Add**.
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

// MARK: - ViewModel

@MainActor @Observable final class AddComicViewModel {
    // MARK: Stored Properties - Comic Info

    var comicName: String = ""
    var comicAuthor: String = ""
    var comicDescription: String = ""
    var comicURL: String = ""
    var comicCurrentURL: String = ""

    // MARK: Stored Properties - CSS Selectors

    var comicSelectorImage: String = "" { didSet { scheduleImageValidation() } }
    var comicSelectorTitle: String = "" { didSet { scheduleTitleValidation() } }
    var comicSelectorNextPage: String = "" { didSet { scheduleNextValidation() } }

    // MARK: Stored Properties - Validation States

    var isImageSelectorSyntaxValid: Bool = true
    var isTitleSelectorSyntaxValid: Bool = true
    var isNextSelectorSyntaxValid: Bool = true

    // MARK: Stored Properties - Validation Tasks

    @ObservationIgnored private var imageValidationTask: Task<Void, Never>?
    @ObservationIgnored private var titleValidationTask: Task<Void, Never>?
    @ObservationIgnored private var nextValidationTask: Task<Void, Never>?

    // MARK: Computed Properties - Validation & State

    var isComicNameEmpty: Bool { comicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isMainURLPresentAndInvalid: Bool { !comicURL.isEmpty && !isValidURL(comicURL) }
    var isFirstPageURLEmpty: Bool { comicCurrentURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isFirstPageURLInvalid: Bool { !isFirstPageURLEmpty && !isValidURL(comicCurrentURL) }
    var isImageSelectorEmpty: Bool { comicSelectorImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isTitleSelectorNonEmptyAndInvalid: Bool {
        let trimmed = comicSelectorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !isTitleSelectorSyntaxValid
    }
    var isNextSelectorEmpty: Bool { comicSelectorNextPage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Indicates whether all required inputs are valid to proceed with adding the comic.
    var isValid: Bool {
        !comicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isValidURL(comicCurrentURL) &&
        !comicSelectorImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !comicSelectorNextPage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isImageSelectorSyntaxValid &&
        isNextSelectorSyntaxValid
    }

    /// Indicates if any user input has been provided.
    var hasUnsavedChanges: Bool {
        !(comicName.isEmpty &&
          comicAuthor.isEmpty &&
          comicDescription.isEmpty &&
          comicURL.isEmpty &&
          comicCurrentURL.isEmpty &&
          comicSelectorImage.isEmpty &&
          comicSelectorTitle.isEmpty &&
          comicSelectorNextPage.isEmpty)
    }

    // MARK: Lifecycle

    init() {
        initializeValidationStates()
    }

    // MARK: Public API

    /// Initializes validation states based on current property values.
    func initializeValidationStates() {
        // Initialize validation states based on current values
        let img = comicSelectorImage.trimmingCharacters(in: .whitespacesAndNewlines)
        isImageSelectorSyntaxValid = !img.isEmpty && isValidCSSSelector(img)

        let ttl = comicSelectorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        isTitleSelectorSyntaxValid = ttl.isEmpty || isValidCSSSelector(ttl)

        let nxt = comicSelectorNextPage.trimmingCharacters(in: .whitespacesAndNewlines)
        isNextSelectorSyntaxValid = !nxt.isEmpty && isValidCSSSelector(nxt)
    }

    /// Builds a normalized `ComicInput` from the current fields if the form is valid.
    /// - Returns: A `ComicInput` when `isValid` is true; otherwise `nil`.
    func buildInput() -> ComicInput? {
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

    /// Validates if the given string is a valid HTTP or HTTPS URL.
    ///
    /// - Parameter string: The string to validate as a URL.
    /// - Returns: `true` if valid URL with http or https scheme, `false` otherwise.
    func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string), let scheme = url.scheme else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// Validates whether a CSS selector string is syntactically valid.
    /// Uses `SwiftSoup` to parse a dummy HTML and attempt selection.
    ///
    /// - Parameter selector: The CSS selector string to validate.
    /// - Returns: `true` if valid selector syntax, `false` otherwise.
    func isValidCSSSelector(_ selector: String) -> Bool {
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

    // MARK: Private Helpers

    /// Normalizes a URL string by trimming whitespaces and lowercasing scheme and host components.
    ///
    /// - Parameter s: The URL string to normalize.
    /// - Returns: A normalized URL string.
    private func normalizeURLString(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var comps = URLComponents(string: t) else { return t }
        if let scheme = comps.scheme { comps.scheme = scheme.lowercased() }
        if let host = comps.host { comps.host = host.lowercased() }
        return comps.string ?? t
    }

    private func scheduleImageValidation() {
        imageValidationTask?.cancel()
        imageValidationTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            let trimmed = self.comicSelectorImage.trimmingCharacters(in: .whitespacesAndNewlines)
            self.isImageSelectorSyntaxValid = !trimmed.isEmpty && self.isValidCSSSelector(trimmed)
        }
    }

    private func scheduleTitleValidation() {
        titleValidationTask?.cancel()
        titleValidationTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            let trimmed = self.comicSelectorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            self.isTitleSelectorSyntaxValid = trimmed.isEmpty || self.isValidCSSSelector(trimmed)
        }
    }

    private func scheduleNextValidation() {
        nextValidationTask?.cancel()
        nextValidationTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            let trimmed = self.comicSelectorNextPage.trimmingCharacters(in: .whitespacesAndNewlines)
            self.isNextSelectorSyntaxValid = !trimmed.isEmpty && self.isValidCSSSelector(trimmed)
        }
    }
}
