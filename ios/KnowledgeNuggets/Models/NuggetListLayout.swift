import Foundation

/// The Nuggets list as one flat run of rows: a header for each section, then
/// its nuggets (or a placeholder when it's empty).
///
/// SwiftUI's `onMove` never moves a row out of its `ForEach`, and its reorder
/// drag never reaches another section's drop handler, so the list uses a
/// single `ForEach` over these rows, with headers and placeholders that can't
/// be moved. A drop anywhere is then mapped back to a section and a position
/// in it. Pure, so the mapping is tested directly.
struct NuggetListLayout: Equatable {
    enum Row: Hashable, Identifiable {
        case header(NuggetState)
        /// Stands in for an empty section, so there's somewhere to drop.
        case placeholder(NuggetState)
        case nugget(UUID, NuggetState)

        var id: String {
            switch self {
            case .header(let state): return "header-\(state.rawValue)"
            case .placeholder(let state): return "placeholder-\(state.rawValue)"
            // Stable across sections, so a dropped row isn't removed and re-added.
            case .nugget(let id, _): return id.uuidString
            }
        }

        var isMovable: Bool {
            if case .nugget = self { return true }
            return false
        }
    }

    /// Where a row ends up.
    struct Destination: Equatable {
        var state: NuggetState
        /// Position among that section's nuggets, not counting the moved one.
        var index: Int
    }

    let rows: [Row]

    init(active: [UUID], queued: [UUID], paused: [UUID]) {
        var rows: [Row] = []
        for (state, ids) in [(NuggetState.active, active), (.queued, queued), (.paused, paused)] {
            rows.append(.header(state))
            if ids.isEmpty {
                rows.append(.placeholder(state))
            } else {
                rows += ids.map { .nugget($0, state) }
            }
        }
        self.rows = rows
    }

    /// Where the nugget at `source` lands when `onMove` reports `destination`
    /// (an insertion offset counted before the row is removed). The nearest
    /// header above it names the section; a drop above the first header counts
    /// as the top of Active. Nil when `source` isn't a nugget.
    func destination(movingRowAt source: Int, toOffset destination: Int) -> Destination? {
        guard rows.indices.contains(source), rows[source].isMovable else { return nil }
        var moved = rows
        moved.move(fromOffsets: IndexSet(integer: source), toOffset: min(max(destination, 0), rows.count))
        guard let landed = moved.firstIndex(of: rows[source]) else { return nil }

        var index = 0
        for row in moved[..<landed].reversed() {
            switch row {
            case .header(let state):
                return Destination(state: state, index: index)
            case .nugget:
                index += 1
            case .placeholder:
                continue
            }
        }
        return Destination(state: .active, index: 0)
    }
}
