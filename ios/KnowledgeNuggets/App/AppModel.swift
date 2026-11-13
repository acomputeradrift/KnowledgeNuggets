import Foundation
import Observation
import UserNotifications

/// Holds what the screens show and runs every change through the store,
/// then rebuilds the notification schedule.
@MainActor
@Observable
final class AppModel {
    private(set) var active: [Nugget] = []
    private(set) var inactive: [Nugget] = []
    private(set) var settings: AppSettings
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var scheduledCount = 0
    /// The start of the current day. Observed, so the Today screen re-renders
    /// when it moves on. The injected clock isn't observable on its own, and a
    /// suspended app can stay in memory overnight, so `refreshDay()` is called
    /// on activation, at midnight and on time zone or clock changes.
    private(set) var today: Date
    /// Set when a store call fails, so a screen can say so.
    var errorMessage: String?

    @ObservationIgnored let store: NuggetStore
    @ObservationIgnored private let scheduler: NotificationScheduler
    @ObservationIgnored private let lookup: MetadataLookup
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var scheduleTask: Task<Void, Never>?
    /// The latest background lookup, kept so tests can wait for it.
    @ObservationIgnored private(set) var lookupTask: Task<Void, Never>?

    init(
        store: NuggetStore,
        scheduler: NotificationScheduler,
        lookup: MetadataLookup,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.scheduler = scheduler
        self.lookup = lookup
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.today = calendar.startOfDay(for: now())
        self.settings = AppSettings.load(from: defaults)
        reload()
    }

    var isEmpty: Bool { active.isEmpty && inactive.isEmpty }

    // MARK: Rotation

    /// The rotation start, or today if notifications haven't been scheduled yet.
    var rotationStart: Date { settings.rotationStart ?? today }

    var todayNugget: Nugget? {
        RotationEngine.item(for: today, in: active, start: rotationStart, calendar: calendar)
    }

    /// Tomorrow's nugget, when it differs from today's.
    var upNextNugget: Nugget? {
        guard active.count > 1,
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
        return RotationEngine.item(for: tomorrow, in: active, start: rotationStart, calendar: calendar)
    }

    /// Moves `today` on to the clock's current day. Returns true when the day changed.
    /// Only assigns when it differs, so views don't re-render needlessly.
    @discardableResult
    func refreshDay() -> Bool {
        let current = calendar.startOfDay(for: now())
        guard current != today else { return false }
        today = current
        return true
    }

    /// Called at midnight and when the clock or time zone changes while the app runs.
    /// Moves Today on and rebuilds the schedule, since fire dates are local times.
    func timeDidChange() {
        refreshDay()
        reschedule()
    }

    // MARK: Nuggets

    func reload() {
        do {
            active = try store.activeNuggets()
            inactive = try store.inactiveNuggets()
        } catch {
            errorMessage = "Couldn't load your nuggets. \(error.localizedDescription)"
        }
    }

    func nugget(id: UUID) -> Nugget? {
        try? store.nugget(id: id)
    }

    /// Adds or updates a nugget. Returns a message to show when the nugget was
    /// saved inactive because the rotation is full. Does nothing unless the draft
    /// has content and, except for affirmations, a By or From.
    @discardableResult
    func save(_ draft: NuggetDraft, editing nugget: Nugget? = nil) -> String? {
        guard draft.canSave else { return nil }
        var message: String?
        do {
            let saved: Nugget
            if let nugget {
                try store.update(nugget, with: draft)
                saved = nugget
            } else {
                let (added, outcome) = try store.add(draft, active: true)
                saved = added
                message = outcome.message
            }
            didChange()
            lookUpMissingMetadata(for: saved)
        } catch {
            errorMessage = "Couldn't save the nugget. \(error.localizedDescription)"
        }
        return message
    }

    @discardableResult
    func setActive(_ nugget: Nugget, _ isActive: Bool) -> String? {
        do {
            let outcome = try store.setActive(nugget, isActive)
            didChange()
            return outcome.message
        } catch {
            errorMessage = "Couldn't update the nugget. \(error.localizedDescription)"
            return nil
        }
    }

    func delete(_ nugget: Nugget) {
        do {
            try store.delete(nugget)
            didChange()
        } catch {
            errorMessage = "Couldn't delete the nugget. \(error.localizedDescription)"
        }
    }

    func moveActive(fromOffsets source: IndexSet, toOffset destination: Int) {
        do {
            try store.moveActive(fromOffsets: source, toOffset: destination)
            didChange()
        } catch {
            errorMessage = "Couldn't reorder. \(error.localizedDescription)"
        }
    }

    private func didChange() {
        reload()
        reschedule()
    }

    /// A source used before, for the editor's tap-to-fill suggestions.
    struct RecentSource: Hashable, Identifiable {
        var from: String
        var by: String?
        var id: String { from.lowercased() }
    }

