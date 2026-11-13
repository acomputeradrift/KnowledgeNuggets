import Foundation

/// What the editor celebrates after a new nugget is saved: the headline, the
/// progress toward a full rotation and whether the sheet closes on its own.
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
        case .first: return "Your first nugget!"
        case .firstWeek: return "Your first week is full"
        case .twoWeeks: return "Two weeks of nuggets"
        case .full: return "Your rotation is full"
        case nil: return "Nugget saved!"
        }
    }

    /// A line under the headline, only for milestones.
    var subtext: String? {
        switch milestone {
        case .first: return "This is the start of your daily rotation."
        case .firstWeek: return "Something different every day for a week."
        case .twoWeeks: return "You're two-thirds of the way to a full rotation."
        case .full: return "Three weeks of nuggets, one each day."
        case nil: return nil
        }
    }

    /// The rotation has no spots left.
    var isFull: Bool { activeCount >= limit }

    /// Share of the rotation filled, from 0 to 1.
    var progress: Double { min(Double(activeCount) / Double(limit), 1) }

    /// The count before this save, so the ring can grow into place.
    var previousActiveCount: Int { keptInactive ? activeCount : max(0, activeCount - 1) }

    var previousProgress: Double { min(Double(previousActiveCount) / Double(limit), 1) }

    /// For example "8 of 21".
    var progressLabel: String { "\(min(activeCount, limit)) of \(limit)" }

    /// The count turned into days.
    var daysLine: String {
        switch activeCount {
        case 0: return "Add nuggets to start your rotation."
        case 1: return "Each nugget you add is another day before anything repeats."
        default: return "\(activeCount) days before anything repeats."
        }
    }

    /// The small note at the bottom, the only part that differs between Active and Inactive.
    var note: String {
        switch outcome {
        case .active: return "Added to the end of your rotation."
        case .keptInactiveLimitReached: return "Added as Inactive. Your rotation is full."
        case .inactive: return "Added as Inactive."
        }
    }

    /// Confetti and a stronger haptic.
    var isBigCelebration: Bool { milestone == .full }

    /// The sheet closes on its own once the rotation is full, since there's
    /// nothing left to fill. The view also checks VoiceOver.
    var closesAutomatically: Bool { isFull }

    /// Add Another is offered while there are spots left.
    var offersAddAnother: Bool { !isFull }

    /// What VoiceOver reads when the screen appears.
    var announcement: String {
        let headline = headline.last.map { ".!?".contains($0) } == true ? headline : headline + "."
        return "\(headline) \(note)"
    }
}
