import SwiftUI

/// Shown in the editor sheet after a new nugget is saved. The check and
/// headline sit at the top and the buttons at the bottom; between them,
/// centered, is the progress ring when the nugget joined the rotation, or an
/// info box when it went to Queued or Paused. It stays until a button is tapped.
struct SaveCelebrationView: View {
    let celebration: SaveCelebration
    let onAddAnother: () -> Void
    let onGoToNuggets: () -> Void
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var checkSize: CGFloat = 88
    @State private var appeared = false
    @State private var burst = false
    @State private var ringProgress: Double

    init(
        celebration: SaveCelebration,
        onAddAnother: @escaping () -> Void,
        onGoToNuggets: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.celebration = celebration
        self.onAddAnother = onAddAnother
        self.onGoToNuggets = onGoToNuggets
        self.onDone = onDone
        _ringProgress = State(initialValue: celebration.previousProgress)
        // Warm up the audio session and chime while the sheet is presented, so
        // the sound starts in step with the haptic. `play` loads it too if needed.
        Task { @MainActor in SoundPlayer.shared.preload(SoundPlayer.saveCelebration) }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                // Equal flexible spacers keep the ring or box centered between
                // the headline and the buttons; at large text sizes the content
                // outgrows the screen and scrolls instead.
                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 28)
                    middle
                    Spacer(minLength: 28)
                    buttons
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(.systemGroupedBackground))
        .overlay {
            if celebration.isBigCelebration && !reduceMotion {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .sensoryFeedback(.success, trigger: appeared) { _, new in new }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: burst) { _, new in new }
        .onAppear(perform: start)
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: min(checkSize, 150), weight: .regular))
                .foregroundStyle(.white, Color.green)
                .symbolEffect(.bounce, value: reduceMotion ? false : appeared)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)

            Text(celebration.headline)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var middle: some View {
        if let box = celebration.infoBox {
            SaveInfoBox(box: box)
        } else {
            RotationProgressRing(progress: ringProgress, celebration: celebration)
        }
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            Button(action: primaryAction) {
                Text(celebration.primaryAction.title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .primaryActionStyle()
            .controlSize(.large)

            Button(action: onDone) {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func primaryAction() {
        switch celebration.primaryAction {
        case .addAnother: onAddAnother()
        case .goToNuggets: onGoToNuggets()
        }
    }

    private func start() {
        let animation: Animation = reduceMotion ? .easeIn(duration: 0.3) : .spring(response: 0.45, dampingFraction: 0.55)
        withAnimation(animation) { appeared = true }
        // `appeared` triggers the success haptic, so the chime plays with it.
        SoundPlayer.shared.play(SoundPlayer.saveCelebration)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.8).delay(0.2)) {
            ringProgress = celebration.progress
        }
        if celebration.isBigCelebration {
            Task {
                try? await Task.sleep(for: .seconds(0.3))
                burst = true
            }
        }
        // Let the sheet settle first so the announcement isn't cut off.
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            AccessibilityNotification.Announcement(celebration.announcement).post()
        }
    }
}

/// Why the nugget isn't in the rotation and how to bring it in.
struct SaveInfoBox: View {
    let box: SaveCelebration.InfoBox

    @ScaledMetric(relativeTo: .subheadline) private var stepSize: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(box.title)
                    .font(.headline)
                Text(box.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(box.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.footnote.bold())
                            .monospacedDigit()
                            .foregroundStyle(Color(.systemBackground))
                            .frame(width: stepSize, height: stepSize)
                            .background(Circle().fill(Color("AccentColor")))
                            .accessibilityHidden(true)
                        Text(step)
                            .font(.subheadline)
                            .accessibilityLabel("Step \(index + 1): \(step)")
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
    }
}

/// How full the rotation is, as a ring with the count in the middle.
struct RotationProgressRing: View {
    let progress: Double
    let celebration: SaveCelebration

    @ScaledMetric(relativeTo: .title) private var diameter: CGFloat = 132
    @ScaledMetric(relativeTo: .title) private var lineWidth: CGFloat = 12

