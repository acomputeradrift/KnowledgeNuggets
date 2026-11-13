import Foundation

/// Example nuggets for previews and debug screenshots.
@MainActor
enum SampleData {
    static let drafts: [NuggetDraft] = [
        NuggetDraft(
            text: "We are what we repeatedly do. Excellence, then, is not an act, but a habit.",
            author: "Will Durant",
            book: "The Story of Philosophy",
            category: "Habits"
        ),
        NuggetDraft(
            text: "You do not rise to the level of your goals. You fall to the level of your systems.",
            author: "James Clear",
            book: "Atomic Habits",
            category: "Habits"
        ),
        NuggetDraft(
            text: "The obstacle in the path becomes the path. Never forget, within every obstacle is an opportunity to improve our condition.",
            author: "Ryan Holiday",
            book: "The Obstacle Is the Way"
        ),
        NuggetDraft(
            text: "What gets measured gets managed — but only if someone is looking at the measurement.",
            book: "High Output Management",
            category: "Work"
        ),
        NuggetDraft(text: "Do. Or do not. There is no try.", author: "Yoda", book: "The Empire Strikes Back", kind: .movie),
        NuggetDraft(text: "I am calm, focused and ready for today.", kind: .affirmation),
        NuggetDraft(text: "Slow is smooth, and smooth is fast.", author: "U.S. Navy SEALs", kind: .quote),
    ]

    /// Exactly `activeCount` active nuggets, reusing the samples with a number added.
    static func seed(into store: NuggetStore, activeCount: Int) {
        for index in 0..<max(0, activeCount) {
            var draft = drafts[index % drafts.count]
            if index >= drafts.count { draft.text += " (\(index + 1))" }
            _ = try? store.add(draft, active: true)
        }
    }

    static func seed(into store: NuggetStore) {
        for draft in drafts {
            _ = try? store.add(draft, active: true)
        }
        _ = try? store.add(
            NuggetDraft(
                text: "The best time to plant a tree was twenty years ago. The second best time is now.",
                author: "Chinese proverb",
                kind: .quote
            ),
            active: false
        )
    }
}
