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
        try (0..<count).map { try store.add(NuggetDraft(text: "Nugget \($0)"), state: .active).0 }
    }

    // MARK: 21-nugget limit

    func testTwentyFirstIsActiveTwentySecondGoesToTheBottomOfQueued() throws {
        try addActive(20)
        try store.add(NuggetDraft(text: "Queued first"), state: .queued)

        let (twentyFirst, outcome21) = try store.add(NuggetDraft(text: "21st"), state: .active)
        XCTAssertEqual(outcome21, .active)
        XCTAssertTrue(twentyFirst.isActive)

        let (twentySecond, outcome22) = try store.add(NuggetDraft(text: "22nd"), state: .active)
        XCTAssertEqual(outcome22, .queuedBecauseActiveFull)
        XCTAssertEqual(twentySecond.nuggetState, .queued)

        XCTAssertEqual(try store.activeNuggets().count, 21)
        XCTAssertEqual(try store.nuggets(in: .queued).map(\.text), ["Queued first", "22nd"])
    }

    func testActivatingPastTheLimitIsRefused() throws {
        let active = try addActive(21)
        let (extra, _) = try store.add(NuggetDraft(text: "Extra"), state: .paused)

        XCTAssertEqual(try store.place(extra, in: .active, at: nil), .activeFull)
        XCTAssertEqual(extra.nuggetState, .paused)

        // Make room, then it goes to the end of the rotation.
        XCTAssertEqual(try store.place(active[5], in: .paused, at: nil), .moved)
        XCTAssertEqual(try store.place(extra, in: .active, at: nil), .moved)
        XCTAssertEqual(try store.activeNuggets().last?.text, "Extra")
        XCTAssertEqual(try store.activeNuggets().count, 21)
    }

    func testEditorNotes() {
        XCTAssertEqual(NuggetRules.statePickerNote, "Tap to move it. Active needs a free spot.")
        XCTAssertEqual(NuggetRules.activeLimitReachedNote, "21 nuggets are already active. Pause one to make room.")
    }

    func testQueuedAndPausedAreUnlimited() throws {
        try addActive(21)
        for index in 0..<30 {
            try store.add(NuggetDraft(text: "Queued \(index)"), state: .queued)
            try store.add(NuggetDraft(text: "Paused \(index)"), state: .paused)
        }
        XCTAssertEqual(try store.nuggets(in: .queued).count, 30)
        XCTAssertEqual(try store.nuggets(in: .paused).count, 30)
    }

    // MARK: Editing and ordering

    func testAddTrimsAndBlanksBecomeNil() throws {
        let (nugget, _) = try store.add(NuggetDraft(text: "  Hello \n", author: "  ", book: " Book ", category: ""), state: .active)
        XCTAssertEqual(nugget.text, "Hello")
        XCTAssertNil(nugget.author)
        XCTAssertEqual(nugget.book, "Book")
        XCTAssertNil(nugget.category)
    }

    func testEmptyTextIsNotValid() {
        XCTAssertFalse(NuggetDraft(text: "   \n ").isValid)
        XCTAssertTrue(NuggetDraft(text: "x").isValid)
    }

    func testDeleteMidCycleKeepsOrderOfTheRest() throws {
        let nuggets = try addActive(5)
        try store.delete(nuggets[2])
        XCTAssertEqual(try store.activeNuggets().map(\.text), ["Nugget 0", "Nugget 1", "Nugget 3", "Nugget 4"])
    }

    func testFillMetadataOnlyFillsBlanks() throws {
        let (nugget, _) = try store.add(NuggetDraft(text: "x", book: "Dune"), state: .active)
        XCTAssertTrue(try store.fillMetadata(id: nugget.id, author: "Frank Herbert", book: "Other"))
        XCTAssertEqual(nugget.author, "Frank Herbert")
        XCTAssertEqual(nugget.book, "Dune")
        XCTAssertFalse(try store.fillMetadata(id: nugget.id, author: "Someone Else", book: nil))
        XCTAssertEqual(nugget.author, "Frank Herbert")
    }

    // MARK: Sections

    /// 21 active, then: two queued because Active was full, one added as
    /// paused, one more queued, and finally the first active nugget paused.
    /// That leaves a free spot that nothing fills on its own.
    @discardableResult
    private func mixedSections() throws -> [Nugget] {
        let active = try addActive(21)
        try store.add(NuggetDraft(text: "Wait A"), state: .active)
        try store.add(NuggetDraft(text: "Wait B"), state: .active)
        try store.add(NuggetDraft(text: "Off X"), state: .paused)
        try store.add(NuggetDraft(text: "Wait C"), state: .active)
        try store.place(active[0], in: .paused, at: nil)
        return active
    }

    func testSectionsKeepTheirOrderAndPausingGoesToTheBottom() throws {
        let active = try mixedSections()
        XCTAssertEqual(try store.nuggets(in: .queued).map(\.text), ["Wait A", "Wait B", "Wait C"])
        XCTAssertEqual(try store.nuggets(in: .paused).map(\.text), ["Off X", "Nugget 0"])
        try store.place(active[1], in: .paused, at: nil)
        XCTAssertEqual(try store.nuggets(in: .paused).last?.text, "Nugget 1")
        XCTAssertEqual(try store.nuggets(in: .paused).map(\.sortOrder), [0, 1, 2])
    }

    func testEditingDoesNotMoveANugget() throws {
        try mixedSections()
        let queued = try store.nuggets(in: .queued)
        let paused = try store.nuggets(in: .paused)
        try store.update(queued[0], with: NuggetDraft(text: "Wait A edited"))
        try store.update(paused[0], with: NuggetDraft(text: "Off X edited"))
        XCTAssertTrue(try store.fillMetadata(id: queued[1].id, author: "Someone", book: nil))
        XCTAssertEqual(try store.nuggets(in: .queued).map(\.text), ["Wait A edited", "Wait B", "Wait C"])
        XCTAssertEqual(try store.nuggets(in: .paused).map(\.text), ["Off X edited", "Nugget 0"])
    }

    func testPlacingAtAPositionAndReordering() throws {
        try mixedSections()
        let paused = try store.nuggets(in: .paused)
        XCTAssertEqual(try store.place(paused[1], in: .queued, at: 1), .moved)
        XCTAssertEqual(try store.nuggets(in: .queued).map(\.text), ["Wait A", "Nugget 0", "Wait B", "Wait C"])
        XCTAssertEqual(try store.nuggets(in: .queued).map(\.sortOrder), [0, 1, 2, 3])
        XCTAssertEqual(try store.place(paused[1], in: .queued, at: 1), .unchanged)
        XCTAssertEqual(try store.place(paused[1], in: .queued, at: 99), .reordered, "Clamped to the bottom")
        XCTAssertEqual(try store.nuggets(in: .queued).last?.text, "Nugget 0")
    }

    func testMoveActiveReordersAndRenumbers() throws {
        try addActive(4)
        try store.move(in: .active, fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(try store.activeNuggets().map(\.text), ["Nugget 3", "Nugget 0", "Nugget 1", "Nugget 2"])
        try store.move(in: .active, fromOffsets: IndexSet(integer: 0), toOffset: 4)
        let active = try store.activeNuggets()
        XCTAssertEqual(active.map(\.text), ["Nugget 0", "Nugget 1", "Nugget 2", "Nugget 3"])
        XCTAssertEqual(active.map(\.sortOrder), [0, 1, 2, 3])
    }

    func testNothingIsPromotedWhenNuggetsArePausedOrDeleted() throws {
        let active = try mixedSections()
        XCTAssertEqual(try store.activeNuggets().count, 20)
        try store.place(active[1], in: .paused, at: nil)
        try store.delete(active[2])
        XCTAssertEqual(try store.activeNuggets().count, 18)
        XCTAssertEqual(try store.nuggets(in: .queued).map(\.text), ["Wait A", "Wait B", "Wait C"])
    }

    func testLegacyNuggetsReadTheirStateBeforeTheMigrationRuns() {
        let nugget = Nugget(text: "x")
        nugget.state = ""
        nugget.legacyIsActive = false
        XCTAssertEqual(nugget.nuggetState, .queued)
        nugget.legacyDeactivatedAt = .now
        XCTAssertEqual(nugget.nuggetState, .paused)
        nugget.legacyIsActive = true
        XCTAssertEqual(nugget.nuggetState, .active)
        nugget.nuggetState = .queued
        XCTAssertEqual(nugget.state, "queued")
    }

    // MARK: Backup states

    func testBackupRoundTripsStatesAndOrder() throws {
        try mixedSections()
        try store.move(in: .queued, fromOffsets: [2], toOffset: 0)
        let backup = try store.exportBackup()
        XCTAssertEqual(backup.version, 2)
        let data = try backup.encoded()
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"state\" : \"paused\""))

        let otherContainer = try SwiftDataNuggetStore.makeContainer(inMemory: true)
        let other = SwiftDataNuggetStore(context: otherContainer.mainContext)
        let summary = try other.importBackup(NuggetBackup.decode(data))
        XCTAssertEqual(summary.added, 25)
        XCTAssertEqual(summary.queuedBecauseActiveFull, 0)
        for state in NuggetState.allCases {
            XCTAssertEqual(try other.nuggets(in: state).map(\.text), try store.nuggets(in: state).map(\.text), state.rawValue)
        }
    }

    func testOldBackupsMapIsActiveAndDeactivatedAt() throws {
        let json = """
        {"version":1,"exportedAt":"2026-01-01T08:00:00Z","nuggets":[
          {"id":"1F9619FF-8B86-D011-B42D-00C04FC964FF","text":"Moved out later","isActive":false,"sortOrder":0,
           "createdAt":"2026-01-01T08:00:00Z","updatedAt":"2026-01-01T08:00:00Z","deactivatedAt":"2026-01-03T08:00:00Z"},
          {"id":"2F9619FF-8B86-D011-B42D-00C04FC964FF","text":"Waiting newer","isActive":false,"sortOrder":0,
           "createdAt":"2026-01-02T08:00:00Z","updatedAt":"2026-01-02T08:00:00Z"},
          {"id":"3F9619FF-8B86-D011-B42D-00C04FC964FF","text":"\\"Old active\\"","isActive":true,"sortOrder":0,
           "createdAt":"2026-01-01T08:00:00Z","updatedAt":"2026-01-01T08:00:00Z"},
          {"id":"4F9619FF-8B86-D011-B42D-00C04FC964FF","text":"Moved out first","isActive":false,"sortOrder":0,
           "createdAt":"2026-01-01T09:00:00Z","updatedAt":"2026-01-01T09:00:00Z","deactivatedAt":"2026-01-02T08:00:00Z"},
          {"id":"5F9619FF-8B86-D011-B42D-00C04FC964FF","text":"Waiting older","isActive":false,"sortOrder":0,
           "createdAt":"2026-01-01T07:00:00Z","updatedAt":"2026-01-01T07:00:00Z"}]}
        """
        let backup = try NuggetBackup.decode(Data(json.utf8))
        XCTAssertNil(backup.nuggets[0].state)
        XCTAssertEqual(backup.nuggets.map(\.resolvedState), [.paused, .queued, .active, .paused, .queued])
        let summary = try store.importBackup(backup)
        XCTAssertEqual(summary.added, 5)
        XCTAssertEqual(try store.activeNuggets().map(\.text), ["Old active"], "Wrapping quotes stripped")
        XCTAssertEqual(try store.nuggets(in: .queued).map(\.text), ["Waiting older", "Waiting newer"])
        XCTAssertEqual(try store.nuggets(in: .paused).map(\.text), ["Moved out first", "Moved out later"])
    }

    func testImportKeepsMergeRulesForStates() throws {
        let nuggets = try addActive(2)
        try store.place(nuggets[0], in: .paused, at: nil)

        // A newer copy from an older backup that only says "inactive" keeps what this device knows.
        var item = NuggetBackup.Item(nuggets[0])
        item.text = "Newer"
        item.updatedAt = nuggets[0].updatedAt.addingTimeInterval(60)
        item.state = nil
        item.isActive = false
        item.deactivatedAt = nil
        XCTAssertEqual(try store.importBackup(NuggetBackup(exportedAt: .now, nuggets: [item])).updated, 1)
        XCTAssertEqual(nuggets[0].text, "Newer")
        XCTAssertEqual(nuggets[0].nuggetState, .paused)

        // A newer copy that's active brings it back to the end of the rotation.
        item.state = "active"
        item.updatedAt = item.updatedAt.addingTimeInterval(60)
        try store.importBackup(NuggetBackup(exportedAt: .now, nuggets: [item]))
        XCTAssertTrue(nuggets[0].isActive)
        XCTAssertEqual(try store.activeNuggets().last?.id, nuggets[0].id)

        // A newer copy that's queued moves it to the bottom of Queued.
        item.state = "queued"
        item.updatedAt = item.updatedAt.addingTimeInterval(60)
        try store.importBackup(NuggetBackup(exportedAt: .now, nuggets: [item]))
        XCTAssertEqual(nuggets[0].nuggetState, .queued)

        // An older copy changes nothing.
        let stale = NuggetBackup.Item(
            id: nuggets[1].id, text: "Stale", state: .paused, createdAt: nuggets[1].createdAt,
            updatedAt: nuggets[1].updatedAt.addingTimeInterval(-60)
        )
        XCTAssertEqual(try store.importBackup(NuggetBackup(exportedAt: .now, nuggets: [stale])).unchanged, 1)
        XCTAssertTrue(nuggets[1].isActive)
    }

    // MARK: Import duplicates

    func testImportSkipsDuplicatesOfADifferentNugget() throws {
        let (local, _) = try store.add(NuggetDraft(text: "Slow is smooth."), state: .active)
        let items = [
            NuggetBackup.Item(id: UUID(), text: "“slow is SMOOTH”", state: .queued, createdAt: .now, updatedAt: .now),
            NuggetBackup.Item(id: UUID(), text: "Fresh", state: .queued, createdAt: .now, updatedAt: .now),
            NuggetBackup.Item(id: UUID(), text: "fresh!", state: .paused, createdAt: .now, updatedAt: .now),
            // The same nugget, newer: not a duplicate of itself.
            NuggetBackup.Item(id: local.id, text: "Slow is smooth!", state: .active, createdAt: local.createdAt,
                              updatedAt: local.updatedAt.addingTimeInterval(60)),
        ]
        let summary = try store.importBackup(NuggetBackup(exportedAt: .now, nuggets: items))
        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(summary.updated, 1)
        XCTAssertEqual(summary.duplicatesSkipped, 2)
        XCTAssertEqual(summary.message, "Added 1, updated 1, unchanged 0. 2 duplicates skipped.")
        XCTAssertEqual(local.text, "Slow is smooth!")
        XCTAssertEqual(try store.nuggets(in: .queued).map(\.text), ["Fresh"])
        XCTAssertTrue(try store.nuggets(in: .paused).isEmpty)
    }

    func testDuplicateLookupIgnoresTheExcludedNugget() throws {
        let (nugget, _) = try store.add(NuggetDraft(text: "Hello there."), state: .paused)
        XCTAssertEqual(try store.duplicate(of: "hello THERE", excluding: nil)?.id, nugget.id)
        XCTAssertNil(try store.duplicate(of: "hello THERE", excluding: nugget.id))
        XCTAssertNil(try store.duplicate(of: "  ", excluding: nil))
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
        let (existing, _) = try store.add(NuggetDraft(text: "Old text"), state: .active)
        let newer = NuggetBackup.Item(
            id: existing.id, text: "New text", author: "A", state: .active, createdAt: existing.createdAt,
            updatedAt: existing.updatedAt.addingTimeInterval(60)
        )
        let fresh = NuggetBackup.Item(
            id: UUID(), text: "Brand new", book: "B", category: "C", state: .queued, createdAt: .now, updatedAt: .now
        )
        let summary = try store.importBackup(NuggetBackup(exportedAt: .now, nuggets: [newer, fresh]))
        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(summary.updated, 1)
        XCTAssertEqual(existing.text, "New text")
        XCTAssertEqual(existing.author, "A")
        XCTAssertEqual(try store.nuggets(in: .queued).map(\.text), ["Brand new"])
    }

    func testImportPastTheActiveLimitGoesToTheBottomOfQueued() throws {
        try addActive(20)
        try store.add(NuggetDraft(text: "Already queued"), state: .queued)
        let items = (0..<3).map { index in
            NuggetBackup.Item(
                id: UUID(), text: "Imported \(index)", state: .active, sortOrder: index, createdAt: .now, updatedAt: .now
            )
        }
        let summary = try store.importBackup(NuggetBackup(exportedAt: .now, nuggets: items))
        XCTAssertEqual(summary.added, 3)
        XCTAssertEqual(summary.queuedBecauseActiveFull, 2)
        XCTAssertEqual(summary.message, "Added 3, updated 0, unchanged 0. 2 went to Queued because 21 nuggets are already active.")
        XCTAssertEqual(try store.activeNuggets().count, 21)
        XCTAssertEqual(try store.activeNuggets().last?.text, "Imported 0")
        XCTAssertEqual(try store.nuggets(in: .queued).map(\.text), ["Already queued", "Imported 1", "Imported 2"])
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
