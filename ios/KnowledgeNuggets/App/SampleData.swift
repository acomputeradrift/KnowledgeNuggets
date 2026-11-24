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

    /// Waiting for a spot, then set aside, so the Nuggets list shows all three sections.
    static let queuedDrafts: [NuggetDraft] = [
        NuggetDraft(
            text: "The best time to plant a tree was twenty years ago. The second best time is now.",
            author: "Chinese proverb",
            kind: .quote
        ),
        NuggetDraft(text: "\u{201C}Simplicity is the ultimate sophistication.\u{201D}", author: "Leonardo da Vinci", kind: .quote),
        NuggetDraft(text: "I finish what I start.", kind: .affirmation),
    ]

    static let pausedDrafts: [NuggetDraft] = [
        NuggetDraft(
            text: "It is not the critic who counts.",
            author: "Theodore Roosevelt",
            book: "Citizenship in a Republic",
            kind: .quote
        ),
        NuggetDraft(text: "\"I'm gonna make him an offer he can't refuse.\"", author: "Vito Corleone", book: "The Godfather", kind: .movie),
    ]

    /// Exactly `activeCount` active nuggets, reusing the samples with a number added.
    static func seed(into store: NuggetStore, activeCount: Int) {
        for index in 0..<max(0, activeCount) {
            var draft = drafts[index % drafts.count]
            if index >= drafts.count { draft.text += " (\(index + 1))" }
            _ = try? store.add(draft, state: .active)
        }
    }

    /// The queued and paused samples.
    static func seedSetAside(into store: NuggetStore) {
        for draft in queuedDrafts { _ = try? store.add(draft, state: .queued) }
        for draft in pausedDrafts { _ = try? store.add(draft, state: .paused) }
    }

    static func seed(into store: NuggetStore) {
        for draft in drafts {
            _ = try? store.add(draft, state: .active)
        }
        seedSetAside(into: store)
    }
}
