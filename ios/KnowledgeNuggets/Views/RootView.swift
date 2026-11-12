import SwiftUI

enum AppTab: String, Hashable {
    case today, nuggets, settings
}

/// Lets `.sheet(item:)` present a nugget by id.
struct NuggetLink: Identifiable, Hashable {
    let id: UUID
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(NotificationRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab
    @State private var openedNugget: NuggetLink?

    init(initialTab: AppTab = .today) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)
            NuggetListView()
                .tabItem { Label("Nuggets", systemImage: "text.quote") }
                .tag(AppTab.nuggets)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(Color("AccentColor"))
        .sheet(item: $openedNugget) { link in
            NuggetDetailView(nuggetID: link.id)
        }
        .onChange(of: router.pendingNuggetID, initial: true) { _, id in
            guard let id else { return }
            openedNugget = NuggetLink(id: id)
            router.pendingNuggetID = nil
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                Task { await model.appBecameActive() }
            }
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(model.errorMessage ?? "") }
        )
    }
}

#Preview {
    RootView()
        .environment(PreviewSupport.model())
        .environment(NotificationRouter())
}

extension View {
    /// The one main action on a screen. The label uses the background color so it
    /// keeps good contrast on the amber fill in both light and dark mode.
    func primaryActionStyle() -> some View {
        buttonStyle(.borderedProminent)
            .foregroundStyle(Color(.systemBackground))
    }
}
