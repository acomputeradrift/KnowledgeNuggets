import Foundation
import SwiftData

/// A saved passage from the owner's reading.
///
/// Every property is optional or has a default, and nothing is marked
/// `@Attribute(.unique)`, so the model can be synced with CloudKit later
/// without a migration.
/// Where a nugget sits. Stored on `Nugget` as its raw value.
enum NuggetState: String, CaseIterable, Codable, Identifiable, Sendable {
    /// In the daily rotation, at most `NuggetRules.activeLimit`.
    case active
    /// Waiting for a spot. New nuggets go here when Active is full.
    case queued
    /// Set aside: not wanted any time soon, but not deleted.
    case paused

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "Active"
        case .queued: return "Queued"
        case .paused: return "Paused"
        }
    }
}

/// A saved passage from the owner's reading.
///
/// Every property is optional or has a default, and nothing is marked
/// `@Attribute(.unique)`, so the model can be synced with CloudKit later
/// without a migration.
@Model
final class Nugget {
    var id: UUID = UUID()
    /// Stored without wrapping quotation marks; shown with `NuggetText.quoted`.
    var text: String = ""
    var author: String?
    var book: String?
    var category: String?
    /// A `NuggetKind` raw value. Nuggets saved before kinds existed were books.
    var kind: String = NuggetKind.default.rawValue
    /// A `NuggetState` raw value. Empty for nuggets saved before states
    /// existed, until `SwiftDataNuggetStore.migrateLegacyStates()` fills it in
    /// from the legacy fields; `nuggetState` reads those meanwhile.
    var state: String = ""
    /// Position within its section (Active, Queued or Paused).
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// Legacy, from before states: the old Active switch. Read only by the
    /// state migration; renamed in Swift with `originalName` so existing
    /// stores open with a lightweight migration and keep the value.
    @Attribute(originalName: "isActive") var legacyIsActive: Bool = true
    /// Legacy, from before states: when an inactive nugget was moved out on
    /// purpose (nil while it waited for a spot). Read only by the migration.
    @Attribute(originalName: "deactivatedAt") var legacyDeactivatedAt: Date?

    init(
        id: UUID = UUID(),
        text: String,
        author: String? = nil,
        book: String? = nil,
        category: String? = nil,
        kind: NuggetKind = .default,
        state: NuggetState = .active,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.author = author
        self.book = book
        self.category = category
        self.kind = kind.rawValue
        self.state = state.rawValue
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.legacyIsActive = state == .active
        self.legacyDeactivatedAt = nil
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

    /// The nugget's section. Before the migration has run, it's worked out
    /// from the legacy fields the same way the migration does.
    var nuggetState: NuggetState {
        get { NuggetState(rawValue: state) ?? legacyState }
        set { state = newValue.rawValue }
    }

    /// In the daily rotation.
    var isActive: Bool { nuggetState == .active }

    /// The mapping from before states: active stays active; inactive and never
    /// moved out on purpose (waiting for a spot) is queued; moved out on
    /// purpose is paused.
    var legacyState: NuggetState {
        if legacyIsActive { return .active }
        return legacyDeactivatedAt == nil ? .queued : .paused
    }

    /// The content as it's shown, in curly quotes.
    var quotedText: String { NuggetText.quoted(text) }
}

/// Fields the editor produces.
struct NuggetDraft: Equatable, Sendable {
    var text: String = ""
    var author: String = ""
    var book: String = ""
    var category: String = ""
    var kind: NuggetKind = .default
    /// The editor's Active | Queued | Paused choice. For a new nugget, Active
    /// is the wish; the store still queues it when Active is full.
    var state: NuggetState = .active

    init(
        text: String = "",
        author: String = "",
        book: String = "",
        category: String = "",
        kind: NuggetKind = .default,
        state: NuggetState = .active
    ) {
        self.text = text
        self.author = author
        self.book = book
        self.category = category
        self.kind = kind
        self.state = state
    }

    init(_ nugget: Nugget) {
        self.init(
            text: nugget.text,
            author: nugget.author ?? "",
            book: nugget.book ?? "",
            category: nugget.category ?? "",
            kind: nugget.nuggetKind,
            state: nugget.nuggetState
        )
    }

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The content as it's stored: trimmed, without wrapping quotation marks.
    var storedText: String { NuggetText.stored(text) }

    /// The content is filled in.
    var isValid: Bool { !storedText.isEmpty }

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
