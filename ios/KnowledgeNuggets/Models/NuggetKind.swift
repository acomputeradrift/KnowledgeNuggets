import Foundation

/// Where a nugget came from. Stored as its raw value so new kinds can be added
/// without a migration; an unknown value reads as `.other`.
enum NuggetKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case book, movie, show, podcast, lyrics, quote, affirmation, other

    static let `default`: NuggetKind = .book

    var id: String { rawValue }

    var title: String {
        switch self {
        case .book: return "Book"
        case .movie: return "Movie"
        case .show: return "Show"
        case .podcast: return "Podcast"
        case .lyrics: return "Lyrics"
        case .quote: return "Quote"
        case .affirmation: return "Affirmation"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .book: return "book"
        case .movie: return "film"
        case .show: return "tv"
        case .podcast: return "mic"
        case .lyrics: return "music.note"
        case .quote: return "quote.bubble"
        case .affirmation: return "heart"
        case .other: return "sparkles"
        }
    }

    /// Affirmations are your own words, so they have no By or From.
    var hasSource: Bool { self != .affirmation }

    /// Placeholder for the "By" field (stored as `author`).
    var byPrompt: String {
        switch self {
        case .book: return "Author"
        case .movie, .show: return "Character, actor or director"
        case .podcast: return "Host or guest"
        case .lyrics: return "Artist"
        case .quote: return "Who said it"
        case .affirmation, .other: return "Person"
        }
    }

    /// Placeholder for the "From" field (stored as `book`).
    var fromPrompt: String {
        switch self {
        case .book: return "Book title"
        case .movie: return "Movie title"
        case .show: return "Show or episode"
        case .podcast: return "Podcast or episode"
        case .lyrics: return "Song"
        case .quote: return "Speech, article or occasion"
        case .affirmation, .other: return "Source"
        }
    }

    /// Open Library only knows books.
    var supportsLookup: Bool { self == .book }

    init(storedValue: String?) {
        self = storedValue.flatMap(NuggetKind.init(rawValue:)) ?? .other
    }
}
