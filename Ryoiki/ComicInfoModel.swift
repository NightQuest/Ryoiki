//  ComicInfoModel.swift
//  MetaComic
//
//  Created by Stardust on 2025-10-03.
//

import Foundation
import Combine

/// Models and utilities for representing and editing ComicInfo.xml metadata.
///
/// This file defines:
/// - Tri-state booleans and content flags (e.g., `YesNo`, `Manga`).
/// - Domain enums (e.g., `AgeRating`, `ComicPageType`).
/// - Value wrappers (e.g., `Rating`).
/// - `ComicInfoModel`: an observable metadata model with dynamic get/set helpers
///   used to drive generic editing UIs.

/// Tri-state boolean used by some metadata fields (Unknown/Yes/No).
internal enum YesNo: String, RawRepresentable, CaseIterable, Identifiable {
    /// Value is not specified
    case Unknown
    /// Affirmative
    case Yes
    /// Negative
    case No
    // NOTE: case names match expected XML raw values

    var id: String { rawValue }
}

/// Indicates whether content is manga and, if applicable, its reading direction.
internal enum Manga: String, RawRepresentable, CaseIterable, Identifiable, Hashable, Equatable {
    /// Content type unknown
    case Unknown
    /// Content is manga (standard reading direction)
    case Yes
    /// Content is not manga
    case No
    /// Content is manga and read from right to left (RTL)
    case YesAndRightToLeft
    // NOTE: case names match expected XML raw values

    var id: String { rawValue }
}

/// 0–5 star rating wrapper with range checks.

internal struct Rating: RawRepresentable, ExpressibleByIntegerLiteral {
    /// Integer value representing the rating (0–5 inclusive)
    var rawValue: Int {
        willSet {
            precondition((0...5).contains(newValue), "Rating must be between 0 and 5 inclusive")
        }
    }

    /// Create a `Rating` with a value from 0 to 5 inclusive.
    /// - Parameter rawValue: Must be in 0...5.
    init(rawValue: Int) {
        precondition((0...5).contains(rawValue), "Rating must be between 0 and 5 inclusive")
        self.rawValue = rawValue
    }

    /// Initialize from an integer literal.
    init(integerLiteral: Int) {
        self = .init(rawValue: integerLiteral)
    }

    /// Produce a clamped rating that bounds the input to 0...5.
    /// - Parameter value: Integer to clamp.
    /// - Returns: A `Rating` clamped within 0 to 5.
    static func clamped(_ value: Int) -> Rating {
        let clampedValue = min(max(value, 0), 5)
        return Rating(rawValue: clampedValue)
    }
}

/// Standardized age ratings for content.
internal enum AgeRating: String, CaseIterable {
    /// Unknown rating
    case Unknown = "Unknown"
    /// Adults Only 18+
    case AdultsOnly18Plus = "Adults Only 18+"
    /// Early Childhood
    case EarlyChildhood = "Early Childhood"
    /// Everyone
    case Everyone = "Everyone"
    /// Everyone 10+
    case Everyone10Plus = "Everyone 10+"
    /// G rating
    case G = "G"
    /// Kids to Adults
    case KidsToAdults = "Kids to Adults"
    /// M rating
    case M = "M"
    /// MA15+
    case MA15Plus = "MA15+"
    /// Mature 17+
    case Mature17Plus = "Mature 17+"
    /// PG rating
    case PG = "PG"
    /// R18+
    case R18Plus = "R18+"
    /// Rating Pending
    case RatingPending = "Rating Pending"
    /// Teen rating
    case Teen = "Teen"
    /// X18+
    case X18Plus = "X18+"
}

/// Per-page metadata for images within a comic archive.
/// Typical fields include page index, type, image size, and flags.
internal struct ComicPageInfo: Identifiable, Hashable {
    var id: UUID = UUID()

    /// Original image attribute value (often a page index as a string)
    var Image: String = ""
    /// Role/type of this page in the comic (story, cover, etc.)
    var PageType: ComicPageType = .Story
    /// Whether this is a double-page spread
    var DoublePage: Bool = false
    /// Image size in bytes
    var ImageSize: Int64 = 0
    /// Key or identifier string, if any
    var Key: String = ""
    /// Bookmark string, if any
    var Bookmark: String = ""
    /// Image pixel width; -1 if unknown
    var ImageWidth: Int = -1
    /// Image pixel height; -1 if unknown
    var ImageHeight: Int = -1
}

