import XCTest
@testable import KnowledgeNuggets

final class RotationEngineTests: XCTestCase {
    let calendar = makeCalendar()

    func testEmptyListHasNoNugget() {
        let start = date(2026, 1, 1, in: calendar)
        XCTAssertNil(RotationEngine.item(for: start, in: [String](), start: start, calendar: calendar))
    }

    func testStartDayIsFirstNuggetAndCyclesInListOrder() {
        let items = ["A", "B", "C"]
        let start = date(2026, 1, 1, 9, in: calendar)
        let picks = (0..<7).map { offset in
            RotationEngine.item(for: calendar.date(byAdding: .day, value: offset, to: start)!, in: items, start: start, calendar: calendar)
        }
        XCTAssertEqual(picks, ["A", "B", "C", "A", "B", "C", "A"])
    }

    func testTimeOfDayDoesNotMatter() {
        let items = ["A", "B"]
        let start = date(2026, 1, 1, 23, 59, in: calendar)
        XCTAssertEqual(RotationEngine.item(for: date(2026, 1, 2, 0, 1, in: calendar), in: items, start: start, calendar: calendar), "B")
        XCTAssertEqual(RotationEngine.item(for: date(2026, 1, 2, 23, 59, in: calendar), in: items, start: start, calendar: calendar), "B")
    }

    func testMonthEnds() {
        let start = date(2026, 1, 30, in: calendar)
        XCTAssertEqual(RotationEngine.dayIndex(from: start, to: date(2026, 1, 31, in: calendar), calendar: calendar), 1)
        XCTAssertEqual(RotationEngine.dayIndex(from: start, to: date(2026, 2, 1, in: calendar), calendar: calendar), 2)
        // 2026 is not a leap year: Feb 28 is followed by Mar 1.
        XCTAssertEqual(RotationEngine.dayIndex(from: date(2026, 2, 28, in: calendar), to: date(2026, 3, 1, in: calendar), calendar: calendar), 1)
        // 2028 is: Feb 28, Feb 29, Mar 1.
        XCTAssertEqual(RotationEngine.dayIndex(from: date(2028, 2, 28, in: calendar), to: date(2028, 3, 1, in: calendar), calendar: calendar), 2)
        // Year end.
        XCTAssertEqual(RotationEngine.dayIndex(from: date(2026, 12, 31, in: calendar), to: date(2027, 1, 1, in: calendar), calendar: calendar), 1)

        let items = Array(0..<21)
        let jan31 = date(2026, 1, 31, in: calendar)
        let feb1 = date(2026, 2, 1, in: calendar)
        let a = RotationEngine.item(for: jan31, in: items, start: start, calendar: calendar)!
        let b = RotationEngine.item(for: feb1, in: items, start: start, calendar: calendar)!
        XCTAssertEqual(b, (a + 1) % 21, "No day is skipped or repeated across a month end")
    }

    func testDaylightSavingSpringForward() {
        // In New York, 2026-03-08 has 23 hours.
        let start = date(2026, 3, 7, 8, in: calendar)
        XCTAssertEqual(RotationEngine.dayIndex(from: start, to: date(2026, 3, 8, 0, 30, in: calendar), calendar: calendar), 1)
        XCTAssertEqual(RotationEngine.dayIndex(from: start, to: date(2026, 3, 8, 23, 30, in: calendar), calendar: calendar), 1)
        XCTAssertEqual(RotationEngine.dayIndex(from: start, to: date(2026, 3, 9, 0, 30, in: calendar), calendar: calendar), 2)
    }

    func testDaylightSavingFallBack() {
        // In New York, 2026-11-01 has 25 hours.
        let start = date(2026, 10, 31, 8, in: calendar)
        XCTAssertEqual(RotationEngine.dayIndex(from: start, to: date(2026, 11, 1, 23, 30, in: calendar), calendar: calendar), 1)
        XCTAssertEqual(RotationEngine.dayIndex(from: start, to: date(2026, 11, 2, 0, 15, in: calendar), calendar: calendar), 2)
    }

    func testEveryDayAcrossAYearAdvancesByExactlyOne() {
        let items = Array(0..<7)
        let start = date(2026, 1, 1, 8, in: calendar)
        var previous = RotationEngine.item(for: start, in: items, start: start, calendar: calendar)!
        for offset in 1...366 {
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            let current = RotationEngine.item(for: day, in: items, start: start, calendar: calendar)!
            XCTAssertEqual(current, (previous + 1) % items.count, "Day \(offset)")
            previous = current
        }
    }

    func testDatesBeforeStartStillGiveAValidNugget() {
        let items = ["A", "B", "C"]
        let start = date(2026, 1, 10, in: calendar)
        XCTAssertEqual(RotationEngine.item(for: date(2026, 1, 9, in: calendar), in: items, start: start, calendar: calendar), "C")
        XCTAssertEqual(RotationEngine.item(for: date(2026, 1, 7, in: calendar), in: items, start: start, calendar: calendar), "A")
    }

    func testDeletingMidCycleNeverLeavesAnEmptyDay() {
        var items = ["A", "B", "C", "D", "E"]
        let start = date(2026, 1, 1, in: calendar)
        let day3 = date(2026, 1, 4, in: calendar)
        XCTAssertEqual(RotationEngine.item(for: day3, in: items, start: start, calendar: calendar), "D")

        items.remove(at: 1) // delete "B" mid-cycle
        XCTAssertEqual(RotationEngine.item(for: day3, in: items, start: start, calendar: calendar), "E")
        for offset in 0..<40 {
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            XCTAssertNotNil(RotationEngine.item(for: day, in: items, start: start, calendar: calendar))
        }

        items.removeAll { $0 != "C" } // down to one
        XCTAssertEqual(RotationEngine.item(for: day3, in: items, start: start, calendar: calendar), "C")
    }

    func testUsesListPositionNotStoredSortNumbers() {
        // Sort numbers with gaps (as after deletions) don't matter; list position does.
        struct Item: Equatable { let name: String; let sortOrder: Int }
        let items = [Item(name: "A", sortOrder: 3), Item(name: "B", sortOrder: 10), Item(name: "C", sortOrder: 42)]
        let start = date(2026, 1, 1, in: calendar)
        XCTAssertEqual(RotationEngine.item(for: date(2026, 1, 3, in: calendar), in: items, start: start, calendar: calendar)?.name, "C")
    }

    func testFullRotationOf21ComesBackEvery21Days() {
        let items = Array(0..<NuggetRules.activeLimit)
        let start = date(2026, 1, 1, in: calendar)
        for offset in 0..<21 {
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            let later = calendar.date(byAdding: .day, value: offset + 21, to: start)!
            XCTAssertEqual(
                RotationEngine.item(for: day, in: items, start: start, calendar: calendar),
                RotationEngine.item(for: later, in: items, start: start, calendar: calendar)
            )
        }
    }
}
