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

    func activeNuggets() throws -> [Nugget] {
        let descriptor = FetchDescriptor<Nugget>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor)
    }

    func inactiveNuggets() throws -> [Nugget] {
        let descriptor = FetchDescriptor<Nugget>(
            predicate: #Predicate { !$0.isActive },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func nugget(id: UUID) throws -> Nugget? {
        var descriptor = FetchDescriptor<Nugget>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func activeCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<Nugget>(predicate: #Predicate { $0.isActive }))
    }

    private func nextSortOrder() throws -> Int {
        (try activeNuggets().map(\.sortOrder).max() ?? -1) + 1
    }

    // MARK: Writing

    @discardableResult
    func add(_ draft: NuggetDraft, active: Bool = true) throws -> (Nugget, ActivationOutcome) {
        let timestamp = now()
        let room = try activeCount() < NuggetRules.activeLimit
        let makeActive = active && room
        let nugget = Nugget(
            text: draft.trimmedText,
            author: NuggetDraft.clean(draft.author),
            book: NuggetDraft.clean(draft.book),
            category: NuggetDraft.clean(draft.category),
            isActive: makeActive,
            sortOrder: makeActive ? try nextSortOrder() : 0,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(nugget)
        try context.save()
        let outcome: ActivationOutcome = makeActive ? .active : (active ? .keptInactiveLimitReached : .inactive)
        return (nugget, outcome)
    }

    func update(_ nugget: Nugget, with draft: NuggetDraft) throws {
        nugget.text = draft.trimmedText
        nugget.author = NuggetDraft.clean(draft.author)
        nugget.book = NuggetDraft.clean(draft.book)
        nugget.category = NuggetDraft.clean(draft.category)
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
    func setActive(_ nugget: Nugget, _ active: Bool) throws -> ActivationOutcome {
        guard nugget.isActive != active else { return active ? .active : .inactive }
        if active {
            guard try activeCount() < NuggetRules.activeLimit else {
                return .keptInactiveLimitReached
            }
            nugget.sortOrder = try nextSortOrder()
        }
        nugget.isActive = active
        nugget.updatedAt = now()
        try context.save()
        return active ? .active : .inactive
    }

    func delete(_ nugget: Nugget) throws {
        context.delete(nugget)
        try context.save()
    }

    func moveActive(fromOffsets source: IndexSet, toOffset destination: Int) throws {
        var ordered = try activeNuggets()
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, nugget) in ordered.enumerated() where nugget.sortOrder != index {
            nugget.sortOrder = index
        }
        try context.save()
    }

    // MARK: Backup

    func exportBackup() throws -> NuggetBackup {
        let all = try activeNuggets() + inactiveNuggets()
        return NuggetBackup(exportedAt: now(), nuggets: all.map(NuggetBackup.Item.init))
    }

    func importBackup(_ backup: NuggetBackup) throws -> ImportSummary {
        var summary = ImportSummary()
        var activeTotal = try activeCount()
        var nextOrder = try nextSortOrder()

        // Bring active items in by their backup order so the rotation keeps its shape.
        let items = backup.nuggets.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            return lhs.sortOrder < rhs.sortOrder
        }

        for item in items {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if let existing = try nugget(id: item.id) {
                guard item.updatedAt > existing.updatedAt else {
                    summary.unchanged += 1
                    continue
                }
                existing.text = text
                existing.author = NuggetDraft.clean(item.author ?? "")
                existing.book = NuggetDraft.clean(item.book ?? "")
                existing.category = NuggetDraft.clean(item.category ?? "")
                existing.updatedAt = item.updatedAt
                if item.isActive && !existing.isActive {
                    if activeTotal < NuggetRules.activeLimit {
                        existing.isActive = true
                        existing.sortOrder = nextOrder
                        nextOrder += 1
                        activeTotal += 1
                    } else {
                        summary.keptInactive += 1
                    }
                } else if !item.isActive && existing.isActive {
                    existing.isActive = false
                    activeTotal -= 1
                }
                summary.updated += 1
            } else {
                var makeActive = item.isActive
                if makeActive && activeTotal >= NuggetRules.activeLimit {
                    makeActive = false
                    summary.keptInactive += 1
                }
                let nugget = Nugget(
                    id: item.id,
                    text: text,
                    author: NuggetDraft.clean(item.author ?? ""),
                    book: NuggetDraft.clean(item.book ?? ""),
                    category: NuggetDraft.clean(item.category ?? ""),
                    isActive: makeActive,
                    sortOrder: makeActive ? nextOrder : 0,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt
                )
                if makeActive {
                    nextOrder += 1
                    activeTotal += 1
                }
                context.insert(nugget)
                summary.added += 1
            }
        }
        try context.save()
        return summary
    }
}
