//  ComicInfoModal.swift
//  MetaComic
//
//  Created by Stardust on 2025-10-03.
//

import Foundation
import Combine

/// Tri-state boolean used by some metadata fields.
internal enum YesNo: String, RawRepresentable, CaseIterable, Identifiable {
    case Unknown
    case Yes
    case No

    var id: String { rawValue }
}

/// Indicates whether content is manga and, if applicable, its reading direction.
internal enum Manga: String, RawRepresentable, CaseIterable, Identifiable, Hashable, Equatable {
    case Unknown
    case Yes
    case No
    case YesAndRightToLeft

    var id: String { rawValue }
}

/// 0–5 star rating wrapper with range checks.
internal struct Rating: RawRepresentable, ExpressibleByIntegerLiteral {
    var rawValue: Int {
        willSet {
            precondition((0...5).contains(newValue))
        }
    }

    init(rawValue: Int) {
        precondition((0...5).contains(rawValue))
        self.rawValue = rawValue
    }

    init(integerLiteral: Int) {
        self = .init(rawValue: integerLiteral)
    }
}

/// Standardized age ratings for content.
internal enum AgeRating: String, CaseIterable {
    case Unknown = "Unknown"
    case AdultsOnly18Plus = "Adults Only 18+"
    case EarlyChildhood = "Early Childhood"
    case Everyone = "Everyone"
    case Everyone10Plus = "Everyone 10+"
    case G = "G"
    case KidsToAdults = "Kids to Adults"
    case M = "M"
    case MA15Plus = "MA15+"
    case Mature17Plus = "Mature 17+"
    case PG = "PG"
    case R18Plus = "R18+"
    case RatingPending = "Rating Pending"
    case Teen = "Teen"
    case X18Plus = "X18+"
}

/// Per-page metadata for images within a comic archive.
internal struct ComicPageInfo: Identifiable, Hashable {
    var id: UUID = UUID()

    // Attributes from <Page ... /> elements in ComicInfo.xml
    // Note: "Image" is kept as String to preserve raw attribute value (often an index as string)
    var Image: String = ""
    var PageType: ComicPageType = .Story
    var DoublePage: Bool = false
    var ImageSize: Int64 = 0
    var Key: String = ""
    var Bookmark: String = ""
    var ImageWidth: Int = -1
    var ImageHeight: Int = -1
}

/// Common page roles used by readers and libraries.
internal enum ComicPageType: String, CaseIterable {
    case FrontCover
    case InnerCover
    case Roundup
    case Story
    case Advertisement
    case Editorial
    case Letters
    case Preview
    case BackCover
    case Other
    case Deleted
}

/// Full metadata model corresponding to ComicInfo.xml fields and related properties.
class ComicInfoModel: ObservableObject, Identifiable {
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
    /// Closure that attempts to write a string value into a model instance (type-converting as needed).
    private typealias Setter = (ComicInfoModel, String) -> Bool

    /// Wraps a KeyPath into a generic getter closure.
    private static func getter<T>(_ kp: KeyPath<ComicInfoModel, T>) -> Getter {
        { $0[keyPath: kp] }
    }

    /// Produces a setter that assigns raw strings.
    private static func stringSetter(_ kp: WritableKeyPath<ComicInfoModel, String>) -> Setter {
        { m, v in
            var ref = m
            ref[keyPath: kp] = v
            return true
        }
    }

    /// Produces a setter that parses Int values; returns false on failure.
    private static func intSetter(_ kp: WritableKeyPath<ComicInfoModel, Int>) -> Setter {
        { m, v in
            guard let x = Int(v) else { return false }
            var ref = m
            ref[keyPath: kp] = x
            return true
        }
    }

    /// Produces a setter that maps raw string values to enums.
    private static func enumSetter<E: RawRepresentable>(_ kp: WritableKeyPath<ComicInfoModel, E>) -> Setter where E.RawValue == String {
        { m, v in
            guard let x = E(rawValue: v) else { return false }
            var ref = m
            ref[keyPath: kp] = x
            return true
        }
    }

