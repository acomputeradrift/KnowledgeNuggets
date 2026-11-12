import Foundation
import UserNotifications

/// In-memory models for SwiftUI previews.
@MainActor
enum PreviewSupport {
    static func model(seed: Bool = true) -> AppModel {
        let container = try! SwiftDataNuggetStore.makeContainer(inMemory: true)
        let store = SwiftDataNuggetStore(context: container.mainContext)
        if seed { SampleData.seed(into: store) }
        retained.append(container)
        return AppModel(
            store: store,
            scheduler: NotificationScheduler(center: PreviewNotificationCenter()),
            lookup: NoLookup(),
            defaults: UserDefaults(suiteName: "previews") ?? .standard
        )
    }

    private static var retained: [AnyObject] = []
}

private final class PreviewNotificationCenter: NotificationCenterClient, @unchecked Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requestAuthorization() async -> Bool { true }
    func removeAllPendingRequests() {}
    func add(_ request: UNNotificationRequest) async throws {}
    func pendingRequestCount() async -> Int { 60 }
}

private struct NoLookup: MetadataLookup {
    func author(forBook book: String) async -> String? { nil }
    func book(forAuthor author: String) async -> String? { nil }
}
