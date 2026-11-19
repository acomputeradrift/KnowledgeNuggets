import UserNotifications
import XCTest
@testable import KnowledgeNuggets

final class NotificationSchedulerTests: XCTestCase {
    let calendar = makeCalendar()
    var settings = AppSettings()

    private func plan(
        _ active: [NuggetSnapshot],
        now: Date,
        start: Date? = nil,
        calendar: Calendar? = nil
    ) -> [PlannedNotification] {
        let calendar = calendar ?? self.calendar
        return NotificationScheduler.plan(
            active: active,
            settings: settings,
            rotationStart: start ?? calendar.startOfDay(for: now),
            now: now,
            calendar: calendar
        )
    }

    // MARK: Planning

    func testPlansSixtyDaysStartingTodayWhenBeforeTheTime() {
        let now = date(2026, 1, 1, 7, 59, in: calendar)
        let planned = plan(snapshots(3), now: now)
        XCTAssertEqual(planned.count, 60)
        XCTAssertEqual(planned.first?.fireDate, date(2026, 1, 1, 8, 0, in: calendar))
        XCTAssertEqual(planned.last?.fireDate, date(2026, 3, 1, 8, 0, in: calendar))
    }

    func testStartsTomorrowWhenTodaysTimeHasPassed() {
        let now = date(2026, 1, 1, 8, 0, in: calendar)
        let planned = plan(snapshots(3), now: now)
        XCTAssertEqual(planned.count, 60)
        XCTAssertEqual(planned.first?.fireDate, date(2026, 1, 2, 8, 0, in: calendar))
    }

    func testOneNotificationPerDayWithUniqueIdentifiers() {
        let planned = plan(snapshots(5), now: date(2026, 1, 1, 6, in: calendar))
        XCTAssertEqual(Set(planned.map(\.identifier)).count, 60)
        XCTAssertEqual(planned.first?.identifier, "nugget-2026-01-01")
        for (index, item) in planned.enumerated() {
            let expectedDay = calendar.date(byAdding: .day, value: index, to: date(2026, 1, 1, in: calendar))!
            XCTAssertTrue(calendar.isDate(item.fireDate, inSameDayAs: expectedDay), "Index \(index)")
        }
    }

    func testFollowsRotationOrderAndContent() {
        let active = snapshots(3)
        let start = date(2026, 1, 1, in: calendar)
        let planned = plan(active, now: date(2026, 1, 2, 6, in: calendar), start: start)
        // Jan 2 is day 1 of the rotation.
        XCTAssertEqual(planned.prefix(4).map(\.nuggetID), [active[1].id, active[2].id, active[0].id, active[1].id])
        let first = planned[0]
        XCTAssertEqual(first.title, "Author 1 · Book 1")
        XCTAssertEqual(first.body, "Nugget 1")
    }

    func testSubtitleUsesWhateverIsKnown() {
        let active = [
            NuggetSnapshot(text: "a", author: "Only Author"),
            NuggetSnapshot(text: "b", book: "Only Book"),
            NuggetSnapshot(text: "c"),
        ]
        let planned = plan(active, now: date(2026, 1, 1, 6, in: calendar))
        XCTAssertEqual(planned.prefix(3).map(\.title), ["Only Author", "Only Book", ""])
        XCTAssertEqual(planned.prefix(3).map(\.body), ["a", "b", "c"])
    }

    func testCustomTime() {
        settings.minutesAfterMidnight = 21 * 60 + 45
        let planned = plan(snapshots(1), now: date(2026, 1, 1, 22, in: calendar))
        XCTAssertEqual(planned.first?.fireDate, date(2026, 1, 2, 21, 45, in: calendar))
        XCTAssertEqual(planned.first?.dateComponents.hour, 21)
        XCTAssertEqual(planned.first?.dateComponents.minute, 45)
    }

    func testPausedSchedulesNothing() {
        settings.isPaused = true
        XCTAssertTrue(plan(snapshots(3), now: date(2026, 1, 1, in: calendar)).isEmpty)
    }

