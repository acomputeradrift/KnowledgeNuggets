import Foundation

/// Decides which nugget falls on a given day.
///
/// The nugget for a day is the active nuggets, in list order, at index
/// (whole days from the rotation start to that day, in the given calendar)
/// modulo the number of active nuggets. Because it uses list position rather
/// than stored sort numbers, deleting or deactivating a nugget never leaves
/// an empty day.
enum RotationEngine {
    /// Whole calendar days from `start` to `date`. Negative if `date` is earlier.
    /// Counted between local midnights, so 23- and 25-hour DST days still count as one.
    static func dayIndex(from start: Date, to date: Date, calendar: Calendar) -> Int {
        let startDay = calendar.startOfDay(for: start)
        let day = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: startDay, to: day).day ?? 0
    }

    /// Position in an active list of `count` items for `date`, or nil when empty.
    static func index(for date: Date, count: Int, start: Date, calendar: Calendar) -> Int? {
        guard count > 0 else { return nil }
        let days = dayIndex(from: start, to: date, calendar: calendar)
        return ((days % count) + count) % count
    }

    /// The item for `date` from `active`, which must already be in rotation order.
    static func item<T>(for date: Date, in active: [T], start: Date, calendar: Calendar) -> T? {
        guard let index = index(for: date, count: active.count, start: start, calendar: calendar) else {
            return nil
        }
        return active[index]
    }
}
