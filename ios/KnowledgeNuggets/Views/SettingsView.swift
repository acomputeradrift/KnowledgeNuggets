import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(ToastCenter.self) private var toasts: ToastCenter?
    @Environment(\.openURL) private var openURL
    @State private var isImporting = false
    @State private var importMessage: String?
    /// Waits for the time picker to settle before confirming the new time.
    @State private var timeConfirmation: Task<Void, Never>?

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
                handleImport(result)
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
                    Task {
                        await model.enableNotifications()
                        // Denied keeps the footer's explanation and the Open iOS Settings button.
                        if Self.allowsNotifications(model.authorizationStatus) {
                            toasts?.show("Notifications on")
                        }
                    }
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
            set: { newValue in
                Task { await model.setDailyTime(newValue) }
                confirmTimeWhenSettled()
            }
        )
    }

    private var pausedBinding: Binding<Bool> {
        Binding(
            get: { model.settings.isPaused },
            set: { paused in
                model.setPaused(paused)
                toasts?.show(paused ? "Notifications paused" : "Notifications resumed")
            }
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

    /// The picker reports every wheel stop, so confirm only once it's been still for a moment.
    private func confirmTimeWhenSettled() {
        timeConfirmation?.cancel()
        timeConfirmation = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let time = model.settings.timeOfDay(calendar: model.calendar, now: .now)
                .formatted(date: .omitted, time: .shortened)
            toasts?.show("Daily nugget set for \(time)")
        }
    }

    static func allowsNotifications(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// A clean import confirms with a short toast. Failures, and imports that
    /// left nuggets out of the full rotation, keep the alert so they can be read.
    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importMessage = "Couldn't open the file. \(error.localizedDescription)"
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                importMessage = "Couldn't read the file."
                return
            }
            switch model.importBackupResult(from: data) {
            case .imported(let summary) where summary.keptInactive == 0 && toasts != nil:
                toasts?.show(Self.importToast(summary))
            case let other:
                importMessage = other.message
            }
        }
    }

    static func importToast(_ summary: ImportSummary) -> String {
        if summary.added == 0 && summary.updated == 0 { return "Backup imported, nothing new" }
        return "Imported \(summary.added) new, \(summary.updated) updated"
    }
}

#Preview {
    SettingsView()
        .environment(PreviewSupport.model())
        .environment(ToastCenter())
}
