import Foundation

/// User settings, stored in `UserDefaults` (the same store `@AppStorage` uses).
struct AppSettings: Equatable, Sendable {
    enum Key {
        static let minutesAfterMidnight = "dailyMinutesAfterMidnight"
        static let isPaused = "notificationsPaused"
        static let rotationStart = "rotationStartDate"
        static let hasChosenTime = "hasChosenDailyTime"
    }

    static let defaultMinutesAfterMidnight = 8 * 60

    /// Daily delivery time, as minutes after local midnight (08:00 = 480).
    var minutesAfterMidnight: Int = AppSettings.defaultMinutesAfterMidnight
    var isPaused: Bool = false
    /// Day zero of the rotation; set the first time notifications are scheduled.
    var rotationStart: Date?
    /// True once the user has set a time, which is when permission is requested.
    var hasChosenTime: Bool = false

    var hour: Int { minutesAfterMidnight / 60 }
    var minute: Int { minutesAfterMidnight % 60 }

    static func load(from defaults: UserDefaults) -> AppSettings {
        var settings = AppSettings()
        if defaults.object(forKey: Key.minutesAfterMidnight) != nil {
            settings.minutesAfterMidnight = min(max(defaults.integer(forKey: Key.minutesAfterMidnight), 0), 24 * 60 - 1)
        }
        settings.isPaused = defaults.bool(forKey: Key.isPaused)
        settings.rotationStart = defaults.object(forKey: Key.rotationStart) as? Date
        settings.hasChosenTime = defaults.bool(forKey: Key.hasChosenTime)
        return settings
    }

    func save(to defaults: UserDefaults) {
        defaults.set(minutesAfterMidnight, forKey: Key.minutesAfterMidnight)
        defaults.set(isPaused, forKey: Key.isPaused)
        defaults.set(rotationStart, forKey: Key.rotationStart)
        defaults.set(hasChosenTime, forKey: Key.hasChosenTime)
    }

    /// The delivery time as a date today, for a `DatePicker`.
    func timeOfDay(calendar: Calendar, now: Date) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
    }

    static func minutes(from date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 8) * 60 + (parts.minute ?? 0)
    }
}