/// Common page roles used by readers and libraries.
internal enum ComicPageType: String, CaseIterable {
    /// Front cover page
    case FrontCover
    /// Inner cover page
    case InnerCover
    /// Roundup page
    case Roundup
    /// Story content page
    case Story
    /// Advertisement page
    case Advertisement
    /// Editorial page
    case Editorial
    /// Letters page
    case Letters
    /// Preview page
    case Preview
    /// Back cover page
    case BackCover
    /// Other page type
    case Other
    /// Deleted page
    case Deleted
}

/// Full metadata model corresponding to ComicInfo.xml fields and related properties.
///
/// This model is observable and drives dynamic editing user interfaces.
final class ComicInfoModel: ObservableObject, Identifiable {
    @Published var Title: String = ""
    @Published var Series: String = ""
    @Published var Number: String = ""
    @Published var Count: Int = -1
    @Published var Volume: Int = -1
    @Published var AlternateSeries: String = ""
    @Published var AlternateNumber: String = ""
    @Published var AlternateCount: Int = -1
    @Published var Summary: String = ""
    @Published var Notes: String = ""
    @Published var Year: Int = -1
    @Published var Month: Int = -1
    @Published var Day: Int = -1
    @Published var Writer: String = ""
    @Published var Penciller: String = ""
    @Published var Inker: String = ""
    @Published var Colorist: String = ""
    @Published var Letterer: String = ""
    @Published var CoverArtist: String = ""
    @Published var Editor: String = ""
    @Published var Publisher: String = ""
    @Published var Imprint: String = ""
    @Published var Genre: String = ""
    @Published var Web: String = ""
    @Published var PageCount: Int = 0
    @Published var LanguageISO: String = ""
    @Published var Format: String = ""
    @Published var BlackAndWhite: YesNo = .Unknown
    @Published var Manga: Manga = .Unknown
    @Published var Characters: String = ""
    @Published var Teams: String = ""
    @Published var Locations: String = ""
    @Published var ScanInformation: String = ""
    @Published var StoryArc: String = ""
    @Published var SeriesGroup: String = ""
    @Published var AgeRating: AgeRating = .Unknown
    @Published var Pages: [ComicPageInfo]?
    @Published var CommunityRating: Rating?
    @Published var MainCharacterOrTeam: String = ""
    @Published var Review: String = ""
}

// MARK: - Dynamic Access & Editing Utilities
/// Utilities to dynamically get/set properties by key, derive display names, and compute non-default state.
extension ComicInfoModel {
    /// Closure that reads a value from a model instance.
    private typealias Getter = (ComicInfoModel) -> Any?

    /// Wraps a KeyPath into a generic getter closure.
    private static func getter<T>(_ kp: KeyPath<ComicInfoModel, T>) -> Getter {
        { $0[keyPath: kp] }
    }

    /// Map of property keys to dynamic getter closures.
    private static let getters: [String: Getter] = [
        "Title": getter(\.Title),
        "Series": getter(\.Series),
        "Number": getter(\.Number),
        "Count": getter(\.Count),
        "Volume": getter(\.Volume),
        "AlternateSeries": getter(\.AlternateSeries),
        "AlternateNumber": getter(\.AlternateNumber),
        "AlternateCount": getter(\.AlternateCount),
        "Summary": getter(\.Summary),
        "Notes": getter(\.Notes),
        "Writer": getter(\.Writer),
        "Penciller": getter(\.Penciller),
        "Inker": getter(\.Inker),
        "Colorist": getter(\.Colorist),
        "Letterer": getter(\.Letterer),
        "CoverArtist": getter(\.CoverArtist),
        "Editor": getter(\.Editor),
        "Publisher": getter(\.Publisher),
        "Imprint": getter(\.Imprint),
        "Genre": getter(\.Genre),
        "Web": getter(\.Web),
        "PageCount": getter(\.PageCount),
        "LanguageISO": getter(\.LanguageISO),
        "Format": getter(\.Format),
        "BlackAndWhite": getter(\.BlackAndWhite),
        "Manga": getter(\.Manga),
        "Characters": getter(\.Characters),
        "Teams": getter(\.Teams),
        "Locations": getter(\.Locations),
        "ScanInformation": getter(\.ScanInformation),
        "StoryArc": getter(\.StoryArc),
        "SeriesGroup": getter(\.SeriesGroup),
        "AgeRating": getter(\.AgeRating),
        "Pages": getter(\.Pages),
        "CommunityRating": getter(\.CommunityRating),
        "MainCharacterOrTeam": getter(\.MainCharacterOrTeam),
        "Review": getter(\.Review)
    ]

