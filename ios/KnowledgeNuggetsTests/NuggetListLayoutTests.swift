import XCTest
@testable import KnowledgeNuggets

/// Mapping a drop in the flat Nuggets list back to a section and position.
final class NuggetListLayoutTests: XCTestCase {
    private let a = (0..<3).map { _ in UUID() }
    private let q = (0..<2).map { _ in UUID() }
    private let p = (0..<2).map { _ in UUID() }

    private var layout: NuggetListLayout { NuggetListLayout(active: a, queued: q, paused: p) }

    /// Rows: 0 H-active, 1-3 a0-a2, 4 H-queued, 5-6 q0-q1, 7 H-paused, 8-9 p0-p1.
    func testRowsAreHeadersThenNuggets() {
        XCTAssertEqual(layout.rows, [
            .header(.active), .nugget(a[0], .active), .nugget(a[1], .active), .nugget(a[2], .active),
            .header(.queued), .nugget(q[0], .queued), .nugget(q[1], .queued),
            .header(.paused), .nugget(p[0], .paused), .nugget(p[1], .paused),
        ])
        XCTAssertEqual(layout.rows.filter(\.isMovable).count, 7)
    }

    func testEmptySectionsGetAPlaceholder() {
        let empty = NuggetListLayout(active: [], queued: q, paused: [])
        XCTAssertEqual(empty.rows, [
            .header(.active), .placeholder(.active),
            .header(.queued), .nugget(q[0], .queued), .nugget(q[1], .queued),
            .header(.paused), .placeholder(.paused),
        ])
        XCTAssertFalse(NuggetListLayout.Row.placeholder(.active).isMovable)
    }

    func testReorderWithinASection() {
        // a2 to the top of Active.
        XCTAssertEqual(layout.destination(movingRowAt: 3, toOffset: 1), .init(state: .active, index: 0))
        // a0 below a1.
        XCTAssertEqual(layout.destination(movingRowAt: 1, toOffset: 3), .init(state: .active, index: 1))
        // q1 above q0.
        XCTAssertEqual(layout.destination(movingRowAt: 6, toOffset: 5), .init(state: .queued, index: 0))
    }

    func testDragPausedToQueued() {
        // p1 between q0 and q1.
        XCTAssertEqual(layout.destination(movingRowAt: 9, toOffset: 6), .init(state: .queued, index: 1))
        // p0 just above the Paused header lands at the bottom of Queued.
        XCTAssertEqual(layout.destination(movingRowAt: 8, toOffset: 7), .init(state: .queued, index: 2))
    }

    func testDragQueuedToPausedAndActiveToEither() {
        // q0 to the bottom of the list.
        XCTAssertEqual(layout.destination(movingRowAt: 5, toOffset: 10), .init(state: .paused, index: 2))
        // a1 just under the Queued header.
        XCTAssertEqual(layout.destination(movingRowAt: 2, toOffset: 5), .init(state: .queued, index: 0))
        // a0 just under the Paused header.
        XCTAssertEqual(layout.destination(movingRowAt: 1, toOffset: 8), .init(state: .paused, index: 0))
    }

    func testDragIntoActive() {
        // q0 between a0 and a1.
        XCTAssertEqual(layout.destination(movingRowAt: 5, toOffset: 2), .init(state: .active, index: 1))
        // p0 just above the Queued header: the bottom of Active.
        XCTAssertEqual(layout.destination(movingRowAt: 8, toOffset: 4), .init(state: .active, index: 3))
        // Above the first header counts as the top of Active.
        XCTAssertEqual(layout.destination(movingRowAt: 9, toOffset: 0), .init(state: .active, index: 0))
    }

    func testDropIntoAnEmptySectionEitherSideOfItsPlaceholder() {
        let layout = NuggetListLayout(active: a, queued: [], paused: p)
        // Rows: 0 H-a, 1-3 a, 4 H-q, 5 placeholder, 6 H-p, 7-8 p.
        XCTAssertEqual(layout.destination(movingRowAt: 7, toOffset: 5), .init(state: .queued, index: 0))
        XCTAssertEqual(layout.destination(movingRowAt: 7, toOffset: 6), .init(state: .queued, index: 0))
    }

    func testHeadersAndPlaceholdersCannotBeMoved() {
        XCTAssertNil(layout.destination(movingRowAt: 0, toOffset: 5))
        XCTAssertNil(layout.destination(movingRowAt: 4, toOffset: 0))
        XCTAssertNil(layout.destination(movingRowAt: 42, toOffset: 0))
    }
}