    var body: some View {
        let size = min(diameter, 220)
        ZStack {
            Circle()
                .stroke(Color("AccentColor").opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color("AccentColor"), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(min(celebration.activeCount, celebration.limit))")
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                Text("of \(celebration.limit)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(lineWidth * 1.5)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rotation")
        .accessibilityValue("\(celebration.progressLabel) spots filled")
    }
}

/// A one-off burst of confetti, drawn with Canvas.
struct ConfettiView: View {
    @State private var pieces = ConfettiPiece.burst(count: 110)
    @State private var start = Date.now
    @State private var finished = false

    private static let duration: TimeInterval = 3.2

    var body: some View {
        TimelineView(.animation(paused: finished)) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                for piece in pieces {
                    let t = elapsed - piece.delay
                    guard t > 0 else { continue }
                    let x = piece.x * size.width + sin(t * piece.wobbleSpeed) * piece.wobble
                    let y = -20 + piece.speed * t + 260 * t * t
                    guard y < size.height + 20 else { continue }
                    let fade = max(0, min(1, (Self.duration - elapsed) / 0.6))
                    var copy = context
                    copy.opacity = fade
                    copy.translateBy(x: x, y: y)
                    copy.rotate(by: .radians(piece.spin * t))
                    let rect = CGRect(x: -piece.width / 2, y: -piece.height / 2, width: piece.width, height: piece.height)
                    let shape = piece.isRound ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
                    // Flatten one axis to fake a flip in 3D.
                    copy.scaleBy(x: 1, y: abs(cos(t * piece.flipSpeed)) * 0.8 + 0.2)
                    copy.fill(shape, with: .color(piece.color))
                }
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(Self.duration))
            finished = true
        }
    }
}

struct ConfettiPiece {
    var x: Double
    var delay: Double
    var speed: Double
    var wobble: Double
    var wobbleSpeed: Double
    var spin: Double
    var flipSpeed: Double
    var width: Double
    var height: Double
    var isRound: Bool
    var color: Color

    private static let colors: [Color] = [Color("AccentColor"), .green, .yellow, .orange, .pink, .blue, .purple, .mint]

    static func burst(count: Int) -> [ConfettiPiece] {
        (0..<count).map { _ in
            let isRound = Double.random(in: 0...1) < 0.25
            let width = Double.random(in: 6...10)
            return ConfettiPiece(
                x: .random(in: 0...1),
                delay: .random(in: 0...0.5),
                speed: .random(in: 80...260),
                wobble: .random(in: 6...26),
                wobbleSpeed: .random(in: 3...7),
                spin: .random(in: -8...8),
                flipSpeed: .random(in: 4...10),
                width: width,
                height: isRound ? width : width * .random(in: 1.4...2.2),
                isRound: isRound,
                color: colors.randomElement() ?? .orange
            )
        }
    }
}

#Preview("A: added, 8 of 21") {
    SaveCelebrationView(celebration: SaveCelebration(activeCount: 8, outcome: .active), onAddAnother: {}, onGoToNuggets: {}, onDone: {})
}

#Preview("A: rotation full, confetti") {
    SaveCelebrationView(celebration: SaveCelebration(activeCount: 21, outcome: .active), onAddAnother: {}, onGoToNuggets: {}, onDone: {})
}

#Preview("B: Active full, went to Queued") {
    SaveCelebrationView(celebration: SaveCelebration(activeCount: 21, outcome: .queuedBecauseActiveFull), onAddAnother: {}, onGoToNuggets: {}, onDone: {})
}

#Preview("C: chose Queued") {
    SaveCelebrationView(celebration: SaveCelebration(activeCount: 8, outcome: .chose(.queued)), onAddAnother: {}, onGoToNuggets: {}, onDone: {})
}

#Preview("C: chose Paused") {
    SaveCelebrationView(celebration: SaveCelebration(activeCount: 8, outcome: .chose(.paused)), onAddAnother: {}, onGoToNuggets: {}, onDone: {})
}
