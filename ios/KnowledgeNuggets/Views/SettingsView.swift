import SwiftUI

struct SettingsView: View {
    @State private var sendTime = Date()
    @State private var sendPush = true
    @State private var sendEmail = true
    @State private var marketplace = "US"
    @State private var errorMessage: String?

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        NavigationView {
            Form {
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
                Section(header: Text("Daily Send")) {
                    DatePicker("Time", selection: $sendTime, displayedComponents: .hourAndMinute)
                }
                Section(header: Text("Channels")) {
                    Toggle("Push Notifications", isOn: $sendPush)
                    Toggle("Email", isOn: $sendEmail)
                }
                Section(header: Text("Amazon Marketplace")) {
                    TextField("Marketplace", text: $marketplace)
                }
                Section(header: Text("Timezone")) {
                    Text(TimeZone.current.identifier)
                        .foregroundColor(.secondary)
                }
                Button("Save") {
                    Task { await save() }
                }
            }
            .navigationTitle("Settings")
        }
        .task {
            await load()
        }
    }

    private func load() async {
        do {
            let settings = try await APIClient.shared.fetchSettings()
            sendPush = settings.sendPush
            sendEmail = settings.sendEmail
            marketplace = settings.marketplace
            if let date = timeFormatter.date(from: settings.sendTimeLocal) {
                sendTime = date
            }
        } catch {
            errorMessage = "Failed to load settings."
        }
    }

    private func save() async {
        do {
            let settings = UserSettings(
                sendTimeLocal: timeFormatter.string(from: sendTime),
                timezone: TimeZone.current.identifier,
                marketplace: marketplace,
                sendPush: sendPush,
                sendEmail: sendEmail
            )
            _ = try await APIClient.shared.updateSettings(settings)
        } catch {
            errorMessage = "Failed to save settings."
        }
    }
}
