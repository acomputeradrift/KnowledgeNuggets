import SwiftData
import XCTest
@testable import KnowledgeNuggets

@MainActor
final class NuggetStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var store: SwiftDataNuggetStore!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        container = try SwiftDataNuggetStore.makeContainer(inMemory: true)
        store = SwiftDataNuggetStore(context: container.mainContext, now: { [unowned self] in
            clock = clock.addingTimeInterval(1)
            return clock
        })
    }

    override func tearDown() async throws {
        store = nil
        container = nil
    }

    @discardableResult
    private func addActive(_ count: Int) throws -> [Nugget] {
        try (0..<count).map { try store.add(NuggetDraft(text: "Nugget \($0)"), active: true).0 }
    }

    // MARK: 21-nugget limit

    func testTwentyFirstIsActiveTwentySecondIsSavedInactive() throws {
        let first = try addActive(20)
        XCTAssertEqual(first.count, 20)

        let (twentyFirst, outcome21) = try store.add(NuggetDraft(text: "21st"), active: true)
        XCTAssertEqual(outcome21, .active)
        XCTAssertTrue(twentyFirst.isActive)

        let (twentySecond, outcome22) = try store.add(NuggetDraft(text: "22nd"), active: true)
        XCTAssertEqual(outcome22, .keptInactiveLimitReached)
        XCTAssertFalse(twentySecond.isActive)
        XCTAssertNotNil(outcome22.message)

        XCTAssertEqual(try store.activeNuggets().count, 21)
        XCTAssertEqual(try store.inactiveNuggets().map(\.text), ["22nd"])
    }

    func testActivatingPastTheLimitIsRefused() throws {
        let active = try addActive(21)
        let (extra, _) = try store.add(NuggetDraft(text: "Extra"), active: false)

        XCTAssertEqual(try store.setActive(extra, true), .keptInactiveLimitReached)
        XCTAssertFalse(extra.isActive)

        // Make room, then it goes to the end of the rotation.
        XCTAssertEqual(try store.setActive(active[5], false), .inactive)
        XCTAssertEqual(try store.setActive(extra, true), .active)
        XCTAssertEqual(try store.activeNuggets().last?.text, "Extra")
        XCTAssertEqual(try store.activeNuggets().count, 21)
    }

    func testActiveLimitReachedNote() {
        XCTAssertEqual(NuggetRules.activeLimitReachedNote, "21 nuggets are already active. Make one inactive first.")
    }

    func testInactiveNuggetsAreUnlimited() throws {
        try addActive(21)
        for index in 0..<30 {
            try store.add(NuggetDraft(text: "Inactive \(index)"), active: false)
        }
        XCTAssertEqual(try store.inactiveNuggets().count, 30)
    }

    // MARK: Editing and ordering

    func testAddTrimsAndBlanksBecomeNil() throws {
        let (nugget, _) = try store.add(NuggetDraft(text: "  Hello \n", author: "  ", book: " Book ", category: ""), active: true)
        XCTAssertEqual(nugget.text, "Hello")
        XCTAssertNil(nugget.author)
        XCTAssertEqual(nugget.book, "Book")
        XCTAssertNil(nugget.category)
    }

    func testEmptyTextIsNotValid() {
        XCTAssertFalse(NuggetDraft(text: "   \n ").isValid)
        XCTAssertTrue(NuggetDraft(text: "x").isValid)
    }

    func testMoveActiveReordersAndRenumbers() throws {
        try addActive(4)
        try store.moveActive(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        let active = try store.activeNuggets()
        XCTAssertEqual(active.map(\.text), ["Nugget 3", "Nugget 0", "Nugget 1", "Nugget 2"])
        XCTAssertEqual(active.map(\.sortOrder), [0, 1, 2, 3])
    }

    func testDeleteMidCycleKeepsOrderOfTheRest() throws {
        let nuggets = try addActive(5)
        try store.delete(nuggets[2])
        XCTAssertEqual(try store.activeNuggets().map(\.text), ["Nugget 0", "Nugget 1", "Nugget 3", "Nugget 4"])
    }

    func testFillMetadataOnlyFillsBlanks() throws {
        let (nugget, _) = try store.add(NuggetDraft(text: "x", book: "Dune"), active: true)
        XCTAssertTrue(try store.fillMetadata(id: nugget.id, author: "Frank Herbert", book: "Other"))
        XCTAssertEqual(nugget.author, "Frank Herbert")
        XCTAssertEqual(nugget.book, "Dune")
        XCTAssertFalse(try store.fillMetadata(id: nugget.id, author: "Someone Else", book: nil))
        XCTAssertEqual(nugget.author, "Frank Herbert")
    }

    // MARK: Inactive order

    /// 21 active, then: two waiting for a spot, one added with the switch off,
    /// one more waiting, and finally the oldest active nugget moved out. That
    /// leaves a free spot that nothing fills on its own.
    @discardableResult
    private func mixedInactive() throws -> [Nugget] {
        let active = try addActive(21)
        try store.add(NuggetDraft(text: "Wait A"), active: true)
        try store.add(NuggetDraft(text: "Wait B"), active: true)
        try store.add(NuggetDraft(text: "Off X"), active: false)
        try store.add(NuggetDraft(text: "Wait C"), active: true)
        try store.setActive(active[0], false)
        return active
    }

    func testInactiveListsWaitingOldestFirstThenMovedOutMostRecentLast() throws {
        try mixedInactive()
        let inactive = try store.inactiveNuggets()
        XCTAssertEqual(inactive.map(\.text), ["Wait A", "Wait B", "Wait C", "Off X", "Nugget 0"])
        XCTAssertEqual(inactive.map { $0.deactivatedAt == nil }, [true, true, true, false, false])
    }

    func testEditingDoesNotMoveAnInactiveNugget() throws {
        try mixedInactive()
        let before = try store.inactiveNuggets()
        try store.update(before[0], with: NuggetDraft(text: "Wait A edited"))
        try store.update(before[3], with: NuggetDraft(text: "Off X edited"))
        XCTAssertTrue(try store.fillMetadata(id: before[1].id, author: "Someone", book: nil))
        XCTAssertEqual(
            try store.inactiveNuggets().map(\.text),
            ["Wait A edited", "Wait B", "Wait C", "Off X edited", "Nugget 0"]
        )
    }

    func testMovingOutAgainGoesToTheBottom() throws {
        let active = try mixedInactive()
        try store.setActive(active[1], false)
        XCTAssertEqual(try store.inactiveNuggets().last?.text, "Nugget 1")
    }

    func testReactivatingClearsDeactivatedAtAndAppendsToActive() throws {
        let nuggets = try addActive(3)
        try store.setActive(nuggets[0], false)
        XCTAssertNotNil(nuggets[0].deactivatedAt)

        XCTAssertEqual(try store.setActive(nuggets[0], true), .active)
        XCTAssertNil(nuggets[0].deactivatedAt)
        XCTAssertEqual(try store.activeNuggets().map(\.text), ["Nugget 1", "Nugget 2", "Nugget 0"])
    }

    func testAddingWithTheSwitchOffGoesToTheBottomOfInactive() throws {
        try mixedInactive()
        let (added, outcome) = try store.add(NuggetDraft(text: "Off Y"), active: false)
        XCTAssertEqual(outcome, .inactive)
        XCTAssertNotNil(added.deactivatedAt)
        XCTAssertEqual(try store.inactiveNuggets().last?.text, "Off Y")
    }

    func testNothingIsPromotedWhenNuggetsAreDeactivatedOrDeleted() throws {
        let active = try mixedInactive()
        XCTAssertEqual(try store.activeNuggets().count, 20)

        try store.setActive(active[1], false)
        try store.delete(active[2])
        XCTAssertEqual(try store.activeNuggets().count, 18)
        let inactive = try store.inactiveNuggets()
        XCTAssertEqual(inactive.count, 6)
        XCTAssertEqual(inactive.prefix(3).map(\.text), ["Wait A", "Wait B", "Wait C"])
    }

    func testBackupRoundTripsDeactivatedAt() throws {
        try mixedInactive()
        let data = try store.exportBackup().encoded()
        let movedOut = try store.inactiveNuggets().filter { $0.deactivatedAt != nil }
        XCTAssertEqual(movedOut.count, 2)

        let otherContainer = try SwiftDataNuggetStore.makeContainer(inMemory: true)
        let other = SwiftDataNuggetStore(context: otherContainer.mainContext)
        let summary = try other.importBackup(NuggetBackup.decode(data))
        XCTAssertEqual(summary.added, 25)
        XCTAssertEqual(summary.keptInactive, 0)
        for original in movedOut {
            XCTAssertEqual(try other.nugget(id: original.id)?.deactivatedAt, original.deactivatedAt)
        }
        XCTAssertEqual(try other.inactiveNuggets().map(\.text), try store.inactiveNuggets().map(\.text))
    }

    func testOldBackupWithoutDeactivatedAtStillLoads() throws {
        let json = """
        {"version":1,"exportedAt":"2026-01-01T08:00:00Z","nuggets":[
          {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"Old inactive","isActive":false,"sortOrder":0,
           "createdAt":"2026-01-01T08:00:00Z","updatedAt":"2026-01-01T08:00:00Z"},
          {"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","text":"Old active","isActive":true,"sortOrder":0,
           "createdAt":"2026-01-01T08:00:00Z","updatedAt":"2026-01-01T08:00:00Z"}]}
        """
        let backup = try NuggetBackup.decode(Data(json.utf8))
        XCTAssertNil(backup.nuggets[0].deactivatedAt)
        let summary = try store.importBackup(backup)
        XCTAssertEqual(summary.added, 2)
        XCTAssertEqual(try store.activeNuggets().map(\.text), ["Old active"])
        let inactive = try store.inactiveNuggets()
        XCTAssertEqual(inactive.map(\.text), ["Old inactive"])
        XCTAssertNil(inactive[0].deactivatedAt, "Unknown, so it waits for a spot")
    }

    func testImportKeepsMergeRulesForDeactivatedAt() throws {
        let nuggets = try addActive(2)
        try store.setActive(nuggets[0], false)
        let local = try XCTUnwrap(nuggets[0].deactivatedAt)

        // A newer copy without the field (an older backup) keeps what this device knows.
        var item = NuggetBackup.Item(nuggets[0])
        item.text = "Newer"
        item.updatedAt = nuggets[0].updatedAt.addingTimeInterval(60)
        item.deactivatedAt = nil
        XCTAssertEqual(try store.importBackup(NuggetBackup(exportedAt: .now, nuggets: [item])).updated, 1)
        XCTAssertEqual(nuggets[0].text, "Newer")
        XCTAssertEqual(nuggets[0].deactivatedAt, local)

        // A newer copy that's active brings it back and clears the date.
        item.isActive = true
        item.updatedAt = item.updatedAt.addingTimeInterval(60)
        try store.importBackup(NuggetBackup(exportedAt: .now, nuggets: [item]))
        XCTAssertTrue(nuggets[0].isActive)
        XCTAssertNil(nuggets[0].deactivatedAt)
        XCTAssertEqual(try store.activeNuggets().last?.id, nuggets[0].id)

        // An older copy changes nothing.
        let stale = NuggetBackup.Item(
            id: nuggets[1].id, text: "Stale", author: nil, book: nil, category: nil,
            isActive: false, sortOrder: 0, createdAt: nuggets[1].createdAt,
            updatedAt: nuggets[1].updatedAt.addingTimeInterval(-60), deactivatedAt: .now
        )
        XCTAssertEqual(try store.importBackup(NuggetBackup(exportedAt: .now, nuggets: [stale])).unchanged, 1)
        XCTAssertTrue(nuggets[1].isActive)
        XCTAssertNil(nuggets[1].deactivatedAt)
    }

    // MARK: Backup

    func testExportImportRoundTripMergesById() throws {
        let originals = try addActive(3)
        let backup = try store.exportBackup()
        let data = try backup.encoded()

        // Change one locally after the export, so the backup copy is older.
        try store.update(originals[0], with: NuggetDraft(text: "Edited locally"))

        let decoded = try NuggetBackup.decode(data)
        let summary = try store.importBackup(decoded)
        XCTAssertEqual(summary.added, 0)
        XCTAssertEqual(summary.updated, 0)
        XCTAssertEqual(summary.unchanged, 3)
        XCTAssertEqual(originals[0].text, "Edited locally")
    }

    func testImportAddsNewAndReplacesOlder() throws {
        let (existing, _) = try store.add(NuggetDraft(text: "Old text"), active: true)
        let newer = NuggetBackup.Item(
            id: existing.id, text: "New text", author: "A", book: nil, category: nil,
            isActive: true, sortOrder: 0, createdAt: existing.createdAt,
            updatedAt: existing.updatedAt.addingTimeInterval(60)
        )
        let fresh = NuggetBackup.Item(
            id: UUID(), text: "Brand new", author: nil, book: "B", category: "C",
            isActive: false, sortOrder: 0, createdAt: .now, updatedAt: .now
        )
        let summary = try store.importBackup(NuggetBackup(exportedAt: .now, nuggets: [newer, fresh]))
        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(summary.updated, 1)
        XCTAssertEqual(existing.text, "New text")
        XCTAssertEqual(existing.author, "A")
        XCTAssertEqual(try store.inactiveNuggets().map(\.text), ["Brand new"])
    }

    func testImportRespectsTheActiveLimit() throws {
        try addActive(20)
        let items = (0..<3).map { index in
            NuggetBackup.Item(
                id: UUID(), text: "Imported \(index)", author: nil, book: nil, category: nil,
                isActive: true, sortOrder: index, createdAt: .now, updatedAt: .now
            )
        }
        let summary = try store.importBackup(NuggetBackup(exportedAt: .now, nuggets: items))
        XCTAssertEqual(summary.added, 3)
        XCTAssertEqual(summary.keptInactive, 2)
        XCTAssertEqual(try store.activeNuggets().count, 21)
        XCTAssertEqual(try store.activeNuggets().last?.text, "Imported 0")
    }

    func testDecodeAcceptsBareArrayAndFractionalDates() throws {
        let json = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"Hi","isActive":true,"sortOrder":0,
          "createdAt":"2026-01-01T08:00:00.123Z","updatedAt":"2026-01-01T08:00:00Z"}]
        """
        let backup = try NuggetBackup.decode(Data(json.utf8))
        XCTAssertEqual(backup.nuggets.count, 1)
        XCTAssertEqual(backup.nuggets[0].text, "Hi")
    }

    func testDecodeRejectsJunk() {
        XCTAssertThrowsError(try NuggetBackup.decode(Data("{\"hello\":1}".utf8)))
    }
}
