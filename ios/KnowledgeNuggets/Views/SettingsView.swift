import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var isImporting = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                notificationSection
                backupSection
                Section("Your Nuggets") {
                    LabeledContent("Active", value: "\(model.active.count) of \(NuggetRules.activeLimit)")
                    LabeledContent("Inactive", value: "\(model.inactive.count)")
                    LabeledContent("Notifications Queued", value: "\(model.scheduledCount)")
                }
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                importMessage = handleImport(result)
            }
            .alert(
                "Import",
                isPresented: Binding(
                    get: { importMessage != nil },
                    set: { if !$0 { importMessage = nil } }
                ),
                actions: { Button("OK", role: .cancel) {} },
                message: { Text(importMessage ?? "") }
            )
        }
    }

    // MARK: Sections

    private var notificationSection: some View {
        Section {
            DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
            Toggle("Pause Notifications", isOn: pausedBinding)

            if model.authorizationStatus == .notDetermined {
                Button("Turn On Notifications") {
                    Task { await model.enableNotifications() }
                }
            } else if model.authorizationStatus == .denied {
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        } header: {
            Text("Daily Nugget")
        } footer: {
            Text(statusText)
        }
    }

    private var backupSection: some View {
        Section {
            if let file = model.backupFile() {
                ShareLink(item: file, preview: SharePreview("Knowledge Nuggets Backup", image: Image(systemName: "doc.text"))) {
                    Label("Export Nuggets", systemImage: "square.and.arrow.up")
                }
                .disabled(model.isEmpty)
            }
            Button {
                isImporting = true
            } label: {
                Label("Import Nuggets", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("Export saves every nugget as a JSON file. Import merges a backup by id: new nuggets are added, and existing ones are replaced only when the backup copy is newer.")
        }
    }

    // MARK: Bindings and text

    private var timeBinding: Binding<Date> {
        Binding(
            get: { model.settings.timeOfDay(calendar: model.calendar, now: .now) },
            set: { newValue in Task { await model.setDailyTime(newValue) } }
        )
    }

    private var pausedBinding: Binding<Bool> {
        Binding(
            get: { model.settings.isPaused },
            set: { model.setPaused($0) }
        )
    }

    private var statusText: String {
        if model.settings.isPaused {
            return "Paused. Nothing is sent until you turn this off."
        }
        switch model.authorizationStatus {
        case .denied:
            return "Notifications are off for Knowledge Nuggets. Turn them on in iOS Settings."
        case .notDetermined:
            return "Choose a time, or tap Turn On, and iOS will ask to allow notifications."
        default:
            if model.active.isEmpty {
                return "Add or activate a nugget to start getting notifications."
            }
            return "One nugget a day, in your list order. Works offline and with the app closed."
        }
    }

    private func handleImport(_ result: Result<URL, Error>) -> String {
        switch result {
        case .failure(let error):
            return "Couldn't open the file. \(error.localizedDescription)"
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                return "Couldn't read the file."
            }
            return model.importBackup(from: data)
        }
    }
}

#Preview {
    SettingsView()
        .environment(PreviewSupport.model())
}
