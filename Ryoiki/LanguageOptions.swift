import Foundation
import SwiftUI

/// Represents a selectable language option shown in the Language picker.
struct LanguageOption: Identifiable, Hashable {
    let code: String
    let nativeName: String
    var id: String { code }
}

/// All available language options, modernized and sorted by their autonym (native name).
/// The mapping replaces deprecated ISO codes (iw→he, ji→yi, in→id) and filters to two-letter language codes.
let languageOptions: [LanguageOption] = {
    let modernize: [String: String] = ["iw": "he", "ji": "yi", "in": "id"]
    let baseCodes: [String] = Locale.LanguageCode.isoLanguageCodes.map { $0.identifier }
    let codes = baseCodes
        .map { modernize[$0] ?? $0 }
        .filter { !$0.contains("-") }
        .filter { $0.count == 2 }
    let uniqueCodes = Array(Set(codes))
    let options = uniqueCodes.map { code in
        let autonym = Locale(identifier: code).localizedString(forLanguageCode: code) ?? code
        return LanguageOption(code: code, nativeName: autonym)
    }
    let sorted = options.sorted { lhs, rhs in
        lhs.nativeName.localizedCaseInsensitiveCompare(rhs.nativeName) == .orderedAscending
    }
    return [LanguageOption(code: "", nativeName: "—")] + sorted
}()
