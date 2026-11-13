import Foundation
import SwiftData

/// A saved passage from the owner's reading.
///
/// Every property is optional or has a default, and nothing is marked
/// `@Attribute(.unique)`, so the model can be synced with CloudKit later
/// without a migration.
@Model
final class Nugget {
    var id: UUID = UUID()
    var text: String = ""
    var author: String?
    var book: String?
    var category: String?
    /// A `NuggetKind` raw value. Nuggets saved before kinds existed were books.
    var kind: String = NuggetKind.default.rawValue
    var isActive: Bool = true
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// When the owner deliberately took this nugget out of the rotation. Nil
    /// while active, and for nuggets left inactive only because the rotation
    /// was full. Orders the Inactive list; optional so CloudKit and
    /// lightweight migration accept it.
    var deactivatedAt: Date?

    init(
        id: UUID = UUID(),
        text: String,
        author: String? = nil,
        book: String? = nil,
        category: String? = nil,
        kind: NuggetKind = .default,
        isActive: Bool = true,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deactivatedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.author = author
        self.book = book
        self.category = category
        self.kind = kind.rawValue
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deactivatedAt = deactivatedAt
    }

    /// A value copy that is safe to pass to the rotation and notification code.
    var snapshot: NuggetSnapshot {
        NuggetSnapshot(id: id, text: text, author: author, book: book)
    }
}

/// The parts of a nugget the rotation and notifications need, as a plain value.
struct NuggetSnapshot: Equatable, Hashable, Sendable, Identifiable {
    var id: UUID
    var text: String
    var author: String?
    var book: String?

    init(id: UUID = UUID(), text: String, author: String? = nil, book: String? = nil) {
        self.id = id
        self.text = text
        self.author = author
        self.book = book
    }

    /// "Author · Book", either one alone, or nil when neither is known.
    var attribution: String? {
        Self.attribution(author: author, book: book)
    }

    static func attribution(author: String?, book: String?) -> String? {
        let parts = [author, book]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension Nugget {
    var attribution: String? { NuggetSnapshot.attribution(author: author, book: book) }

    var nuggetKind: NuggetKind {
        get { NuggetKind(storedValue: kind) }
        set { kind = newValue.rawValue }
    }
}

/// Fields the editor produces.
struct NuggetDraft: Equatable, Sendable {
    var text: String = ""
    var author: String = ""
    var book: String = ""
    var category: String = ""
    var kind: NuggetKind = .default
    /// The editor's Active switch. For a new nugget this is the wish; the store
    /// still keeps it inactive when the rotation is full.
    var isActive: Bool = true

    init(
        text: String = "",
        author: String = "",
        book: String = "",
        category: String = "",
        kind: NuggetKind = .default,
        isActive: Bool = true
    ) {
        self.text = text
        self.author = author
        self.book = book
        self.category = category
        self.kind = kind
        self.isActive = isActive
    }

    init(_ nugget: Nugget) {
        self.init(
            text: nugget.text,
            author: nugget.author ?? "",
            book: nugget.book ?? "",
            category: nugget.category ?? "",
            kind: nugget.nuggetKind,
            isActive: nugget.isActive
        )
    }

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The content is filled in.
    var isValid: Bool { !trimmedText.isEmpty }

    /// By or From is filled in, unless this kind has no source (affirmations).
    var hasRequiredSource: Bool {
        !kind.hasSource || Self.clean(author) != nil || Self.clean(book) != nil
    }

    /// Everything the editor requires before Done is enabled.
    var canSave: Bool { isValid && hasRequiredSource }

    /// Why Done is disabled, or nil when it isn't.
    var missingRequirement: String? {
        if !hasRequiredSource { return "Add who it's by or where it's from." }
        return nil
    }

    /// Author and book as they should be stored: nil when blank or when this kind has no source.
    var storedAuthor: String? { kind.hasSource ? Self.clean(author) : nil }
    var storedBook: String? { kind.hasSource ? Self.clean(book) : nil }

    /// Empty strings become nil so blank fields are stored as "unknown".
    static func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
