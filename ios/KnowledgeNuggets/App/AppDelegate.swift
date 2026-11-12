import Observation
import UIKit
import UserNotifications

/// Carries the nugget a tapped notification should open.
@MainActor
@Observable
final class NotificationRouter {
    var pendingNuggetID: UUID?
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let router = NotificationRouter()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Show the banner even when the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// Tapping a notification opens that nugget.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = NotificationScheduler.nuggetID(from: response.notification.request.content.userInfo)
        Task { @MainActor in
            self.router.pendingNuggetID = id
            completionHandler()
        }
    }
}
