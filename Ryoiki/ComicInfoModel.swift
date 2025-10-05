//
//  ComicInfoModal.swift
//  MetaComic
//
//  Created by Stardust on 2025-10-03.
//

internal enum YesNo: String, CaseIterable {
    case Unknown = "Unknown"
    case Yes = "Yes"
    case No = "No"
}

internal enum Manga: String, CaseIterable {
    case Unknown = "Unknown"
    case Yes = "Yes"
    case No = "No"
    case YesAndRightToLeft = "YesAndRightToLeft"
}

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

internal struct ComicPageInfo: Identifiable {
    var id: ObjectIdentifier

    var Image: String
    var PageType: ComicPageType = .Story
    var DoublePage: Bool = false
    var ImageSize: Int64 = 0
    var Key: String = ""
    var Bookmark: String = ""
    var ImageWidth: Int = -1
    var ImageHeight: Int = -1
}

internal enum ComicPageType: String, CaseIterable {
    case FrontCover = "FrontCover"
    case InnerCover = "InnerCover"
    case Roundup = "Roundup"
    case Story = "Story"
    case Advertisement = "Advertisement"
    case Editorial = "Editorial"
    case Letters = "Letters"
    case Preview = "Preview"
    case BackCover = "BackCover"
    case Other = "Other"
    case Deleted = "Deleted"
}

class ComicInfoModel: Identifiable {
    var Title: String = ""
    var Series: String = ""
    var Number: String = ""
    var Count: Int = -1
    var Volume: Int = -1
    var AlternateSeries: String = ""
    var AlternateNumber: String = ""
    var AlternateCount: Int = -1
    var Summary: String = ""
    var Notes: String = ""
    var Year: Int = -1
    var Month: Int = -1
    var Day: Int = -1
    var Writer: String = ""
    var Penciller: String = ""
    var Inker: String = ""
    var Colorist: String = ""
    var Letterer: String = ""
    var CoverArtist: String = ""
    var Editor: String = ""
    var Publisher: String = ""
    var Imprint: String = ""
    var Genre: String = ""
    var Web: String = ""
    var PageCount: Int = 0
    var LanguageISO: String = ""
    var Format: String = ""
    var BlackAndWhite: YesNo = .Unknown
    var Manga: Manga = .Unknown
    var Characters: String = ""
    var Teams: String = ""
    var Locations: String = ""
    var ScanInformation: String = ""
    var StoryArc: String = ""
    var SeriesGroup: String = ""
    var AgeRating: AgeRating = .Unknown
    var Pages: [ComicPageInfo]?
    var CommunityRating: Rating?
    var MainCharacterOrTeam: String = ""
    var Review: String = ""
}
