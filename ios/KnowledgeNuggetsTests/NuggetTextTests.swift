import XCTest
@testable import KnowledgeNuggets

final class NuggetTextTests: XCTestCase {
    // MARK: Stored

    func testStoredStripsOneLayerOfAnyStyleOfQuotes() {
        XCTAssertEqual(NuggetText.stored("\"Hello\""), "Hello")
        XCTAssertEqual(NuggetText.stored("“Hello”"), "Hello")
        XCTAssertEqual(NuggetText.stored("„Hallo“"), "Hallo")
        XCTAssertEqual(NuggetText.stored("«Bonjour»"), "Bonjour")
        XCTAssertEqual(NuggetText.stored("»Hej«"), "Hej")
        XCTAssertEqual(NuggetText.stored("'Hi'"), "Hi")
        XCTAssertEqual(NuggetText.stored("‘Hi’"), "Hi")
        XCTAssertEqual(NuggetText.stored("  \n“Padded.”  "), "Padded.")
        XCTAssertEqual(NuggetText.stored("“ Inner space ”"), "Inner space")
    }

    func testStoredStripsOnlyOneLayerAndLeavesInnerQuotes() {
        XCTAssertEqual(NuggetText.stored("\"'Nested'\""), "'Nested'")
        XCTAssertEqual(NuggetText.stored("He said \"no\" twice"), "He said \"no\" twice")
        XCTAssertEqual(NuggetText.stored("\"Start\" and \"end\""), "Start\" and \"end", "Only the outer pair goes")
    }

    func testStoredLeavesUnwrappedTextAlone() {
        XCTAssertEqual(NuggetText.stored("Plain"), "Plain")
        XCTAssertEqual(NuggetText.stored("\"Only opening"), "\"Only opening")
        XCTAssertEqual(NuggetText.stored("Only closing\""), "Only closing\"")
        XCTAssertEqual(NuggetText.stored("\""), "\"")
        XCTAssertEqual(NuggetText.stored("\"\""), "")
        XCTAssertEqual(NuggetText.stored(""), "")
    }

    // MARK: Quoted

    func testQuotedWrapsInCurlyQuotesWithoutDoubling() {
        XCTAssertEqual(NuggetText.quoted("Hello"), "“Hello”")
        XCTAssertEqual(NuggetText.quoted("“Hello”"), "“Hello”")
        XCTAssertEqual(NuggetText.quoted("\"Hello\""), "“Hello”")
        XCTAssertEqual(NuggetText.quoted("I am calm."), "“I am calm.”", "Affirmations too")
        XCTAssertEqual(NuggetText.quoted(NuggetText.quoted("Twice")), "“Twice”")
    }

    func testDraftValidityIgnoresWrappingQuotes() {
        XCTAssertFalse(NuggetDraft(text: " “ ” ", kind: .affirmation).isValid)
        XCTAssertEqual(NuggetDraft(text: "“x”", kind: .affirmation).storedText, "x")
    }

    func testDeletePreviewIsQuotedAndTruncatedInside() {
        XCTAssertEqual(NuggetListView.deletePreview("“Short”"), "“Short”")
        let long = String(repeating: "a", count: 100)
        XCTAssertEqual(NuggetListView.deletePreview(long, limit: 10), "“aaaaaaaaaa…”")
        XCTAssertEqual(NuggetListView.deletePreview("Two\nlines"), "“Two lines”")
    }

    // MARK: Matching

    func testMatchIgnoresCaseSpacingQuotesAndEndPunctuation() {
        let base = "Slow is smooth, and smooth is fast"
        for variant in [
            "slow is smooth, and smooth is fast",
            "  Slow   is smooth,\nand smooth is fast  ",
            "\"Slow is smooth, and smooth is fast.\"",
            "“Slow is smooth, and smooth is fast!”",
            "'Slow is smooth, and smooth is fast'?",
            "«SLOW IS SMOOTH, AND SMOOTH IS FAST…»",
            "Slow is smooth, and smooth is fast,",
            "„Slow is smooth, and smooth is fast“...",
        ] {
            XCTAssertTrue(NuggetText.isDuplicate(base, variant), variant)
        }
    }

    func testMatchKeepsMeaningfulDifferences() {
        XCTAssertFalse(NuggetText.isDuplicate("Slow is smooth", "Slow is smooth and fast"))
        XCTAssertFalse(NuggetText.isDuplicate("Do, or do not", "Do or do not"), "Inner punctuation counts")
        XCTAssertFalse(NuggetText.isDuplicate("Why?", "Why not?"))
        XCTAssertFalse(NuggetText.isDuplicate("", ""), "Empty never matches")
        XCTAssertFalse(NuggetText.isDuplicate("\"\"", "..."))
    }

    func testMatchKey() {
        XCTAssertEqual(NuggetText.matchKey("  “Hello,   World!” "), "hello, world")
        XCTAssertEqual(NuggetText.matchKey("Hello."), NuggetText.matchKey("hello"))
    }
}
