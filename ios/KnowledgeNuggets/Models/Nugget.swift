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
    var isActive: Bool = true
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        text: String,
        author: String? = nil,
        book: String? = nil,
        category: String? = nil,
        isActive: Bool = true,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.author = author
        self.book = book
        self.category = category
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
}

/// Fields the editor produces.
struct NuggetDraft: Equatable, Sendable {
    var text: String = ""
    var author: String = ""
    var book: String = ""
    var category: String = ""

    init(text: String = "", author: String = "", book: String = "", category: String = "") {
        self.text = text
        self.author = author
        self.book = book
        self.category = category
    }

    init(_ nugget: Nugget) {
        self.init(
            text: nugget.text,
            author: nugget.author ?? "",
            book: nugget.book ?? "",
            category: nugget.category ?? ""
        )
    }

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isValid: Bool { !trimmedText.isEmpty }

    /// Empty strings become nil so blank fields are stored as "unknown".
    static func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
