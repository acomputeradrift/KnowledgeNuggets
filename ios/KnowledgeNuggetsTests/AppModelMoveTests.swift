import SwiftData
import XCTest
@testable import KnowledgeNuggets

/// Moving nuggets between Active, Queued and Paused (swipe, drag and the
/// editor), undoing it, duplicates and the launch migrations.
@MainActor
final class AppModelMoveTests: XCTestCase {
    private var container: ModelContainer!
    private var defaults: UserDefaults!
    private let calendar = makeCalendar()
    /// Moves on a minute each time it's read, so every change gets its own timestamp.
    private var clock = Date()

    override func setUp() async throws {
        container = try SwiftDataNuggetStore.makeContainer(inMemory: true)
        let suite = "AppModelMoveTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        clock = date(2026, 1, 1, 6, in: calendar)
    }

    private func makeModel() -> AppModel {
        let tick: () -> Date = { [unowned self] in
            clock = clock.addingTimeInterval(60)
            return clock
        }
        return AppModel(
            store: SwiftDataNuggetStore(context: container.mainContext, now: tick),
            scheduler: NotificationScheduler(center: FakeNotificationCenter(), calendar: calendar, now: tick),
            lookup: FakeLookup(),
            defaults: defaults,
            calendar: calendar,
            now: tick
        )
    }

    private func add(_ texts: [String], to state: NuggetState = .active, in model: AppModel) {
        for text in texts { model.save(NuggetDraft(text: text, kind: .affirmation, state: state)) }
    }

    /// 21 active (N0…N20), queued Q1 Q2, paused P1 P2.
    private func fullModel() -> AppModel {
        let model = makeModel()
        add((0..<21).map { "N\($0)" }, in: model)
        add(["Q1", "Q2"], to: .queued, in: model)
        add(["P1", "P2"], to: .paused, in: model)
        return model
    }

    private struct NotMoved: Error {}

    private func moved(_ result: AppModel.MoveResult, file: StaticString = #filePath, line: UInt = #line) throws -> AppModel.StateMove {
        guard case .moved(let move) = result else {
            XCTFail("Expected a move, got \(result)", file: file, line: line)
            throw NotMoved()
        }
        return move
    }

    // MARK: Swipes

    func testPausingGoesToTheBottomOfPausedAndUndoPutsItBack() throws {
        let model = makeModel()
        add(["A", "B", "C"], in: model)
        add(["P1"], to: .paused, in: model)

        let move = try moved(model.move(model.active[1], to: .paused))
        XCTAssertEqual(move.from, .active)
        XCTAssertEqual(move.to, .paused)
        XCTAssertEqual(move.previousIndex, 1)
        XCTAssertEqual(move.message, "Moved to Paused")
        XCTAssertFalse(move.entersActive, "No success haptic out of Active")
        XCTAssertEqual(model.active.map(\.text), ["A", "C"])
        XCTAssertEqual(model.paused.map(\.text), ["P1", "B"])

        XCTAssertNil(model.undo(move))
        XCTAssertEqual(model.active.map(\.text), ["A", "B", "C"])
        XCTAssertEqual(model.paused.map(\.text), ["P1"])
    }

    func testActivatingFromQueuedOrPausedAppendsToActiveAndUndoRestoresItsPlace() throws {
        let model = makeModel()
        add(["A"], in: model)
        add(["Q1", "Q2", "Q3"], to: .queued, in: model)
        add(["P1", "P2"], to: .paused, in: model)

        let fromQueued = try moved(model.move(model.queued[1], to: .active))
        XCTAssertEqual(fromQueued.message, "Moved to Active")
        XCTAssertTrue(fromQueued.entersActive, "Success haptic into Active")
        XCTAssertEqual(model.active.map(\.text), ["A", "Q2"])
        XCTAssertEqual(model.queued.map(\.text), ["Q1", "Q3"])
        model.undo(fromQueued)
        XCTAssertEqual(model.queued.map(\.text), ["Q1", "Q2", "Q3"], "Back in the middle where it was")

        let fromPaused = try moved(model.move(model.paused[0], to: .active))
        XCTAssertEqual(model.active.map(\.text), ["A", "P1"])
        model.undo(fromPaused)
        XCTAssertEqual(model.paused.map(\.text), ["P1", "P2"])
        XCTAssertEqual(model.active.map(\.text), ["A"])
    }

    func testActivatingWhileFullIsRefusedAndChangesNothing() {
        let model = fullModel()
        for nugget in [model.queued[0], model.paused[0]] {
            XCTAssertEqual(model.move(nugget, to: .active), .activeFull(NuggetRules.activeFullMessage))
        }
        XCTAssertEqual(NuggetRules.activeFullMessage, "21 nuggets are already active. Pause at least one to make room.")
        XCTAssertEqual(model.active.count, 21)
        XCTAssertEqual(model.queued.map(\.text), ["Q1", "Q2"])
        XCTAssertEqual(model.paused.map(\.text), ["P1", "P2"])
    }

