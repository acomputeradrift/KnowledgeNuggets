import Foundation
import Observation
import UserNotifications

/// Holds what the screens show and runs every change through the store,
/// then rebuilds the notification schedule.
@MainActor
@Observable
final class AppModel {
    /// The rotation, in order.
    private(set) var active: [Nugget] = []
    /// Waiting for a spot, in the user's order.
    private(set) var queued: [Nugget] = []
    /// Set aside, in the user's order.
    private(set) var paused: [Nugget] = []
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
    /// The selected tab. Here rather than in RootView so a sheet can switch it,
    /// like the save celebration's Go to Nuggets.
    var selectedTab: AppTab = .today

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
        runLaunchMigrations()
        reload()
    }

    var isEmpty: Bool { active.isEmpty && queued.isEmpty && paused.isEmpty }

    /// Every nugget: Active, then Queued, then Paused.
    var all: [Nugget] { active + queued + paused }

    func nuggets(in state: NuggetState) -> [Nugget] {
        switch state {
        case .active: return active
        case .queued: return queued
        case .paused: return paused
        }
    }

    /// Whether `nugget` (or a new one, when nil) can be active: there's a free
    /// spot, or it already is.
    func canBeActive(_ nugget: Nugget?) -> Bool {
        nugget?.isActive == true || active.count < NuggetRules.activeLimit
    }

    /// Where a new nugget starts in the editor: Active, or Queued when it's full.
    var defaultNewState: NuggetState { canBeActive(nil) ? .active : .queued }

    // MARK: Migrations

    static let quotesMigratedKey = "migrations.quotesStripped"

    /// Fills in states for nuggets saved before they existed (every launch,
    /// since it only touches those), then, once, strips wrapping quotes from
    /// stored texts so nothing shows double-quoted.
    private func runLaunchMigrations() {
        do {
            try store.migrateLegacyStates()
            if !defaults.bool(forKey: Self.quotesMigratedKey) {
                try store.stripStoredQuotes()
                defaults.set(true, forKey: Self.quotesMigratedKey)
            }
        } catch {
            errorMessage = "Couldn't update your nuggets. \(error.localizedDescription)"
        }
    }

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
            active = try store.nuggets(in: .active)
            queued = try store.nuggets(in: .queued)
            paused = try store.nuggets(in: .paused)
        } catch {
            errorMessage = "Couldn't load your nuggets. \(error.localizedDescription)"
        }
    }

    func nugget(id: UUID) -> Nugget? {
        try? store.nugget(id: id)
    }

    /// The nugget that already has this content, other than `nugget` itself.
    func duplicate(of text: String, excluding nugget: Nugget? = nil) -> Nugget? {
        try? store.duplicate(of: text, excluding: nugget?.id)
    }

    /// Adds or updates a nugget. For a new nugget, returns what to celebrate:
    /// the active count after the save and where it went (Active, Queued
    /// because Active was full, or the section chosen). Edits go through
    /// `update(_:with:)` and return nil here, as does a save that fails or is
    /// refused. Does nothing unless the draft has content, isn't a duplicate
    /// and, except for affirmations, has a By or From.
    @discardableResult
    func save(_ draft: NuggetDraft, editing nugget: Nugget? = nil) -> SaveCelebration? {
        guard draft.canSave else { return nil }
        if let nugget {
            update(nugget, with: draft)
            return nil
        }
        guard duplicate(of: draft.text) == nil else { return nil }
        do {
            let (added, outcome) = try store.add(draft, state: draft.state)
            didChange()
            lookUpMissingMetadata(for: added)
            return SaveCelebration(activeCount: active.count, outcome: outcome)
        } catch {
            errorMessage = "Couldn't save the nugget. \(error.localizedDescription)"
            return nil
        }
    }

    /// What an edit did, for its confirmation.
    enum EditResult: Equatable {
        case updated
        /// The edit also changed the section.
        case moved(StateMove)
    }

    /// Saves an edit. A changed section goes through the same rules as the
    /// list: to the bottom of the new section, and into Active only when
    /// there's room. Returns nil when nothing was saved (invalid or a duplicate).
    @discardableResult
    func update(_ nugget: Nugget, with draft: NuggetDraft) -> EditResult? {
        guard draft.canSave, duplicate(of: draft.text, excluding: nugget) == nil else { return nil }
        let before = MoveOrigin(nugget, in: self)
        var result = EditResult.updated
        do {
            try store.update(nugget, with: draft)
            if draft.state != before.state {
                // Refused (Active full) leaves it where it was; the editor greys Active out then.
                if try store.place(nugget, in: draft.state, at: nil) == .moved {
                    result = .moved(before.move(to: draft.state))
                }
            }
            didChange()
            lookUpMissingMetadata(for: nugget)
        } catch {
            errorMessage = "Couldn't save the nugget. \(error.localizedDescription)"
            return nil
        }
        return result
    }

    // MARK: Moving between sections

    /// A move from one section to another, with what's needed to undo it.
    struct StateMove: Equatable {
        let nuggetID: UUID
        let from: NuggetState
        let to: NuggetState
        /// Its position in the section it left.
        let previousIndex: Int

        var message: String { "Moved to \(to.title)" }
        /// Only a move into Active plays the success haptic.
        var entersActive: Bool { to == .active }
    }

    enum MoveResult: Equatable {
        case moved(StateMove)
        /// Reordered within its section; no confirmation.
        case reordered
        /// Refused because Active is full; the message explains it.
        case activeFull(String)
        /// Already there.
        case unchanged
        /// The store failed; `errorMessage` says so.
        case failed
    }

    /// Where a nugget sat before a move.
    private struct MoveOrigin {
        let id: UUID
        let state: NuggetState
        let index: Int

        @MainActor
        init(_ nugget: Nugget, in model: AppModel) {
            let list = model.nuggets(in: nugget.nuggetState)
            id = nugget.id
            state = nugget.nuggetState
            index = list.firstIndex { $0.id == nugget.id } ?? list.count
        }

        func move(to state: NuggetState) -> StateMove {
            StateMove(nuggetID: id, from: self.state, to: state, previousIndex: index)
        }
    }

    /// Moves a nugget to `state` at `index` (the bottom when nil): a swipe, a
    /// drag within or between sections, or the editor. Into Active is refused
    /// when it's full; nothing else ever moves into Active.
    func move(_ nugget: Nugget, to state: NuggetState, at index: Int? = nil) -> MoveResult {
        let before = MoveOrigin(nugget, in: self)
        do {
            switch try store.place(nugget, in: state, at: index) {
            case .moved:
                didChange()
                return .moved(before.move(to: state))
            case .reordered:
                didChange()
                return .reordered
            case .unchanged:
                return .unchanged
            case .activeFull:
                return .activeFull(NuggetRules.activeFullMessage)
            }
        } catch {
            errorMessage = "Couldn't update the nugget. \(error.localizedDescription)"
            return .failed
        }
    }

    /// Puts a moved nugget back in the section and position it came from.
    /// Returns a message when Active filled up meanwhile, so it can't go back
    /// in. Does nothing if it has been moved again or deleted since.
    @discardableResult
    func undo(_ move: StateMove) -> String? {
        guard let nugget = try? store.nugget(id: move.nuggetID), nugget.nuggetState == move.to else { return nil }
        do {
            if try store.place(nugget, in: move.from, at: move.previousIndex) == .activeFull {
                return "Active filled up, so this nugget can't go back in. Pause another to make room."
            }
            didChange()
        } catch {
            errorMessage = "Couldn't undo. \(error.localizedDescription)"
        }
        return nil
    }

    /// Returns true when it was deleted. An active nugget's spot is left open.
    @discardableResult
    func delete(_ nugget: Nugget) -> Bool {
        do {
            try store.delete(nugget)
            didChange()
            return true
        } catch {
            errorMessage = "Couldn't delete the nugget. \(error.localizedDescription)"
            return false
        }
    }

    /// Reorders one section using `List.onMove` offsets.
    func move(in state: NuggetState, fromOffsets source: IndexSet, toOffset destination: Int) {
        do {
            try store.move(in: state, fromOffsets: source, toOffset: destination)
            didChange()
        } catch {
            errorMessage = "Couldn't reorder. \(error.localizedDescription)"
        }
    }

    func moveActive(fromOffsets source: IndexSet, toOffset destination: Int) {
        move(in: .active, fromOffsets: source, toOffset: destination)
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
        for nugget in all.sorted(by: { $0.updatedAt > $1.updatedAt }) {
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

    enum ImportResult: Equatable {
        case imported(ImportSummary)
        case failed(String)

        var message: String {
            switch self {
            case .imported(let summary): return summary.message
            case .failed(let message): return message
            }
        }
    }

    func importBackup(from data: Data) -> String {
        importBackupResult(from: data).message
    }

    func importBackupResult(from data: Data) -> ImportResult {
        do {
            let backup = try NuggetBackup.decode(data)
            let summary = try store.importBackup(backup)
            didChange()
            return .imported(summary)
        } catch {
            return .failed("That file isn't a Knowledge Nuggets backup. \(error.localizedDescription)")
        }
    }
}