    /// Computed maps of setters that capture `self` for low-complexity dispatch.
    private var stringSetters: [String: (String) -> Void] {
        [
            "Title": { self.Title = $0 },
            "Series": { self.Series = $0 },
            "Number": { self.Number = $0 },
            "AlternateSeries": { self.AlternateSeries = $0 },
            "AlternateNumber": { self.AlternateNumber = $0 },
            "Summary": { self.Summary = $0 },
            "Notes": { self.Notes = $0 },
            "Writer": { self.Writer = $0 },
            "Penciller": { self.Penciller = $0 },
            "Inker": { self.Inker = $0 },
            "Colorist": { self.Colorist = $0 },
            "Letterer": { self.Letterer = $0 },
            "CoverArtist": { self.CoverArtist = $0 },
            "Editor": { self.Editor = $0 },
            "Publisher": { self.Publisher = $0 },
            "Imprint": { self.Imprint = $0 },
            "Genre": { self.Genre = $0 },
            "Web": { self.Web = $0 },
            "LanguageISO": { self.LanguageISO = $0 },
            "Format": { self.Format = $0 },
            "Characters": { self.Characters = $0 },
            "Teams": { self.Teams = $0 },
            "Locations": { self.Locations = $0 },
            "ScanInformation": { self.ScanInformation = $0 },
            "StoryArc": { self.StoryArc = $0 },
            "SeriesGroup": { self.SeriesGroup = $0 },
            "MainCharacterOrTeam": { self.MainCharacterOrTeam = $0 },
            "Review": { self.Review = $0 }
        ]
    }

    private var intSetters: [String: (Int) -> Void] {
        [
            "Count": { self.Count = $0 },
            "Volume": { self.Volume = $0 },
            "AlternateCount": { self.AlternateCount = $0 },
            "Year": { self.Year = $0 },
            "Month": { self.Month = $0 },
            "Day": { self.Day = $0 },
            "PageCount": { self.PageCount = $0 }
        ]
    }

    private var enumSetters: [String: (String) -> Bool] {
        [
            "BlackAndWhite": { raw in
                guard let v = YesNo(rawValue: raw) else { return false }
                self.BlackAndWhite = v
                return true
            },
            "Manga": { raw in
                guard let v = Ryoiki.Manga(rawValue: raw) else { return false }
                self.Manga = v
                return true
            },
            "AgeRating": { raw in
                guard let v = Ryoiki.AgeRating(rawValue: raw) else { return false }
                self.AgeRating = v
                return true
            }
        ]
    }

    /// Dynamically sets a property by key with a string value.
    ///
    /// - Parameters:
    ///   - key: The property key to write.
    ///   - value: The string value to parse and set.
    /// - Returns: True if the key is known and the value was successfully converted and set, false otherwise.
    func zset(key: String, value: String) -> Bool {
        // Try string-backed properties
        if let s = stringSetters[key] {
            s(value)
            return true
        }

        // Try int-backed properties
        if let i = intSetters[key] {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let x = Int(trimmed) else { return false }
            i(x)
            return true
        }

        // Try enum-backed properties
        if let e = enumSetters[key] {
            return e(value)
        }

        // Special case: rating
        if key == "CommunityRating" {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let x = Int(trimmed) else { return false }
            CommunityRating = Rating.clamped(x)
            return true
        }

        return false
    }

    /// Public wrapper around zset that discards the return value when unused.
    ///
    /// - Parameters:
    ///   - key: The property key to write.
    ///   - value: The string value to parse and set.
    /// - Returns: True on success, false on failure or unknown key.
    @discardableResult
    func set(key: String, value: String) -> Bool {
        zset(key: key, value: value)
    }

    // MARK: - EditableProperty
    /// Properties that can be edited in the UI; determines order and display labels.
    enum EditableProperty: String, CaseIterable, Identifiable, Hashable {
        case Title
        case Series
        case Number
        case Count
        case Volume
        case AlternateSeries
        case AlternateNumber
        case AlternateCount
        case Summary
        case Notes
        case Writer
        case Penciller
        case Inker
        case Colorist
        case Letterer
        case CoverArtist
        case Editor
        case Publisher
        case Imprint
        case Genre
        case Web
        case LanguageISO
        case Format
        case BlackAndWhite
        case Manga
        case Characters
        case Teams
        case Locations
        case ScanInformation
        case StoryArc
        case SeriesGroup
        case AgeRating
        case CommunityRating
        case MainCharacterOrTeam
        case Review
        case PublishDate

