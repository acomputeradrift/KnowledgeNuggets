import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var isLogin = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Email")) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }
                Section(header: Text("Password")) {
                    SecureField("Password", text: $password)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
                Button(isLogin ? "Log In" : "Sign Up") {
                    Task { await submit() }
                }
                Button(isLogin ? "Need an account? Sign Up" : "Have an account? Log In") {
                    isLogin.toggle()
                    errorMessage = nil
                }
                .foregroundColor(.secondary)
            }
            .navigationTitle("Welcome")
        }
    }

    private func submit() async {
        do {
            if isLogin {
                let token = try await APIClient.shared.login(email: email, password: password)
                session.setToken(token)
                if let deviceToken = session.deviceToken {
                    try? await APIClient.shared.registerDevice(token: deviceToken)
                }
            } else {
                try await APIClient.shared.register(email: email, password: password)
                errorMessage = "Check your email to verify, then log in."
                isLogin = true
            }
        } catch {
            errorMessage = "Auth failed."
        }
    }
}
