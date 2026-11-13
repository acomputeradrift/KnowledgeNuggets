import AVFoundation

/// Plays short bundled sounds that go with haptics. Uses the ambient audio
/// session, so it obeys the silent switch and mixes with whatever the user is
/// listening to. Every failure (missing file, audio session refused) is silent.
@MainActor
final class SoundPlayer {
    /// The sound played with the success haptic after a nugget is saved.
    /// To change it, drop a file into Resources/Sounds and change this name.
    static let saveCelebration = "success.caf"

    static let shared = SoundPlayer()

    private var players: [String: AVAudioPlayer] = [:]
    private var sessionReady = false

    /// No sound under unit tests or in Xcode Previews.
    private let isEnabled: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] == nil && env["XCODE_RUNNING_FOR_PREVIEWS"] != "1"
    }()

    private init() {}

    /// Where a bundled file such as "success.caf" lives, or nil if it isn't there.
    nonisolated static func url(for fileName: String, in bundle: Bundle = .main) -> URL? {
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        return bundle.url(forResource: name, withExtension: ext.isEmpty ? nil : ext)
    }

    /// Loads a sound ahead of time so `play` starts at once, in step with the haptic.
    /// Safe to call often; each file is only loaded once.
    func preload(_ fileName: String) {
        guard isEnabled, players[fileName] == nil else { return }
        prepareSession()
        guard let url = Self.url(for: fileName),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.prepareToPlay()
        players[fileName] = player
    }

    func play(_ fileName: String) {
        guard isEnabled else { return }
        preload(fileName)
        guard let player = players[fileName] else { return }
        player.currentTime = 0
        player.play()
    }

    private func prepareSession() {
        guard !sessionReady else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            sessionReady = true
        } catch {
            // Without a session the players may still work; if not, stay quiet.
        }
    }
}