        var id: String { rawValue }

        private static let displayNames: [EditableProperty: String] = [
            .Title: "Title",
            .Series: "Series",
            .Number: "Number",
            .Count: "Count",
            .Volume: "Volume",
            .AlternateSeries: "Alternate Series",
            .AlternateNumber: "Alternate Number",
            .AlternateCount: "Alternate Count",
            .Summary: "Summary",
            .Notes: "Notes",
            .Writer: "Writer",
            .Penciller: "Penciller",
            .Inker: "Inker",
            .Colorist: "Colorist",
            .Letterer: "Letterer",
            .CoverArtist: "Cover Artist",
            .Editor: "Editor",
            .Publisher: "Publisher",
            .Imprint: "Imprint",
            .Genre: "Genre",
            .Web: "Web",
            .LanguageISO: "Language",
            .Format: "Format",
            .BlackAndWhite: "Black and White",
            .Manga: "Manga",
            .Characters: "Characters",
            .Teams: "Teams",
            .Locations: "Locations",
            .ScanInformation: "Scan Information",
            .StoryArc: "Story Arc",
            .SeriesGroup: "Series Group",
            .AgeRating: "Age Rating",
            .CommunityRating: "Community Rating",
            .MainCharacterOrTeam: "Main Character or Team",
            .Review: "Review",
            .PublishDate: "Publish Date"
        ]

        /// Human-readable label for UI presentation.
        var displayName: String {
            Self.displayNames[self] ?? rawValue
        }

        /// Returns all display names for all cases.
        static func allDisplayNames() -> [String] {
            allCases.map { $0.displayName }
        }
    }

    /// Map of `EditableProperty` cases to predicates that determine if the property is non-default (populated).
    private static let propertyPredicates: [EditableProperty: (ComicInfoModel) -> Bool] = [
        .Title: { $0.hasNonEmpty(\.Title) },
        .Series: { $0.hasNonEmpty(\.Series) },
        .Number: { $0.hasNonEmpty(\.Number) },
        .Count: { $0.isSet(\.Count) },
        .Volume: { $0.isSet(\.Volume) },
        .AlternateSeries: { $0.hasNonEmpty(\.AlternateSeries) },
        .AlternateNumber: { $0.hasNonEmpty(\.AlternateNumber) },
        .AlternateCount: { $0.isSet(\.AlternateCount) },
        .Summary: { $0.hasNonEmpty(\.Summary) },
        .Notes: { $0.hasNonEmpty(\.Notes) },
        .Writer: { $0.hasNonEmpty(\.Writer) },
        .Penciller: { $0.hasNonEmpty(\.Penciller) },
        .Inker: { $0.hasNonEmpty(\.Inker) },
        .Colorist: { $0.hasNonEmpty(\.Colorist) },
        .Letterer: { $0.hasNonEmpty(\.Letterer) },
        .CoverArtist: { $0.hasNonEmpty(\.CoverArtist) },
        .Editor: { $0.hasNonEmpty(\.Editor) },
        .Publisher: { $0.hasNonEmpty(\.Publisher) },
        .Imprint: { $0.hasNonEmpty(\.Imprint) },
        .Genre: { $0.hasNonEmpty(\.Genre) },
        .Web: { $0.hasNonEmpty(\.Web) },
        .LanguageISO: { $0.hasNonEmpty(\.LanguageISO) },
        .Format: { $0.hasNonEmpty(\.Format) },
        .BlackAndWhite: { $0.isNotUnknown(\.BlackAndWhite, unknown: .Unknown) },
        .Manga: { $0.isNotUnknown(\.Manga, unknown: .Unknown) },
        .Characters: { $0.hasNonEmpty(\.Characters) },
        .Teams: { $0.hasNonEmpty(\.Teams) },
        .Locations: { $0.hasNonEmpty(\.Locations) },
        .ScanInformation: { $0.hasNonEmpty(\.ScanInformation) },
        .StoryArc: { $0.hasNonEmpty(\.StoryArc) },
        .SeriesGroup: { $0.hasNonEmpty(\.SeriesGroup) },
        .AgeRating: { $0.isNotUnknown(\.AgeRating, unknown: .Unknown) },
        .CommunityRating: { $0.hasPositiveRating(\.CommunityRating) },
        .MainCharacterOrTeam: { $0.hasNonEmpty(\.MainCharacterOrTeam) },
        .Review: { $0.hasNonEmpty(\.Review) },
        .PublishDate: { $0.anyPositive([\.Year, \.Month, \.Day]) }
    ]

