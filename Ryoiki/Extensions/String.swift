//
//  String.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-21.
//

extension String {
    /// Returns `nil` when the string is empty, otherwise returns `self`.
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
