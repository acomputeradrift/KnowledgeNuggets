import SwiftUI

/// Shown in the editor sheet after a new nugget is saved. Looks the same whether
/// the nugget went to Active or Inactive; only the note at the bottom differs.
struct SaveCelebrationView: View {
    let celebration: SaveCelebration
    let onAddAnother: () -> Void
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @ScaledMetric(relativeTo: .largeTitle) private var checkSize: CGFloat = 88
    @State private var appeared = false
    @State private var burst = false
    @State private var ringProgress: Double

    init(celebration: SaveCelebration, onAddAnother: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.celebration = celebration
        self.onAddAnother = onAddAnother
        self.onDone = onDone
        _ringProgress = State(initialValue: celebration.previousProgress)
    }

    private var closesAutomatically: Bool {
        celebration.closesAutomatically && !voiceOverEnabled
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 12)
                    header
                    RotationProgressRing(progress: ringProgress, celebration: celebration)
                    Text(celebration.daysLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 12)
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(.systemGroupedBackground))
        .contentShape(Rectangle())
        // Once the rotation is full, a tap anywhere closes the sheet early.
        .onTapGesture { if celebration.closesAutomatically { onDone() } }
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
        .task {
            guard closesAutomatically else { return }
            // Cancelled when the sheet goes away first, so it never closes twice.
            guard (try? await Task.sleep(for: .seconds(1.5))) != nil else { return }
            onDone()
        }
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

            if let subtext = celebration.subtext {
                Text(subtext)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Text(celebration.note)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)

            if celebration.offersAddAnother {
                Button(action: onAddAnother) {
                    Text("Add Another")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .primaryActionStyle()
                .controlSize(.large)
            }

            Button(action: onDone) {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func start() {
        let animation: Animation = reduceMotion ? .easeIn(duration: 0.3) : .spring(response: 0.45, dampingFraction: 0.55)
        withAnimation(animation) { appeared = true }
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

#Preview("Saved") {
    SaveCelebrationView(celebration: SaveCelebration(activeCount: 8, keptInactive: false), onAddAnother: {}, onDone: {})
}

#Preview("First week") {
    SaveCelebrationView(celebration: SaveCelebration(activeCount: 7, keptInactive: false), onAddAnother: {}, onDone: {})
}

#Preview("Rotation full") {
    SaveCelebrationView(celebration: SaveCelebration(activeCount: 21, keptInactive: false), onAddAnother: {}, onDone: {})
}

#Preview("Kept inactive") {
    SaveCelebrationView(celebration: SaveCelebration(activeCount: 21, keptInactive: true), onAddAnother: {}, onDone: {})
}
