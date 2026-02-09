import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published var token: String? = nil
    @Published var email: String? = nil
    @Published var deviceToken: String? = nil

    init() {
        if let stored = UserDefaults.standard.string(forKey: "auth_token") {
            token = stored
            APIClient.shared.setToken(stored)
        }
    }

    func setToken(_ token: String) {
        self.token = token
        UserDefaults.standard.set(token, forKey: "auth_token")
        APIClient.shared.setToken(token)
    }

    func clear() {
        token = nil
        UserDefaults.standard.removeObject(forKey: "auth_token")
        APIClient.shared.setToken("")
    }
}
