import Foundation

/// Rules shared by every store implementation.
enum NuggetRules {
    /// The most nuggets that can be in the daily rotation at once.
    static let activeLimit = 21

    /// Under the editor's Active switch when it's disabled because the limit is reached.
    static var activeLimitReachedNote: String {
        "\(activeLimit) nuggets are already active. Make one inactive first."
    }
}

/// What happened when a nugget was added or activated.
enum ActivationOutcome: Equatable, Sendable {
    /// The nugget is in the daily rotation.
    case active
    /// The nugget was saved but left out of the rotation because it is full.
    case keptInactiveLimitReached
    /// The nugget was saved as inactive on purpose.
    case inactive

    var message: String? {
        switch self {
        case .keptInactiveLimitReached:
            return "You already have \(NuggetRules.activeLimit) active nuggets, so this one was saved as inactive. Deactivate another to make room."
        case .active, .inactive:
            return nil
        }
    }
}

/// The result of importing a backup.
struct ImportSummary: Equatable, Sendable {
    var added = 0
    var updated = 0
    var unchanged = 0
    /// Nuggets that were active in the backup but saved inactive because of the limit.
    var keptInactive = 0

    var message: String {
        var lines = ["Added \(added), updated \(updated), unchanged \(unchanged)."]
        if keptInactive > 0 {
            lines.append("\(keptInactive) saved as inactive because the \(NuggetRules.activeLimit)-nugget limit was reached.")
        }
        return lines.joined(separator: " ")
    }
}

/// Storage for nuggets. Screens and the app model talk to this protocol, so the
/// SwiftData implementation can be swapped (for example for a remote store).
@MainActor
protocol NuggetStore: AnyObject {
    /// Active nuggets in rotation order.
    func activeNuggets() throws -> [Nugget]
    /// Inactive nuggets: those waiting for a spot, oldest first, then those moved
    /// out on purpose, most recently moved out last. Editing never changes it.
    func inactiveNuggets() throws -> [Nugget]
    func nugget(id: UUID) throws -> Nugget?

    /// Adds a nugget. It goes to the end of the rotation unless the rotation is full.
    /// `active: false` saves it inactive on purpose, so it counts as moved out.
    @discardableResult
    func add(_ draft: NuggetDraft, active: Bool) throws -> (Nugget, ActivationOutcome)
    func update(_ nugget: Nugget, with draft: NuggetDraft) throws
    /// Fills in a looked-up author or book, only where the field is still blank.
    func fillMetadata(id: UUID, author: String?, book: String?) throws -> Bool
    /// Moving out stamps `deactivatedAt`; moving in clears it and appends to the
    /// rotation, unless the rotation is full. Nothing is ever promoted automatically.
    @discardableResult
    func setActive(_ nugget: Nugget, _ active: Bool) throws -> ActivationOutcome
    func delete(_ nugget: Nugget) throws
    /// Reorders the active nuggets using `List.onMove` offsets.
    func moveActive(fromOffsets source: IndexSet, toOffset destination: Int) throws

    func exportBackup() throws -> NuggetBackup
    func importBackup(_ backup: NuggetBackup) throws -> ImportSummary
}