    /// Distinct "From" values for this kind, most recently changed first,
    /// narrowed to ones containing `matching` when it isn't empty.
    func recentSources(for kind: NuggetKind, matching query: String = "", limit: Int = 5) -> [RecentSource] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        var result: [RecentSource] = []
        for nugget in (active + inactive).sorted(by: { $0.updatedAt > $1.updatedAt }) {
            guard nugget.nuggetKind == kind, let from = nugget.book else { continue }
            let key = from.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            if !query.isEmpty {
                guard from.localizedCaseInsensitiveContains(query), key != query.lowercased() else { continue }
            }
            result.append(RecentSource(from: from, by: nugget.author))
            if result.count == limit { break }
        }
        return result
    }

    // MARK: Metadata lookup

    private func lookUpMissingMetadata(for nugget: Nugget) {
        guard nugget.nuggetKind.supportsLookup,
              let request = LookupRequest(author: nugget.author, book: nugget.book) else { return }
        let id = nugget.id
        let lookup = self.lookup
        lookupTask = Task { [weak self] in
            switch request {
            case .authorForBook(let book):
                guard let author = await lookup.author(forBook: book) else { return }
                self?.applyLookup(id: id, author: author, book: nil, ifBookStill: book, authorStill: nil)
            case .bookForAuthor(let author):
                guard let book = await lookup.book(forAuthor: author) else { return }
                self?.applyLookup(id: id, author: nil, book: book, ifBookStill: nil, authorStill: author)
            }
        }
    }

    /// Fills the blank field, but only if the user hasn't changed the nugget meanwhile.
    private func applyLookup(id: UUID, author: String?, book: String?, ifBookStill expectedBook: String?, authorStill expectedAuthor: String?) {
        guard let nugget = try? store.nugget(id: id) else { return }
        if let expectedBook, nugget.book != expectedBook { return }
        if let expectedAuthor, nugget.author != expectedAuthor { return }
        if (try? store.fillMetadata(id: id, author: author, book: book)) == true {
            didChange()
        }
    }

    // MARK: Settings

    /// Sets the daily time. The first time, this is when notification permission is requested.
    func setDailyTime(_ date: Date) async {
        settings.minutesAfterMidnight = AppSettings.minutes(from: date, calendar: calendar)
        await requestPermissionIfFirstTime()
        settings.save(to: defaults)
        reschedule()
    }

    /// Turns notifications on at the current time (counts as choosing a time).
    func enableNotifications() async {
        await requestPermissionIfFirstTime()
        settings.save(to: defaults)
        reschedule()
    }

    func setPaused(_ paused: Bool) {
        settings.isPaused = paused
        settings.save(to: defaults)
        reschedule()
    }

    private func requestPermissionIfFirstTime() async {
        if !settings.hasChosenTime {
            settings.hasChosenTime = true
            settings.save(to: defaults)
        }
        if await scheduler.authorizationStatus() == .notDetermined {
            _ = await scheduler.requestAuthorization()
        }
        authorizationStatus = await scheduler.authorizationStatus()
    }

    // MARK: Scheduling

    /// Rebuilds the schedule. Calls run one after another so they never interleave.
    func reschedule() {
        let previous = scheduleTask
        scheduleTask = Task { [weak self] in
            await previous?.value
            await self?.performReschedule()
        }
    }

    /// Rebuilds the schedule and waits for it to finish.
    func rescheduleNow() async {
        reschedule()
        await scheduleTask?.value
    }

    private func performReschedule() async {
        refreshDay()
        if settings.rotationStart == nil {
            settings.rotationStart = today
            settings.save(to: defaults)
        }
        authorizationStatus = await scheduler.authorizationStatus()
        let snapshots = active.map(\.snapshot)
        await scheduler.reschedule(active: snapshots, settings: settings, rotationStart: rotationStart)
        scheduledCount = await scheduler.pendingCount()
    }

    /// Called whenever the app comes to the foreground.
    func appBecameActive() async {
        refreshDay()
        settings = AppSettings.load(from: defaults)
        reload()
        await rescheduleNow()
    }

    // MARK: Backup

    func backupFile() -> NuggetBackupFile? {
        guard let data = try? store.exportBackup().encoded() else { return nil }
        let stamp = now().formatted(.iso8601.year().month().day())
        return NuggetBackupFile(data: data, fileName: "KnowledgeNuggets-\(stamp).json")
    }

    func importBackup(from data: Data) -> String {
        do {
            let backup = try NuggetBackup.decode(data)
            let summary = try store.importBackup(backup)
            didChange()
            return summary.message
        } catch {
            return "That file isn't a Knowledge Nuggets backup. \(error.localizedDescription)"
        }
    }
}
