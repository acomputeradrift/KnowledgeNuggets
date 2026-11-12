import SwiftData
import XCTest
@testable import KnowledgeNuggets

@MainActor
final class AppModelTests: XCTestCase {
    private var container: ModelContainer!
    private var center: FakeNotificationCenter!
    private var defaults: UserDefaults!
    private let calendar = makeCalendar()

    override func setUp() async throws {
        container = try SwiftDataNuggetStore.makeContainer(inMemory: true)
        center = FakeNotificationCenter(status: .notDetermined)
        let suite = "AppModelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeModel(lookup: MetadataLookup = FakeLookup(), now: Date? = nil) -> AppModel {
        let fixed = now ?? date(2026, 1, 1, 6, in: calendar)
        return AppModel(
            store: SwiftDataNuggetStore(context: container.mainContext),
            scheduler: NotificationScheduler(center: center, calendar: calendar, now: { fixed }),
            lookup: lookup,
            defaults: defaults,
            calendar: calendar,
            now: { fixed }
        )
    }

    func testPermissionIsNotRequestedAtLaunchButWhenATimeIsSet() async {
        let model = makeModel()
        model.save(NuggetDraft(text: "One"))
        await model.appBecameActive()
        XCTAssertEqual(center.authorizationRequests, 0)
        XCTAssertEqual(center.pending.count, 0)

        await model.setDailyTime(date(2026, 1, 1, 7, 30, in: calendar))
        await model.rescheduleNow()
        XCTAssertEqual(center.authorizationRequests, 1)
        XCTAssertEqual(model.settings.minutesAfterMidnight, 7 * 60 + 30)
        XCTAssertTrue(model.settings.hasChosenTime)
        XCTAssertEqual(center.pending.count, 60)
        XCTAssertEqual(model.scheduledCount, 60)
    }

    func testEveryChangeReschedules() async {
        center.setStatus(.authorized)
        let model = makeModel()
        model.save(NuggetDraft(text: "One"))
        model.save(NuggetDraft(text: "Two"))
        await model.rescheduleNow()
        XCTAssertEqual(Set(center.pending.map(\.content.body)), ["One", "Two"])

        model.setActive(model.active[0], false)
        await model.rescheduleNow()
        XCTAssertEqual(Set(center.pending.map(\.content.body)), ["Two"])

        model.setPaused(true)
        await model.rescheduleNow()
        XCTAssertEqual(center.pending.count, 0)

        model.setPaused(false)
        model.delete(model.active[0])
        await model.rescheduleNow()
        XCTAssertEqual(center.pending.count, 0, "No active nuggets means nothing scheduled")
    }

    func testRotationStartIsSetOnFirstScheduleAndKept() async {
        center.setStatus(.authorized)
        let model = makeModel()
        XCTAssertNil(model.settings.rotationStart)
        await model.rescheduleNow()
        XCTAssertEqual(model.settings.rotationStart, date(2026, 1, 1, 0, in: calendar))

        let later = makeModel(now: date(2026, 2, 1, 6, in: calendar))
        await later.rescheduleNow()
        XCTAssertEqual(later.settings.rotationStart, date(2026, 1, 1, 0, in: calendar))
    }

    func testTodayAndUpNextFollowListOrder() async {
        let model = makeModel()
        for name in ["A", "B", "C"] { model.save(NuggetDraft(text: name)) }
        XCTAssertEqual(model.todayNugget?.text, "A")
        XCTAssertEqual(model.upNextNugget?.text, "B")

        model.moveActive(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(model.todayNugget?.text, "C")
        XCTAssertEqual(model.upNextNugget?.text, "A")
    }

    func testSavingPastTheLimitReturnsAMessage() {
        let model = makeModel()
        for index in 0..<21 {
            XCTAssertNil(model.save(NuggetDraft(text: "N\(index)")))
        }
        XCTAssertNotNil(model.save(NuggetDraft(text: "Too many")))
        XCTAssertEqual(model.active.count, 21)
        XCTAssertEqual(model.inactive.map(\.text), ["Too many"])
    }

    func testMissingAuthorIsFilledAfterSave() async {
        let model = makeModel(lookup: FakeLookup(authors: ["Dune": "Frank Herbert"]))
        model.save(NuggetDraft(text: "Fear is the mind-killer.", book: "Dune"))
        await model.lookupTask?.value
        XCTAssertEqual(model.active.first?.author, "Frank Herbert")
    }

    func testMissingBookIsFilledAfterSave() async {
        let model = makeModel(lookup: FakeLookup(books: ["James Clear": "Atomic Habits"]))
        model.save(NuggetDraft(text: "Systems.", author: "James Clear"))
        await model.lookupTask?.value
        XCTAssertEqual(model.active.first?.book, "Atomic Habits")
    }

    func testNoMatchLeavesTheFieldBlank() async {
        let model = makeModel(lookup: FakeLookup())
        model.save(NuggetDraft(text: "x", book: "Unknown Book"))
        await model.lookupTask?.value
        XCTAssertNil(model.active.first?.author)
    }

    func testNoLookupWhenBothOrNeitherKnown() async {
        let model = makeModel(lookup: FakeLookup(authors: ["B": "Should not be used"]))
        model.save(NuggetDraft(text: "x", author: "A", book: "B"))
        model.save(NuggetDraft(text: "y"))
        XCTAssertNil(model.lookupTask)
        XCTAssertEqual(model.active.first?.author, "A")
    }
}
