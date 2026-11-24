import Foundation

/// Rules shared by every store implementation.
enum NuggetRules {
    /// The most nuggets that can be in the daily rotation at once.
    static let activeLimit = 21

    /// Explains a refused move into Active: the list's alert, and Undo when
    /// Active filled up meanwhile.
    static var activeFullMessage: String {
        "\(activeLimit) nuggets are already active. Pause at least one to make room."
    }

    /// Under the editor's state pill.
    static let statePickerNote = "Tap to move it. Active needs a free spot."

    /// Under the editor's state pill when Active is greyed out.
    static var activeLimitReachedNote: String {
        "\(activeLimit) nuggets are already active. Pause one to make room."
    }
}

/// Where a new nugget went.
enum ActivationOutcome: Equatable, Sendable {
    /// Into the daily rotation.
    case active
    /// Active was chosen but full, so it went to the bottom of Queued.
    case queuedBecauseActiveFull
    /// Queued or Paused was chosen.
    case chose(NuggetState)

    /// The section it ended up in.
    var state: NuggetState {
        switch self {
        case .active: return .active
        case .queuedBecauseActiveFull: return .queued
        case .chose(let state): return state
        }
    }
}

/// What happened when a nugget was moved to a section and position.
enum PlacementOutcome: Equatable, Sendable {
    /// It changed section.
    case moved
    /// It stayed in its section at a new position.
    case reordered
    /// Already there.
    case unchanged
    /// Refused: Active is full and it isn't one of them.
    case activeFull
}

/// The result of importing a backup.
struct ImportSummary: Equatable, Sendable {
    var added = 0
    var updated = 0
    var unchanged = 0
    /// Nuggets that were active in the backup but went to the bottom of Queued
    /// because Active was full.
    var queuedBecauseActiveFull = 0
    /// Nuggets skipped because their content matches a different nugget already here.
    var duplicatesSkipped = 0

    var message: String {
        var lines = ["Added \(added), updated \(updated), unchanged \(unchanged)."]
        if duplicatesSkipped > 0 {
            lines.append("\(Self.duplicatesText(duplicatesSkipped)).")
        }
        if queuedBecauseActiveFull > 0 {
            lines.append("\(queuedBecauseActiveFull) went to Queued because \(NuggetRules.activeLimit) nuggets are already active.")
        }
        return lines.joined(separator: " ")
    }

    /// "1 duplicate skipped", "2 duplicates skipped".
    static func duplicatesText(_ count: Int) -> String {
        count == 1 ? "1 duplicate skipped" : "\(count) duplicates skipped"
    }
}

/// Storage for nuggets. Screens and the app model talk to this protocol, so the
/// SwiftData implementation can be swapped (for example for a remote store).
///
/// Nuggets are in one of three user-ordered sections: Active (the rotation, at
/// most `NuggetRules.activeLimit`), Queued and Paused. Nothing ever moves into
/// Active on its own: pausing or deleting an active nugget leaves the spot open.
@MainActor
protocol NuggetStore: AnyObject {
    /// The nuggets in one section, in the user's order.
    func nuggets(in state: NuggetState) throws -> [Nugget]
    func nugget(id: UUID) throws -> Nugget?
    /// The nugget whose content matches `text` (see `NuggetText.matchKey`),
    /// other than the one with `excluding`'s id.
    func duplicate(of text: String, excluding id: UUID?) throws -> Nugget?

    /// Adds a nugget to the bottom of `state`'s section. Active when full goes
    /// to the bottom of Queued instead.
    @discardableResult
    func add(_ draft: NuggetDraft, state: NuggetState) throws -> (Nugget, ActivationOutcome)
    /// Saves the content fields. The section and position don't change.
    func update(_ nugget: Nugget, with draft: NuggetDraft) throws
    /// Fills in a looked-up author or book, only where the field is still blank.
    func fillMetadata(id: UUID, author: String?, book: String?) throws -> Bool
    /// Moves a nugget to `state` at `index` (the bottom when nil), within its
    /// section or between sections. Into Active is refused when it's full.
    @discardableResult
    func place(_ nugget: Nugget, in state: NuggetState, at index: Int?) throws -> PlacementOutcome
    func delete(_ nugget: Nugget) throws

    /// Fills in `state` for nuggets saved before states existed. Safe to run every launch.
    @discardableResult
    func migrateLegacyStates() throws -> Int
    /// Strips one layer of wrapping quotation marks from every stored text.
    /// Run once; the app model remembers that it has.
    @discardableResult
    func stripStoredQuotes() throws -> Int

    func exportBackup() throws -> NuggetBackup
    func importBackup(_ backup: NuggetBackup) throws -> ImportSummary
}

extension NuggetStore {
    /// Active nuggets in rotation order.
    func activeNuggets() throws -> [Nugget] { try nuggets(in: .active) }

    /// Reorders one section using `List.onMove` offsets.
    func move(in state: NuggetState, fromOffsets source: IndexSet, toOffset destination: Int) throws {
        let ordered = try nuggets(in: state)
        guard let from = source.first, ordered.indices.contains(from) else { return }
        // onMove's destination counts the row itself; place(at:) counts the others.
        let index = destination > from ? destination - 1 : destination
        try place(ordered[from], in: state, at: index)
    }
}
