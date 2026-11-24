import Foundation
import SwiftData

/// `NuggetStore` backed by SwiftData.
@MainActor
final class SwiftDataNuggetStore: NuggetStore {
    let context: ModelContext
    private let now: () -> Date

    init(context: ModelContext, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.now = now
    }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([Nugget.self])
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration("KnowledgeNuggets", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            // Create Application Support first; on a fresh install it doesn't exist yet.
            let folder = URL.applicationSupportDirectory
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            configuration = ModelConfiguration(
                schema: schema,
                url: folder.appending(path: "KnowledgeNuggets.store"),
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(for: schema, configurations: configuration)
    }

    // MARK: Reading

    private func allNuggets() throws -> [Nugget] {
        try context.fetch(FetchDescriptor<Nugget>())
    }

    /// One section in the user's order. Filtered and sorted here rather than in
    /// a predicate: the list is small, and nuggets not yet migrated read their
    /// section from the legacy fields.
    func nuggets(in state: NuggetState) throws -> [Nugget] {
        try allNuggets().filter { $0.nuggetState == state }.sorted(by: Self.sectionOrder)
    }

    static func sectionOrder(_ lhs: Nugget, _ rhs: Nugget) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    func nugget(id: UUID) throws -> Nugget? {
        var descriptor = FetchDescriptor<Nugget>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func duplicate(of text: String, excluding id: UUID?) throws -> Nugget? {
        let key = NuggetText.matchKey(text)
        guard !key.isEmpty else { return nil }
        return try allNuggets()
            .sorted(by: Self.sectionOrder)
            .first { $0.id != id && NuggetText.matchKey($0.text) == key }
    }

    private func activeCount() throws -> Int {
        try nuggets(in: .active).count
    }

    /// Numbers a section 0, 1, 2… in the given order.
    private static func renumber(_ ordered: [Nugget]) {
        for (index, nugget) in ordered.enumerated() where nugget.sortOrder != index {
            nugget.sortOrder = index
        }
    }

    // MARK: Writing

    @discardableResult
    func add(_ draft: NuggetDraft, state: NuggetState = .active) throws -> (Nugget, ActivationOutcome) {
        let timestamp = now()
        let full = try activeCount() >= NuggetRules.activeLimit
        let outcome: ActivationOutcome
        switch state {
        case .active: outcome = full ? .queuedBecauseActiveFull : .active
        case .queued, .paused: outcome = .chose(state)
        }
        let section = try nuggets(in: outcome.state)
        let nugget = Nugget(
            text: draft.storedText,
            author: draft.storedAuthor,
            book: draft.storedBook,
            category: NuggetDraft.clean(draft.category),
            kind: draft.kind,
            state: outcome.state,
            // The bottom of its section.
            sortOrder: (section.map(\.sortOrder).max() ?? -1) + 1,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(nugget)
        try context.save()
        return (nugget, outcome)
    }

    func update(_ nugget: Nugget, with draft: NuggetDraft) throws {
        nugget.text = draft.storedText
        nugget.author = draft.storedAuthor
        nugget.book = draft.storedBook
        nugget.category = NuggetDraft.clean(draft.category)
        nugget.nuggetKind = draft.kind
        nugget.updatedAt = now()
        try context.save()
    }

    func fillMetadata(id: UUID, author: String?, book: String?) throws -> Bool {
        guard let nugget = try nugget(id: id) else { return false }
        var changed = false
        if let author = NuggetDraft.clean(author ?? ""), nugget.author == nil {
            nugget.author = author
            changed = true
        }
        if let book = NuggetDraft.clean(book ?? ""), nugget.book == nil {
            nugget.book = book
            changed = true
        }
        if changed {
            nugget.updatedAt = now()
            try context.save()
        }
        return changed
    }

    @discardableResult
    func place(_ nugget: Nugget, in state: NuggetState, at index: Int? = nil) throws -> PlacementOutcome {
        let from = nugget.nuggetState
        if state == .active, from != .active, try activeCount() >= NuggetRules.activeLimit {
            return .activeFull
        }
        let current = try nuggets(in: state)
        let oldIndex = current.firstIndex { $0.id == nugget.id }
        var target = current.filter { $0.id != nugget.id }
        let newIndex = min(max(index ?? target.count, 0), target.count)
        if from == state, oldIndex == newIndex { return .unchanged }

        if from != state {
            // Close the gap it leaves. Nothing moves up into Active.
            Self.renumber(try nuggets(in: from).filter { $0.id != nugget.id })
            nugget.nuggetState = state
            nugget.updatedAt = now()
        }
        target.insert(nugget, at: newIndex)
        Self.renumber(target)
        try context.save()
        return from == state ? .reordered : .moved
    }

    func delete(_ nugget: Nugget) throws {
        context.delete(nugget)
        try context.save()
    }

    // MARK: Migrations

    /// Gives every nugget saved before states existed its section: active stays
    /// active in rotation order; inactive and never moved out on purpose
    /// becomes queued, oldest first; moved out on purpose becomes paused, in
    /// the order it was moved out. Each group goes below anything already
    /// migrated. Doesn't touch `updatedAt`, so backups still merge as before.
    @discardableResult
    func migrateLegacyStates() throws -> Int {
        let all = try allNuggets()
        let legacy = all.filter { NuggetState(rawValue: $0.state) == nil }
        guard !legacy.isEmpty else { return 0 }
        for state in NuggetState.allCases {
            let migrated = all.filter { $0.state == state.rawValue }.sorted(by: Self.sectionOrder)
            let group = legacy.filter { $0.legacyState == state }.sorted { lhs, rhs in
                switch state {
                case .active:
                    return Self.sectionOrder(lhs, rhs)
                case .queued:
                    if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                case .paused:
                    let left = lhs.legacyDeactivatedAt ?? .distantPast
                    let right = rhs.legacyDeactivatedAt ?? .distantPast
                    if left != right { return left < right }
                    if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            for nugget in group { nugget.state = state.rawValue }
            Self.renumber(migrated + group)
        }
        try context.save()
        return legacy.count
    }

    @discardableResult
    func stripStoredQuotes() throws -> Int {
        var changed = 0
        for nugget in try allNuggets() {
            let stripped = NuggetText.stored(nugget.text)
            guard stripped != nugget.text, !stripped.isEmpty else { continue }
            nugget.text = stripped
            changed += 1
        }
        if changed > 0 { try context.save() }
        return changed
    }

    // MARK: Backup

    func exportBackup() throws -> NuggetBackup {
        let all = try NuggetState.allCases.flatMap { try nuggets(in: $0) }
        return NuggetBackup(exportedAt: now(), nuggets: all.map(NuggetBackup.Item.init))
    }

    /// Merges by id: new nuggets go to the bottom of their section, and existing
    /// ones are replaced only when the backup copy is newer. Active past the
    /// limit goes to the bottom of Queued. A nugget whose content matches a
    /// different nugget already here is skipped.
    func importBackup(_ backup: NuggetBackup) throws -> ImportSummary {
        var summary = ImportSummary()
        var sections: [NuggetState: [Nugget]] = [:]
        for state in NuggetState.allCases {
            sections[state] = try nuggets(in: state)
        }
        var owners: [String: UUID] = [:]
        for nugget in sections.values.joined() {
            owners[NuggetText.matchKey(nugget.text)] = owners[NuggetText.matchKey(nugget.text)] ?? nugget.id
        }

        /// Where it should go, falling back to Queued when Active is full.
        func admit(_ wanted: NuggetState, alreadyActive: Bool) -> NuggetState {
            guard wanted == .active, !alreadyActive,
                  (sections[.active]?.count ?? 0) >= NuggetRules.activeLimit else { return wanted }
            summary.queuedBecauseActiveFull += 1
            return .queued
        }

        func move(_ nugget: Nugget, from: NuggetState, to: NuggetState) {
            guard from != to else { return }
            sections[from]?.removeAll { $0.id == nugget.id }
            sections[to, default: []].append(nugget)
            nugget.nuggetState = to
        }

        for item in backup.nuggets.sorted(by: NuggetBackup.Item.importOrder) {
            let text = NuggetText.stored(item.text)
            guard !text.isEmpty else { continue }
            let key = NuggetText.matchKey(text)
            if let owner = owners[key], owner != item.id {
                summary.duplicatesSkipped += 1
                continue
            }

            if let existing = try nugget(id: item.id) {
                guard item.updatedAt > existing.updatedAt else {
                    summary.unchanged += 1
                    continue
                }
                let oldKey = NuggetText.matchKey(existing.text)
                if owners[oldKey] == existing.id { owners[oldKey] = nil }
                owners[key] = existing.id
                existing.text = text
                existing.author = NuggetDraft.clean(item.author ?? "")
                existing.book = NuggetDraft.clean(item.book ?? "")
                existing.category = NuggetDraft.clean(item.category ?? "")
                existing.nuggetKind = item.resolvedKind
                existing.updatedAt = item.updatedAt
                let from = existing.nuggetState
                // An older backup can't tell a waiting nugget from a paused one,
                // so out of the rotation on both sides keeps what this device knows.
                let wanted = !item.isStateKnown && from != .active ? from : item.resolvedState
                move(existing, from: from, to: admit(wanted, alreadyActive: from == .active))
                summary.updated += 1
            } else {
                let state = admit(item.resolvedState, alreadyActive: false)
                let nugget = Nugget(
                    id: item.id,
                    text: text,
                    author: NuggetDraft.clean(item.author ?? ""),
                    book: NuggetDraft.clean(item.book ?? ""),
                    category: NuggetDraft.clean(item.category ?? ""),
                    kind: item.resolvedKind,
                    state: state,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt
                )
                context.insert(nugget)
                sections[state, default: []].append(nugget)
                owners[key] = nugget.id
                summary.added += 1
            }
        }
        for ordered in sections.values { Self.renumber(ordered) }
        try context.save()
        return summary
    }
}
