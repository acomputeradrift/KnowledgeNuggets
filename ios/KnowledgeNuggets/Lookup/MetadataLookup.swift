import Foundation

/// Fills in a missing author or book.
protocol MetadataLookup: Sendable {
    /// The author of the book with exactly this title, or nil.
    func author(forBook book: String) async -> String?
    /// A book by exactly this author, or nil.
    func book(forAuthor author: String) async -> String?
}

/// What to look up after a save: only when exactly one of author or book is known.
enum LookupRequest: Equatable, Sendable {
    case authorForBook(String)
    case bookForAuthor(String)

    init?(author: String?, book: String?) {
        let author = NuggetDraft.clean(author ?? "")
        let book = NuggetDraft.clean(book ?? "")
        switch (author, book) {
        case let (nil, book?): self = .authorForBook(book)
        case let (author?, nil): self = .bookForAuthor(author)
        default: return nil
        }
    }
}

/// Normalises names and titles so only exact matches are accepted.
enum MetadataNormalizer {
    /// Lowercases, drops straight and curly quotes, turns dashes into hyphens
    /// and collapses whitespace.
    static func normalize(_ value: String) -> String {
        var result = value.lowercased()
        for quote in ["\"", "'", "\u{2018}", "\u{2019}", "\u{201C}", "\u{201D}", "\u{00AB}", "\u{00BB}", "`"] {
            result = result.replacingOccurrences(of: quote, with: "")
        }
        for dash in ["\u{2013}", "\u{2014}"] {
            result = result.replacingOccurrences(of: dash, with: "-")
        }
        return result
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalize(lhs)
        return !left.isEmpty && left == normalize(rhs)
    }
}

/// Looks up books on Open Library (https://openlibrary.org/developers/api).
/// Sends only the author or title. Any error or non-exact match returns nil.
struct OpenLibraryLookup: MetadataLookup {
    struct SearchResponse: Decodable {
        struct Doc: Decodable {
            var title: String?
            var author_name: [String]?
        }
        var docs: [Doc]
    }

    var session: URLSession = .shared
    var baseURL = URL(string: "https://openlibrary.org/search.json")!

    func author(forBook book: String) async -> String? {
        guard let docs = await search([URLQueryItem(name: "title", value: book)]) else { return nil }
        return Self.author(forBook: book, in: docs)
    }

    func book(forAuthor author: String) async -> String? {
        guard let docs = await search([URLQueryItem(name: "author", value: author)]) else { return nil }
        return Self.book(forAuthor: author, in: docs)
    }

    /// First author of the first result whose title matches exactly.
    static func author(forBook book: String, in docs: [SearchResponse.Doc]) -> String? {
        docs.first { MetadataNormalizer.matches($0.title ?? "", book) }?
            .author_name?.first
            .flatMap { NuggetDraft.clean($0) }
    }

    /// Title of the most relevant result whose first author matches exactly.
    static func book(forAuthor author: String, in docs: [SearchResponse.Doc]) -> String? {
        docs.first { MetadataNormalizer.matches($0.author_name?.first ?? "", author) }?
            .title
            .flatMap { NuggetDraft.clean($0) }
    }

    private func search(_ items: [URLQueryItem]) async -> [SearchResponse.Doc]? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = items + [
            URLQueryItem(name: "fields", value: "title,author_name"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("KnowledgeNuggets-iOS/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(SearchResponse.self, from: data).docs
        } catch {
            return nil
        }
    }
}
