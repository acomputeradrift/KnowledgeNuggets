import XCTest
@testable import KnowledgeNuggets

@MainActor
final class ToastCenterTests: XCTestCase {
    private var announcements: [String] = []

    private func makeCenter(duration: Duration = .seconds(10), voiceOver: Bool = false) -> ToastCenter {
        ToastCenter(
            duration: duration,
            accessibleDuration: .seconds(10),
            isVoiceOverRunning: { voiceOver },
            announce: { [unowned self] in announcements.append($0) }
        )
    }

    func testShowingSetsTheToastAndAnnouncesIt() {
        let center = makeCenter()
        center.show("Moved to Active", successHaptic: true)
        XCTAssertEqual(center.current?.text, "Moved to Active")
        XCTAssertEqual(center.current?.playsSuccessHaptic, true)
        XCTAssertNil(center.current?.undo)
        XCTAssertEqual(announcements, ["Moved to Active"])
    }

    func testANewToastReplacesTheCurrentOne() throws {
        let center = makeCenter()
        var undone: [String] = []
        center.show("Moved to Inactive") { undone.append("first") }
        let first = try XCTUnwrap(center.current?.id)
        center.show("Nugget deleted")

        XCTAssertNotEqual(center.current?.id, first)
        XCTAssertEqual(center.current?.text, "Nugget deleted")
        XCTAssertEqual(center.current?.playsSuccessHaptic, false)
        center.undo()
        XCTAssertTrue(undone.isEmpty, "The replaced toast's Undo is gone")
    }

    func testUndoRunsOnceAndHidesTheToast() {
        let center = makeCenter()
        var count = 0
        center.show("Moved to Inactive") { count += 1 }
        center.undo()
        center.undo()
        XCTAssertEqual(count, 1)
        XCTAssertNil(center.current)
    }

    func testDismissingAnOldToastLeavesTheNewOne() throws {
        let center = makeCenter()
        center.show("First")
        let first = try XCTUnwrap(center.current?.id)
        center.show("Second")
        center.dismiss(first)
        XCTAssertEqual(center.current?.text, "Second")
        center.dismiss(try XCTUnwrap(center.current?.id))
        XCTAssertNil(center.current)
    }

    func testItHidesItselfAndAReplacementGetsItsOwnTime() async throws {
        let center = makeCenter(duration: .milliseconds(300))
        center.show("First")
        try await Task.sleep(for: .milliseconds(180))
        center.show("Second")
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(center.current?.text, "Second", "The first toast's timer doesn't hide its replacement")
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(center.current)
    }

    func testItStaysLongerWithVoiceOver() async throws {
        let center = makeCenter(duration: .milliseconds(50), voiceOver: true)
        center.show("Moved to Active")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(center.current?.text, "Moved to Active")
    }

    func testImportToastText() {
        XCTAssertEqual(SettingsView.importToast(ImportSummary(added: 3, updated: 1, unchanged: 2)), "Imported 3 new, 1 updated")
        XCTAssertEqual(SettingsView.importToast(ImportSummary(unchanged: 4)), "Backup imported, nothing new")
    }
}