    func testMovingToWhereItAlreadyIsDoesNothing() {
        let model = makeModel()
        add(["A"], in: model)
        XCTAssertEqual(model.move(model.active[0], to: .active), .unchanged)
        XCTAssertEqual(model.move(model.active[0], to: .active, at: 0), .unchanged)
    }

    // MARK: Dragging

    func testDraggingBetweenQueuedAndPausedPlacesItWhereDropped() throws {
        let model = fullModel()
        let move = try moved(model.move(model.paused[1], to: .queued, at: 1))
        XCTAssertEqual(move.message, "Moved to Queued")
        XCTAssertEqual(model.queued.map(\.text), ["Q1", "P2", "Q2"])
        XCTAssertEqual(model.paused.map(\.text), ["P1"])

        try moved(model.move(model.queued[0], to: .paused, at: 0))
        XCTAssertEqual(model.paused.map(\.text), ["Q1", "P1"])
        XCTAssertEqual(model.queued.map(\.text), ["P2", "Q2"])
    }

    func testDraggingOutOfActiveIsAllowedAndIntoActiveNeedsRoom() throws {
        let model = fullModel()
        XCTAssertEqual(model.move(model.queued[0], to: .active, at: 3), .activeFull(NuggetRules.activeFullMessage))

        try moved(model.move(model.active[5], to: .queued, at: 0))
        XCTAssertEqual(model.queued.map(\.text), ["N5", "Q1", "Q2"])
        XCTAssertEqual(model.active.count, 20)

        let move = try moved(model.move(model.paused[0], to: .active, at: 2))
        XCTAssertTrue(move.entersActive)
        XCTAssertEqual(model.active.prefix(4).map(\.text), ["N0", "N1", "P1", "N2"])
        XCTAssertEqual(model.active.count, 21)
    }

    func testReorderingWithinASectionIsNotAMove() {
        let model = fullModel()
        XCTAssertEqual(model.move(model.queued[1], to: .queued, at: 0), .reordered)
        XCTAssertEqual(model.queued.map(\.text), ["Q2", "Q1"])
        XCTAssertEqual(model.move(model.active[20], to: .active, at: 0), .reordered, "Allowed while full")
        XCTAssertEqual(model.active.first?.text, "N20")
        model.move(in: .paused, fromOffsets: [0], toOffset: 2)
        XCTAssertEqual(model.paused.map(\.text), ["P2", "P1"])
    }

    // MARK: Nothing is promoted

    func testPausingOrDeletingAnActiveNuggetLeavesTheSpotOpen() throws {
        let model = fullModel()
        model.move(model.active[0], to: .paused)
        XCTAssertTrue(model.delete(model.active[0]))
        XCTAssertEqual(model.active.count, 19)
        XCTAssertEqual(model.queued.map(\.text), ["Q1", "Q2"], "Queued stays queued")
        XCTAssertEqual(model.paused.map(\.text), ["P1", "P2", "N0"])
    }

    // MARK: Undo

    func testUndoIsRefusedWhenActiveFilledUpMeanwhile() throws {
        let model = fullModel()
        let move = try moved(model.move(model.active[0], to: .paused))
        add(["New"], in: model) // Takes the free spot.

        XCTAssertNotNil(model.undo(move))
        XCTAssertEqual(model.active.count, 21)
        XCTAssertEqual(model.paused.map(\.text), ["P1", "P2", "N0"])
    }

    func testUndoDoesNothingOnceTheNuggetHasMovedAgainOrGone() throws {
        let model = makeModel()
        add(["A", "B"], in: model)
        let a = model.active[0]
        let first = try moved(model.move(a, to: .paused))
        model.move(a, to: .active)
        XCTAssertNil(model.undo(first))
        XCTAssertEqual(model.active.map(\.text), ["B", "A"], "The stale undo is ignored")

        let second = try moved(model.move(a, to: .queued))
        XCTAssertTrue(model.delete(a))
        XCTAssertNil(model.undo(second))
        XCTAssertEqual(model.active.map(\.text), ["B"])
    }

    func testUndoingAnEditsMoveKeepsTheTextEdit() throws {
        let model = makeModel()
        add(["A", "B", "C"], in: model)
        let b = model.active[1]
        var draft = NuggetDraft(b)
        draft.text = "B edited"
        draft.state = .queued

        guard case .moved(let move) = model.update(b, with: draft) else {
            return XCTFail("Expected the edit to report a move")
        }
        XCTAssertEqual(move.message, "Moved to Queued")
        XCTAssertEqual(model.queued.map(\.text), ["B edited"])

        model.undo(move)
        XCTAssertEqual(model.active.map(\.text), ["A", "B edited", "C"])
    }

    // MARK: Edits

    func testAnEditWithoutAMoveReportsUpdated() {
        let model = makeModel()
        add(["A"], in: model)
        let nugget = model.active[0]
        XCTAssertEqual(model.update(nugget, with: NuggetDraft(text: "A edited", kind: .affirmation)), .updated)
        XCTAssertEqual(nugget.text, "A edited")
    }