    /// Produces a setter specialized for Rating (0–5).
    private static func ratingSetter(_ kp: WritableKeyPath<ComicInfoModel, Rating?>) -> Setter {
        { m, v in
            guard let x = Int(v) else { return false }
            var ref = m
            ref[keyPath: kp] = Rating(rawValue: x)
            return true
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

    /// Map of property keys to dynamic setter closures. Integers and enums are type-checked.
    private static let setters: [String: Setter] = [
        // Ints
        "Count": intSetter(\.Count),
        "Volume": intSetter(\.Volume),
        "AlternateCount": intSetter(\.AlternateCount),
        "Year": intSetter(\.Year),
        "Month": intSetter(\.Month),
        "Day": intSetter(\.Day),
        "PageCount": intSetter(\.PageCount),

        // Strings
        "Title": stringSetter(\.Title),
        "Series": stringSetter(\.Series),
        "Number": stringSetter(\.Number),
        "AlternateSeries": stringSetter(\.AlternateSeries),
        "AlternateNumber": stringSetter(\.AlternateNumber),
        "Summary": stringSetter(\.Summary),
        "Notes": stringSetter(\.Notes),
        "Writer": stringSetter(\.Writer),
        "Penciller": stringSetter(\.Penciller),
        "Inker": stringSetter(\.Inker),
        "Colorist": stringSetter(\.Colorist),
        "Letterer": stringSetter(\.Letterer),
        "CoverArtist": stringSetter(\.CoverArtist),
        "Editor": stringSetter(\.Editor),
        "Publisher": stringSetter(\.Publisher),
        "Imprint": stringSetter(\.Imprint),
        "Genre": stringSetter(\.Genre),
        "Web": stringSetter(\.Web),
        "LanguageISO": stringSetter(\.LanguageISO),
        "Format": stringSetter(\.Format),
        "Characters": stringSetter(\.Characters),
        "Teams": stringSetter(\.Teams),
        "Locations": stringSetter(\.Locations),
        "ScanInformation": stringSetter(\.ScanInformation),
        "StoryArc": stringSetter(\.StoryArc),
        "SeriesGroup": stringSetter(\.SeriesGroup),
        "MainCharacterOrTeam": stringSetter(\.MainCharacterOrTeam),
        "Review": stringSetter(\.Review),

        // Special types
        "BlackAndWhite": enumSetter(\.BlackAndWhite),
        "Manga": enumSetter(\.Manga),
        "AgeRating": enumSetter(\.AgeRating),
        "CommunityRating": ratingSetter(\.CommunityRating)
    ]

    /// Dynamically reads a value for a given key.
    func get(key: String) -> Any? {
        Self.getters[key]?(self)
    }

    /// Internal set implementation; returns false if the key is unknown or conversion fails.
    func zset(key: String, value: String) -> Bool {
        guard let setter = Self.setters[key] else { return false }
        return setter(self, value) != true
    }
    /// Public wrapper around zset that discards the return value when unused.
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

        /// Human-readable label for UI presentation.
        var displayName: String {
            switch self {
            case .Title: return "Title"
            case .Series: return "Series"
            case .Number: return "Number"
            case .Count: return "Count"
            case .Volume: return "Volume"
            case .AlternateSeries: return "Alternate Series"
            case .AlternateNumber: return "Alternate Number"
            case .AlternateCount: return "Alternate Count"
            case .Summary: return "Summary"
            case .Notes: return "Notes"
            case .Writer: return "Writer"
            case .Penciller: return "Penciller"
            case .Inker: return "Inker"
            case .Colorist: return "Colorist"
            case .Letterer: return "Letterer"
            case .CoverArtist: return "Cover Artist"
            case .Editor: return "Editor"
            case .Publisher: return "Publisher"
            case .Imprint: return "Imprint"
            case .Genre: return "Genre"
            case .Web: return "Web"
            case .LanguageISO: return "Language"
            case .Format: return "Format"
            case .BlackAndWhite: return "Black and White"
            case .Manga: return "Manga"
            case .Characters: return "Characters"
            case .Teams: return "Teams"
            case .Locations: return "Locations"
            case .ScanInformation: return "Scan Information"
            case .StoryArc: return "Story Arc"
            case .SeriesGroup: return "Series Group"
            case .AgeRating: return "Age Rating"
            case .CommunityRating: return "Community Rating"
            case .MainCharacterOrTeam: return "Main Character or Team"
            case .Review: return "Review"
            case .PublishDate: return "Publish Date"
            }
        }
    }

    /// Returns true if the given property is considered populated (i.e., not default/unknown).
    func hasNonDefaultValue(_ property: EditableProperty) -> Bool {
        switch property {
        case .Title: return hasNonEmpty(\.Title)
        case .Series: return hasNonEmpty(\.Series)
        case .Number: return hasNonEmpty(\.Number)
        case .Count: return isSet(\.Count)
        case .Volume: return isSet(\.Volume)
        case .AlternateSeries: return hasNonEmpty(\.AlternateSeries)
        case .AlternateNumber: return hasNonEmpty(\.AlternateNumber)
        case .AlternateCount: return isSet(\.AlternateCount)
        case .Summary: return hasNonEmpty(\.Summary)
        case .Notes: return hasNonEmpty(\.Notes)
        case .Writer: return hasNonEmpty(\.Writer)
        case .Penciller: return hasNonEmpty(\.Penciller)
        case .Inker: return hasNonEmpty(\.Inker)
        case .Colorist: return hasNonEmpty(\.Colorist)
        case .Letterer: return hasNonEmpty(\.Letterer)
        case .CoverArtist: return hasNonEmpty(\.CoverArtist)
        case .Editor: return hasNonEmpty(\.Editor)
        case .Publisher: return hasNonEmpty(\.Publisher)
        case .Imprint: return hasNonEmpty(\.Imprint)
        case .Genre: return hasNonEmpty(\.Genre)
        case .Web: return hasNonEmpty(\.Web)
        case .LanguageISO: return hasNonEmpty(\.LanguageISO)
        case .Format: return hasNonEmpty(\.Format)
        case .BlackAndWhite: return isNotUnknown(\.BlackAndWhite, unknown: .Unknown)
        case .Manga: return isNotUnknown(\.Manga, unknown: .Unknown)
        case .Characters: return hasNonEmpty(\.Characters)
        case .Teams: return hasNonEmpty(\.Teams)
        case .Locations: return hasNonEmpty(\.Locations)
        case .ScanInformation: return hasNonEmpty(\.ScanInformation)
        case .StoryArc: return hasNonEmpty(\.StoryArc)
        case .SeriesGroup: return hasNonEmpty(\.SeriesGroup)
        case .AgeRating: return isNotUnknown(\.AgeRating, unknown: .Unknown)
        case .CommunityRating: return hasPositiveRating(\.CommunityRating)
        case .MainCharacterOrTeam: return hasNonEmpty(\.MainCharacterOrTeam)
        case .Review: return hasNonEmpty(\.Review)
        case .PublishDate: return anyPositive([\.Year, \.Month, \.Day])
        }
    }

    /// Bridges Year/Month/Day to a Date for UI pickers and back.
    var publishDate: Date {
        get {
            var comps = DateComponents()
            let y = Year > 0 ? Year : 2000
            let m = Month > 0 ? Month : 1
            let d = Day > 0 ? Day : 1
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
}

extension ComicInfoModel {
    /// Overwrite this model's properties from another instance (without changing object identity).
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
