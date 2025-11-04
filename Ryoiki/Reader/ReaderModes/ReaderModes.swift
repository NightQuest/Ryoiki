//
//  ReadingMode.swift
//  Ryoiki
//
//  Created by Stardust on 2025-11-04.
//
import Foundation

public enum ReadingMode: String, CaseIterable, Codable, Sendable {
    case pager
    case vertical

    var label: String {
        switch self {
        case .pager: return "Pager"
        case .vertical: return "Vertical"
        }
    }
}