    func testNoActiveNuggetsSchedulesNothing() {
        XCTAssertTrue(plan([], now: date(2026, 1, 1, in: calendar)).isEmpty)
    }

    func testMonthEndsAreNotSkipped() {
        let active = snapshots(4)
        let planned = plan(active, now: date(2026, 1, 30, 6, in: calendar))
        let ids = planned.map(\.identifier)
        for id in ["nugget-2026-01-31", "nugget-2026-02-01", "nugget-2026-02-28", "nugget-2026-03-01"] {
            XCTAssertTrue(ids.contains(id), id)
        }
        XCTAssertFalse(ids.contains("nugget-2026-02-29"))
        // Rotation keeps stepping by one across month ends.
        let positions = planned.map { item in active.firstIndex { $0.id == item.nuggetID }! }
        for (previous, next) in zip(positions, positions.dropFirst()) {
            XCTAssertEqual(next, (previous + 1) % active.count)
        }

        let leap = plan(snapshots(4), now: date(2028, 2, 27, 6, in: calendar))
        XCTAssertTrue(leap.map(\.identifier).contains("nugget-2028-02-29"))
    }

    func testDaylightSavingKeepsTheLocalTime() {
        // Spring forward on 2026-03-08 and fall back on 2026-11-01 in New York.
        for now in [date(2026, 3, 1, 6, in: calendar), date(2026, 10, 25, 6, in: calendar)] {
            let planned = plan(snapshots(3), now: now)
            XCTAssertEqual(planned.count, 60)
            for item in planned {
                let parts = calendar.dateComponents([.hour, .minute], from: item.fireDate)
                XCTAssertEqual(parts.hour, 8)
                XCTAssertEqual(parts.minute, 0)
                XCTAssertEqual(item.dateComponents.hour, 8)
            }
            let gaps = zip(planned, planned.dropFirst()).map { $1.fireDate.timeIntervalSince($0.fireDate) / 3600 }
            XCTAssertTrue(gaps.allSatisfy { [23, 24, 25].contains($0) })
        }
        let spring = plan(snapshots(1), now: date(2026, 3, 7, 9, in: calendar))
        // 08:00 Mar 7 to 08:00 Mar 8 spans the lost hour, so it's 23 hours, and still 08:00 local.
        XCTAssertEqual(spring[0].identifier, "nugget-2026-03-08")
        XCTAssertEqual(spring[0].fireDate.timeIntervalSince(date(2026, 3, 7, 8, in: calendar)) / 3600, 23)
    }

    func testTimeInsideTheSpringForwardGapStillFiresThatDay() {
        settings.minutesAfterMidnight = 2 * 60 + 30 // 02:30 doesn't exist on 2026-03-08
        let planned = plan(snapshots(2), now: date(2026, 3, 7, 6, in: calendar))
        let march8 = planned.first { $0.identifier == "nugget-2026-03-08" }
        XCTAssertNotNil(march8)
        XCTAssertEqual(planned.count, 60)
    }

    func testDeletingMidCycleKeepsEveryDayFilled() {
        var active = snapshots(5)
        let start = date(2026, 1, 1, in: calendar)
        let now = date(2026, 1, 3, 6, in: calendar)
        let before = plan(active, now: now, start: start)
        let deleted = active.remove(at: 3)
        let after = plan(active, now: now, start: start)

        XCTAssertEqual(after.count, 60)
        XCTAssertEqual(before.map(\.identifier), after.map(\.identifier), "Same days are covered")
        XCTAssertFalse(after.contains { $0.nuggetID == deleted.id })
        XCTAssertEqual(Set(after.map(\.nuggetID)), Set(active.map(\.id)))
    }

    func testTwentyOneActiveEachAppearAtLeastTwiceInSixtyDays() {
        let active = snapshots(NuggetRules.activeLimit)
        let planned = plan(active, now: date(2026, 1, 1, 6, in: calendar))
        let counts = Dictionary(grouping: planned, by: \.nuggetID).mapValues(\.count)
        XCTAssertEqual(counts.count, 21)
        XCTAssertTrue(counts.values.allSatisfy { $0 == 2 || $0 == 3 })
    }

