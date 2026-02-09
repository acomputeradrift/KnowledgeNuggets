import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        Form {
            Section(header: Text("Email")) {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
            }
            Section(header: Text("Password")) {
                SecureField("Password", text: $password)
            }
            Button("Log In") {
                // TODO: Call API
            }
        }
        .navigationTitle("Log In")
    }
}
