import Foundation

/// What the editor shows after a new nugget is saved: which layout, the
/// headline, the progress ring or the info box, and the main button.
/// Built from counts only, so it can be tested without any views.
struct SaveCelebration: Equatable, Sendable {
    /// Active nuggets after the save.
    let activeCount: Int
    /// The most nuggets the rotation holds.
    let limit: Int
    /// Where the nugget went: into the rotation, inactive because the rotation
    /// was full, or inactive because the switch was turned off.
    let outcome: ActivationOutcome

    init(activeCount: Int, limit: Int = NuggetRules.activeLimit, outcome: ActivationOutcome) {
        self.activeCount = max(0, activeCount)
        self.limit = max(1, limit)
        self.outcome = outcome
    }

    /// `keptInactive: true` means the rotation was full.
    init(activeCount: Int, limit: Int = NuggetRules.activeLimit, keptInactive: Bool) {
        self.init(activeCount: activeCount, limit: limit, outcome: keptInactive ? .keptInactiveLimitReached : .active)
    }

    /// The nugget was saved as inactive, for either reason.
    var keptInactive: Bool { outcome != .active }

    // MARK: Layout

    /// What sits between the headline and the buttons.
    enum Layout: Equatable, Sendable {
        /// Added to Active: the progress ring.
        case progress
        /// Kept inactive because the rotation is full: an info box with the
        /// two steps to swap it in.
        case rotationFull
        /// Saved as inactive on purpose: an info box with one step.
        case switchedOff
    }

    var layout: Layout {
        switch outcome {
        case .active: return .progress
        case .keptInactiveLimitReached: return .rotationFull
        case .inactive: return .switchedOff
        }
    }

    /// The main button. Done is always offered under it.
    enum PrimaryAction: Equatable, Sendable {
        case addAnother
        /// Closes the sheet and switches to the Nuggets tab.
        case goToNuggets

        var title: String {
            switch self {
            case .addAnother: return "Add Another"
            case .goToNuggets: return "Go to Nuggets"
            }
        }
    }

    var primaryAction: PrimaryAction {
        layout == .rotationFull ? .goToNuggets : .addAnother
    }

    // MARK: Headline

    /// A count worth marking. Only reached when this save added to the rotation.
    enum Milestone: Equatable, Sendable {
        case first, firstWeek, twoWeeks, full
    }

    var milestone: Milestone? {
        guard !keptInactive else { return nil }
        switch activeCount {
        case limit: return .full
        case 1: return .first
        case 7: return .firstWeek
        case 14: return .twoWeeks
        default: return nil
        }
    }

    var headline: String {
        switch milestone {
        case .first: return "Your first nugget"
        case .firstWeek: return "One week of nuggets"
        case .twoWeeks: return "Two weeks of nuggets"
        case .full: return "Your rotation is full"
        case nil: return "Nugget saved"
        }
    }

    // MARK: Info box

    /// The card shown in place of the ring when the nugget went to Inactive.
    struct InfoBox: Equatable, Sendable {
        let title: String
        let message: String
        /// Shown as numbered steps.
        let steps: [String]
    }

    var infoBox: InfoBox? {
        let message = "It won't come up in your daily rotation until you move it to Active."
        switch layout {
        case .progress:
            return nil
        case .rotationFull:
            return InfoBox(
                title: "Your \(limit) active spots are full",
                message: message,
                steps: ["Swipe an active nugget to Inactive", "Swipe this one to Active"]
            )
        case .switchedOff:
            return InfoBox(
                title: "Added to Inactive",
                message: message,
                steps: ["Swipe it to Active when you're ready"]
            )
        }
    }

    // MARK: Progress

    /// The ring is only shown when the nugget joined the rotation.
    var showsProgress: Bool { layout == .progress }

    /// Share of the rotation filled, from 0 to 1.
    var progress: Double { min(Double(activeCount) / Double(limit), 1) }

    /// The count before this save, so the ring can grow into place.
    var previousActiveCount: Int { keptInactive ? activeCount : max(0, activeCount - 1) }

    var previousProgress: Double { min(Double(previousActiveCount) / Double(limit), 1) }

    /// For example "8 of 21".
    var progressLabel: String { "\(min(activeCount, limit)) of \(limit)" }

    // MARK: Feedback

    /// Confetti and a stronger haptic.
    var isBigCelebration: Bool { milestone == .full }

    /// What VoiceOver reads when the screen appears: the headline, then the
    /// ring's count or the box's title.
    var announcement: String {
        let detail = infoBox?.title ?? progressLabel
        return "\(headline). \(detail)."
    }
}
