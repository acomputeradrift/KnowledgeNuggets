import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            if session.token == nil {
                AuthView()
            } else {
                TabView {
                    NuggetListView()
                        .tabItem { Label("Nuggets", systemImage: "list.bullet") }
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gear") }
                }
            }
        }
        .onChange(of: session.deviceToken) { token in
            guard let token else { return }
            Task { try? await APIClient.shared.registerDevice(token: token) }
        }
    }
}