    /// Returns true if the given property is considered populated (i.e., not default/unknown).
    func hasNonDefaultValue(_ property: EditableProperty) -> Bool {
        if let predicate = Self.propertyPredicates[property] { return predicate(self) }
        return false
    }

    /// Bridges Year/Month/Day to a Date for UI pickers and back.
    ///
    /// Defaults fallback to the current date components if Year/Month/Day are unset or invalid.
    var publishDate: Date {
        get {
            let now = Date()
            let fallback = Calendar.current.dateComponents([.year, .month, .day], from: now)
            let y = Year > 0 ? Year : (fallback.year ?? 2000)
            let m = Month > 0 ? Month : (fallback.month ?? 1)
            let d = Day > 0 ? Day : (fallback.day ?? 1)
            var comps = DateComponents()
            comps.year = y
            comps.month = m
            comps.day = d
            return Calendar.current.date(from: comps) ?? Date()
        }
        set {
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: newValue)
            Year = comps.year ?? -1
            Month = comps.month ?? -1
            Day = comps.day ?? -1
        }
    }

    /// Checks a string key path for non-empty content.
    private func hasNonEmpty(_ kp: KeyPath<ComicInfoModel, String>) -> Bool {
        !self[keyPath: kp].isEmpty
    }

    /// Checks an Int key path against a default sentinel (default -1).
    private func isSet(_ kp: KeyPath<ComicInfoModel, Int>, default defaultValue: Int = -1) -> Bool {
        self[keyPath: kp] != defaultValue
    }

    /// Checks an equatable value against a provided "unknown" sentinel.
    private func isNotUnknown<E: Equatable>(_ kp: KeyPath<ComicInfoModel, E>, unknown: E) -> Bool {
        self[keyPath: kp] != unknown
    }

    /// True if an optional Rating has a value greater than zero.
    private func hasPositiveRating(_ kp: KeyPath<ComicInfoModel, Rating?>) -> Bool {
        (self[keyPath: kp]?.rawValue ?? 0) > 0
    }

    /// True if any of the provided Int key paths is strictly positive.
    private func anyPositive(_ kps: [KeyPath<ComicInfoModel, Int>]) -> Bool {
        for kp in kps where self[keyPath: kp] > 0 {
            return true
        }
        return false
    }
}

extension ComicInfoModel {
    /// Overwrite this model's properties from another instance (without changing object identity).
    ///
    /// Performs a shallow copy of scalar properties and reference types.
    /// Useful for updating a model but keeping the same object instance.
    func overwrite(from other: ComicInfoModel) {
        Title = other.Title
        Series = other.Series
        Number = other.Number
        Count = other.Count
        Volume = other.Volume
        AlternateSeries = other.AlternateSeries
        AlternateNumber = other.AlternateNumber
        AlternateCount = other.AlternateCount
        Summary = other.Summary
        Notes = other.Notes
        Year = other.Year
        Month = other.Month
        Day = other.Day
        Writer = other.Writer
        Penciller = other.Penciller
        Inker = other.Inker
        Colorist = other.Colorist
        Letterer = other.Letterer
        CoverArtist = other.CoverArtist
        Editor = other.Editor
        Publisher = other.Publisher
        Imprint = other.Imprint
        Genre = other.Genre
        Web = other.Web
        PageCount = other.PageCount
        LanguageISO = other.LanguageISO
        Format = other.Format
        BlackAndWhite = other.BlackAndWhite
        Manga = other.Manga
        Characters = other.Characters
        Teams = other.Teams
        Locations = other.Locations
        ScanInformation = other.ScanInformation
        StoryArc = other.StoryArc
        SeriesGroup = other.SeriesGroup
        AgeRating = other.AgeRating
        Pages = other.Pages
        CommunityRating = other.CommunityRating
        MainCharacterOrTeam = other.MainCharacterOrTeam
        Review = other.Review
    }
}
