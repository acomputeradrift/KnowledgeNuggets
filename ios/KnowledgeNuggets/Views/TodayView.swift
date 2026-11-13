import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var isAdding = false
    @State private var openedNugget: NuggetLink?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Today")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isAdding = true
                        } label: {
                            Label("Add Nugget", systemImage: "plus")
                        }
                    }
                }
                .sheet(isPresented: $isAdding) {
                    NuggetEditorView(nugget: nil)
                }
                .sheet(item: $openedNugget) { link in
                    NuggetDetailView(nuggetID: link.id)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isEmpty {
            ContentUnavailableView {
                Label("No Nuggets Yet", systemImage: "text.quote")
            } description: {
                Text("Save a passage from your reading and it will come back to you, one a day.")
            } actions: {
                Button("Add a Nugget") { isAdding = true }
                    .primaryActionStyle()
            }
        } else if model.active.isEmpty {
            ContentUnavailableView {
                Label("Nothing in Rotation", systemImage: "pause.circle")
            } description: {
                Text("All your nuggets are inactive. Activate some in the Nuggets tab, or add a new one.")
            } actions: {
                Button("Add a Nugget") { isAdding = true }
                    .primaryActionStyle()
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let today = model.todayNugget {
                        NuggetCard(
                            heading: model.today.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                            nugget: today,
                            prominent: true
                        ) {
                            openedNugget = NuggetLink(id: today.id)
                        }
                    }
                    if let next = model.upNextNugget {
                        NuggetCard(heading: "Up Next", nugget: next, prominent: false) {
                            openedNugget = NuggetLink(id: next.id)
                        }
                    }
                    ScheduleStatusLabel()
                        .padding(.horizontal, 4)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}

/// A nugget shown as a card on the Today screen.
struct NuggetCard: View {
    let heading: String
    let nugget: Nugget
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            Button(action: action) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(nugget.text)
                        .font(prominent ? .title2 : .body)
                        .fontDesign(.serif)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(prominent ? nil : 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let attribution = nugget.attribution {
                        Text(attribution)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(prominent ? 20 : 16)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(heading): \(nugget.text)")
            .accessibilityValue(nugget.attribution ?? "")
            .accessibilityHint("Opens the nugget.")
        }
    }
}

/// One line saying when the next notification arrives, or why it won't.
struct ScheduleStatusLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var time: String {
        model.settings.timeOfDay(calendar: model.calendar, now: model.today).formatted(date: .omitted, time: .shortened)
    }

    private var symbol: String {
        if model.settings.isPaused { return "bell.slash" }
        switch model.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "bell"
        default: return "bell.badge"
        }
    }

    private var text: String {
        if model.settings.isPaused { return "Notifications are paused." }
        switch model.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "A nugget arrives every day at \(time)."
        case .denied:
            return "Notifications are turned off in iOS Settings."
        default:
            return "Turn on notifications in Settings to get a nugget each day."
        }
    }
}

#Preview("Today") {
    TodayView()
        .environment(PreviewSupport.model())
}

#Preview("Empty") {
    TodayView()
        .environment(PreviewSupport.model(seed: false))
}
