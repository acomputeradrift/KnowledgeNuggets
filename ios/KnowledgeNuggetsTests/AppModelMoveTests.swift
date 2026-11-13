import SwiftData
import XCTest
@testable import KnowledgeNuggets

/// Moving nuggets between Active and Inactive, and undoing it.
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

    private func add(_ texts: [String], active: Bool = true, to model: AppModel) {
        for text in texts { model.save(NuggetDraft(text: text, kind: .affirmation, isActive: active)) }
    }

    private struct NotMoved: Error {}

    private func moved(_ result: AppModel.MoveResult, file: StaticString = #filePath, line: UInt = #line) throws -> AppModel.ActiveMove {
        guard case .moved(let move) = result else {
            XCTFail("Expected a move, got \(result)", file: file, line: line)
            throw NotMoved()
        }
        return move
    }

    func testDeactivatingReportsTheMoveAndUndoPutsItBackInPlace() throws {
        let model = makeModel()
        add(["A", "B", "C"], to: model)

        let move = try moved(model.move(model.active[1], toActive: false))
        XCTAssertFalse(move.isActive)
        XCTAssertEqual(move.previousIndex, 1)
        XCTAssertEqual(move.message, "Moved to Inactive")
        XCTAssertEqual(model.active.map(\.text), ["A", "C"])
        XCTAssertEqual(model.inactive.map(\.text), ["B"])

        XCTAssertNil(model.undo(move))
        XCTAssertEqual(model.active.map(\.text), ["A", "B", "C"])
        XCTAssertTrue(model.inactive.isEmpty)
        XCTAssertNil(model.active[1].deactivatedAt)
    }

    func testActivatingReportsTheMoveAndUndoRestoresItsInactivePlace() throws {
        let model = makeModel()
        add(["X", "Y", "Z"], active: false, to: model)
        let x = model.inactive[0]
        let stamp = try XCTUnwrap(x.deactivatedAt)

        let move = try moved(model.move(x, toActive: true))
        XCTAssertTrue(move.isActive)
        XCTAssertEqual(move.previousIndex, 0)
        XCTAssertEqual(move.message, "Moved to Active")
        XCTAssertEqual(model.active.map(\.text), ["X"])
        XCTAssertEqual(model.inactive.map(\.text), ["Y", "Z"])

        model.undo(move)
        XCTAssertTrue(model.active.isEmpty)
        XCTAssertEqual(model.inactive.map(\.text), ["X", "Y", "Z"], "Back at the top, not stamped as just moved out")
        XCTAssertEqual(x.deactivatedAt, stamp)
    }

    func testUndoKeepsAWaitingNuggetWaiting() throws {
        let model = makeModel()
        add((0..<21).map { "N\($0)" }, to: model)
        add(["Off"], active: false, to: model)
        add(["Waiting"], to: model) // Kept inactive by the limit, so it waits for a spot.
        XCTAssertEqual(model.inactive.map(\.text), ["Waiting", "Off"])
        model.move(model.active[0], toActive: false)
        let waiting = try XCTUnwrap(model.inactive.first { $0.text == "Waiting" })

        let move = try moved(model.move(waiting, toActive: true))
        model.undo(move)
        XCTAssertNil(waiting.deactivatedAt)
        XCTAssertEqual(model.inactive.first?.text, "Waiting")
    }

    func testUndoingTheLastActiveReturnsItToTheEnd() throws {
        let model = makeModel()
        add(["A", "B", "C"], to: model)
        let move = try moved(model.move(model.active[2], toActive: false))
        model.undo(move)
        XCTAssertEqual(model.active.map(\.text), ["A", "B", "C"])
    }

    func testMovingIntoAFullRotationIsRefusedAndChangesNothing() throws {
        let model = makeModel()
        add((0..<21).map { "N\($0)" }, to: model)
        add(["Off"], active: false, to: model)
        let off = model.inactive[0]

        guard case .rotationFull(let message) = model.move(off, toActive: true) else {
            return XCTFail("Expected the rotation to be full")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(model.active.count, 21)
        XCTAssertFalse(off.isActive)
        XCTAssertNotNil(off.deactivatedAt)
    }

    func testMovingToWhereItAlreadyIsDoesNothing() {
        let model = makeModel()
        add(["A"], to: model)
        XCTAssertEqual(model.move(model.active[0], toActive: true), .unchanged)
    }

    func testUndoIsRefusedWhenTheRotationFilledUpMeanwhile() throws {
        let model = makeModel()
        add((0..<21).map { "N\($0)" }, to: model)
        let move = try moved(model.move(model.active[0], toActive: false))
        add(["New"], to: model) // Takes the free spot.

        XCTAssertNotNil(model.undo(move))
        XCTAssertEqual(model.active.count, 21)
        XCTAssertEqual(model.inactive.map(\.text), ["N0"])
    }

    func testUndoDoesNothingOnceTheNuggetHasMovedAgainOrGone() throws {
        let model = makeModel()
        add(["A", "B"], to: model)
        let a = model.active[0]
        let first = try moved(model.move(a, toActive: false))
        model.move(a, toActive: true)
        XCTAssertNil(model.undo(first))
        XCTAssertEqual(model.active.map(\.text), ["B", "A"], "The stale undo is ignored")

        let second = try moved(model.move(a, toActive: false))
        XCTAssertTrue(model.delete(a))
        XCTAssertNil(model.undo(second))
        XCTAssertEqual(model.active.map(\.text), ["B"])
    }

    func testSetActiveStillReturnsTheLimitMessage() {
        let model = makeModel()
        add((0..<21).map { "N\($0)" }, to: model)
        add(["Off"], active: false, to: model)
        XCTAssertNotNil(model.setActive(model.inactive[0], true))
        XCTAssertNil(model.setActive(model.active[0], false))
    }

    // MARK: Edits

    func testAnEditWithoutAMoveReportsUpdated() {
        let model = makeModel()
        add(["A"], to: model)
        let nugget = model.active[0]
        XCTAssertEqual(model.update(nugget, with: NuggetDraft(text: "A edited", kind: .affirmation)), .updated)
        XCTAssertEqual(nugget.text, "A edited")
    }

    func testAnEditThatFlipsTheSwitchReportsTheMoveAndCanBeUndone() throws {
        let model = makeModel()
        add(["A", "B", "C"], to: model)
        let b = model.active[1]
        var draft = NuggetDraft(b)
        draft.text = "B edited"
        draft.isActive = false

        guard case .moved(let move) = model.update(b, with: draft) else {
            return XCTFail("Expected the edit to report a move")
        }
        XCTAssertEqual(move.message, "Moved to Inactive")
        XCTAssertEqual(model.inactive.map(\.text), ["B edited"])

        model.undo(move)
        XCTAssertEqual(model.active.map(\.text), ["A", "B edited", "C"], "Undo reverses the move and keeps the text edit")
    }

    func testAnEditSwitchedOnWhileFullReportsOnlyTheUpdate() {
        let model = makeModel()
        add((0..<21).map { "N\($0)" }, to: model)
        add(["Off"], active: false, to: model)
        let off = model.inactive[0]
        var draft = NuggetDraft(off)
        draft.isActive = true
        XCTAssertEqual(model.update(off, with: draft), .updated)
        XCTAssertFalse(off.isActive)
    }

    func testAnInvalidEditSavesNothing() {
        let model = makeModel()
        add(["A"], to: model)
        XCTAssertNil(model.update(model.active[0], with: NuggetDraft(text: " ", kind: .affirmation)))
        XCTAssertEqual(model.active.map(\.text), ["A"])
    }
}
