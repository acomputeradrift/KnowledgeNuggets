import XCTest
@testable import KnowledgeNuggets

final class SaveCelebrationTests: XCTestCase {
    private func added(_ count: Int) -> SaveCelebration {
        SaveCelebration(activeCount: count, limit: 21, activeFull: false)
    }

    private var keptFull: SaveCelebration {
        SaveCelebration(activeCount: 21, limit: 21, outcome: .queuedBecauseActiveFull)
    }

    private func choseQueued(_ count: Int = 8) -> SaveCelebration {
        SaveCelebration(activeCount: count, limit: 21, outcome: .chose(.queued))
    }

    // MARK: Layout

    func testAddedToActiveShowsTheRingWithAddAnother() {
        for count in [1, 7, 8, 14, 20, 21] {
            let celebration = added(count)
            XCTAssertEqual(celebration.layout, .progress, "\(count)")
            XCTAssertTrue(celebration.showsProgress, "\(count)")
            XCTAssertNil(celebration.infoBox, "\(count)")
            XCTAssertEqual(celebration.primaryAction, .addAnother, "\(count)")
        }
    }

    func testQueuedBecauseActiveFullShowsTheTwoStepBoxWithGoToNuggets() {
        let kept = keptFull
        XCTAssertEqual(kept.layout, .rotationFull)
        XCTAssertFalse(kept.showsProgress)
        XCTAssertEqual(kept.primaryAction, .goToNuggets)
        XCTAssertEqual(kept.primaryAction.title, "Go to Nuggets")
        XCTAssertEqual(kept.infoBox, SaveCelebration.InfoBox(
            title: "Your 21 active spots are full",
            message: "It's at the bottom of your queue. It won't come up in your daily rotation until you activate it.",
            steps: ["Pause an active nugget", "Swipe this one to Activate"]
        ))
    }

    func testChoosingQueuedShowsTheOneStepBoxWithAddAnother() {
        let off = choseQueued()
        XCTAssertEqual(off.layout, .setAside)
        XCTAssertFalse(off.showsProgress)
        XCTAssertEqual(off.primaryAction, .addAnother)
        XCTAssertEqual(off.primaryAction.title, "Add Another")
        XCTAssertEqual(off.infoBox, SaveCelebration.InfoBox(
            title: "Added to Queued",
            message: "It won't come up in your daily rotation until you activate it.",
            steps: ["Swipe it to Activate when you're ready"]
        ))
        XCTAssertNotEqual(off, SaveCelebration(activeCount: 8, limit: 21, outcome: .queuedBecauseActiveFull))
    }

    func testChoosingQueuedWhileFullStillReadsAsChosen() {
        let off = choseQueued(21)
        XCTAssertEqual(off.layout, .setAside)
        XCTAssertEqual(off.infoBox?.title, "Added to Queued")
        XCTAssertEqual(off.primaryAction, .addAnother)
    }

    func testChoosingPausedShowsTheOneStepBoxTitledPaused() {
        let paused = SaveCelebration(activeCount: 8, limit: 21, outcome: .chose(.paused))
        XCTAssertEqual(paused.layout, .setAside)
        XCTAssertEqual(paused.primaryAction, .addAnother)
        XCTAssertEqual(paused.infoBox, SaveCelebration.InfoBox(
            title: "Added to Paused",
            message: "It won't come up in your daily rotation until you activate it.",
            steps: ["Swipe it to Activate when you're ready"]
        ))
        XCTAssertEqual(paused.announcement, "Nugget saved. Added to Paused.")
        XCTAssertNil(paused.milestone)
    }

    func testOutcomesNameTheSectionTheNuggetEndsUpIn() {
        XCTAssertEqual(ActivationOutcome.active.state, .active)
        XCTAssertEqual(ActivationOutcome.queuedBecauseActiveFull.state, .queued)
        XCTAssertEqual(ActivationOutcome.chose(.paused).state, .paused)
    }

