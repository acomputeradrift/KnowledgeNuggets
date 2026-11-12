import Foundation
import UserNotifications
@testable import KnowledgeNuggets

/// A calendar fixed to one time zone, so tests don't depend on the Mac's settings.
func makeCalendar(_ identifier: String = "America/New_York") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: identifier)!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}

/// Builds a date in `calendar`'s time zone.
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, in calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func snapshots(_ count: Int) -> [NuggetSnapshot] {
    (0..<count).map { NuggetSnapshot(text: "Nugget \($0)", author: "Author \($0)", book: "Book \($0)") }
}

/// Records what the scheduler asks of the notification center.
final class FakeNotificationCenter: NotificationCenterClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _status: UNAuthorizationStatus
    private var _pending: [UNNotificationRequest] = []
    private var _removeAllCount = 0
    private var _authorizationRequests = 0

    init(status: UNAuthorizationStatus = .authorized) {
        _status = status
    }

    var pending: [UNNotificationRequest] { lock.withLock { _pending } }
    var removeAllCount: Int { lock.withLock { _removeAllCount } }
    var authorizationRequests: Int { lock.withLock { _authorizationRequests } }

    func setStatus(_ status: UNAuthorizationStatus) {
        lock.withLock { _status = status }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        lock.withLock { _status }
    }

    func requestAuthorization() async -> Bool {
        lock.withLock {
            _authorizationRequests += 1
            _status = .authorized
        }
        return true
    }

    func removeAllPendingRequests() {
        lock.withLock {
            _removeAllCount += 1
            _pending.removeAll()
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        lock.withLock {
            _pending.removeAll { $0.identifier == request.identifier }
            _pending.append(request)
        }
    }

    func pendingRequestCount() async -> Int {
        lock.withLock { _pending.count }
    }
}

/// Returns canned lookup answers.
struct FakeLookup: MetadataLookup {
    var authors: [String: String] = [:]
    var books: [String: String] = [:]

    func author(forBook book: String) async -> String? { authors[book] }
    func book(forAuthor author: String) async -> String? { books[author] }
}
