import BackgroundTasks
import SwiftData
import SwiftUI

@main
struct KnowledgeNuggetsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel
    private let container: ModelContainer

    init() {
        let launch = LaunchOptions.current
        let container: ModelContainer
        do {
            container = try SwiftDataNuggetStore.makeContainer(inMemory: launch.inMemoryStore)
        } catch {
            // Keep the app usable rather than crash; nothing will persist this session.
            container = try! SwiftDataNuggetStore.makeContainer(inMemory: true)
        }
        self.container = container
        let store = SwiftDataNuggetStore(context: container.mainContext)
        if launch.seedSampleData {
            SampleData.seed(into: store)
        } else if let count = launch.seedActiveCount {
            SampleData.seed(into: store, activeCount: count)
        }
        _model = State(initialValue: AppModel(
            store: store,
            scheduler: NotificationScheduler(center: SystemNotificationCenter()),
            lookup: OpenLibraryLookup()
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(initialTab: LaunchOptions.current.initialTab)
                .environment(model)
                .environment(appDelegate.router)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                BackgroundRefresh.submit()
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            BackgroundRefresh.submit()
            await model.appBecameActive()
        }
    }
}

enum BackgroundRefresh {
    static let identifier = "com.acomputeradrift.KnowledgeNuggets.refresh"

    /// Asks iOS to wake the app about once a day to top up the queue.
    static func submit() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(12 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Debug launch arguments used for screenshots and UI checks.
struct LaunchOptions {
    var inMemoryStore = false
    var seedSampleData = false
    /// `-seedActiveCount N`: N active nuggets and nothing else, for checking the
    /// add-nugget celebration at each milestone.
    var seedActiveCount: Int?
    var initialTab: AppTab = .today

    static var current: LaunchOptions {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        var options = LaunchOptions()
        options.inMemoryStore = arguments.contains("-inMemoryStore")
        options.seedSampleData = arguments.contains("-seedSampleData")
        if let index = arguments.firstIndex(of: "-seedActiveCount"), arguments.indices.contains(index + 1) {
            options.seedActiveCount = Int(arguments[index + 1])
        }
        if let index = arguments.firstIndex(of: "-tab"), arguments.indices.contains(index + 1),
           let tab = AppTab(rawValue: arguments[index + 1]) {
            options.initialTab = tab
        }
        return options
        #else
        return LaunchOptions()
        #endif
    }
}