    func testFullBoxUsesTheLimitItIsGiven() {
        let small = SaveCelebration(activeCount: 5, limit: 5, activeFull: true)
        XCTAssertEqual(small.infoBox?.title, "Your 5 active spots are full")
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
        XCTAssertEqual(added(1).headline, "Your first nugget")
        XCTAssertEqual(added(7).headline, "One week of nuggets")
        XCTAssertEqual(added(14).headline, "Two weeks of nuggets")
        XCTAssertEqual(added(21).headline, "Your rotation is full")
        XCTAssertEqual(added(8).headline, "Nugget saved")
    }

    func testHeadlinesHaveNoExclamationMarks() {
        for celebration in [added(1), added(7), added(8), added(14), added(21), keptFull, choseQueued()] {
            XCTAssertFalse(celebration.headline.contains("!"), celebration.headline)
        }
    }

    func testSavesOutOfTheRotationAreNeverAMilestone() {
        for celebration in [keptFull, choseQueued(7), choseQueued(21)] {
            XCTAssertNil(celebration.milestone)
            XCTAssertEqual(celebration.headline, "Nugget saved")
            XCTAssertFalse(celebration.isBigCelebration)
        }
    }

    func testOnlyAFullRotationGetsConfetti() {
        XCTAssertTrue(added(21).isBigCelebration)
        for count in [1, 7, 14, 20] {
            XCTAssertFalse(added(count).isBigCelebration, "\(count)")
        }
    }

    func testOutcomeInitializer() {
        XCTAssertFalse(SaveCelebration(activeCount: 3, limit: 21, outcome: .active).isOutOfRotation)
        XCTAssertTrue(keptFull.isOutOfRotation)
        XCTAssertTrue(choseQueued(3).isOutOfRotation)
        XCTAssertEqual(SaveCelebration(activeCount: 21, limit: 21, activeFull: true), keptFull)
    }

    // MARK: Sound

    func testCelebrationSoundShipsInTheAppBundle() {
        // Only checks the files are there; nothing is played under tests.
        let bundle = Bundle(for: SoundPlayer.self)
        XCTAssertNotNil(SoundPlayer.url(for: SoundPlayer.saveCelebration, in: bundle), SoundPlayer.saveCelebration)
        XCTAssertNil(SoundPlayer.url(for: "no-such-sound.caf", in: bundle))
    }

    // MARK: Progress

    func testProgress() {
        XCTAssertEqual(added(8).progressLabel, "8 of 21")
        XCTAssertEqual(added(8).progress, 8.0 / 21.0, accuracy: 0.0001)
        XCTAssertEqual(added(8).previousActiveCount, 7)
        XCTAssertEqual(added(21).progress, 1)
        XCTAssertEqual(keptFull.previousActiveCount, 21, "Nothing moved")
        XCTAssertEqual(choseQueued(7).previousActiveCount, 7, "Nothing moved")
    }

    func testUsesTheLimitItIsGiven() {
        let small = SaveCelebration(activeCount: 5, limit: 5, activeFull: false)
        XCTAssertEqual(small.milestone, .full)
        XCTAssertEqual(small.progressLabel, "5 of 5")
        XCTAssertEqual(SaveCelebration(activeCount: 3, activeFull: false).limit, NuggetRules.activeLimit)
    }

    // MARK: VoiceOver

    func testAnnouncementReadsHeadlineAndRingOrBox() {
        XCTAssertEqual(added(8).announcement, "Nugget saved. 8 of 21.")
        XCTAssertEqual(added(7).announcement, "One week of nuggets. 7 of 21.")
        XCTAssertEqual(added(21).announcement, "Your rotation is full. 21 of 21.")
        XCTAssertEqual(keptFull.announcement, "Nugget saved. Your 21 active spots are full.")
        XCTAssertEqual(choseQueued().announcement, "Nugget saved. Added to Queued.")
    }
}
