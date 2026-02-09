import SwiftUI

@main
struct KnowledgeNuggetsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .task {
                    await appDelegate.registerForPushNotifications()
                }
                .onReceive(NotificationCenter.default.publisher(for: .didReceiveDeviceToken)) { notification in
                    if let token = notification.object as? String {
                        session.deviceToken = token
                    }
                }
        }
    }
}
