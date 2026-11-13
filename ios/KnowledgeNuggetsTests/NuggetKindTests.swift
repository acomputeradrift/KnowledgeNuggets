import SwiftData
import XCTest
@testable import KnowledgeNuggets

@MainActor
final class NuggetKindTests: XCTestCase {
    private var container: ModelContainer!
    private var store: SwiftDataNuggetStore!

    override func setUp() async throws {
        container = try SwiftDataNuggetStore.makeContainer(inMemory: true)
        store = SwiftDataNuggetStore(context: container.mainContext)
    }

    private func makeModel(lookup: MetadataLookup = FakeLookup()) -> AppModel {
        let suite = "NuggetKindTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppModel(
            store: store,
            scheduler: NotificationScheduler(center: FakeNotificationCenter(status: .denied)),
            lookup: lookup,
            defaults: defaults
        )
    }

    // MARK: The By-or-From rule

    func testEveryKindExceptAffirmationNeedsByOrFrom() {
        for kind in NuggetKind.allCases {
            let bare = NuggetDraft(text: "Content", kind: kind)
            XCTAssertEqual(bare.canSave, kind == .affirmation, "\(kind)")
            XCTAssertTrue(NuggetDraft(text: "Content", author: "Someone", kind: kind).canSave, "\(kind)")
            XCTAssertTrue(NuggetDraft(text: "Content", book: "Somewhere", kind: kind).canSave, "\(kind)")
        }
    }

    func testBlankOrWhitespaceSourceDoesNotCount() {
        let draft = NuggetDraft(text: "Content", author: "  ", book: "\n", kind: .movie)
        XCTAssertFalse(draft.canSave)
        XCTAssertEqual(draft.missingRequirement, "Add who it's by or where it's from.")
    }

    func testContentIsAlwaysRequired() {
        XCTAssertFalse(NuggetDraft(text: "  ", author: "A", book: "B").canSave)
        XCTAssertFalse(NuggetDraft(text: "", kind: .affirmation).canSave)
    }

    func testAppModelRefusesToSaveWithoutASource() {
        let model = makeModel()
        model.save(NuggetDraft(text: "No source", kind: .book))
        XCTAssertTrue(model.isEmpty)
        model.save(NuggetDraft(text: "Mine", kind: .affirmation))
        XCTAssertEqual(model.active.map(\.text), ["Mine"])
    }

    // MARK: Storing kinds

    func testKindIsStoredAndAffirmationsDropTheSource() throws {
        let (movie, _) = try store.add(NuggetDraft(text: "Try not.", author: "Yoda", book: "The Empire Strikes Back", kind: .movie), active: true)
        XCTAssertEqual(movie.nuggetKind, .movie)
        XCTAssertEqual(movie.author, "Yoda")

        // Switching to an affirmation clears the hidden fields.
        try store.update(movie, with: NuggetDraft(text: "I can.", author: "Yoda", book: "Empire", kind: .affirmation))
        XCTAssertEqual(movie.nuggetKind, .affirmation)
        XCTAssertNil(movie.author)
        XCTAssertNil(movie.book)
        XCTAssertNil(movie.attribution)
    }

    func testUnknownStoredKindReadsAsOther() {
        let nugget = Nugget(text: "x")
        nugget.kind = "something-new"
        XCTAssertEqual(nugget.nuggetKind, .other)
        XCTAssertEqual(Nugget(text: "y").nuggetKind, .book, "Default for older nuggets")
    }

    func testBackupKeepsKindAndOldBackupsReadAsBooks() throws {
        try store.add(NuggetDraft(text: "Listen.", author: "Host", kind: .podcast), active: true)
        let decoded = try NuggetBackup.decode(try store.exportBackup().encoded())
        XCTAssertEqual(decoded.nuggets.first?.kind, "podcast")

        let old = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"Old","book":"Dune","isActive":true,"sortOrder":0,
          "createdAt":"2026-01-01T08:00:00Z","updatedAt":"2026-01-01T08:00:00Z"}]
        """
        let backup = try NuggetBackup.decode(Data(old.utf8))
        XCTAssertNil(backup.nuggets[0].kind)
        _ = try store.importBackup(backup)
        XCTAssertEqual(try store.nugget(id: backup.nuggets[0].id)?.nuggetKind, .book)
    }

    func testLyricsKindMetadataAndRequirements() {
        XCTAssertEqual(NuggetKind(storedValue: "lyrics"), .lyrics)
        XCTAssertEqual(NuggetKind.lyrics.rawValue, "lyrics")
        XCTAssertEqual(NuggetKind.lyrics.title, "Lyrics")
        XCTAssertEqual(NuggetKind.lyrics.byPrompt, "Artist")
        XCTAssertEqual(NuggetKind.lyrics.fromPrompt, "Song")
        XCTAssertTrue(NuggetKind.lyrics.hasSource)
        XCTAssertFalse(NuggetKind.lyrics.supportsLookup)
        XCTAssertEqual(NuggetKind.allCases.firstIndex(of: .lyrics), NuggetKind.allCases.firstIndex(of: .podcast)! + 1)

        XCTAssertFalse(NuggetDraft(text: "Placeholder chorus line", kind: .lyrics).canSave)
        XCTAssertTrue(NuggetDraft(text: "Placeholder chorus line", author: "Made-up Artist", kind: .lyrics).canSave)
        XCTAssertTrue(NuggetDraft(text: "Placeholder chorus line", book: "Made-up Song", kind: .lyrics).canSave)
    }

    func testLyricsDoesNotTriggerLookupAndRoundTripsThroughBackup() async throws {
        let model = makeModel(lookup: FakeLookup(authors: ["Made-up Song": "Someone"]))
        model.save(NuggetDraft(text: "Placeholder chorus line", book: "Made-up Song", kind: .lyrics))
        XCTAssertNil(model.lookupTask)
        XCTAssertNil(model.active.first?.author)

        let (nugget, _) = try store.add(NuggetDraft(text: "Placeholder verse line", author: "Made-up Artist", book: "Made-up Song", kind: .lyrics), active: true)
        let decoded = try NuggetBackup.decode(try store.exportBackup().encoded())
        XCTAssertEqual(decoded.nuggets.first { $0.id == nugget.id }?.kind, "lyrics")
        _ = try store.importBackup(decoded)
        XCTAssertEqual(try store.nugget(id: nugget.id)?.nuggetKind, .lyrics)
    }

    // MARK: Lookup and recents

    func testLookupOnlyRunsForBooks() async {
        let model = makeModel(lookup: FakeLookup(authors: ["Dune": "Frank Herbert"]))
        model.save(NuggetDraft(text: "Movie line", book: "Dune", kind: .movie))
        XCTAssertNil(model.lookupTask)
        XCTAssertNil(model.active.first?.author)

        model.save(NuggetDraft(text: "Book line", book: "Dune", kind: .book))
        await model.lookupTask?.value
        XCTAssertEqual(model.active.last?.author, "Frank Herbert")
    }

    func testRecentSourcesAreDistinctPerKindAndFilterable() {
        let model = makeModel()
        model.save(NuggetDraft(text: "1", author: "James Clear", book: "Atomic Habits"))
        model.save(NuggetDraft(text: "2", book: "atomic habits"))
        model.save(NuggetDraft(text: "3", author: "Marcus Aurelius", book: "Meditations"))
        model.save(NuggetDraft(text: "4", book: "Inception", kind: .movie))

        let books = model.recentSources(for: .book)
        XCTAssertEqual(books.count, 2, "Case-insensitive duplicates collapse")
        XCTAssertEqual(Set(books.map { $0.from.lowercased() }), ["atomic habits", "meditations"])
        XCTAssertEqual(model.recentSources(for: .movie).map(\.from), ["Inception"])
        XCTAssertTrue(model.recentSources(for: .podcast).isEmpty)

        XCTAssertEqual(model.recentSources(for: .book, matching: "medi").map(\.from), ["Meditations"])
        XCTAssertEqual(model.recentSources(for: .book, matching: "medi").first?.by, "Marcus Aurelius")
        XCTAssertTrue(model.recentSources(for: .book, matching: "Meditations").isEmpty, "Already filled in")
    }
}
