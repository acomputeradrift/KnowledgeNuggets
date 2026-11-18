import Foundation

/// Which build is running, so you can tell on the phone whether an update landed.
/// The commit and build time are written into Info.plist by a build script.
struct AppInfo: Equatable {
    var version: String
    var commit: String?
    var builtAt: Date?

    init(version: String, commit: String?, builtAt: Date?) {
        self.version = version
        self.commit = commit
        self.builtAt = builtAt
    }

    init(info: [String: Any]?) {
        version = info?["CFBundleShortVersionString"] as? String ?? "?"
        commit = info?["KNBuildCommit"] as? String
        builtAt = (info?["KNBuildDate"] as? String).flatMap { try? Date($0, strategy: .iso8601) }
    }

    static let current = AppInfo(info: Bundle.main.infoDictionary)

    /// "1.0 (05c395f)", or just "1.0" when the build wasn't stamped.
    var versionText: String {
        guard let commit else { return version }
        return "\(version) (\(commit))"
    }

    /// "Nov 18, 2026 at 3:55 PM" in the phone's time zone.
    func builtText(timeZone: TimeZone = .current) -> String? {
        guard let builtAt else { return nil }
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.timeZone = timeZone
        return builtAt.formatted(style)
    }
}
