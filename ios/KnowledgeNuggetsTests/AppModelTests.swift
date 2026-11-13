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
        model.save(NuggetDraft(text: "One", kind: .affirmation))
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
        model.save(NuggetDraft(text: "One", kind: .affirmation))
        model.save(NuggetDraft(text: "Two", kind: .affirmation))
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
        for name in ["A", "B", "C"] { model.save(NuggetDraft(text: name, kind: .affirmation)) }
        XCTAssertEqual(model.todayNugget?.text, "A")
        XCTAssertEqual(model.upNextNugget?.text, "B")

        model.moveActive(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(model.todayNugget?.text, "C")
        XCTAssertEqual(model.upNextNugget?.text, "A")
    }

    func testSavingPastTheLimitReturnsAMessage() {
        let model = makeModel()
        for index in 0..<21 {
            XCTAssertNil(model.save(NuggetDraft(text: "N\(index)", kind: .affirmation)))
        }
        XCTAssertNotNil(model.save(NuggetDraft(text: "Too many", kind: .affirmation)))
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

    // MARK: Day changes

    private func makeModel(clock: TestClock) -> AppModel {
        AppModel(
            store: SwiftDataNuggetStore(context: container.mainContext),
            scheduler: NotificationScheduler(center: center, calendar: calendar, now: { clock.now }),
            lookup: FakeLookup(),
            defaults: defaults,
            calendar: calendar,
            now: { clock.now }
        )
    }

    func testTodayIsTheStartOfTheClocksDay() {
        let clock = TestClock(date(2026, 1, 1, 18, in: calendar))
        let model = makeModel(clock: clock)
        XCTAssertEqual(model.today, date(2026, 1, 1, 0, in: calendar))
    }

    func testRefreshAfterMidnightMovesTodayOn() async {
        center.setStatus(.authorized)
        let clock = TestClock(date(2026, 1, 1, 22, in: calendar))
        let model = makeModel(clock: clock)
        for name in ["A", "B", "C"] { model.save(NuggetDraft(text: name, kind: .affirmation)) }
        await model.rescheduleNow()
        XCTAssertEqual(model.todayNugget?.text, "A")
        XCTAssertEqual(model.upNextNugget?.text, "B")

        // Still the same day: nothing moves.
        clock.now = date(2026, 1, 1, 23, 59, in: calendar)
        XCTAssertFalse(model.refreshDay())
        XCTAssertEqual(model.todayNugget?.text, "A")

        // Past midnight, but before anything tells the model: the shown day is
        // the observed one, so it only changes on refresh.
        clock.now = date(2026, 1, 2, 7, in: calendar)
        XCTAssertEqual(model.todayNugget?.text, "A")
        XCTAssertTrue(model.refreshDay())
        XCTAssertEqual(model.today, date(2026, 1, 2, 0, in: calendar))
        XCTAssertEqual(model.todayNugget?.text, "B")
        XCTAssertEqual(model.upNextNugget?.text, "C")
        XCTAssertFalse(model.refreshDay(), "A second refresh on the same day changes nothing")
    }

    func testBecomingActiveTheNextMorningMovesTodayOn() async {
        let clock = TestClock(date(2026, 1, 1, 9, in: calendar))
        let model = makeModel(clock: clock)
        for name in ["A", "B"] { model.save(NuggetDraft(text: name, kind: .affirmation)) }
        await model.rescheduleNow()
        XCTAssertEqual(model.todayNugget?.text, "A")

        clock.now = date(2026, 1, 2, 8, in: calendar)
        await model.appBecameActive()
        XCTAssertEqual(model.todayNugget?.text, "B")
        XCTAssertEqual(model.upNextNugget?.text, "A")
    }

    func testTimeDidChangeMovesTodayOnAndReschedules() async {
        center.setStatus(.authorized)
        let clock = TestClock(date(2026, 1, 1, 23, in: calendar))
        let model = makeModel(clock: clock)
        for name in ["A", "B"] { model.save(NuggetDraft(text: name, kind: .affirmation)) }
        await model.rescheduleNow()

        clock.now = date(2026, 1, 2, 0, 0, in: calendar)
        model.timeDidChange()
        await model.rescheduleNow()
        XCTAssertEqual(model.todayNugget?.text, "B")
        XCTAssertFalse(center.pending.contains { $0.identifier == "nugget-2026-01-01" })
    }

    func testRotationIsAnchoredWhileTheDayMovesOn() async {
        let clock = TestClock(date(2026, 1, 1, 9, in: calendar))
        let model = makeModel(clock: clock)
        for name in ["A", "B", "C"] { model.save(NuggetDraft(text: name, kind: .affirmation)) }
        await model.rescheduleNow()
        XCTAssertEqual(model.settings.rotationStart, date(2026, 1, 1, 0, in: calendar))

        clock.now = date(2026, 1, 3, 9, in: calendar)
        model.refreshDay()
        XCTAssertEqual(model.todayNugget?.text, "C")
    }

    func testTodaysNotificationMatchesTodayNugget() async {
        center.setStatus(.authorized)
        let clock = TestClock(date(2026, 1, 1, 6, in: calendar))
        let model = makeModel(clock: clock)
        for name in ["A", "B", "C"] { model.save(NuggetDraft(text: name, kind: .affirmation)) }
        // Daily time 08:00, after the clock, so today's notification is queued.
        await model.setDailyTime(date(2026, 1, 1, 8, in: calendar))
        await model.rescheduleNow()

        for day in 1...5 {
            clock.now = date(2026, 1, day, 6, in: calendar)
            await model.appBecameActive()
            let identifier = String(format: "nugget-2026-01-%02d", day)
            let request = center.pending.first { $0.identifier == identifier }
            XCTAssertNotNil(request, "Today's notification is queued on day \(day)")
            XCTAssertEqual(request?.content.body, model.todayNugget?.text, "Day \(day)")
            XCTAssertEqual(
                request.flatMap { NotificationScheduler.nuggetID(from: $0.content.userInfo) },
                model.todayNugget?.id
            )
        }
    }

    func testNoLookupWhenBothOrNeitherKnown() async {
        let model = makeModel(lookup: FakeLookup(authors: ["B": "Should not be used"]))
        model.save(NuggetDraft(text: "x", author: "A", book: "B"))
        model.save(NuggetDraft(text: "y", kind: .affirmation))
        XCTAssertNil(model.lookupTask)
        XCTAssertEqual(model.active.first?.author, "A")
    }
}
