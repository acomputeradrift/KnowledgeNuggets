import Foundation
import UserNotifications

/// One planned daily notification.
struct PlannedNotification: Equatable, Sendable {
    static let titleText = "Knowledge Nugget"
    static let nuggetIDKey = "nuggetID"

    var identifier: String
    var nuggetID: UUID
    /// The moment it fires, in the calendar used to plan it.
    var fireDate: Date
    /// Year, month, day, hour and minute with no time zone, so it fires at
    /// the same local time when the phone changes time zone.
    var dateComponents: DateComponents
    var title: String
    var subtitle: String
    var body: String
}

/// The parts of `UNUserNotificationCenter` the scheduler uses, so tests can fake it.
protocol NotificationCenterClient: AnyObject, Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
    func removeAllPendingRequests()
    func add(_ request: UNNotificationRequest) async throws
    func pendingRequestCount() async -> Int
}

final class SystemNotificationCenter: NotificationCenterClient, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func removeAllPendingRequests() {
        center.removeAllPendingNotificationRequests()
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func pendingRequestCount() async -> Int {
        await center.pendingNotificationRequests().count
    }
}

/// Clears and re-queues the daily notifications.
final class NotificationScheduler: @unchecked Sendable {
    /// Days to queue ahead. iOS keeps at most 64 pending requests per app.
    static let daysAhead = 60

    private let center: NotificationCenterClient
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        center: NotificationCenterClient,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.center = center
        self.calendar = calendar
        self.now = now
    }

    /// Works out the next `days` notifications. Pure, so it can be tested directly.
    static func plan(
        active: [NuggetSnapshot],
        settings: AppSettings,
        rotationStart: Date,
        now: Date,
        calendar: Calendar,
        days: Int = NotificationScheduler.daysAhead
    ) -> [PlannedNotification] {
        guard !settings.isPaused, !active.isEmpty, days > 0 else { return [] }

        var planned: [PlannedNotification] = []
        let today = calendar.startOfDay(for: now)
        var offset = 0
        // Today is skipped if its time has passed, so look one day further.
        while planned.count < days, offset <= days {
            defer { offset += 1 }
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: today),
                let fireDate = calendar.date(
                    bySettingHour: settings.hour,
                    minute: settings.minute,
                    second: 0,
                    of: day,
                    matchingPolicy: .nextTime,
                    repeatedTimePolicy: .first,
                    direction: .forward
                ),
                fireDate > now,
                let nugget = RotationEngine.item(for: day, in: active, start: rotationStart, calendar: calendar)
            else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = settings.hour
            components.minute = settings.minute

            planned.append(
                PlannedNotification(
                    identifier: identifier(for: components),
                    nuggetID: nugget.id,
                    fireDate: fireDate,
                    dateComponents: components,
                    title: PlannedNotification.titleText,
                    subtitle: nugget.attribution ?? "",
                    body: nugget.text
                )
            )
        }
        return planned
    }

    static func identifier(for components: DateComponents) -> String {
        String(format: "nugget-%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func request(for planned: PlannedNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.subtitle = planned.subtitle
        content.body = planned.body
        content.sound = .default
        content.userInfo = [PlannedNotification.nuggetIDKey: planned.nuggetID.uuidString]
        content.threadIdentifier = "daily-nugget"
        let trigger = UNCalendarNotificationTrigger(dateMatching: planned.dateComponents, repeats: false)
        return UNNotificationRequest(identifier: planned.identifier, content: content, trigger: trigger)
    }

    /// Removes every pending notification and queues the next 60 days.
    /// Returns what was queued (empty when paused, empty or not authorised).
    @discardableResult
    func reschedule(active: [NuggetSnapshot], settings: AppSettings, rotationStart: Date) async -> [PlannedNotification] {
        center.removeAllPendingRequests()
        let plan = Self.plan(active: active, settings: settings, rotationStart: rotationStart, now: now(), calendar: calendar)
        guard !plan.isEmpty else { return [] }

        switch await center.authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return []
        }

        var queued: [PlannedNotification] = []
        for item in plan {
            if Task.isCancelled { break }
            do {
                try await center.add(Self.request(for: item))
                queued.append(item)
            } catch {
                continue
            }
        }
        return queued
    }

    func requestAuthorization() async -> Bool {
        await center.requestAuthorization()
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.authorizationStatus()
    }

    func pendingCount() async -> Int {
        await center.pendingRequestCount()
    }

    /// The nugget id carried by a delivered notification.
    static func nuggetID(from userInfo: [AnyHashable: Any]) -> UUID? {
        (userInfo[PlannedNotification.nuggetIDKey] as? String).flatMap(UUID.init(uuidString:))
    }
}
