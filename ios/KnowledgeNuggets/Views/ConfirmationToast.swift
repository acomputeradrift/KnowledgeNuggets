import Observation
import SwiftUI
import UIKit

/// One short "that worked" message, with an optional Undo.
struct Toast: Identifiable {
    let id = UUID()
    let text: String
    /// Plays the success haptic when shown. Only moving a nugget into the rotation does.
    let playsSuccessHaptic: Bool
    let undo: (@MainActor () -> Void)?
}

/// Shows one confirmation at a time, app-wide. A new toast replaces the current
/// one, and each hides itself after a short while.
@MainActor
@Observable
final class ToastCenter {
    private(set) var current: Toast?

    @ObservationIgnored private let duration: Duration
    /// Longer when VoiceOver is on, so there's time to reach Undo.
    @ObservationIgnored private let accessibleDuration: Duration
    @ObservationIgnored private let isVoiceOverRunning: @MainActor () -> Bool
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    /// Pass `isVoiceOverRunning` and `announce` in tests; by default they use UIAccessibility.
    init(
        duration: Duration = .seconds(2.5),
        accessibleDuration: Duration = .seconds(8),
        isVoiceOverRunning: (@MainActor () -> Bool)? = nil,
        announce: (@MainActor (String) -> Void)? = nil
    ) {
        self.duration = duration
        self.accessibleDuration = accessibleDuration
        self.isVoiceOverRunning = isVoiceOverRunning ?? { UIAccessibility.isVoiceOverRunning }
        self.announce = announce ?? ToastCenter.postAnnouncement
    }

    func show(_ text: String, successHaptic: Bool = false, undo: (@MainActor () -> Void)? = nil) {
        let toast = Toast(text: text, playsSuccessHaptic: successHaptic, undo: undo)
        current = toast
        announce(text)
        hideTask?.cancel()
        let wait = isVoiceOverRunning() ? accessibleDuration : duration
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.dismiss(toast.id)
        }
    }

    /// Hides the toast, but only if it's still the one with this id.
    func dismiss(_ id: Toast.ID) {
        guard current?.id == id else { return }
        current = nil
        hideTask?.cancel()
    }

    /// Runs the current toast's Undo, once, and hides it.
    func undo() {
        guard let toast = current else { return }
        current = nil
        hideTask?.cancel()
        toast.undo?()
    }

    /// Queued, and sent on the next turn, so it isn't cut off by the list
    /// updating at the same moment.
    static func postAnnouncement(_ text: String) {
        Task { @MainActor in
            let message = NSAttributedString(string: text, attributes: [.accessibilitySpeechQueueAnnouncement: true])
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }
}

/// The toast itself: a green check, a short message and an optional Undo.
struct ConfirmationToast: View {
    let text: String
    var onUndo: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.white, .green)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let onUndo {
                Spacer(minLength: 4)
                Button("Undo", action: onUndo)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, onUndo == nil ? 18 : 12)
        .padding(.vertical, onUndo == nil ? 12 : 0)
        .frame(minHeight: 44)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Shows `ToastCenter.current` at the bottom, above the tab bar, and plays the haptic.
struct ToastOverlay: View {
    let center: ToastCenter
    /// Reports where the toast is so the window lets touches elsewhere through.
    var onFrameChange: (CGRect) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if let toast = center.current {
                ConfirmationToast(text: toast.text, onUndo: toast.undo == nil ? nil : { center.undo() })
                    .id(toast.id)
                    .background(GeometryReader { proxy in
                        Color.clear
                            .onAppear { onFrameChange(proxy.frame(in: .global)) }
                            .onChange(of: proxy.frame(in: .global)) { _, frame in onFrameChange(frame) }
                    })
                    .onDisappear { if center.current == nil { onFrameChange(.zero) } }
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        // Clears the tab bar (the floating one on iOS 26 and the classic one before).
        .padding(.bottom, 64)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy, value: center.current?.id)
        // Its own window doesn't inherit the app's tint, so set it for Undo.
        .tint(Color("AccentColor"))
        .sensoryFeedback(trigger: center.current?.id) { _, _ in
            center.current?.playsSuccessHaptic == true ? .success : nil
        }
    }
}

extension View {
    /// Hosts the app's toasts in a window of their own above the app, so they
    /// show over sheets too. Apply once, at the root.
    func toastWindow(_ center: ToastCenter) -> some View {
        background(ToastWindowInstaller(center: center).frame(width: 0, height: 0))
    }
}

/// Lets touches through except on the toast.
private final class ToastPassthroughWindow: UIWindow {
    var toastFrame: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard toastFrame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

private struct ToastWindowInstaller: UIViewRepresentable {
    let center: ToastCenter

    func makeUIView(context: Context) -> InstallerView {
        InstallerView(center: center)
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        let toasts: ToastCenter
        private var overlayWindow: ToastPassthroughWindow?

        init(center: ToastCenter) {
            self.toasts = center
            super.init(frame: .zero)
            isHidden = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard overlayWindow == nil, let scene = window?.windowScene else { return }
            let overlayWindow = ToastPassthroughWindow(windowScene: scene)
            let host = UIHostingController(rootView: ToastOverlay(center: toasts) { [weak overlayWindow] frame in
                overlayWindow?.toastFrame = frame
            })
            host.view.backgroundColor = .clear
            overlayWindow.rootViewController = host
            // Above the app and its sheets, below system alerts and the status bar.
            overlayWindow.windowLevel = .normal + 1
            overlayWindow.backgroundColor = .clear
            overlayWindow.isHidden = false
            self.overlayWindow = overlayWindow
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ConfirmationToast(text: "Moved to Active", onUndo: {})
        ConfirmationToast(text: "Nugget updated")
    }
    .padding()
}
