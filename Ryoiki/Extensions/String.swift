//
//  String.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-21.
//

import Foundation

extension String {
    /// Returns `nil` when the string is empty, otherwise returns `self`.
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    /// Returns `nil` when the string is empty after trimming whitespace/newlines; otherwise returns the trimmed string.
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Returns a filesystem-safe filename by replacing characters that are invalid on common filesystems.
    func sanitizedForFileName() -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return components(separatedBy: invalid).joined(separator: "_")
    }
}