    func testWorksInOtherTimeZones() {
        let tokyo = makeCalendar("Asia/Tokyo")
        let planned = plan(snapshots(2), now: date(2026, 6, 1, 6, in: tokyo), calendar: tokyo)
        XCTAssertEqual(tokyo.component(.hour, from: planned[0].fireDate), 8)
        XCTAssertNil(planned[0].dateComponents.timeZone, "Floating time follows the phone's time zone")
    }

    // MARK: Rescheduling against the notification center

    func testRescheduleClearsAndQueuesRequests() async {
        let center = FakeNotificationCenter()
        let now = date(2026, 1, 1, 6, in: calendar)
        let scheduler = NotificationScheduler(center: center, calendar: calendar, now: { now })
        let active = snapshots(3)

        let queued = await scheduler.reschedule(active: active, settings: settings, rotationStart: now)
        XCTAssertEqual(queued.count, 60)
        XCTAssertEqual(center.pending.count, 60)
        XCTAssertEqual(center.removeAllCount, 1)

        let request = center.pending[0]
        XCTAssertEqual(request.content.title, "Author 0 · Book 0", "The attribution takes the bold line")
        XCTAssertEqual(request.content.subtitle, "", "No subtitle, so the quote keeps every body line")
        XCTAssertEqual(request.content.body, "Nugget 0")
        XCTAssertEqual(NotificationScheduler.nuggetID(from: request.content.userInfo), active[0].id)
        let trigger = request.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents.day, 1)
        XCTAssertEqual(trigger?.dateComponents.hour, 8)
        XCTAssertEqual(trigger?.repeats, false)

        // Running again replaces rather than adds.
        await scheduler.reschedule(active: Array(active.prefix(1)), settings: settings, rotationStart: now)
        XCTAssertEqual(center.pending.count, 60)
        XCTAssertEqual(center.removeAllCount, 2)
        XCTAssertTrue(center.pending.allSatisfy { $0.content.body == "Nugget 0" })
    }

    func testPausingOrEmptyingClearsTheQueue() async {
        let center = FakeNotificationCenter()
        let now = date(2026, 1, 1, 6, in: calendar)
        let scheduler = NotificationScheduler(center: center, calendar: calendar, now: { now })
        await scheduler.reschedule(active: snapshots(3), settings: settings, rotationStart: now)
        XCTAssertEqual(center.pending.count, 60)

        var paused = settings
        paused.isPaused = true
        await scheduler.reschedule(active: snapshots(3), settings: paused, rotationStart: now)
        XCTAssertEqual(center.pending.count, 0)

        await scheduler.reschedule(active: snapshots(3), settings: settings, rotationStart: now)
        await scheduler.reschedule(active: [], settings: settings, rotationStart: now)
        XCTAssertEqual(center.pending.count, 0)
    }

    func testNothingQueuedWithoutPermission() async {
        for status in [UNAuthorizationStatus.notDetermined, .denied] {
            let center = FakeNotificationCenter(status: status)
            let scheduler = NotificationScheduler(center: center, calendar: calendar, now: { Date() })
            let queued = await scheduler.reschedule(active: snapshots(3), settings: settings, rotationStart: Date())
            XCTAssertTrue(queued.isEmpty)
            XCTAssertEqual(center.pending.count, 0)
            XCTAssertEqual(center.authorizationRequests, 0, "The scheduler never asks for permission itself")
        }
    }

    func testNuggetIDFromUserInfo() {
        let id = UUID()
        XCTAssertEqual(NotificationScheduler.nuggetID(from: ["nuggetID": id.uuidString]), id)
        XCTAssertNil(NotificationScheduler.nuggetID(from: ["nuggetID": "nope"]))
        XCTAssertNil(NotificationScheduler.nuggetID(from: [:]))
    }
}