    func testAnInvalidEditSavesNothing() {
        let model = makeModel()
        add(["A"], in: model)
        XCTAssertNil(model.update(model.active[0], with: NuggetDraft(text: " ", kind: .affirmation)))
        XCTAssertEqual(model.active.map(\.text), ["A"])
    }

    // MARK: Duplicates

    func testADuplicateNewNuggetIsNotSaved() {
        let model = makeModel()
        add(["Slow is smooth, and smooth is fast."], to: .paused, in: model)
        XCTAssertNotNil(model.duplicate(of: "  “slow is SMOOTH,   and smooth is fast!” "))
        XCTAssertNil(model.save(NuggetDraft(text: "\"Slow is smooth, and smooth is fast\"", kind: .affirmation)))
        XCTAssertEqual(model.all.count, 1)
    }

    func testAnEditDoesNotMatchItselfButCannotCopyAnother() {
        let model = makeModel()
        add(["Alpha.", "Beta"], in: model)
        let alpha = model.active[0]
        XCTAssertNil(model.duplicate(of: "alpha", excluding: alpha), "An edit never matches itself")
        XCTAssertEqual(model.update(alpha, with: NuggetDraft(text: "“ALPHA”", kind: .affirmation)), .updated)
        XCTAssertEqual(alpha.text, "ALPHA")

        XCTAssertEqual(model.duplicate(of: "beta.", excluding: alpha)?.text, "Beta")
        XCTAssertNil(model.update(alpha, with: NuggetDraft(text: "beta.", kind: .affirmation)))
        XCTAssertEqual(alpha.text, "ALPHA")
    }

    // MARK: Quotes

    func testSavedContentDropsOneLayerOfWrappingQuotes() {
        let model = makeModel()
        add(["\"Straight\"", "“Curly”", "‘Single’", "«Guillemets»", "He said \"hi\" twice"], in: model)
        XCTAssertEqual(model.active.map(\.text), ["Straight", "Curly", "Single", "Guillemets", "He said \"hi\" twice"])
        XCTAssertEqual(model.active.map(\.quotedText), ["“Straight”", "“Curly”", "“Single”", "“Guillemets”", "“He said \"hi\" twice”"])
    }

    func testTheLaunchMigrationStripsStoredQuotesOnce() throws {
        let context = container.mainContext
        context.insert(Nugget(text: "“Already quoted”", state: .active))
        context.insert(Nugget(text: "\"\"Twice\"\"", state: .queued))
        try context.save()

        let model = makeModel()
        XCTAssertEqual(model.active.map(\.quotedText), ["“Already quoted”"], "Never double-quoted")
        XCTAssertEqual(model.queued.map(\.text), ["\"Twice\""], "One layer only")
        XCTAssertTrue(defaults.bool(forKey: AppModel.quotesMigratedKey))

        let relaunched = makeModel()
        XCTAssertEqual(relaunched.queued.map(\.text), ["\"Twice\""], "Runs once")
        XCTAssertEqual(relaunched.queued.map(\.quotedText), ["“Twice”"], "Still shown with one pair")
    }

    // MARK: State migration

    func testTheLaunchMigrationMapsLegacyNuggets() throws {
        let context = container.mainContext
        let base = date(2025, 6, 1, in: calendar)
        func legacy(_ text: String, active: Bool, order: Int = 0, created: Double, movedOut: Double? = nil) {
            let nugget = Nugget(text: text, createdAt: base.addingTimeInterval(created), updatedAt: base)
            nugget.state = ""
            nugget.sortOrder = order
            nugget.legacyIsActive = active
            nugget.legacyDeactivatedAt = movedOut.map { base.addingTimeInterval($0) }
            context.insert(nugget)
        }
        legacy("Second active", active: true, order: 1, created: 1)
        legacy("First active", active: true, order: 0, created: 2)
        legacy("Waiting newer", active: false, created: 20)
        legacy("Waiting older", active: false, created: 10)
        legacy("Moved out later", active: false, created: 5, movedOut: 200)
        legacy("Moved out first", active: false, created: 6, movedOut: 100)
        try context.save()

        let model = makeModel()
        XCTAssertEqual(model.active.map(\.text), ["First active", "Second active"])
        XCTAssertEqual(model.queued.map(\.text), ["Waiting older", "Waiting newer"], "Oldest first")
        XCTAssertEqual(model.paused.map(\.text), ["Moved out first", "Moved out later"], "In the order moved out")
        XCTAssertEqual(Set(model.all.map(\.state)), ["active", "queued", "paused"], "Stored, not just read")
        XCTAssertEqual(model.queued.map(\.sortOrder), [0, 1])
        XCTAssertTrue(model.all.allSatisfy { $0.updatedAt == base }, "Not a user change, so backups still merge")

        XCTAssertEqual(try model.store.migrateLegacyStates(), 0, "Safe to run again")
    }
}
