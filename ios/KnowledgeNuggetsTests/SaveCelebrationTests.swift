import XCTest
@testable import KnowledgeNuggets

final class SaveCelebrationTests: XCTestCase {
    private func added(_ count: Int) -> SaveCelebration {
        SaveCelebration(activeCount: count, limit: 21, keptInactive: false)
    }

    // MARK: Milestones

    func testMilestonesAtOneSevenFourteenAndTwentyOne() {
        XCTAssertEqual(added(1).milestone, .first)
        XCTAssertEqual(added(7).milestone, .firstWeek)
        XCTAssertEqual(added(14).milestone, .twoWeeks)
        XCTAssertEqual(added(21).milestone, .full)
        for count in [2, 6, 8, 13, 15, 20] {
            XCTAssertNil(added(count).milestone, "\(count)")
        }
    }

    func testHeadlines() {
        XCTAssertEqual(added(1).headline, "Your first nugget!")
        XCTAssertEqual(added(7).headline, "Your first week is full")
        XCTAssertEqual(added(14).headline, "Two weeks of nuggets")
        XCTAssertEqual(added(21).headline, "Your rotation is full")
        XCTAssertEqual(added(8).headline, "Nugget saved!")
        XCTAssertNil(added(8).subtext)
        XCTAssertNotNil(added(7).subtext)
    }

    func testKeptInactiveIsNeverAMilestone() {
        let kept = SaveCelebration(activeCount: 21, limit: 21, keptInactive: true)
        XCTAssertNil(kept.milestone)
        XCTAssertEqual(kept.headline, "Nugget saved!")
        XCTAssertFalse(kept.isBigCelebration)
    }

    func testOnlyAFullRotationGetsConfetti() {
        XCTAssertTrue(added(21).isBigCelebration)
        for count in [1, 7, 14, 20] {
            XCTAssertFalse(added(count).isBigCelebration, "\(count)")
        }
    }

    // MARK: Note

    func testNoteSaysWhereTheNuggetWent() {
        XCTAssertEqual(added(8).note, "Added to the end of your rotation.")
        XCTAssertEqual(added(21).note, "Added to the end of your rotation.")
        XCTAssertEqual(
            SaveCelebration(activeCount: 21, limit: 21, keptInactive: true).note,
            "Added as Inactive. Your rotation is full."
        )
    }

    func testNoteNeverMentionsNew() {
        for celebration in [added(3), SaveCelebration(activeCount: 21, limit: 21, keptInactive: true)] {
            XCTAssertFalse(celebration.note.localizedCaseInsensitiveContains("new"))
        }
    }

    func testOutcomeInitializer() {
        XCTAssertFalse(SaveCelebration(activeCount: 3, limit: 21, outcome: .active).keptInactive)
        XCTAssertTrue(SaveCelebration(activeCount: 21, limit: 21, outcome: .keptInactiveLimitReached).keptInactive)
    }

    // MARK: Closing

    func testStaysOpenWithAddAnotherUntilFull() {
        for count in [1, 7, 14, 20] {
            XCTAssertFalse(added(count).closesAutomatically, "\(count)")
            XCTAssertTrue(added(count).offersAddAnother, "\(count)")
        }
    }

    func testClosesAutomaticallyWhenFullEitherWay() {
        let filled = added(21)
        let kept = SaveCelebration(activeCount: 21, limit: 21, keptInactive: true)
        for celebration in [filled, kept] {
            XCTAssertTrue(celebration.isFull)
            XCTAssertTrue(celebration.closesAutomatically)
            XCTAssertFalse(celebration.offersAddAnother)
        }
    }

    // MARK: Progress

    func testProgress() {
        XCTAssertEqual(added(8).progressLabel, "8 of 21")
        XCTAssertEqual(added(8).progress, 8.0 / 21.0, accuracy: 0.0001)
        XCTAssertEqual(added(8).previousActiveCount, 7)
        XCTAssertEqual(added(21).progress, 1)
        let kept = SaveCelebration(activeCount: 21, limit: 21, keptInactive: true)
        XCTAssertEqual(kept.previousActiveCount, 21, "Nothing moved, so the ring doesn't grow")
        XCTAssertEqual(kept.progressLabel, "21 of 21")
    }

    func testDaysLine() {
        XCTAssertEqual(added(8).daysLine, "8 days before anything repeats.")
        XCTAssertEqual(added(21).daysLine, "21 days before anything repeats.")
        XCTAssertFalse(added(1).daysLine.contains("1 days"))
    }

    func testUsesTheLimitItIsGiven() {
        let small = SaveCelebration(activeCount: 5, limit: 5, keptInactive: false)
        XCTAssertEqual(small.milestone, .full)
        XCTAssertTrue(small.closesAutomatically)
        XCTAssertEqual(SaveCelebration(activeCount: 3, keptInactive: false).limit, NuggetRules.activeLimit)
    }

    // MARK: VoiceOver

    func testAnnouncementReadsHeadlineAndNote() {
        XCTAssertEqual(added(8).announcement, "Nugget saved! Added to the end of your rotation.")
        XCTAssertEqual(
            added(7).announcement,
            "Your first week is full. Added to the end of your rotation."
        )
    }
}
