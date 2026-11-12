import XCTest
@testable import KnowledgeNuggets

final class MetadataLookupTests: XCTestCase {
    typealias Doc = OpenLibraryLookup.SearchResponse.Doc

    func testNormalizerIgnoresCaseQuotesAndSpacing() {
        XCTAssertEqual(MetadataNormalizer.normalize("  The  “Obstacle”   Is the Way "), "the obstacle is the way")
        XCTAssertTrue(MetadataNormalizer.matches("Man's Search for Meaning", "MAN’S SEARCH  FOR MEANING"))
        XCTAssertTrue(MetadataNormalizer.matches("Antifragile – Things", "antifragile - things"))
        XCTAssertFalse(MetadataNormalizer.matches("Atomic Habits", "Atomic Habit"))
        XCTAssertFalse(MetadataNormalizer.matches("", ""))
    }

    func testLookupRequestOnlyWhenExactlyOneIsKnown() {
        XCTAssertEqual(LookupRequest(author: nil, book: "Dune"), .authorForBook("Dune"))
        XCTAssertEqual(LookupRequest(author: "Frank Herbert", book: "  "), .bookForAuthor("Frank Herbert"))
        XCTAssertNil(LookupRequest(author: "A", book: "B"))
        XCTAssertNil(LookupRequest(author: nil, book: nil))
    }

    func testAuthorForBookAcceptsOnlyExactTitle() {
        let docs = [
            Doc(title: "Atomic Habits Workbook", author_name: ["Someone"]),
            Doc(title: "Atomic Habits", author_name: ["James Clear", "Other"]),
        ]
        XCTAssertEqual(OpenLibraryLookup.author(forBook: "atomic habits", in: docs), "James Clear")
        XCTAssertNil(OpenLibraryLookup.author(forBook: "Atomic", in: docs))
        XCTAssertNil(OpenLibraryLookup.author(forBook: "Atomic Habits", in: [Doc(title: "Atomic Habits", author_name: nil)]))
    }

    func testBookForAuthorAcceptsOnlyExactAuthor() {
        let docs = [
            Doc(title: "Wrong", author_name: ["Jim Clear"]),
            Doc(title: "Atomic Habits", author_name: ["James Clear"]),
        ]
        XCTAssertEqual(OpenLibraryLookup.book(forAuthor: "james  clear", in: docs), "Atomic Habits")
        XCTAssertNil(OpenLibraryLookup.book(forAuthor: "Clear", in: docs))
    }

    func testOfflineFailsSilently() async {
        let lookup = OpenLibraryLookup(baseURL: URL(string: "http://127.0.0.1:9/search.json")!)
        let author = await lookup.author(forBook: "Dune")
        XCTAssertNil(author)
    }
}
